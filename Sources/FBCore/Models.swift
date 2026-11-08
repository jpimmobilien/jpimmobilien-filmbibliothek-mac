import Foundation

// =============================================================================================
// Grundmodelle der Filmbibliothek.
//
// Grundsätze (wie in der Android-App):
//  - Videodateien bleiben, wo sie sind. Die App liest sie nur; die Datenbank ist ein Index.
//  - Ein Film gehört zu einem Speicherort und wird über seinen Pfad RELATIV zum Speicherort geführt.
//    Dadurch bleibt alles erhalten, wenn ein Laufwerk unter einem anderen Pfad eingebunden wird
//    (z. B. „/Volumes/Filme 1“ statt „/Volumes/Filme“).
//  - Nichts wird automatisch gelöscht: Fehlt ein Laufwerk, sind seine Filme „nicht verfügbar“;
//    fehlt eine Datei auf einem vorhandenen Laufwerk, ist sie „Datei fehlt“.
// =============================================================================================

/// Art des Datenträgers, auf dem ein Speicherort liegt (nur für Anzeige und Hinweise).
public enum LocationKind: String, Codable, Sendable, CaseIterable {
    /// Interne SSD/Festplatte des Macs
    case internalDisk = "internal"
    /// Externe SSD/Festplatte (USB, Thunderbolt)
    case externalDisk = "external"
    /// Wechseldatenträger: USB-Stick, SD-Karte
    case removable = "removable"
    /// Netzlaufwerk (SMB/AFP/NFS, z. B. NAS)
    case network = "network"
    case unknown = "unknown"

    public var label: String {
        switch self {
        case .internalDisk: return "Interner Speicher"
        case .externalDisk: return "Externes Laufwerk"
        case .removable: return "Wechseldatenträger"
        case .network: return "Netzlaufwerk"
        case .unknown: return "Speicherort"
        }
    }

    /// SF-Symbol-Name
    public var symbol: String {
        switch self {
        case .internalDisk: return "internaldrive"
        case .externalDisk: return "externaldrive"
        case .removable: return "sdcard"
        case .network: return "server.rack"
        case .unknown: return "folder"
        }
    }
}

/// Ein vom Nutzer hinzugefügter Speicherort (Ordner oder ganzes Laufwerk).
public struct StorageLocation: Identifiable, Hashable, Sendable {
    public var id: Int64
    /// Anzeigename (Standard: Ordnername bzw. Laufwerksname)
    public var name: String
    /// Zuletzt bekannter absoluter Pfad (nur Hinweis – maßgeblich ist das Lesezeichen)
    public var lastKnownPath: String
    /// Pfad des Ordners relativ zur Wurzel seines Laufwerks ("" = ganzes Laufwerk)
    public var pathInVolume: String
    /// Kennung des Laufwerks (siehe `VolumeIdentity.key`)
    public var volumeKey: String
    public var volumeName: String
    public var kind: LocationKind
    /// Sicherheitsgeschütztes Lesezeichen (Sandbox) – nil, wenn (noch) keines erstellt werden konnte
    public var bookmark: Data?
    public var addedAt: Date
    public var lastScanAt: Date?
    /// Zuletzt erreichbar (für „zuletzt gesehen vor …“)
    public var lastSeenAt: Date?

    public init(id: Int64 = 0, name: String, lastKnownPath: String, pathInVolume: String, volumeKey: String,
                volumeName: String, kind: LocationKind, bookmark: Data?, addedAt: Date = Date(),
                lastScanAt: Date? = nil, lastSeenAt: Date? = nil) {
        self.id = id
        self.name = name
        self.lastKnownPath = lastKnownPath
        self.pathInVolume = pathInVolume
        self.volumeKey = volumeKey
        self.volumeName = volumeName
        self.kind = kind
        self.bookmark = bookmark
        self.addedAt = addedAt
        self.lastScanAt = lastScanAt
        self.lastSeenAt = lastSeenAt
    }

    /// Ganzes Laufwerk statt eines Ordners darauf?
    public var isWholeVolume: Bool { pathInVolume.isEmpty }
}

/// Erreichbarkeit eines Speicherorts zur Laufzeit.
public enum LocationAvailability: Equatable, Sendable {
    /// Erreichbar und lesbar
    case available
    /// Laufwerk ist nicht angeschlossen bzw. Netzlaufwerk nicht verbunden
    case offline
    /// Laufwerk ist da, aber macOS erlaubt den Zugriff nicht (mehr) – Nutzer muss ihn erneut erteilen
    case noAccess(String)
    /// Laufwerk ist da, der Ordner aber nicht (umbenannt/gelöscht)
    case folderMissing
    /// Noch nicht geprüft (App-Start)
    case unknown

    public var isAvailable: Bool { self == .available }

    public var label: String {
        switch self {
        case .available: return "Verfügbar"
        case .offline: return "Nicht verfügbar"
        case .noAccess: return "Kein Zugriff"
        case .folderMissing: return "Ordner nicht gefunden"
        case .unknown: return "Wird geprüft …"
        }
    }
}

/// Wie die App eine Datei abspielt (aus Metadaten-Prüfung).
public enum Playability: Int, Codable, Sendable {
    /// Noch nicht geprüft
    case unknown = 0
    /// AVFoundation kann die Datei öffnen (Standard-Engine)
    case native = 1
    /// Nur mit VLCKit abspielbar
    case vlc = 2
    /// Keine der Engines kann die Datei öffnen (beschädigt oder nicht unterstütztes Format)
    case unsupported = 3

    public var label: String {
        switch self {
        case .unknown: return "Noch nicht geprüft"
        case .native: return "AVFoundation (macOS)"
        case .vlc: return "VLCKit"
        case .unsupported: return "Nicht abspielbar"
        }
    }
}

/// Herkunft des Titelbilds.
public enum CoverSource: Int, Codable, Sendable {
    case none = 0
    /// In die Datei eingebettetes Bild (z. B. MP4-„covr“, MKV-Anhang)
    case embedded = 1
    /// Posterdatei im Ordner (poster.jpg, Film.jpg …)
    case posterFile = 2
    /// Automatisch aus dem Video erzeugtes Bild
    case videoFrame = 3
    /// Zuletzt gesehenes Bild (Android-Funktion „Titelbild = zuletzt gesehenes Bild“)
    case lastFrame = 4

    public var label: String {
        switch self {
        case .none: return "Kein Titelbild"
        case .embedded: return "Eingebettetes Cover"
        case .posterFile: return "Posterdatei im Ordner"
        case .videoFrame: return "Bild aus dem Video"
        case .lastFrame: return "Zuletzt gesehenes Bild"
        }
    }
}

/// Technische Angaben aus dem Video (Metadaten-Prüfung).
public struct VideoInfo: Hashable, Sendable, Codable {
    public var durationSeconds: Double?
    public var width: Int?
    public var height: Int?
    public var frameRate: Double?
    public var videoCodec: String?
    public var audioCodec: String?
    public var audioTrackCount: Int
    public var subtitleTrackCount: Int
    public var chapterCount: Int
    public var bitRate: Int?
    /// Titel aus den Metadaten der Datei (falls vorhanden)
    public var embeddedTitle: String?

    public init(durationSeconds: Double? = nil, width: Int? = nil, height: Int? = nil, frameRate: Double? = nil,
                videoCodec: String? = nil, audioCodec: String? = nil, audioTrackCount: Int = 0,
                subtitleTrackCount: Int = 0, chapterCount: Int = 0, bitRate: Int? = nil, embeddedTitle: String? = nil) {
        self.durationSeconds = durationSeconds
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.audioTrackCount = audioTrackCount
        self.subtitleTrackCount = subtitleTrackCount
        self.chapterCount = chapterCount
        self.bitRate = bitRate
        self.embeddedTitle = embeddedTitle
    }

    public static let empty = VideoInfo()
}

/// Ein Film (eine Videodatei) in der Bibliothek.
public struct Film: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var locationId: Int64
    /// Pfad relativ zum Speicherort, mit „/“ getrennt, z. B. "Sci-Fi/Alien (1979).mkv"
    public var relativePath: String
    public var fileName: String
    /// Endung in Kleinbuchstaben ohne Punkt, z. B. "mkv"
    public var fileExtension: String
    public var sizeBytes: Int64
    public var modifiedAt: Date?
    public var createdAt: Date?
    /// Wann die App die Datei zum ersten Mal gefunden hat
    public var addedAt: Date

    // Metadaten
    public var info: VideoInfo
    public var metadataVersion: Int
    public var playability: Playability
    public var coverSource: CoverSource
    /// Zeitstempel des Titelbilds im Cache (ändert sich bei neuem Bild → Neu laden in der Oberfläche)
    public var coverStamp: Int64

    // Nutzerdaten
    public var isFavorite: Bool
    public var positionSeconds: Double
    public var finished: Bool
    public var lastPlayedAt: Date?
    public var playCount: Int

    /// Datei fehlt auf dem (erreichbaren) Speicherort
    public var isMissing: Bool
    public var missingSince: Date?

    public init(id: Int64 = 0, locationId: Int64, relativePath: String, sizeBytes: Int64, modifiedAt: Date?,
                createdAt: Date? = nil, addedAt: Date = Date(), info: VideoInfo = .empty, metadataVersion: Int = 0,
                playability: Playability = .unknown, coverSource: CoverSource = .none, coverStamp: Int64 = 0,
                isFavorite: Bool = false, positionSeconds: Double = 0, finished: Bool = false,
                lastPlayedAt: Date? = nil, playCount: Int = 0, isMissing: Bool = false, missingSince: Date? = nil) {
        self.id = id
        self.locationId = locationId
        self.relativePath = relativePath
        let name = RelativePath.lastComponent(relativePath)
        self.fileName = name
        self.fileExtension = RelativePath.fileExtension(name)
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
        self.addedAt = addedAt
        self.info = info
        self.metadataVersion = metadataVersion
        self.playability = playability
        self.coverSource = coverSource
        self.coverStamp = coverStamp
        self.isFavorite = isFavorite
        self.positionSeconds = positionSeconds
        self.finished = finished
        self.lastPlayedAt = lastPlayedAt
        self.playCount = playCount
        self.isMissing = isMissing
        self.missingSince = missingSince
    }

    /// Anzeigetitel (aus dem Dateinamen, siehe `TitleCleaner`)
    public var title: String { TitleCleaner.title(forFileName: fileName) }

    /// Ordner relativ zum Speicherort ("" = oberste Ebene)
    public var folder: String { RelativePath.parent(relativePath) }

    /// Fortschritt 0…1 (nil = nie angefangen bzw. Dauer unbekannt)
    public var progress: Double? { ResumePolicy.displayProgress(position: positionSeconds, duration: info.durationSeconds) }

    public var playbackStatus: PlaybackStatus {
        if finished { return .finished }
        if ResumePolicy.isInProgress(position: positionSeconds, duration: info.durationSeconds) { return .inProgress }
        return .unwatched
    }

    public var resolutionClass: ResolutionClass? { ResolutionClass(width: info.width, height: info.height) }
}

/// Wiedergabestatus eines Films (Filter „Wiedergabestatus“).
public enum PlaybackStatus: String, CaseIterable, Sendable, Codable {
    case unwatched, inProgress, finished

    public var label: String {
        switch self {
        case .unwatched: return "Nicht angesehen"
        case .inProgress: return "Angefangen"
        case .finished: return "Gesehen"
        }
    }
}

/// Eigene Sammlung (Android: „Sammlungen“).
public struct FilmCollection: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var name: String
    public var createdAt: Date
    public var filmIds: [Int64]

    public init(id: Int64 = 0, name: String, createdAt: Date = Date(), filmIds: [Int64] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.filmIds = filmIds
    }
}
