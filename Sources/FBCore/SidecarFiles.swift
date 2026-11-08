import Foundation

/// Begleitdateien neben einem Film: Posterbilder und Untertitel.
///
/// Poster (in dieser Reihenfolge, Groß-/Kleinschreibung egal):
///   1. „<Film>-poster.jpg“, „<Film>.poster.jpg“, „<Film>.jpg“ (auch .jpeg/.png/.webp/.heic) – gehört eindeutig zum Film
///   2. „poster.jpg“, „folder.jpg“, „cover.jpg“, „movie.jpg“ im Ordner – NUR, wenn der Ordner genau einen Film enthält
///      (Kodi/Plex/Jellyfin-Aufbau „ein Ordner je Film“); sonst gehört das Bild zum Ordner, nicht zu jedem Film darin.
public enum SidecarFiles {

    public static let folderPosterNames = ["poster", "folder", "cover", "movie", "default"]

    /// Bester Poster-Kandidat aus den Dateinamen eines Ordners.
    /// - Parameters:
    ///   - filmFileName: Dateiname des Films
    ///   - siblingNames: alle Dateinamen im selben Ordner
    ///   - videosInFolder: Anzahl der Videos im Ordner
    public static func posterCandidate(filmFileName: String, siblingNames: [String], videosInFolder: Int) -> String? {
        let stem = RelativePath.stem(filmFileName).lowercased()
        var byLower: [String: String] = [:]
        for n in siblingNames { byLower[n.lowercased()] = byLower[n.lowercased()] ?? n }
        let exts = VideoFormats.imageExtensions
        for pattern in ["\(stem)-poster", "\(stem).poster", "\(stem)"] {
            for e in exts {
                if let hit = byLower["\(pattern).\(e)"] { return hit }
            }
        }
        guard videosInFolder == 1 else { return nil }
        for base in folderPosterNames {
            for e in exts {
                if let hit = byLower["\(base).\(e)"] { return hit }
            }
        }
        return nil
    }

    /// Untertiteldateien zum Film: „Film.srt“, „Film.de.srt“, „Film.deu.forced.srt“ …
    public static func subtitleCandidates(filmFileName: String, siblingNames: [String]) -> [String] {
        let stem = RelativePath.stem(filmFileName).lowercased()
        return siblingNames.filter { name in
            let lower = name.lowercased()
            let ext = RelativePath.fileExtension(lower)
            guard VideoFormats.subtitleExtensions.contains(ext), ext != "idx" else { return false }
            let base = RelativePath.stem(lower)
            return base == stem || base.hasPrefix(stem + ".")
        }.sorted { LibrarySorter.compareText($0, $1) == .orderedAscending }
    }

    /// Sprache aus dem Untertitel-Dateinamen („Film.de.srt“ → "de"), nil wenn keine
    public static func subtitleLanguage(fileName: String, filmFileName: String) -> String? {
        let stem = RelativePath.stem(filmFileName)
        let base = RelativePath.stem(fileName)
        guard base.count > stem.count + 1 else { return nil }
        let rest = base.dropFirst(stem.count + 1)
        return rest.split(separator: ".").first.map(String.init)
    }
}

/// Ein Untertitel-Eintrag.
public struct SubtitleCue: Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let text: String
}

/// Einfacher, robuster Leser für SRT und WebVTT (für AVFoundation, das externe Untertitel nicht selbst lädt).
/// VLCKit lädt externe Untertitel selbst (auch ASS/SSA).
public enum SubtitleParser {
    public static func parse(_ text: String) -> [SubtitleCue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []
        let blocks = normalized.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timeIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTime(parts[0]),
                  let end = parseTime(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "") else { continue }
            let body = lines[(timeIndex + 1)...].joined(separator: "\n")
            let clean = stripTags(body).trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty && end > start { cues.append(SubtitleCue(start: start, end: end, text: clean)) }
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// „00:01:02,500“, „01:02.500“, „00:01:02.5“
    public static func parseTime(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = s.split(separator: ":").map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var total = 0.0
        for (i, p) in parts.enumerated() {
            guard let v = Double(p), v >= 0 else { return nil }
            if i == parts.count - 1 { total += v } else { total = (total + v) * 60 }
        }
        if parts.count == 3 {
            // h:m:s – oben wurde (h*60 + m)*60 gerechnet
        }
        return total
    }

    static func stripTags(_ s: String) -> String {
        var out = ""
        var inTag = false
        var inBrace = false
        for ch in s {
            if ch == "<" { inTag = true; continue }
            if ch == ">" && inTag { inTag = false; continue }
            if ch == "{" { inBrace = true; continue }
            if ch == "}" && inBrace { inBrace = false; continue }
            if !inTag && !inBrace { out.append(ch) }
        }
        return out
    }

    /// Text zur Zeit `t` (mehrere gleichzeitige Einträge untereinander)
    public static func text(at t: Double, in cues: [SubtitleCue]) -> String? {
        // Binäre Suche nach dem letzten Eintrag mit start <= t
        var lo = 0, hi = cues.count - 1, idx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if cues[mid].start <= t { idx = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard idx >= 0 else { return nil }
        var lines: [String] = []
        var i = idx
        // Überlappende frühere Einträge mitnehmen (höchstens 4 zurück)
        while i >= 0 && idx - i < 4 {
            let c = cues[i]
            if c.start <= t && t < c.end { lines.insert(c.text, at: 0) }
            i -= 1
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

/// Warteschlange mit Vorheriges/Nächstes, Zufall und Wiederholen (Android: PlayQueue/QueuePlanner).
public struct PlayQueue: Equatable, Sendable {
    public enum Repeat: String, Codable, Sendable, CaseIterable {
        case off, all, one
        public var label: String {
            switch self {
            case .off: return "Wiederholen aus"
            case .all: return "Alle wiederholen"
            case .one: return "Aktuellen wiederholen"
            }
        }
    }

    /// Reihenfolge der Film-IDs (bei Zufall bereits gemischt)
    public private(set) var order: [Int64]
    public private(set) var index: Int
    public private(set) var shuffled: Bool
    public var repeatMode: Repeat
    /// Ursprüngliche Reihenfolge (zum Aufheben von Zufall)
    private var original: [Int64]

    public init(ids: [Int64], startAt id: Int64?, shuffle: Bool = false, repeatMode: Repeat = .off) {
        original = ids
        order = ids
        index = 0
        shuffled = false
        self.repeatMode = repeatMode
        if let id, let i = ids.firstIndex(of: id) { index = i }
        if shuffle { setShuffle(true) }
    }

    public var current: Int64? { order.indices.contains(index) ? order[index] : nil }

    public var hasNext: Bool { repeatMode != .off ? !order.isEmpty : index + 1 < order.count }
    public var hasPrevious: Bool { repeatMode == .all ? !order.isEmpty : index > 0 }

    /// Nach Ende eines Films (berücksichtigt „Aktuellen wiederholen“)
    public mutating func advanceAfterEnd() -> Int64? {
        if repeatMode == .one { return current }
        return next()
    }

    /// „Nächster“ (Knopf): bei „Aktuellen wiederholen“ trotzdem weiter
    @discardableResult
    public mutating func next() -> Int64? {
        guard !order.isEmpty else { return nil }
        if index + 1 < order.count { index += 1; return current }
        if repeatMode != .off { index = 0; return current }
        return nil
    }

    @discardableResult
    public mutating func previous() -> Int64? {
        guard !order.isEmpty else { return nil }
        if index > 0 { index -= 1; return current }
        if repeatMode == .all { index = order.count - 1; return current }
        return nil
    }

    /// Zufall ein/aus – der aktuelle Film bleibt aktuell und steht bei „ein“ vorn.
    public mutating func setShuffle(_ on: Bool, seed: UInt64? = nil) {
        guard on != shuffled else { return }
        let cur = current
        if on {
            var rest = original.filter { $0 != cur }
            if let seed {
                var g = SeededGenerator(seed: seed)
                rest.shuffle(using: &g)
            } else {
                rest.shuffle()
            }
            order = (cur.map { [$0] } ?? []) + rest
            index = 0
        } else {
            order = original
            index = cur.flatMap { original.firstIndex(of: $0) } ?? 0
        }
        shuffled = on
    }

    /// Film aus der Warteschlange entfernen (z. B. Datei nicht mehr verfügbar)
    public mutating func remove(_ id: Int64) {
        let cur = current
        original.removeAll { $0 == id }
        order.removeAll { $0 == id }
        if let cur, cur != id, let i = order.firstIndex(of: cur) { index = i }
        else { index = min(index, max(0, order.count - 1)) }
    }
}

/// Deterministischer Zufallsgenerator (SplitMix64) für reproduzierbare Tests.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
