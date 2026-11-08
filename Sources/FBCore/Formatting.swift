import Foundation

/// Deutsche Anzeige von Zeiten, Größen und technischen Angaben.
public enum Fmt {
    private static let de = Locale(identifier: "de_DE")

    /// Wiedergabezeit „1:52:03“ bzw. „4:07“
    public static func clock(_ seconds: Double?) -> String {
        guard let s = seconds, s.isFinite, s >= 0 else { return "–:––" }
        let total = Int(s.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    /// Laufzeit „1 Std. 52 Min.“ bzw. „47 Min.“ bzw. „35 Sek.“
    public static func runtime(_ seconds: Double?) -> String {
        guard let s = seconds, s.isFinite, s > 0 else { return "Laufzeit unbekannt" }
        if s < 60 { return "\(Int(s.rounded())) Sek." }
        let totalMinutes = Int((s / 60).rounded())
        let h = totalMinutes / 60, m = totalMinutes % 60
        if h == 0 { return "\(m) Min." }
        if m == 0 { return "\(h) Std." }
        return "\(h) Std. \(m) Min."
    }

    /// Restzeit „noch 34 Min.“
    public static func remaining(position: Double, duration: Double?) -> String? {
        guard let d = duration, d > 0, position > 0 else { return nil }
        let rest = max(0, d - position)
        return "noch " + runtime(rest)
    }

    /// Dateigröße „4,37 GB“ (Dezimal wie im Finder)
    public static func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        f.includesUnit = true
        f.isAdaptive = true
        return f.string(fromByteCount: n)
    }

    public static func number(_ v: Double, digits: Int) -> String {
        let f = NumberFormatter()
        f.locale = de
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    public static func integer(_ v: Int) -> String {
        let f = NumberFormatter()
        f.locale = de
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    /// Bildrate „23,976 fps“
    public static func frameRate(_ fps: Double?) -> String? {
        guard let f = fps, f.isFinite, f > 0 else { return nil }
        return number(f, digits: 3) + " fps"
    }

    /// Auflösung „1920 × 1080“
    public static func resolution(_ w: Int?, _ h: Int?) -> String? {
        guard let w, let h, w > 0, h > 0 else { return nil }
        return "\(w) × \(h)"
    }

    /// Seitenverhältnis „16:9“, „2,39:1“, „4:3“
    public static func aspectRatio(_ w: Int?, _ h: Int?) -> String? {
        guard let w, let h, w > 0, h > 0 else { return nil }
        let r = Double(w) / Double(h)
        let known: [(Double, String)] = [(16.0 / 9.0, "16:9"), (4.0 / 3.0, "4:3"), (21.0 / 9.0, "21:9"), (1.85, "1,85:1"),
                                         (2.39, "2,39:1"), (2.35, "2,35:1"), (3.0 / 2.0, "3:2"), (1.0, "1:1"),
                                         (9.0 / 16.0, "9:16"), (5.0 / 4.0, "5:4"), (2.0, "2:1")]
        for (value, label) in known where abs(r - value) < 0.012 { return label }
        return number(r, digits: 2) + ":1"
    }

    /// Bitrate „8,4 Mbit/s“
    public static func bitRate(_ bps: Int?) -> String? {
        guard let b = bps, b > 0 else { return nil }
        if b >= 1_000_000 { return number(Double(b) / 1_000_000, digits: 1) + " Mbit/s" }
        return number(Double(b) / 1000, digits: 0) + " kbit/s"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = de
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = de
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    public static func date(_ d: Date?) -> String {
        guard let d else { return "–" }
        return dateFormatter.string(from: d)
    }

    public static func day(_ d: Date?) -> String {
        guard let d else { return "–" }
        return dayFormatter.string(from: d)
    }

    /// „vor 3 Tagen“, „gerade eben“
    public static func relative(_ d: Date?, now: Date = Date()) -> String {
        guard let d else { return "nie" }
        let s = now.timeIntervalSince(d)
        if s < 60 { return "gerade eben" }
        let f = RelativeDateTimeFormatter()
        f.locale = de
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: now)
    }

    /// Anzahl mit Einzahl/Mehrzahl: „1 Film“, „12 Filme“
    public static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(integer(n)) \(n == 1 ? singular : plural)"
    }

    /// Codec-Kürzel lesbar machen (FourCC bzw. VLC-Kennung → Name)
    public static func codecName(_ raw: String?) -> String? {
        guard var c = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else { return nil }
        c = c.trimmingCharacters(in: CharacterSet(charactersIn: "\0'\""))
        let map: [String: String] = [
            "avc1": "H.264", "avc3": "H.264", "h264": "H.264", "x264": "H.264",
            "hvc1": "HEVC (H.265)", "hev1": "HEVC (H.265)", "hevc": "HEVC (H.265)", "h265": "HEVC (H.265)",
            "mp4v": "MPEG-4 Part 2", "xvid": "MPEG-4 Part 2 (Xvid)", "divx": "MPEG-4 Part 2 (DivX)", "dx50": "MPEG-4 Part 2 (DivX)", "fmp4": "MPEG-4 Part 2",
            "mpgv": "MPEG-2", "mp2v": "MPEG-2", "mpg2": "MPEG-2", "mpg1": "MPEG-1", "mp1v": "MPEG-1",
            "wmv1": "Windows Media Video 7", "wmv2": "Windows Media Video 8", "wmv3": "Windows Media Video 9", "wvc1": "VC-1",
            "vp80": "VP8", "vp8": "VP8", "vp90": "VP9", "vp9": "VP9", "vp09": "VP9", "av01": "AV1", "av1": "AV1",
            "flv1": "Sorenson Spark", "h263": "H.263", "s263": "H.263", "mjpg": "Motion JPEG", "jpeg": "Motion JPEG",
            "apcn": "Apple ProRes 422", "apch": "Apple ProRes 422 HQ", "apcs": "Apple ProRes 422 LT", "apco": "Apple ProRes 422 Proxy", "ap4h": "Apple ProRes 4444",
            "mp4a": "AAC", "aac": "AAC", "ac-3": "AC-3", "a52": "AC-3", "a52 ": "AC-3", "ac3": "AC-3", "ec-3": "E-AC-3", "eac3": "E-AC-3",
            "mpga": "MPEG-Audio", ".mp3": "MP3", "mp3": "MP3", "mp2": "MPEG Layer 2", "lpcm": "PCM", "araw": "PCM", "sowt": "PCM", "twos": "PCM",
            "opus": "Opus", "vorb": "Vorbis", "vorbis": "Vorbis", "wma2": "WMA 2", "wma1": "WMA 1", "wmap": "WMA Pro", "alac": "Apple Lossless",
            "flac": "FLAC", "dts": "DTS", "dts ": "DTS", "dtsc": "DTS", "mlpa": "Dolby TrueHD", "trhd": "Dolby TrueHD",
        ]
        if let hit = map[c.lowercased()] { return hit }
        return c.uppercased()
    }
}
