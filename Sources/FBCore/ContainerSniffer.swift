import Foundation

/// Erkennt MPEG-Container an ihrer Signatur (die ersten Bytes der Datei) – unabhängig von der Endung.
///
/// Wozu: libVLC kennt bei MPEG-Programmströmen (.mpg/.mpeg/.vob) und Transportströmen (.ts/.mts/.m2ts) die Spuren
/// erst beim Dekodieren; die schnelle Vorprüfung meldet dort oft nichts. Die Signatur zeigt, dass es wirklich ein
/// solcher Container ist (und keine umbenannte Textdatei) – erst dann wird ein Bild dekodiert.
public enum ContainerSniffer {
    public enum Kind: String, Sendable, Equatable {
        /// MPEG-Programmstrom (Pack-Header 00 00 01 BA) bzw. MPEG-Videoelementarstrom (00 00 01 B3)
        case mpegProgramStream
        /// MPEG-Transportstrom, 188-Byte-Pakete (Sync-Byte 0x47)
        case mpegTransportStream
        /// Blu-ray/AVCHD-Transportstrom, 192-Byte-Pakete (4 Byte Zeitstempel + 188)
        case m2ts
    }

    /// Prüft die ersten Bytes (höchstens 64 KB werden gelesen).
    public static func sniff(url: URL) -> Kind? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 65_536)
        return sniff(Array(data))
    }

    public static func sniff(_ bytes: [UInt8]) -> Kind? {
        if bytes.count >= 4 && bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 1 && (bytes[3] == 0xBA || bytes[3] == 0xB3) {
            return .mpegProgramStream
        }
        if syncBytes(bytes, offset: 0, packet: 188) { return .mpegTransportStream }
        if syncBytes(bytes, offset: 4, packet: 192) { return .m2ts }
        return nil
    }

    /// Mindestens 5 aufeinanderfolgende Pakete mit Sync-Byte 0x47 an der erwarteten Stelle
    static func syncBytes(_ bytes: [UInt8], offset: Int, packet: Int) -> Bool {
        let needed = 5
        guard bytes.count >= offset + packet * (needed - 1) + 1 else { return false }
        for i in 0..<needed where bytes[offset + i * packet] != 0x47 { return false }
        return true
    }
}
