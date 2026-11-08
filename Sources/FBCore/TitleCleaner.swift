import Foundation

/// Lesbarer Titel aus dem Dateinamen – rein offline, ohne Online-Datenbank.
///
/// Beispiele:
///   "Alien.1979.1080p.BluRay.x264-GROUP.mkv" → Titel "Alien", Jahr 1979
///   "Der_Pate_(1972).mp4"                    → Titel "Der Pate", Jahr 1972
///   "Urlaub Sommer 2024.mov"                  → Titel "Urlaub Sommer 2024" (kein Release-Kennzeichen → unverändert)
///   "Mein Film 2026Heart.mkv"                 → "Mein Film 2026Heart" (Dateiname bleibt maßgeblich)
///
/// Regel: Nur wenn der Name typische Kennzeichen von Veröffentlichungen enthält (Auflösung, Quelle, Codec),
/// wird ab dem ersten Kennzeichen abgeschnitten; Punkte und Unterstriche werden nur dann zu Leerzeichen,
/// wenn der Name selbst keine Leerzeichen enthält. Der vollständige Dateiname bleibt immer durchsuchbar.
public enum TitleCleaner {

    private static let releaseTags: Set<String> = [
        "2160p", "1080p", "1080i", "720p", "576p", "480p", "4k", "uhd", "hdr", "hdr10", "dv", "dolbyvision", "10bit",
        "bluray", "blu-ray", "brrip", "bdrip", "bdremux", "remux", "web", "web-dl", "webdl", "webrip", "hdtv", "dvdrip",
        "dvd", "dvdscr", "hdrip", "x264", "x265", "h264", "h.264", "h265", "h.265", "hevc", "avc", "xvid", "divx",
        "aac", "ac3", "dts", "dd5.1", "ddp5.1", "truehd", "atmos", "proper", "repack", "extended", "unrated",
        "german", "ger", "dl", "multi", "subbed", "dubbed", "ac3d", "internal", "limited", "complete",
    ]

    public struct Result: Equatable, Sendable {
        public let title: String
        public let year: Int?
    }

    /// Zwischenspeicher – Titel werden in Listen sehr oft abgefragt.
    private static let cache = NSCache<NSString, Box>()
    private final class Box { let value: Result; init(_ v: Result) { value = v } }

    public static func title(forFileName fileName: String) -> String { clean(fileName).title }

    public static func year(forFileName fileName: String) -> Int? { clean(fileName).year }

    public static func clean(_ fileName: String) -> Result {
        if let hit = cache.object(forKey: fileName as NSString) { return hit.value }
        let result = compute(fileName)
        cache.setObject(Box(result), forKey: fileName as NSString)
        return result
    }

    static func compute(_ fileName: String) -> Result {
        let stem = VideoFormats.isVideo(fileName: fileName) ? RelativePath.stem(fileName) : fileName
        let hasSpaces = stem.contains(" ")
        // In Teile zerlegen: Leerzeichen immer, Punkte/Unterstriche nur ohne Leerzeichen im Namen
        let separators: Set<Character> = hasSpaces ? [" "] : [" ", ".", "_"]
        var tokens: [String] = []
        var current = ""
        for ch in stem {
            if separators.contains(ch) {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        guard !tokens.isEmpty else { return Result(title: stem, year: nil) }

        // Erstes Release-Kennzeichen suchen (nicht als erstes Wort – „4K Naturfilm“ bleibt ganz)
        var cut: Int? = nil
        for (i, token) in tokens.enumerated() where i > 0 {
            let lower = token.lowercased()
            let core = lower.split(separator: "-").first.map(String.init) ?? lower
            if releaseTags.contains(lower) || releaseTags.contains(core) { cut = i; break }
        }

        var titleTokens = cut.map { Array(tokens[..<$0]) } ?? tokens
        var year: Int? = nil
        if let last = titleTokens.last, titleTokens.count > 1, let y = parseYear(last) {
            // Jahr am Ende („Alien 1979“ bzw. „Der Pate (1972)“) nur abtrennen, wenn es eingeklammert ist
            // oder ein Release-Kennzeichen folgt – „Urlaub Sommer 2024“ bleibt sonst vollständig.
            if cut != nil || last.hasPrefix("(") || last.hasPrefix("[") {
                year = y
                titleTokens.removeLast()
            }
        }
        var title = titleTokens.joined(separator: " ")
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " -–_.([")).trimmingCharacters(in: .whitespaces)
        if title.isEmpty { title = stem }
        if !hasSpaces && cut == nil && year == nil {
            // Nur Trennzeichen ersetzt (z. B. "Mein_Urlaub" → "Mein Urlaub")
            title = tokens.joined(separator: " ")
        }
        return Result(title: title, year: year)
    }

    static func parseYear(_ token: String) -> Int? {
        let digits = token.trimmingCharacters(in: CharacterSet(charactersIn: "()[]"))
        guard digits.count == 4, let y = Int(digits), (1900...2100).contains(y) else { return nil }
        return y
    }
}

/// „Heart“ im Dateinamen (Android 7.3): endet der Name direkt vor der Endung auf „Heart“ (beliebige
/// Groß-/Kleinschreibung), gilt der Film als Favorit – nur wenn die Einstellung eingeschaltet ist.
public enum HeartMarker {
    public static func hasMarker(fileName: String) -> Bool {
        RelativePath.stem(fileName).lowercased().hasSuffix("heart")
    }
}
