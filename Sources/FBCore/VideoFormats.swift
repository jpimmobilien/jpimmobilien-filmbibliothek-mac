import Foundation

/// Videoformate, die die App beim Durchsuchen erkennt.
///
/// Ehrlich: Die Endung sagt nur, WELCHE Dateien aufgenommen werden. Ob eine Datei tatsächlich abspielbar ist,
/// entscheidet die Metadaten-Prüfung zur Laufzeit (AVFoundation bzw. VLCKit öffnen die Datei wirklich) –
/// siehe `Playability`. Die bevorzugte Engine je Endung ist nur der erste Versuch.
public enum VideoFormats {

    public struct Format: Hashable, Sendable {
        public let ext: String
        public let name: String
        /// Wird zuerst mit AVFoundation versucht (Apple-Container MP4/MOV/M4V/3GP)
        public let prefersAVFoundation: Bool
    }

    /// Die 13 geforderten Formate plus wenige verwandte Endungen (3GP, OGV, VOB, DIVX, ASF).
    public static let all: [Format] = [
        Format(ext: "mp4", name: "MPEG-4", prefersAVFoundation: true),
        Format(ext: "m4v", name: "MPEG-4 (iTunes)", prefersAVFoundation: true),
        Format(ext: "mov", name: "QuickTime", prefersAVFoundation: true),
        Format(ext: "mkv", name: "Matroska", prefersAVFoundation: false),
        Format(ext: "avi", name: "AVI", prefersAVFoundation: false),
        Format(ext: "wmv", name: "Windows Media", prefersAVFoundation: false),
        Format(ext: "mpg", name: "MPEG", prefersAVFoundation: false),
        Format(ext: "mpeg", name: "MPEG", prefersAVFoundation: false),
        Format(ext: "ts", name: "MPEG-Transportstrom", prefersAVFoundation: false),
        Format(ext: "mts", name: "AVCHD", prefersAVFoundation: false),
        Format(ext: "m2ts", name: "Blu-ray-Transportstrom", prefersAVFoundation: false),
        Format(ext: "webm", name: "WebM", prefersAVFoundation: false),
        Format(ext: "flv", name: "Flash Video", prefersAVFoundation: false),
        Format(ext: "3gp", name: "3GPP", prefersAVFoundation: true),
        Format(ext: "ogv", name: "Ogg Video", prefersAVFoundation: false),
        Format(ext: "vob", name: "DVD-Video", prefersAVFoundation: false),
        Format(ext: "divx", name: "DivX", prefersAVFoundation: false),
        Format(ext: "asf", name: "ASF", prefersAVFoundation: false),
    ]

    private static let byExt: [String: Format] = Dictionary(uniqueKeysWithValues: all.map { ($0.ext, $0) })

    /// Endungen, die beim Durchsuchen aufgenommen werden.
    public static let extensions: Set<String> = Set(all.map(\.ext))

    public static func isVideo(fileName: String) -> Bool {
        extensions.contains(RelativePath.fileExtension(fileName))
    }

    public static func format(forExtension ext: String) -> Format? { byExt[ext.lowercased()] }

    public static func prefersAVFoundation(_ ext: String) -> Bool { byExt[ext.lowercased()]?.prefersAVFoundation ?? false }

    /// Anzeige der Endung, z. B. "MKV"
    public static func label(_ ext: String) -> String { ext.uppercased() }

    /// Untertiteldateien neben dem Video
    public static let subtitleExtensions: Set<String> = ["srt", "vtt", "ass", "ssa", "sub", "idx", "smi"]
    /// Bilder als Poster
    public static let imageExtensions: [String] = ["jpg", "jpeg", "png", "webp", "heic", "tif", "tiff"]
}

/// Auflösungsklassen (wie in der Android-App: 8K, 4K, Full HD, HD, SD).
public enum ResolutionClass: Int, CaseIterable, Comparable, Sendable, Codable {
    case sd = 0, hd = 1, fullHD = 2, uhd4k = 3, uhd8k = 4

    public init?(width: Int?, height: Int?) {
        guard let w = width, let h = height, w > 0, h > 0 else { return nil }
        // Hochformat-Videos nach der langen bzw. kurzen Seite einordnen
        let long = max(w, h), short = min(w, h)
        if long >= 7000 || short >= 4000 { self = .uhd8k }
        else if long >= 3200 || short >= 2000 { self = .uhd4k }
        else if long >= 1800 || short >= 1000 { self = .fullHD }
        else if long >= 1200 || short >= 700 { self = .hd }
        else { self = .sd }
    }

    public static func < (a: ResolutionClass, b: ResolutionClass) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .sd: return "SD"
        case .hd: return "HD"
        case .fullHD: return "Full HD"
        case .uhd4k: return "4K"
        case .uhd8k: return "8K"
        }
    }
}

/// Pfade relativ zu einem Speicherort – immer mit „/“, ohne führenden Schrägstrich, nie mit „..“.
public enum RelativePath {
    public static func lastComponent(_ path: String) -> String {
        if let i = path.lastIndex(of: "/") { return String(path[path.index(after: i)...]) }
        return path
    }

    public static func parent(_ path: String) -> String {
        if let i = path.lastIndex(of: "/") { return String(path[..<i]) }
        return ""
    }

    /// Endung in Kleinbuchstaben ohne Punkt ("" wenn keine). ".DS_Store" hat keine Endung.
    public static func fileExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    /// Name ohne Endung
    public static func stem(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }

    /// Pfad `child` relativ zu `root` (beide absolut, normalisiert). nil, wenn `child` nicht unter `root` liegt.
    public static func relative(_ child: String, to root: String) -> String? {
        let r = trimSlashes(root)
        let c = trimSlashes(child)
        if r.isEmpty { return c }
        if c == r { return "" }
        guard c.hasPrefix(r + "/") else { return nil }
        let rel = String(c.dropFirst(r.count + 1))
        return isSafe(rel) ? rel : nil
    }

    /// Fügt einen relativen Pfad an eine Wurzel an. nil bei unsicheren Pfaden („..“).
    public static func join(_ root: String, _ relative: String) -> String? {
        guard isSafe(relative) else { return nil }
        if relative.isEmpty { return root }
        return root.hasSuffix("/") ? root + relative : root + "/" + relative
    }

    /// Kein „..“, kein führender „/“, keine leeren Teile.
    public static func isSafe(_ relative: String) -> Bool {
        if relative.isEmpty { return true }
        if relative.hasPrefix("/") { return false }
        for part in relative.split(separator: "/", omittingEmptySubsequences: false) {
            if part.isEmpty || part == ".." || part == "." { return false }
        }
        return true
    }

    private static func trimSlashes(_ p: String) -> String {
        var s = p
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        if s == "/" { return "" }
        if s.hasPrefix("/") { s.removeFirst() }
        return s
    }

    /// Zerlegt einen Ordnerpfad in seine Teile (für Brotkrumen)
    public static func components(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }
}

/// Dateien und Ordner, die beim Durchsuchen übersprungen werden.
public enum ScanRules {
    /// Ordner, die nie durchsucht werden (System, Papierkörbe, NAS-Hilfsordner)
    public static let skippedDirectoryNames: Set<String> = [
        ".Trashes", ".Trash", ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100", ".TemporaryItems",
        ".AppleDouble", ".AppleDB", ".AppleDesktop", "$RECYCLE.BIN", "System Volume Information",
        "@eaDir", "#recycle", "#snapshot", ".@__thumb", "lost+found", ".vol", "Network Trash Folder",
        "Temporary Items", ".PKInstallSandboxManager", ".MobileBackups",
    ]

    /// Datei überspringen? (versteckte Dateien, AppleDouble-Begleitdateien „._Name“ auf FAT/exFAT/NAS)
    public static func skipFile(named name: String) -> Bool {
        name.hasPrefix(".") || name.hasPrefix("~$")
    }

    /// Ordner überspringen? (versteckte Ordner und die Liste oben)
    public static func skipDirectory(named name: String) -> Bool {
        name.hasPrefix(".") || skippedDirectoryNames.contains(name)
    }

    /// Teilweise geladene/kopierte Dateien anderer Programme
    public static let partialSuffixes = [".part", ".crdownload", ".download", ".partial", ".filmbibliothek-teil"]

    public static func isPartialDownload(_ name: String) -> Bool {
        let lower = name.lowercased()
        return partialSuffixes.contains { lower.hasSuffix($0) }
    }
}
