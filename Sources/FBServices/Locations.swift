import Foundation
import AppKit
import FBCore

/// Ergebnis der Prüfung eines Speicherorts.
public enum LocationResolution {
    /// Erreichbar; `access` hält den Sandbox-Zugriff offen, solange das Objekt lebt
    case available(url: URL, access: ScopedAccess, refreshedBookmark: Data?)
    case offline
    case folderMissing
    case noAccess(String)

    public var availability: LocationAvailability {
        switch self {
        case .available: return .available
        case .offline: return .offline
        case .folderMissing: return .folderMissing
        case .noAccess(let m): return .noAccess(m)
        }
    }
}

public enum LocationResolver {

    public enum AddError: LocalizedError, Equatable {
        case notADirectory
        case unreadable(String)
        case bookmarkFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notADirectory: return "Bitte einen Ordner oder ein Laufwerk wählen, keine einzelne Datei."
            case .unreadable(let m): return "Der Ordner kann nicht gelesen werden: \(m)"
            case .bookmarkFailed(let m): return "macOS hat den dauerhaften Zugriff nicht erlaubt: \(m)"
            }
        }
    }

    /// Erstellt einen neuen Speicherort aus einem vom Nutzer gewählten Ordner (Sandbox-Zugriff muss bestehen).
    public static func makeLocation(for url: URL, now: Date = Date()) throws -> StorageLocation {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
        guard values?.isDirectory == true else { throw AddError.notADirectory }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
        } catch {
            throw AddError.unreadable(error.localizedDescription)
        }
        let bookmark: Data
        do {
            bookmark = try SecurityScope.makeBookmark(for: url)
        } catch {
            throw AddError.bookmarkFailed(error.localizedDescription)
        }
        let volume = VolumeInspector.volume(for: url)
        let pathInVolume = volume.map { VolumeInspector.pathInVolume(url, volumeURL: $0.volumeURL) } ?? url.path
        let isRoot = pathInVolume.isEmpty
        let name = isRoot ? (volume?.name ?? url.lastPathComponent) : url.lastPathComponent
        let key = volume?.key ?? VolumeIdentity(kind: .fingerprint, value: "path|" + url.path).key
        return StorageLocation(name: name, lastKnownPath: url.path, pathInVolume: pathInVolume, volumeKey: key,
                               volumeName: volume?.name ?? "", kind: volume?.kind ?? .unknown, bookmark: bookmark,
                               addedAt: now, lastSeenAt: now)
    }

    /// Eingebundene Laufwerke (Schlüssel und Namen) – zur Unterscheidung „nicht angeschlossen“ / „kein Zugriff“
    public struct Mounted: Sendable {
        public var keys: Set<String>
        public var names: Set<String>
        /// Volume-UUIDs aller eingebundenen Laufwerke (auch versteckte wie /System/Volumes/Data)
        public var uuids: Set<String>
        /// Einhängepunkte aller Laufwerke außer „/“ (z. B. „/Volumes/Filme“)
        public var mountPaths: Set<String>
        public init(keys: Set<String>, names: Set<String>, uuids: Set<String> = [], mountPaths: Set<String> = []) {
            self.keys = keys
            self.names = names
            self.uuids = uuids
            self.mountPaths = mountPaths
        }

        public static func current() -> Mounted {
            // Auch versteckte Volumes: Ordner im Benutzerordner liegen auf dem Daten-Volume (/System/Volumes/Data),
            // das macOS als „versteckt“ führt – sonst gälte die interne SSD fälschlich als „nicht angeschlossen“.
            let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(VolumeInspector.keys), options: []) ?? []
            let volumes = urls.compactMap { VolumeInspector.info(volumeURL: $0) }
            var names = Set(volumes.map(\.name))
            var uuids = Set<String>()
            var paths = Set<String>()
            for u in urls {
                names.insert(u.lastPathComponent)
                if let id = (try? u.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString { uuids.insert(id.uppercased()) }
                let path = u.standardizedFileURL.path
                if path != "/" && !path.isEmpty { paths.insert(path) }
            }
            return Mounted(keys: Set(volumes.map(\.key)), names: names, uuids: uuids, mountPaths: paths)
        }

        func contains(_ l: StorageLocation) -> Bool {
            if l.kind == .internalDisk { return true }   // die interne SSD ist immer da
            if keys.contains(l.volumeKey) || (!l.volumeName.isEmpty && names.contains(l.volumeName)) { return true }
            // Laufwerkskennung aus dem Lesezeichen (bleibt gleich, auch wenn sich Name oder gespeicherte Kennung unterscheiden)
            if let data = l.bookmark, let id = SecurityScope.volumeUUID(inBookmark: data), uuids.contains(id.uppercased()) { return true }
            // Zuletzt bekannter Pfad liegt auf einem eingebundenen Laufwerk (z. B. Netzfreigabe ohne Volume-UUID)
            let last = l.lastKnownPath
            if !last.isEmpty, mountPaths.contains(where: { last == $0 || last.hasPrefix($0 + "/") }) { return true }
            return false
        }
    }

    /// Läuft die App in der App-Sandbox?
    static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// Prüft einen Speicherort. Bindet NIE selbst Netzlaufwerke ein und zeigt keine Dialoge.
    public static func resolve(_ location: StorageLocation, mounted: Mounted) -> LocationResolution {
        guard let bookmark = location.bookmark else {
            return mounted.contains(location) ? .noAccess("Für diesen Ort ist kein Zugriff gespeichert.") : .offline
        }
        switch SecurityScope.resolve(bookmark) {
        case .success(let r):
            let access = ScopedAccess(url: r.url)
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: r.url.path, isDirectory: &isDir)
            guard exists, isDir.boolValue else {
                access.stop()
                guard mounted.contains(location) else { return .offline }
                // In der Sandbox ohne bestätigten Zugriff ist der Ordner unsichtbar – das ist eine abgelaufene
                // Freigabe, kein fehlender Ordner.
                if isSandboxed && !access.isSandboxGrant {
                    return .noAccess("Die gespeicherte Freigabe gilt nicht mehr – z. B. nach einer neuen App-Version.")
                }
                return .folderMissing
            }
            // Lesbar? (Sandbox: ohne gültigen Zugriff schlägt das Auflisten fehl)
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: r.url.path)
            } catch {
                access.stop()
                return .noAccess(error.localizedDescription)
            }
            var refreshed: Data? = nil
            if r.isStale { refreshed = try? SecurityScope.makeBookmark(for: r.url) }
            return .available(url: r.url, access: access, refreshedBookmark: refreshed)
        case .failure(.notFound), .failure(.volumeNotMounted):
            return mounted.contains(location) ? .folderMissing : .offline
        case .failure(.accessDenied(let message)):
            return mounted.contains(location)
                ? .noAccess("Die gespeicherte Freigabe gilt nicht mehr – z. B. nach einer neuen App-Version (\(message))")
                : .offline
        }
    }

    /// Adresse zum erneuten Verbinden eines Netzlaufwerks (z. B. „smb://nas.local/Filme“)
    public static func reconnectURL(for location: StorageLocation) -> URL? {
        guard let id = VolumeIdentity(key: location.volumeKey), id.kind == .network else { return nil }
        return URL(string: id.value)
    }

    /// Liegt `inner` (gleiches Laufwerk) innerhalb von `outer`?
    public static func isInside(_ inner: StorageLocation, _ outer: StorageLocation) -> Bool {
        guard inner.volumeKey == outer.volumeKey, inner.id != outer.id else { return false }
        if outer.pathInVolume.isEmpty { return true }
        return inner.pathInVolume == outer.pathInVolume || inner.pathInVolume.hasPrefix(outer.pathInVolume + "/")
    }

    /// Unterordner (relativ zu `location`), die zu ANDEREN Speicherorten gehören und daher übersprungen werden
    public static func excludedSubpaths(for location: StorageLocation, among all: [StorageLocation]) -> [String] {
        all.compactMap { other in
            guard other.id != location.id, isInside(other, location), other.pathInVolume != location.pathInVolume else { return nil }
            if location.pathInVolume.isEmpty { return other.pathInVolume }
            return RelativePath.relative("/" + other.pathInVolume, to: "/" + location.pathInVolume)
        }
    }
}
