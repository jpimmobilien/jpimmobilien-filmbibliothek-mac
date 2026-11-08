import Foundation
import FBCore

/// Zugriff auf die Bibliotheksdatenbank (SQLite).
///
/// Threadsicher: Alle Zugriffe laufen über eine Sperre; Aufrufer dürfen von beliebigen Threads/Tasks kommen.
/// Lange Vorgänge (Scan-Ergebnisse) werden in EINER Transaktion geschrieben.
public final class LibraryStore: @unchecked Sendable {
    private let db: SQLiteConnection
    private let lock = NSRecursiveLock()
    public let path: String

    /// Öffnet (bzw. erstellt) die Datenbank. `":memory:"` für Tests.
    public init(path: String) throws {
        self.path = path
        if path != ":memory:" {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        db = try SQLiteConnection(path: path)
        try Schema.migrate(db)
    }

    public static func inMemory() throws -> LibraryStore { try LibraryStore(path: ":memory:") }

    private func sync<T>(_ body: (SQLiteConnection) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(db)
    }

    public func integrityCheck() -> String { sync { $0.integrityCheck() } }

    // MARK: - Hilfen

    private static func date(_ row: SQLRow, _ i: Int) -> Date? {
        row.isNull(i) ? nil : Date(timeIntervalSince1970: row.double(i))
    }

    private static func ts(_ d: Date?) -> SQLValue { d.map { .double($0.timeIntervalSince1970) } ?? .null }

    // MARK: - Speicherorte

    private static let locationColumns = "id, name, lastKnownPath, pathInVolume, volumeKey, volumeName, kind, bookmark, addedAt, lastScanAt, lastSeenAt"

    private static func location(_ r: SQLRow) -> StorageLocation {
        StorageLocation(id: r.int64(0), name: r.string(1), lastKnownPath: r.string(2), pathInVolume: r.string(3),
                        volumeKey: r.string(4), volumeName: r.string(5), kind: LocationKind(rawValue: r.string(6)) ?? .unknown,
                        bookmark: r.data(7), addedAt: date(r, 8) ?? Date(), lastScanAt: date(r, 9), lastSeenAt: date(r, 10))
    }

    public func locations() throws -> [StorageLocation] {
        try sync { db in
            try db.query("SELECT \(Self.locationColumns) FROM locations ORDER BY name COLLATE NOCASE, id", [], Self.location)
        }
    }

    public func location(id: Int64) throws -> StorageLocation? {
        try sync { db in try db.queryOne("SELECT \(Self.locationColumns) FROM locations WHERE id = ?", [.int(id)], Self.location) }
    }

    public func location(volumeKey: String, pathInVolume: String) throws -> StorageLocation? {
        try sync { db in
            try db.queryOne("SELECT \(Self.locationColumns) FROM locations WHERE volumeKey = ? AND pathInVolume = ?",
                            [.text(volumeKey), .text(pathInVolume)], Self.location)
        }
    }

    /// Legt einen Speicherort an und gibt ihn mit ID zurück.
    @discardableResult
    public func insertLocation(_ l: StorageLocation) throws -> StorageLocation {
        try sync { db in
            try db.run("""
                INSERT INTO locations (name, lastKnownPath, pathInVolume, volumeKey, volumeName, kind, bookmark, addedAt, lastScanAt, lastSeenAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [.text(l.name), .text(l.lastKnownPath), .text(l.pathInVolume), .text(l.volumeKey), .text(l.volumeName),
                      .text(l.kind.rawValue), SQLValue(l.bookmark), Self.ts(l.addedAt), Self.ts(l.lastScanAt), Self.ts(l.lastSeenAt)])
            var copy = l
            copy.id = db.lastInsertRowID
            return copy
        }
    }

    public func updateLocation(_ l: StorageLocation) throws {
        try sync { db in
            try db.run("""
                UPDATE locations SET name = ?, lastKnownPath = ?, pathInVolume = ?, volumeKey = ?, volumeName = ?, kind = ?,
                bookmark = ?, lastScanAt = ?, lastSeenAt = ? WHERE id = ?
                """, [.text(l.name), .text(l.lastKnownPath), .text(l.pathInVolume), .text(l.volumeKey), .text(l.volumeName),
                      .text(l.kind.rawValue), SQLValue(l.bookmark), Self.ts(l.lastScanAt), Self.ts(l.lastSeenAt), .int(l.id)])
        }
    }

    public func renameLocation(id: Int64, name: String) throws {
        try sync { db in _ = try db.run("UPDATE locations SET name = ? WHERE id = ?", [.text(name), .int(id)]) }
    }

    public func setLocationSeen(id: Int64, path: String, at date: Date = Date()) throws {
        try sync { db in _ = try db.run("UPDATE locations SET lastKnownPath = ?, lastSeenAt = ? WHERE id = ?", [.text(path), Self.ts(date), .int(id)]) }
    }

    public func setLocationBookmark(id: Int64, bookmark: Data?) throws {
        try sync { db in _ = try db.run("UPDATE locations SET bookmark = ? WHERE id = ?", [SQLValue(bookmark), .int(id)]) }
    }

    public func setLastScan(id: Int64, at date: Date = Date()) throws {
        try sync { db in _ = try db.run("UPDATE locations SET lastScanAt = ? WHERE id = ?", [Self.ts(date), .int(id)]) }
    }

    /// Entfernt einen Speicherort samt seiner Film-Einträge (Videodateien bleiben unberührt).
    /// Nur als bewusste Nutzeraktion mit Bestätigung aufrufen.
    public func deleteLocation(id: Int64) throws {
        try sync { db in
            try db.transaction {
                _ = try db.run("DELETE FROM films WHERE locationId = ?", [.int(id)])
                _ = try db.run("DELETE FROM locations WHERE id = ?", [.int(id)])
            }
        }
    }

    // MARK: - Filme lesen

    private static let filmColumns = """
        id, locationId, relativePath, sizeBytes, modifiedAt, createdAt, addedAt, durationSeconds, width, height, frameRate,
        videoCodec, audioCodec, audioTrackCount, subtitleTrackCount, chapterCount, bitRate, embeddedTitle, metadataVersion,
        playability, coverSource, coverStamp, isFavorite, positionSeconds, finished, lastPlayedAt, playCount, isMissing, missingSince
        """

    private static func film(_ r: SQLRow) -> Film {
        let info = VideoInfo(durationSeconds: r.isNull(7) ? nil : r.double(7), width: r.optInt(8), height: r.optInt(9),
                             frameRate: r.isNull(10) ? nil : r.double(10), videoCodec: r.optString(11), audioCodec: r.optString(12),
                             audioTrackCount: r.int(13), subtitleTrackCount: r.int(14), chapterCount: r.int(15),
                             bitRate: r.optInt(16), embeddedTitle: r.optString(17))
        return Film(id: r.int64(0), locationId: r.int64(1), relativePath: r.string(2), sizeBytes: r.int64(3),
                    modifiedAt: date(r, 4), createdAt: date(r, 5), addedAt: date(r, 6) ?? Date(), info: info,
                    metadataVersion: r.int(18), playability: Playability(rawValue: r.int(19)) ?? .unknown,
                    coverSource: CoverSource(rawValue: r.int(20)) ?? .none, coverStamp: r.int64(21),
                    isFavorite: r.bool(22), positionSeconds: r.double(23), finished: r.bool(24), lastPlayedAt: date(r, 25),
                    playCount: r.int(26), isMissing: r.bool(27), missingSince: date(r, 28))
    }

    public func films() throws -> [Film] {
        try sync { db in try db.query("SELECT \(Self.filmColumns) FROM films", [], Self.film) }
    }

    public func film(id: Int64) throws -> Film? {
        try sync { db in try db.queryOne("SELECT \(Self.filmColumns) FROM films WHERE id = ?", [.int(id)], Self.film) }
    }

    public func films(locationId: Int64) throws -> [Film] {
        try sync { db in try db.query("SELECT \(Self.filmColumns) FROM films WHERE locationId = ?", [.int(locationId)], Self.film) }
    }

    public func filmCount() throws -> Int {
        try sync { db in try db.queryOne("SELECT COUNT(*) FROM films", []) { $0.int(0) } ?? 0 }
    }

    /// Index eines Speicherorts für den Abgleich beim Durchsuchen
    public func indexedFiles(locationId: Int64) throws -> [IndexedFile] {
        try sync { db in
            try db.query("SELECT id, relativePath, sizeBytes, modifiedAt, fileId, isMissing FROM films WHERE locationId = ?", [.int(locationId)]) { r in
                IndexedFile(id: r.int64(0), relativePath: r.string(1), sizeBytes: r.int64(2), modifiedAt: Self.date(r, 3),
                            fileId: r.isNull(4) ? nil : UInt64(bitPattern: r.int64(4)), isMissing: r.bool(5))
            }
        }
    }

    // MARK: - Scan-Ergebnisse schreiben

    public struct ApplyResult: Sendable, Equatable {
        public var insertedIds: [Int64] = []
        public var changedIds: [Int64] = []
        public init() {}
    }

    /// Schreibt das Ergebnis eines vollständigen Durchlaufs in einer Transaktion.
    /// - Parameter heartFavorites: „Heart“ im Dateinamen → Favorit (Einstellung)
    @discardableResult
    public func apply(_ changes: ScanChanges, locationId: Int64, heartFavorites: Bool, now: Date = Date()) throws -> ApplyResult {
        try sync { db in
            try db.transaction {
                var result = ApplyResult()
                for f in changes.inserts {
                    let heart = heartFavorites && HeartMarker.hasMarker(fileName: f.fileName)
                    try db.run("""
                        INSERT INTO films (locationId, relativePath, sizeBytes, modifiedAt, createdAt, addedAt, fileId, isFavorite, heartApplied)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(locationId, relativePath) DO UPDATE SET sizeBytes = excluded.sizeBytes,
                            modifiedAt = excluded.modifiedAt, fileId = excluded.fileId, isMissing = 0, missingSince = NULL
                        """, [.int(locationId), .text(f.relativePath), .int(f.sizeBytes), Self.ts(f.modifiedAt), Self.ts(f.createdAt),
                              Self.ts(now), f.fileId.map { .int(Int64(bitPattern: $0)) } ?? .null, SQLValue(heart), SQLValue(heart)])
                    if let id = try db.queryOne("SELECT id FROM films WHERE locationId = ? AND relativePath = ?", [.int(locationId), .text(f.relativePath)], { $0.int64(0) }) {
                        result.insertedIds.append(id)
                    }
                }
                for u in changes.updates {
                    if u.contentChanged {
                        // Inhalt geändert: Metadaten neu ermitteln; gespeicherte Position passt nicht mehr sicher
                        try db.run("""
                            UPDATE films SET sizeBytes = ?, modifiedAt = ?, fileId = ?, metadataVersion = 0, playability = 0,
                            isMissing = 0, missingSince = NULL WHERE id = ?
                            """, [.int(u.file.sizeBytes), Self.ts(u.file.modifiedAt), u.file.fileId.map { .int(Int64(bitPattern: $0)) } ?? .null, .int(u.id)])
                        result.changedIds.append(u.id)
                    } else {
                        try db.run("UPDATE films SET fileId = ? WHERE id = ?", [u.file.fileId.map { .int(Int64(bitPattern: $0)) } ?? .null, .int(u.id)])
                    }
                }
                for m in changes.moves {
                    try db.run("UPDATE films SET relativePath = ?, fileId = ?, modifiedAt = ?, isMissing = 0, missingSince = NULL WHERE id = ?",
                               [.text(m.file.relativePath), m.file.fileId.map { .int(Int64(bitPattern: $0)) } ?? .null, Self.ts(m.file.modifiedAt), .int(m.id)])
                }
                for id in changes.reappeared {
                    try db.run("UPDATE films SET isMissing = 0, missingSince = NULL WHERE id = ?", [.int(id)])
                }
                for id in changes.newlyMissing {
                    try db.run("UPDATE films SET isMissing = 1, missingSince = ? WHERE id = ? AND isMissing = 0", [Self.ts(now), .int(id)])
                }
                try db.run("UPDATE locations SET lastScanAt = ?, lastSeenAt = ? WHERE id = ?", [Self.ts(now), Self.ts(now), .int(locationId)])
                return result
            }
        }
    }

    /// Entfernt Einträge, deren Datei fehlt (bewusste Nutzeraktion). nil = alle Speicherorte.
    @discardableResult
    public func removeMissingFilms(locationId: Int64?) throws -> Int {
        try sync { db in
            if let locationId {
                return try db.run("DELETE FROM films WHERE isMissing = 1 AND locationId = ?", [.int(locationId)])
            }
            return try db.run("DELETE FROM films WHERE isMissing = 1", [])
        }
    }

    // MARK: - Metadaten

    /// Filme ohne aktuelle Metadaten (älteste Prüfversion zuerst, neue Filme bevorzugt)
    public func filmsNeedingMetadata(currentVersion: Int, locationIds: [Int64], limit: Int) throws -> [Film] {
        guard !locationIds.isEmpty else { return [] }
        let placeholders = locationIds.map { _ in "?" }.joined(separator: ",")
        return try sync { db in
            try db.query("""
                SELECT \(Self.filmColumns) FROM films
                WHERE metadataVersion < ? AND isMissing = 0 AND locationId IN (\(placeholders))
                ORDER BY addedAt DESC LIMIT ?
                """, [.int(Int64(currentVersion))] + locationIds.map { .int($0) } + [.int(Int64(limit))], Self.film)
        }
    }

    public func updateMetadata(id: Int64, info: VideoInfo, playability: Playability, version: Int) throws {
        try sync { db in
            _ = try db.run("""
                UPDATE films SET durationSeconds = ?, width = ?, height = ?, frameRate = ?, videoCodec = ?, audioCodec = ?,
                audioTrackCount = ?, subtitleTrackCount = ?, chapterCount = ?, bitRate = ?, embeddedTitle = ?,
                playability = ?, metadataVersion = ? WHERE id = ?
                """, [SQLValue(info.durationSeconds), SQLValue(info.width), SQLValue(info.height), SQLValue(info.frameRate),
                      SQLValue(info.videoCodec), SQLValue(info.audioCodec), .int(Int64(info.audioTrackCount)),
                      .int(Int64(info.subtitleTrackCount)), .int(Int64(info.chapterCount)), SQLValue(info.bitRate),
                      SQLValue(info.embeddedTitle), .int(Int64(playability.rawValue)), .int(Int64(version)), .int(id)])
        }
    }

    public func updatePlayability(id: Int64, _ p: Playability) throws {
        try sync { db in _ = try db.run("UPDATE films SET playability = ? WHERE id = ?", [.int(Int64(p.rawValue)), .int(id)]) }
    }

    public func updateCover(id: Int64, source: CoverSource, stamp: Int64) throws {
        try sync { db in _ = try db.run("UPDATE films SET coverSource = ?, coverStamp = ? WHERE id = ?", [.int(Int64(source.rawValue)), .int(stamp), .int(id)]) }
    }

    // MARK: - Nutzerdaten

    public func setFavorite(ids: [Int64], _ on: Bool) throws {
        try sync { db in
            try db.transaction {
                for id in ids { try db.run("UPDATE films SET isFavorite = ? WHERE id = ?", [SQLValue(on), .int(id)]) }
            }
        }
    }

    /// Gesehen markieren (Position wird verworfen) bzw. wieder als nicht gesehen.
    public func setFinished(ids: [Int64], _ on: Bool) throws {
        try sync { db in
            try db.transaction {
                for id in ids {
                    try db.run("UPDATE films SET finished = ?, positionSeconds = 0, positionSize = NULL WHERE id = ?", [SQLValue(on), .int(id)])
                }
            }
        }
    }

    /// Wiedergabeposition speichern (`size` = Dateigröße zum Zeitpunkt, damit ersetzte Dateien erkannt werden)
    public func savePosition(id: Int64, seconds: Double, fileSize: Int64) throws {
        try sync { db in
            _ = try db.run("UPDATE films SET positionSeconds = ?, positionSize = ?, finished = 0 WHERE id = ?", [.double(seconds), .int(fileSize), .int(id)])
        }
    }

    public func positionFileSize(id: Int64) throws -> Int64? {
        try sync { db in try db.queryOne("SELECT positionSize FROM films WHERE id = ?", [.int(id)]) { $0.optInt64(0) } ?? nil }
    }

    /// Film wurde bis zum Ende gesehen
    public func markFinishedAfterPlayback(id: Int64) throws {
        try sync { db in _ = try db.run("UPDATE films SET finished = 1, positionSeconds = 0, positionSize = NULL WHERE id = ?", [.int(id)]) }
    }

    /// Eine Wiedergabe zählen (nach 3 Sekunden tatsächlicher Wiedergabe)
    @discardableResult
    public func recordPlay(id: Int64, at date: Date = Date()) throws -> Int64 {
        try sync { db in
            try db.transaction {
                try db.run("UPDATE films SET playCount = playCount + 1, lastPlayedAt = ? WHERE id = ?", [Self.ts(date), .int(id)])
                try db.run("INSERT INTO play_history (filmId, playedAt, secondsWatched) VALUES (?, ?, 0)", [.int(id), Self.ts(date)])
                return db.lastInsertRowID
            }
        }
    }

    /// Gesehene Zeit eines Verlaufseintrags aktualisieren
    public func updateHistory(entryId: Int64, secondsWatched: Double) throws {
        try sync { db in _ = try db.run("UPDATE play_history SET secondsWatched = ? WHERE id = ?", [.double(secondsWatched), .int(entryId)]) }
    }

    /// „Zuletzt abgespielt“ für einen Film leeren
    public func clearPlayback(ids: [Int64]) throws {
        try sync { db in
            try db.transaction {
                for id in ids {
                    try db.run("UPDATE films SET lastPlayedAt = NULL, positionSeconds = 0, positionSize = NULL WHERE id = ?", [.int(id)])
                    try db.run("DELETE FROM play_history WHERE filmId = ?", [.int(id)])
                }
            }
        }
    }

    public struct Statistics: Sendable, Equatable {
        public var totalPlays: Int
        public var totalSecondsWatched: Double
        public var playsLast30Days: Int
    }

    public func statistics(now: Date = Date()) throws -> Statistics {
        try sync { db in
            let total = try db.queryOne("SELECT COUNT(*), COALESCE(SUM(secondsWatched), 0) FROM play_history", []) { ($0.int(0), $0.double(1)) } ?? (0, 0)
            let recent = try db.queryOne("SELECT COUNT(*) FROM play_history WHERE playedAt >= ?", [.double(now.timeIntervalSince1970 - 30 * 86_400)]) { $0.int(0) } ?? 0
            return Statistics(totalPlays: total.0, totalSecondsWatched: total.1, playsLast30Days: recent)
        }
    }

    // MARK: - Sammlungen

    public func collections() throws -> [FilmCollection] {
        try sync { db in
            var list = try db.query("SELECT id, name, createdAt FROM collections ORDER BY name COLLATE NOCASE, id", []) { r in
                FilmCollection(id: r.int64(0), name: r.string(1), createdAt: Self.date(r, 2) ?? Date())
            }
            for i in list.indices {
                list[i].filmIds = try db.query("SELECT filmId FROM collection_items WHERE collectionId = ? ORDER BY position, addedAt", [.int(list[i].id)]) { $0.int64(0) }
            }
            return list
        }
    }

    @discardableResult
    public func createCollection(name: String, now: Date = Date()) throws -> FilmCollection {
        try sync { db in
            try db.run("INSERT INTO collections (name, createdAt) VALUES (?, ?)", [.text(name), Self.ts(now)])
            return FilmCollection(id: db.lastInsertRowID, name: name, createdAt: now)
        }
    }

    public func renameCollection(id: Int64, name: String) throws {
        try sync { db in _ = try db.run("UPDATE collections SET name = ? WHERE id = ?", [.text(name), .int(id)]) }
    }

    public func deleteCollection(id: Int64) throws {
        try sync { db in _ = try db.run("DELETE FROM collections WHERE id = ?", [.int(id)]) }
    }

    public func addToCollection(id: Int64, filmIds: [Int64], now: Date = Date()) throws {
        try sync { db in
            try db.transaction {
                var next = try db.queryOne("SELECT COALESCE(MAX(position), -1) + 1 FROM collection_items WHERE collectionId = ?", [.int(id)]) { $0.int64(0) } ?? 0
                for f in filmIds {
                    let changed = try db.run("INSERT OR IGNORE INTO collection_items (collectionId, filmId, position, addedAt) VALUES (?, ?, ?, ?)",
                                             [.int(id), .int(f), .int(next), Self.ts(now)])
                    if changed > 0 { next += 1 }
                }
            }
        }
    }

    public func removeFromCollection(id: Int64, filmIds: [Int64]) throws {
        try sync { db in
            try db.transaction {
                for f in filmIds { try db.run("DELETE FROM collection_items WHERE collectionId = ? AND filmId = ?", [.int(id), .int(f)]) }
            }
        }
    }

    // MARK: - Einstellungen (klein, z. B. Datenbank-Merkmale)

    public func meta(_ key: String) throws -> String? {
        try sync { db in try db.queryOne("SELECT value FROM app_meta WHERE key = ?", [.text(key)]) { $0.string(0) } }
    }

    public func setMeta(_ key: String, _ value: String) throws {
        try sync { db in _ = try db.run("INSERT INTO app_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [.text(key), .text(value)]) }
    }
}
