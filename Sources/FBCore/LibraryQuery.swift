import Foundation

// =============================================================================================
// Suche, Filter und Sortierung der Bibliothek – reine Logik.
// =============================================================================================

/// UND-Suche mit Ausschlussbegriffen (Übertragung von FilmSearch.kt der Android-App):
///  - Die Anfrage wird an Leerraum in Begriffe zerlegt; leere Begriffe zählen nicht.
///  - Groß-/Kleinschreibung und Akzent-Zusammensetzung (NFC/NFD, häufig bei Mac-Dateinamen) spielen keine Rolle.
///  - Ein Film passt nur, wenn JEDER Begriff vorkommt (Reihenfolge egal).
///  - Neu für macOS: Ein Begriff mit „-“ davor schließt aus („alien -director“). Ein einzelnes „-“ zählt nicht.
///  - Begriffe in Anführungszeichen („"der pate"“) werden als zusammenhängender Text gesucht.
///  - Kein regulärer Ausdruck, keine Längengrenzen.
public struct SearchQuery: Equatable, Sendable {
    public let include: [String]
    public let exclude: [String]

    public var isEmpty: Bool { include.isEmpty && exclude.isEmpty }

    public init(_ text: String) {
        var inc: [String] = []
        var exc: [String] = []
        for raw in SearchQuery.tokenize(text) {
            if raw.count > 1 && raw.hasPrefix("-") {
                let t = SearchQuery.normalize(String(raw.dropFirst()))
                if !t.isEmpty && !exc.contains(t) { exc.append(t) }
            } else {
                let t = SearchQuery.normalize(raw)
                if !t.isEmpty && t != "-" && !inc.contains(t) { inc.append(t) }
            }
        }
        include = inc
        exclude = exc
    }

    /// Zerlegt an Leerraum; Anführungszeichen fassen zusammen.
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quoted = false
        for ch in text {
            if ch == "\"" || ch == "„" || ch == "“" || ch == "”" {
                if quoted {
                    if !current.isEmpty { tokens.append(current) }
                    current = ""
                    quoted = false
                } else {
                    // „-"…"“ schließt einen zusammenhängenden Text aus
                    quoted = true
                    if current != "-" && !current.isEmpty { tokens.append(current); current = "" }
                }
            } else if !quoted && ch.isWhitespace {
                if !current.isEmpty { tokens.append(current) }
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// Vergleichbare Form: Unicode-NFC + Kleinschreibung (sprachunabhängig).
    public static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// Prüft einen bereits normalisierten Suchtext.
    public func matches(normalized haystack: String) -> Bool {
        for term in include where !haystack.contains(term) { return false }
        for term in exclude where haystack.contains(term) { return false }
        return true
    }
}

/// Alles, worin gesucht wird: Titel, Dateiname, Endung, Ordner, Speicherort, technische Angaben.
public enum SearchIndex {
    public static func haystack(for film: Film, locationName: String) -> String {
        var parts: [String] = [film.title, film.fileName, film.fileExtension, film.folder, locationName]
        if let y = TitleCleaner.year(forFileName: film.fileName) { parts.append(String(y)) }
        if let r = film.resolutionClass { parts.append(r.label) }
        if let w = film.info.width, let h = film.info.height { parts.append("\(w)x\(h)") }
        if let v = film.info.videoCodec { parts.append(v) }
        if let a = film.info.audioCodec { parts.append(a) }
        if let t = film.info.embeddedTitle { parts.append(t) }
        if film.isFavorite { parts.append("favorit") }
        return SearchQuery.normalize(parts.joined(separator: " \u{1F} "))
    }
}

// MARK: - Filter

public enum SizeFilter: String, CaseIterable, Sendable, Codable {
    case any, under1GB, from1GB, from2GB, from4GB, from10GB

    public var label: String {
        switch self {
        case .any: return "Alle Größen"
        case .under1GB: return "Unter 1 GB"
        case .from1GB: return "Ab 1 GB"
        case .from2GB: return "Ab 2 GB"
        case .from4GB: return "Ab 4 GB"
        case .from10GB: return "Ab 10 GB"
        }
    }

    public func matches(_ bytes: Int64) -> Bool {
        let gb: Int64 = 1_000_000_000
        switch self {
        case .any: return true
        case .under1GB: return bytes < gb
        case .from1GB: return bytes >= gb
        case .from2GB: return bytes >= 2 * gb
        case .from4GB: return bytes >= 4 * gb
        case .from10GB: return bytes >= 10 * gb
        }
    }
}

public enum DurationFilter: String, CaseIterable, Sendable, Codable {
    case any, under30, from30to90, from90to150, over150

    public var label: String {
        switch self {
        case .any: return "Alle Laufzeiten"
        case .under30: return "Unter 30 Min."
        case .from30to90: return "30–90 Min."
        case .from90to150: return "90–150 Min."
        case .over150: return "Über 150 Min."
        }
    }

    /// Filme ohne bekannte Dauer passen nur zu „Alle“.
    public func matches(_ seconds: Double?) -> Bool {
        if self == .any { return true }
        guard let s = seconds, s > 0 else { return false }
        let m = s / 60
        switch self {
        case .any: return true
        case .under30: return m < 30
        case .from30to90: return m >= 30 && m < 90
        case .from90to150: return m >= 90 && m < 150
        case .over150: return m >= 150
        }
    }
}

public enum AvailabilityFilter: String, CaseIterable, Sendable, Codable {
    case any, available, unavailable

    public var label: String {
        switch self {
        case .any: return "Alle"
        case .available: return "Nur verfügbare"
        case .unavailable: return "Nur nicht verfügbare"
        }
    }
}

/// Kombinierbare Filter (Werkzeugleiste „Filter“ und Chips).
public struct LibraryFilter: Equatable, Sendable, Codable {
    public var locationIds: Set<Int64> = []
    public var extensions: Set<String> = []
    public var resolutions: Set<ResolutionClass> = []
    public var size: SizeFilter = .any
    public var duration: DurationFilter = .any
    public var favoritesOnly = false
    public var playback: Set<PlaybackStatus> = []
    public var availability: AvailabilityFilter = .any

    public init() {}

    public var isEmpty: Bool { self == LibraryFilter() }

    /// Anzahl aktiver Filtergruppen (für das Abzeichen am Filter-Knopf)
    public var activeCount: Int {
        var n = 0
        if !locationIds.isEmpty { n += 1 }
        if !extensions.isEmpty { n += 1 }
        if !resolutions.isEmpty { n += 1 }
        if size != .any { n += 1 }
        if duration != .any { n += 1 }
        if favoritesOnly { n += 1 }
        if !playback.isEmpty { n += 1 }
        if availability != .any { n += 1 }
        return n
    }

    public func matches(_ film: Film, isAvailable: Bool) -> Bool {
        if !locationIds.isEmpty && !locationIds.contains(film.locationId) { return false }
        if !extensions.isEmpty && !extensions.contains(film.fileExtension) { return false }
        if !resolutions.isEmpty {
            guard let r = film.resolutionClass, resolutions.contains(r) else { return false }
        }
        if !size.matches(film.sizeBytes) { return false }
        if !duration.matches(film.info.durationSeconds) { return false }
        if favoritesOnly && !film.isFavorite { return false }
        if !playback.isEmpty && !playback.contains(film.playbackStatus) { return false }
        switch availability {
        case .any: break
        case .available: if !isAvailable { return false }
        case .unavailable: if isAvailable { return false }
        }
        return true
    }
}

// MARK: - Sortierung

public enum SortKey: String, CaseIterable, Sendable, Codable {
    case title, fileName, dateAdded, dateModified, size, duration, resolution, lastPlayed, format

    public var label: String {
        switch self {
        case .title: return "Titel"
        case .fileName: return "Dateiname"
        case .dateAdded: return "Hinzugefügt"
        case .dateModified: return "Geändert"
        case .size: return "Größe"
        case .duration: return "Laufzeit"
        case .resolution: return "Auflösung"
        case .lastPlayed: return "Zuletzt abgespielt"
        case .format: return "Format"
        }
    }

    /// Natürliche Richtung beim ersten Wählen (Datum/Größe: Neueste/Größte zuerst)
    public var defaultAscending: Bool {
        switch self {
        case .title, .fileName, .format: return true
        default: return false
        }
    }
}

public struct SortOrder: Equatable, Sendable, Codable {
    public var key: SortKey
    public var ascending: Bool

    public init(key: SortKey = .title, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }
}

public enum LibrarySorter {
    /// Natürlicher Textvergleich („Folge 2“ vor „Folge 10“), sprachbewusst, ohne Groß-/Kleinschreibung.
    public static func compareText(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [.caseInsensitive, .numeric, .diacriticInsensitive, .widthInsensitive], range: nil, locale: Locale(identifier: "de_DE"))
    }

    public static func sort(_ films: [Film], by order: SortOrder) -> [Film] {
        films.sorted { a, b in
            let r = compare(a, b, key: order.key)
            if r != .orderedSame { return order.ascending ? r == .orderedAscending : r == .orderedDescending }
            // Stabil und eindeutig: danach Titel, dann Pfad, dann ID
            let t = compareText(a.title, b.title)
            if t != .orderedSame { return t == .orderedAscending }
            let p = compareText(a.relativePath, b.relativePath)
            if p != .orderedSame { return p == .orderedAscending }
            return a.id < b.id
        }
    }

    static func compare(_ a: Film, _ b: Film, key: SortKey) -> ComparisonResult {
        switch key {
        case .title: return compareText(a.title, b.title)
        case .fileName: return compareText(a.fileName, b.fileName)
        case .format: return compareText(a.fileExtension, b.fileExtension)
        case .dateAdded: return cmp(a.addedAt, b.addedAt)
        case .dateModified: return cmpOpt(a.modifiedAt, b.modifiedAt)
        case .size: return cmp(a.sizeBytes, b.sizeBytes)
        case .duration: return cmpOpt(a.info.durationSeconds, b.info.durationSeconds)
        case .resolution: return cmp((a.info.width ?? 0) * (a.info.height ?? 0), (b.info.width ?? 0) * (b.info.height ?? 0))
        case .lastPlayed: return cmpOpt(a.lastPlayedAt, b.lastPlayedAt)
        }
    }

    static func cmp<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }

    /// Fehlende Werte gelten als „kleinster“ Wert (stehen absteigend am Ende)
    static func cmpOpt<T: Comparable>(_ a: T?, _ b: T?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case let (x?, y?): return cmp(x, y)
        }
    }
}

// MARK: - Bereiche der Seitenleiste

/// Was im Inhaltsbereich gezeigt wird.
public enum LibraryScope: Hashable, Sendable {
    case all
    case continueWatching
    case recentlyAdded
    case recentlyPlayed
    case favorites
    case unavailable
    case collection(Int64)
    case location(Int64)
    /// Ordner innerhalb eines Speicherorts ("" = oberste Ebene)
    case folder(location: Int64, path: String)

    /// Wie viele Tage „Zuletzt hinzugefügt“ zurückreicht
    public static let recentlyAddedDays = 30

    public func contains(_ film: Film, collections: [Int64: Set<Int64>], isAvailable: Bool, now: Date = Date()) -> Bool {
        switch self {
        case .all: return true
        case .continueWatching: return film.playbackStatus == .inProgress
        case .recentlyAdded:
            return film.addedAt >= now.addingTimeInterval(-Double(LibraryScope.recentlyAddedDays) * 86_400)
        case .recentlyPlayed: return film.lastPlayedAt != nil
        case .favorites: return film.isFavorite
        case .unavailable: return !isAvailable
        case .collection(let id): return collections[id]?.contains(film.id) ?? false
        case .location(let id): return film.locationId == id
        case .folder(let loc, let path):
            guard film.locationId == loc else { return false }
            return path.isEmpty || film.folder == path || film.folder.hasPrefix(path + "/")
        }
    }

    /// Feste Sortierung, die in diesem Bereich sinnvoll ist (nil = Nutzerauswahl gilt)
    public var impliedSort: SortOrder? {
        switch self {
        case .recentlyAdded: return SortOrder(key: .dateAdded, ascending: false)
        case .recentlyPlayed, .continueWatching: return SortOrder(key: .lastPlayed, ascending: false)
        default: return nil
        }
    }
}
