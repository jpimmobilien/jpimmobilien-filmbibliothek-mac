import Foundation

/// Dauerhafte Kennung eines Laufwerks – NICHT der Name (zwei USB-Sticks heißen oft beide „NO NAME“,
/// und macOS hängt bei Namensgleichheit „ 1“ an den Einhängepunkt an).
///
/// Reihenfolge der Merkmale:
///  1. Volume-UUID (APFS, HFS+, exFAT, FAT – macOS leitet sie bei FAT aus der Seriennummer ab)
///  2. Netzlaufwerk: Adresse der Freigabe („smb://nas.local/Filme“) ohne Benutzername/Passwort
///  3. Fingerabdruck aus Gesamtgröße, Dateisystem und Erstellungsdatum (selten nötig)
public struct VolumeIdentity: Hashable, Sendable, Codable {
    public enum Kind: String, Codable, Sendable {
        case uuid, network, fingerprint
    }

    public let kind: Kind
    public let value: String

    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }

    /// Schlüssel für Datenbank und Vergleich, z. B. "uuid:1A2B…"
    public var key: String { "\(kind.rawValue):\(value)" }

    public init?(key: String) {
        guard let colon = key.firstIndex(of: ":") else { return nil }
        guard let kind = Kind(rawValue: String(key[..<colon])) else { return nil }
        self.kind = kind
        self.value = String(key[key.index(after: colon)...])
    }

    /// Beschreibung eines eingebundenen Laufwerks (aus URL-Ressourcenwerten)
    public struct Facts: Sendable, Equatable {
        public var uuid: String?
        public var remountURL: String?
        public var name: String?
        public var totalCapacity: Int64?
        public var fileSystem: String?
        public var creationDate: Date?
        public var isLocal: Bool
        public var isInternal: Bool
        public var isRemovable: Bool
        public var isEjectable: Bool
        public var isRootFileSystem: Bool

        public init(uuid: String? = nil, remountURL: String? = nil, name: String? = nil, totalCapacity: Int64? = nil,
                    fileSystem: String? = nil, creationDate: Date? = nil, isLocal: Bool = true, isInternal: Bool = false,
                    isRemovable: Bool = false, isEjectable: Bool = false, isRootFileSystem: Bool = false) {
            self.uuid = uuid
            self.remountURL = remountURL
            self.name = name
            self.totalCapacity = totalCapacity
            self.fileSystem = fileSystem
            self.creationDate = creationDate
            self.isLocal = isLocal
            self.isInternal = isInternal
            self.isRemovable = isRemovable
            self.isEjectable = isEjectable
            self.isRootFileSystem = isRootFileSystem
        }
    }

    /// Kennung aus den Merkmalen eines Laufwerks.
    public static func from(_ f: Facts) -> VolumeIdentity {
        if let u = f.uuid?.trimmingCharacters(in: .whitespaces), !u.isEmpty {
            return VolumeIdentity(kind: .uuid, value: u.uppercased())
        }
        if !f.isLocal, let r = f.remountURL, let cleaned = sanitizeNetworkURL(r) {
            return VolumeIdentity(kind: .network, value: cleaned)
        }
        var parts: [String] = []
        parts.append(f.fileSystem?.lowercased() ?? "?")
        parts.append(f.totalCapacity.map(String.init) ?? "?")
        parts.append(f.creationDate.map { String(Int64($0.timeIntervalSince1970)) } ?? "?")
        if f.totalCapacity == nil && f.creationDate == nil {
            // Zu wenig Merkmale – dann eben der Name (besser als nichts, aber als solcher erkennbar)
            parts.append(f.name ?? "?")
        }
        return VolumeIdentity(kind: .fingerprint, value: parts.joined(separator: "|"))
    }

    /// Entfernt Zugangsdaten und Endschrägstriche: „smb://anna:geheim@NAS.local/Filme/“ → „smb://nas.local/Filme“
    public static func sanitizeNetworkURL(_ raw: String) -> String? {
        guard var comps = URLComponents(string: raw), let scheme = comps.scheme?.lowercased(), let host = comps.host, !host.isEmpty else { return nil }
        comps.user = nil
        comps.password = nil
        comps.scheme = scheme
        comps.host = host.lowercased()
        comps.query = nil
        comps.fragment = nil
        var s = comps.string ?? raw
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Art des Datenträgers aus den Merkmalen
    public static func kind(of f: Facts) -> LocationKind {
        if !f.isLocal { return .network }
        if f.isInternal && !f.isRemovable && !f.isEjectable { return .internalDisk }
        if f.isRemovable { return .removable }
        if f.isEjectable || !f.isInternal { return .externalDisk }
        return .unknown
    }
}
