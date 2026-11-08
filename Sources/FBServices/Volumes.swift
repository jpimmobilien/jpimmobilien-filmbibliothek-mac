import Foundation
import AppKit
import FBCore

/// Angaben zu einem eingebundenen Laufwerk.
public struct VolumeInfo: Sendable, Equatable {
    public var identity: VolumeIdentity
    public var facts: VolumeIdentity.Facts
    public var volumeURL: URL
    public var name: String
    public var kind: LocationKind
    public var totalBytes: Int64?
    public var availableBytes: Int64?
    public var fileSystem: String?
    public var isReadOnly: Bool

    public var key: String { identity.key }
}

/// Liest Laufwerksangaben über die offiziellen URL-Ressourcenwerte (keine privaten Schnittstellen).
public enum VolumeInspector {
    static let keys: Set<URLResourceKey> = [
        .volumeURLKey, .volumeUUIDStringKey, .volumeURLForRemountingKey, .volumeNameKey, .volumeLocalizedNameKey,
        .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeLocalizedFormatDescriptionKey, .volumeCreationDateKey,
        .volumeIsLocalKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsRootFileSystemKey,
        .volumeIsReadOnlyKey,
    ]

    /// Laufwerk, auf dem `url` liegt. nil, wenn macOS keine Angaben liefert (z. B. Laufwerk gerade entfernt).
    public static func volume(for url: URL) -> VolumeInfo? {
        guard let v = try? url.resourceValues(forKeys: [.volumeURLKey]), let volumeURL = v.volume else { return nil }
        return info(volumeURL: volumeURL)
    }

    public static func info(volumeURL: URL) -> VolumeInfo? {
        guard let r = try? volumeURL.resourceValues(forKeys: keys) else { return nil }
        var important: Int64? = nil
        if let imp = try? volumeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage, imp > 0 {
            important = imp
        }
        let facts = VolumeIdentity.Facts(
            uuid: r.volumeUUIDString,
            remountURL: r.volumeURLForRemounting?.absoluteString,
            name: r.volumeName,
            totalCapacity: r.volumeTotalCapacity.map(Int64.init),
            fileSystem: r.volumeLocalizedFormatDescription,
            creationDate: r.volumeCreationDate,
            isLocal: r.volumeIsLocal ?? true,
            isInternal: r.volumeIsInternal ?? false,
            isRemovable: r.volumeIsRemovable ?? false,
            isEjectable: r.volumeIsEjectable ?? false,
            isRootFileSystem: r.volumeIsRootFileSystem ?? false
        )
        let name = r.volumeLocalizedName ?? r.volumeName ?? volumeURL.lastPathComponent
        return VolumeInfo(identity: VolumeIdentity.from(facts), facts: facts, volumeURL: volumeURL, name: name,
                          kind: VolumeIdentity.kind(of: facts), totalBytes: r.volumeTotalCapacity.map(Int64.init),
                          availableBytes: important ?? r.volumeAvailableCapacity.map(Int64.init),
                          fileSystem: r.volumeLocalizedFormatDescription, isReadOnly: r.volumeIsReadOnly ?? false)
    }

    /// Alle eingebundenen, sichtbaren Laufwerke
    public static func mountedVolumes() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { info(volumeURL: $0) }
    }

    /// Pfad von `url` relativ zur Laufwerkswurzel ("" = Wurzel)
    public static func pathInVolume(_ url: URL, volumeURL: URL) -> String {
        let v = volumeURL.standardizedFileURL.resolvingSymlinksInPath().path
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path
        // Das Startlaufwerk ist „/“, Daten liegen unter /System/Volumes/Data mit Firmlinks (/Users → …/Data/Users)
        if v == "/" { return RelativePath.relative(p, to: "/") ?? p }
        if let rel = RelativePath.relative(p, to: v) { return rel }
        if v.hasPrefix("/System/Volumes/Data"), let rel = RelativePath.relative(p, to: "/") { return rel }
        return RelativePath.relative(url.path, to: volumeURL.path) ?? url.lastPathComponent
    }
}

/// Sicherheitsgeschützte Lesezeichen (App-Sandbox).
///
/// Ablauf (Apple-Dokumentation „Accessing files from the macOS App Sandbox“):
///  1. Der Nutzer wählt einen Ordner (NSOpenPanel), zieht ihn ins Fenster oder auf das Dock-Symbol →
///     die App erhält vorübergehend Zugriff.
///  2. Die App speichert ein Lesezeichen mit `.withSecurityScope` (nur Lesen).
///  3. Nach einem Neustart wird das Lesezeichen aufgelöst und `startAccessingSecurityScopedResource()` gerufen.
public enum SecurityScope {
    public static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                             includingResourceValuesForKeys: [.volumeUUIDStringKey, .volumeNameKey],
                             relativeTo: nil)
    }

    public enum ResolveError: Error, Equatable {
        /// Laufwerk nicht eingebunden (Lesezeichen zeigt auf ein fehlendes Laufwerk)
        case volumeNotMounted
        /// Lesezeichen ungültig oder Zugriff verweigert (z. B. nach Neuinstallation)
        case accessDenied(String)
        /// Ziel existiert nicht mehr
        case notFound
    }

    public struct Resolved {
        public let url: URL
        public let isStale: Bool
    }

    /// Löst ein Lesezeichen auf, OHNE Netzlaufwerke einzubinden oder Dialoge zu zeigen.
    public static func resolve(_ data: Data, mount: Bool = false) -> Result<Resolved, ResolveError> {
        var stale = false
        var options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        if !mount { options.insert(.withoutMounting) }
        do {
            let url = try URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
            return .success(Resolved(url: url, isStale: stale))
        } catch let e as NSError {
            if e.domain == NSCocoaErrorDomain && (e.code == NSFileNoSuchFileError || e.code == NSFileReadNoSuchFileError) {
                return .failure(.notFound)
            }
            if e.domain == NSCocoaErrorDomain && (e.code == NSFileReadNoPermissionError || e.code == NSFileReadCorruptFileError
                                                  || e.code == NSFileReadUnknownError) {
                return .failure(.accessDenied(e.localizedDescription))
            }
            return .failure(.accessDenied(e.localizedDescription))
        }
    }

    /// Volume-UUID, die im Lesezeichen mitgespeichert wurde (auch wenn das Laufwerk fehlt)
    public static func volumeUUID(inBookmark data: Data) -> String? {
        let values = URL.resourceValues(forKeys: [.volumeUUIDStringKey], fromBookmarkData: data)
        return values?.volumeUUIDString
    }
}

/// Ein laufender Sandbox-Zugriff; endet automatisch, wenn das Objekt freigegeben wird.
public final class ScopedAccess: @unchecked Sendable {
    public let url: URL
    private let started: Bool
    private var stopped = false
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
        started = url.startAccessingSecurityScopedResource()
    }

    /// Hat macOS den Zugriff bestätigt? (Außerhalb der Sandbox ist das immer false – Zugriff besteht dann ohnehin.)
    public var isSandboxGrant: Bool { started }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return }
        stopped = true
        if started { url.stopAccessingSecurityScopedResource() }
    }

    deinit { stop() }
}

/// Meldet Laufwerksereignisse von macOS (Einbinden, Auswerfen, Umbenennen, Ruhezustand).
@MainActor
public final class VolumeMonitor {
    public enum Event: Sendable, Equatable {
        case mounted(URL)
        case willUnmount(URL)
        case unmounted(URL)
        case renamed(URL)
        case didWake
        case periodicCheck
    }

    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private let handler: @MainActor (Event) -> Void

    public init(handler: @escaping @MainActor (Event) -> Void) {
        self.handler = handler
    }

    public func start(periodicInterval: TimeInterval = 45) {
        let nc = NSWorkspace.shared.notificationCenter
        func add(_ name: Notification.Name, _ make: @escaping (Notification) -> Event?) {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let ev = make(note) else { return }
                Task { @MainActor in self?.handler(ev) }
            })
        }
        add(NSWorkspace.didMountNotification) { n in (n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL).map(Event.mounted) }
        add(NSWorkspace.willUnmountNotification) { n in (n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL).map(Event.willUnmount) }
        add(NSWorkspace.didUnmountNotification) { n in (n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL).map(Event.unmounted) }
        add(NSWorkspace.didRenameVolumeNotification) { n in (n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL).map(Event.renamed) }
        add(NSWorkspace.didWakeNotification) { _ in .didWake }
        // Netzlaufwerke verschwinden manchmal ohne Meldung (WLAN weg) → regelmäßig nachsehen
        timer = Timer.scheduledTimer(withTimeInterval: periodicInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.handler(.periodicCheck) }
        }
    }

    public func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.forEach { nc.removeObserver($0) }
        observers.removeAll()
        timer?.invalidate()
        timer = nil
    }
}
