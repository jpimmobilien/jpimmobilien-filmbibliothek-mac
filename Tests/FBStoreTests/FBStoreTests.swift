import XCTest
import FBCore
@testable import FBStore

final class LibraryStoreTests: XCTestCase {
    var store: LibraryStore!
    var loc: StorageLocation!
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        store = try LibraryStore.inMemory()
        loc = try store.insertLocation(StorageLocation(name: "Filme", lastKnownPath: "/Volumes/Filme", pathInVolume: "",
                                                        volumeKey: "uuid:A", volumeName: "Filme", kind: .externalDisk, bookmark: Data([1, 2, 3])))
    }

    func found(_ p: String, _ size: Int64 = 100, ino: UInt64? = nil) -> FoundFile {
        FoundFile(relativePath: p, sizeBytes: size, modifiedAt: t0, createdAt: t0, fileId: ino)
    }

    func scan(_ files: [FoundFile], protected: [String] = []) throws -> ScanChanges {
        let c = ScanDiff.compute(existing: try store.indexedFiles(locationId: loc.id), found: files, protectedPrefixes: protected)
        try store.apply(c, locationId: loc.id, heartFavorites: true, now: t0)
        return c
    }

    func testSchemaAndIntegrity() throws {
        XCTAssertEqual(store.integrityCheck(), "ok")
        XCTAssertEqual(try store.locations().count, 1)
        XCTAssertEqual(try store.locations().first?.bookmark, Data([1, 2, 3]))
        XCTAssertNotNil(try store.location(volumeKey: "uuid:A", pathInVolume: ""))
    }

    func testDuplicateLocationRejectedByDatabase() {
        XCTAssertThrowsError(try store.insertLocation(StorageLocation(name: "X", lastKnownPath: "/x", pathInVolume: "", volumeKey: "uuid:A",
                                                                      volumeName: "X", kind: .unknown, bookmark: nil)))
    }

    func testScanInsertUpdateMoveKeepsUserData() throws {
        _ = try scan([found("a.mkv", ino: 1), found("b/Film_Heart.mp4", ino: 2)])
        var films = try store.films()
        XCTAssertEqual(films.count, 2)
        XCTAssertEqual(films.first { $0.fileName == "Film_Heart.mp4" }?.isFavorite, true, "„Heart“ im Namen → Favorit")
        let a = try XCTUnwrap(films.first { $0.relativePath == "a.mkv" })
        try store.setFavorite(ids: [a.id], true)
        try store.savePosition(id: a.id, seconds: 321, fileSize: 100)
        try store.updateMetadata(id: a.id, info: VideoInfo(durationSeconds: 999, width: 1920, height: 1080), playability: .vlc, version: 1)
        // umbenannt (gleiche Inode)
        let c = try scan([found("Neu/a-umbenannt.mkv", ino: 1), found("b/Film_Heart.mp4", ino: 2)])
        XCTAssertEqual(c.moves.count, 1)
        films = try store.films()
        let moved = try XCTUnwrap(films.first { $0.id == a.id })
        XCTAssertEqual(moved.relativePath, "Neu/a-umbenannt.mkv")
        XCTAssertTrue(moved.isFavorite)
        XCTAssertEqual(moved.positionSeconds, 321)
        XCTAssertEqual(moved.playability, .vlc, "Metadaten bleiben bei reinem Umbenennen")
        // Inhalt geändert → Metadaten neu, Nutzerdaten bleiben
        _ = try scan([found("Neu/a-umbenannt.mkv", 555, ino: 1), found("b/Film_Heart.mp4", ino: 2)])
        let changed = try XCTUnwrap(try store.film(id: a.id))
        XCTAssertEqual(changed.metadataVersion, 0)
        XCTAssertEqual(changed.playability, .unknown)
        XCTAssertTrue(changed.isFavorite)
        XCTAssertEqual(changed.sizeBytes, 555)
    }

    func testMissingIsKeptAndCanReappear() throws {
        _ = try scan([found("a.mkv"), found("b.mkv")])
        _ = try scan([found("a.mkv")])
        var b = try XCTUnwrap(try store.films().first { $0.relativePath == "b.mkv" })
        XCTAssertTrue(b.isMissing)
        XCTAssertEqual(b.missingSince, t0)
        XCTAssertEqual(try store.films().count, 2, "nie automatisch löschen")
        _ = try scan([found("a.mkv"), found("b.mkv")])
        b = try XCTUnwrap(try store.film(id: b.id))
        XCTAssertFalse(b.isMissing)
    }

    func testRemoveMissingOnlyRemovesMissing() throws {
        _ = try scan([found("a.mkv"), found("b.mkv")])
        _ = try scan([found("a.mkv")])
        XCTAssertEqual(try store.removeMissingFilms(locationId: loc.id), 1)
        XCTAssertEqual(try store.films().map(\.relativePath), ["a.mkv"])
    }

    func testDeleteLocationCascades() throws {
        _ = try scan([found("a.mkv")])
        let id = try XCTUnwrap(try store.films().first?.id)
        let c = try store.createCollection(name: "Filmabend")
        try store.addToCollection(id: c.id, filmIds: [id])
        try store.recordPlay(id: id)
        try store.deleteLocation(id: loc.id)
        XCTAssertTrue(try store.films().isEmpty)
        XCTAssertTrue(try store.locations().isEmpty)
        XCTAssertEqual(try store.collections().first?.filmIds, [])
        XCTAssertEqual(try store.statistics().totalPlays, 0)
    }

    func testCollectionsKeepOrderAndIgnoreDuplicates() throws {
        _ = try scan([found("a.mkv"), found("b.mkv"), found("c.mkv")])
        let ids = try store.films().sorted { $0.relativePath < $1.relativePath }.map(\.id)
        let c = try store.createCollection(name: "Liste")
        try store.addToCollection(id: c.id, filmIds: [ids[2], ids[0]])
        try store.addToCollection(id: c.id, filmIds: [ids[0], ids[1]])
        XCTAssertEqual(try store.collections().first?.filmIds, [ids[2], ids[0], ids[1]])
        try store.removeFromCollection(id: c.id, filmIds: [ids[0]])
        XCTAssertEqual(try store.collections().first?.filmIds, [ids[2], ids[1]])
        try store.renameCollection(id: c.id, name: "Neu")
        XCTAssertEqual(try store.collections().first?.name, "Neu")
        try store.deleteCollection(id: c.id)
        XCTAssertTrue(try store.collections().isEmpty)
    }

    func testPlaybackHistoryAndFinished() throws {
        _ = try scan([found("a.mkv", 777)])
        let id = try XCTUnwrap(try store.films().first?.id)
        try store.savePosition(id: id, seconds: 100, fileSize: 777)
        XCTAssertEqual(try store.positionFileSize(id: id), 777)
        let entry = try store.recordPlay(id: id, at: t0)
        try store.updateHistory(entryId: entry, secondsWatched: 90)
        var f = try XCTUnwrap(try store.film(id: id))
        XCTAssertEqual(f.playCount, 1)
        XCTAssertEqual(f.lastPlayedAt, t0)
        try store.markFinishedAfterPlayback(id: id)
        f = try XCTUnwrap(try store.film(id: id))
        XCTAssertTrue(f.finished)
        XCTAssertEqual(f.positionSeconds, 0)
        let stats = try store.statistics(now: t0.addingTimeInterval(60))
        XCTAssertEqual(stats.totalPlays, 1)
        XCTAssertEqual(stats.totalSecondsWatched, 90)
        XCTAssertEqual(stats.playsLast30Days, 1)
        try store.clearPlayback(ids: [id])
        f = try XCTUnwrap(try store.film(id: id))
        XCTAssertNil(f.lastPlayedAt)
        XCTAssertEqual(try store.statistics().totalPlays, 0)
    }

    func testMetadataQueueOnlyForCurrentLocations() throws {
        _ = try scan([found("a.mkv"), found("b.mkv")])
        XCTAssertEqual(try store.filmsNeedingMetadata(currentVersion: 1, locationIds: [loc.id], limit: 10).count, 2)
        XCTAssertEqual(try store.filmsNeedingMetadata(currentVersion: 1, locationIds: [999], limit: 10).count, 0)
        let id = try XCTUnwrap(try store.films().first?.id)
        try store.updateMetadata(id: id, info: .empty, playability: .unsupported, version: 1)
        XCTAssertEqual(try store.filmsNeedingMetadata(currentVersion: 1, locationIds: [loc.id], limit: 10).count, 1)
        try store.updateCover(id: id, source: .videoFrame, stamp: 42)
        let f = try XCTUnwrap(try store.film(id: id))
        XCTAssertEqual(f.coverSource, .videoFrame)
        XCTAssertEqual(f.coverStamp, 42)
    }

    func testPersistenceOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fbstore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("Bibliothek.sqlite").path
        do {
            let s = try LibraryStore(path: path)
            let l = try s.insertLocation(StorageLocation(name: "SD", lastKnownPath: "/Volumes/SD", pathInVolume: "", volumeKey: "uuid:SD",
                                                         volumeName: "SD", kind: .removable, bookmark: nil))
            try s.apply(ScanDiff.compute(existing: [], found: [found("x.mp4")]), locationId: l.id, heartFavorites: false)
        }
        let reopened = try LibraryStore(path: path)
        XCTAssertEqual(try reopened.films().count, 1)
        XCTAssertEqual(try reopened.locations().first?.kind, .removable)
    }

    func testNewerSchemaIsRefused() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fbstore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("db.sqlite").path
        do {
            let c = try SQLiteConnection(path: path)
            try c.setUserVersion(99)
        }
        XCTAssertThrowsError(try LibraryStore(path: path))
    }

    func testConcurrentAccess() throws {
        _ = try scan((0..<200).map { found("f\($0).mkv") })
        let ids = try store.films().map(\.id)
        let s = store!
        DispatchQueue.concurrentPerform(iterations: 8) { i in
            for id in ids where Int(id) % 8 == i {
                try? s.savePosition(id: id, seconds: Double(id), fileSize: 100)
                _ = try? s.films()
            }
        }
        XCTAssertEqual(try store.films().filter { $0.positionSeconds > 0 }.count, 200)
    }
}
