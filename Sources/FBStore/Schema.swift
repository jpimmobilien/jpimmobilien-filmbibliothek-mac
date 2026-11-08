import Foundation

/// Datenbankschema und Migrationen. `PRAGMA user_version` enthält die Schemaversion.
///
/// Grundsätze:
///  - Die Datenbank ist ein Index; Videodateien werden nie verändert.
///  - Filme werden NIE automatisch gelöscht. Nur zwei bewusste Nutzeraktionen entfernen Einträge:
///    „Speicherort entfernen“ und „Fehlende Einträge entfernen“ (jeweils mit Bestätigung).
///  - Favoriten, Fortschritt, Verlauf und Sammlungen hängen an der dauerhaften Film-ID.
enum Schema {
    static let currentVersion = 1

    static func migrate(_ db: SQLiteConnection) throws {
        let version = db.userVersion
        if version > currentVersion {
            throw SQLiteError(code: -1, message: "Die Datenbank stammt von einer neueren App-Version (Schema \(version)). Bitte die neueste Filmbibliothek installieren.", sql: nil)
        }
        if version < 1 {
            try db.transaction {
                try db.execute(v1)
                try db.setUserVersion(1)
            }
        }
    }

    static let v1 = """
    CREATE TABLE IF NOT EXISTS locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        lastKnownPath TEXT NOT NULL,
        pathInVolume TEXT NOT NULL,
        volumeKey TEXT NOT NULL,
        volumeName TEXT NOT NULL,
        kind TEXT NOT NULL,
        bookmark BLOB,
        addedAt REAL NOT NULL,
        lastScanAt REAL,
        lastSeenAt REAL,
        UNIQUE(volumeKey, pathInVolume)
    );

    CREATE TABLE IF NOT EXISTS films (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        locationId INTEGER NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
        relativePath TEXT NOT NULL,
        sizeBytes INTEGER NOT NULL DEFAULT 0,
        modifiedAt REAL,
        createdAt REAL,
        addedAt REAL NOT NULL,
        fileId INTEGER,
        durationSeconds REAL,
        width INTEGER,
        height INTEGER,
        frameRate REAL,
        videoCodec TEXT,
        audioCodec TEXT,
        audioTrackCount INTEGER NOT NULL DEFAULT 0,
        subtitleTrackCount INTEGER NOT NULL DEFAULT 0,
        chapterCount INTEGER NOT NULL DEFAULT 0,
        bitRate INTEGER,
        embeddedTitle TEXT,
        metadataVersion INTEGER NOT NULL DEFAULT 0,
        playability INTEGER NOT NULL DEFAULT 0,
        coverSource INTEGER NOT NULL DEFAULT 0,
        coverStamp INTEGER NOT NULL DEFAULT 0,
        isFavorite INTEGER NOT NULL DEFAULT 0,
        heartApplied INTEGER NOT NULL DEFAULT 0,
        positionSeconds REAL NOT NULL DEFAULT 0,
        positionSize INTEGER,
        finished INTEGER NOT NULL DEFAULT 0,
        lastPlayedAt REAL,
        playCount INTEGER NOT NULL DEFAULT 0,
        isMissing INTEGER NOT NULL DEFAULT 0,
        missingSince REAL,
        UNIQUE(locationId, relativePath)
    );
    CREATE INDEX IF NOT EXISTS films_location ON films(locationId);
    CREATE INDEX IF NOT EXISTS films_metadata ON films(metadataVersion);

    CREATE TABLE IF NOT EXISTS collections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        createdAt REAL NOT NULL
    );

    CREATE TABLE IF NOT EXISTS collection_items (
        collectionId INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
        filmId INTEGER NOT NULL REFERENCES films(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        addedAt REAL NOT NULL,
        PRIMARY KEY(collectionId, filmId)
    );

    CREATE TABLE IF NOT EXISTS play_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        filmId INTEGER NOT NULL REFERENCES films(id) ON DELETE CASCADE,
        playedAt REAL NOT NULL,
        secondsWatched REAL NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS play_history_film ON play_history(filmId);

    CREATE TABLE IF NOT EXISTS app_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    """
}
