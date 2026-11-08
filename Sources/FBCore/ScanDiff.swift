import Foundation

/// Ein Eintrag des Index (aus der Datenbank) – nur, was der Abgleich braucht.
public struct IndexedFile: Sendable, Equatable {
    public let id: Int64
    public let relativePath: String
    public let sizeBytes: Int64
    public let modifiedAt: Date?
    public let fileId: UInt64?
    public let isMissing: Bool

    public init(id: Int64, relativePath: String, sizeBytes: Int64, modifiedAt: Date?, fileId: UInt64?, isMissing: Bool) {
        self.id = id
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.fileId = fileId
        self.isMissing = isMissing
    }
}

/// Eine beim Durchsuchen gefundene Videodatei.
public struct FoundFile: Sendable, Equatable {
    public let relativePath: String
    public let sizeBytes: Int64
    public let modifiedAt: Date?
    public let createdAt: Date?
    public let fileId: UInt64?

    public init(relativePath: String, sizeBytes: Int64, modifiedAt: Date?, createdAt: Date?, fileId: UInt64?) {
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
        self.fileId = fileId
    }

    public var fileName: String { RelativePath.lastComponent(relativePath) }
}

public struct ScanUpdate: Sendable, Equatable {
    public let id: Int64
    public let file: FoundFile
    /// Größe oder Änderungsdatum anders → Metadaten und Cover neu ermitteln (Nutzerdaten bleiben)
    public let contentChanged: Bool
}

/// Ergebnis des Abgleichs Index ↔ Datenträger.
public struct ScanChanges: Sendable, Equatable {
    public var inserts: [FoundFile] = []
    public var updates: [ScanUpdate] = []
    /// Umbenannt/verschoben innerhalb des Speicherorts (Nutzerdaten ziehen mit)
    public var moves: [ScanUpdate] = []
    /// Bisher vorhanden, jetzt nicht gefunden → als „Datei fehlt“ markieren (nicht löschen!)
    public var newlyMissing: [Int64] = []
    /// Waren als fehlend markiert und sind wieder da
    public var reappeared: [Int64] = []
    public var unchanged = 0

    public init() {}

    public var isEmpty: Bool { inserts.isEmpty && updates.isEmpty && moves.isEmpty && newlyMissing.isEmpty && reappeared.isEmpty }
}

public enum ScanDiff {
    /// Toleranz für Änderungsdaten (FAT speichert nur auf 2 Sekunden genau)
    public static let timeTolerance: TimeInterval = 2.0

    static func sameTime(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return abs(x.timeIntervalSince(y)) <= timeTolerance
        default: return false
        }
    }

    /// Vergleicht den Index eines Speicherorts mit einem VOLLSTÄNDIGEN Durchlauf.
    /// Darf nur mit vollständigen Ergebnissen aufgerufen werden – nach Abbruch oder Fehler (z. B. Laufwerk
    /// während des Durchsuchens entfernt) gäbe es sonst fälschlich „fehlende“ Dateien.
    /// - Parameter protectedPrefixes: Ordner (relativ), die nicht gelesen werden konnten (fehlende Rechte,
    ///   Lesefehler). Einträge darunter gelten als unverändert – sie werden weder als fehlend markiert noch verschoben.
    public static func compute(existing: [IndexedFile], found: [FoundFile], protectedPrefixes: [String] = []) -> ScanChanges {
        var changes = ScanChanges()
        var byPath: [String: IndexedFile] = [:]
        for e in existing { byPath[e.relativePath] = e }
        var seen = Set<Int64>()
        var newFiles: [FoundFile] = []

        for f in found {
            if let e = byPath[f.relativePath] {
                seen.insert(e.id)
                let changed = e.sizeBytes != f.sizeBytes || !sameTime(e.modifiedAt, f.modifiedAt)
                if changed {
                    changes.updates.append(ScanUpdate(id: e.id, file: f, contentChanged: true))
                } else if e.fileId != f.fileId && f.fileId != nil {
                    changes.updates.append(ScanUpdate(id: e.id, file: f, contentChanged: false))
                } else if !e.isMissing {
                    changes.unchanged += 1
                }
                if e.isMissing { changes.reappeared.append(e.id) }
            } else {
                newFiles.append(f)
            }
        }

        // Nicht mehr gefundene Einträge: Kandidaten für Umbenennen/Verschieben
        // (Einträge in nicht lesbaren Ordnern bleiben unangetastet)
        func isProtected(_ path: String) -> Bool {
            protectedPrefixes.contains { p in p.isEmpty || path == p || path.hasPrefix(p + "/") }
        }
        var vanished = existing.filter { !seen.contains($0.id) && !isProtected($0.relativePath) }
        changes.unchanged += existing.filter { !seen.contains($0.id) && isProtected($0.relativePath) }.count

        for f in newFiles {
            // 1. gleiche Datei-ID und Größe (APFS/HFS+: bleibt bei Umbenennen/Verschieben gleich)
            var matchIndex = vanished.firstIndex { v in
                v.fileId != nil && v.fileId == f.fileId && v.sizeBytes == f.sizeBytes
            }
            // 2. gleicher Dateiname, gleiche Größe, gleiches Änderungsdatum (in anderen Ordner verschoben)
            if matchIndex == nil {
                matchIndex = vanished.firstIndex { v in
                    RelativePath.lastComponent(v.relativePath) == f.fileName && v.sizeBytes == f.sizeBytes && sameTime(v.modifiedAt, f.modifiedAt)
                }
            }
            if let i = matchIndex {
                let v = vanished.remove(at: i)
                changes.moves.append(ScanUpdate(id: v.id, file: f, contentChanged: false))
                if v.isMissing { changes.reappeared.append(v.id) }
            } else {
                changes.inserts.append(f)
            }
        }

        for v in vanished where !v.isMissing {
            changes.newlyMissing.append(v.id)
        }
        return changes
    }
}
