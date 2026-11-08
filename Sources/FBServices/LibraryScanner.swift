import Foundation
import FBCore
import FBStore

/// Fortschritt eines Durchlaufs (für die Anzeige).
public struct ScanProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case enumerating, saving, finished, cancelled, failed(String) }
    public var locationId: Int64
    public var phase: Phase
    public var videosFound: Int
    public var foldersVisited: Int
    public var currentFolder: String

    public init(locationId: Int64, phase: Phase, videosFound: Int = 0, foldersVisited: Int = 0, currentFolder: String = "") {
        self.locationId = locationId
        self.phase = phase
        self.videosFound = videosFound
        self.foldersVisited = foldersVisited
        self.currentFolder = currentFolder
    }
}

/// Ergebnis eines Durchlaufs.
public struct ScanReport: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        /// Vollständig durchsucht und gespeichert
        case completed
        /// Vom Nutzer abgebrochen – nichts als fehlend markiert
        case cancelled
        /// Speicherort während des Durchsuchens verschwunden (Laufwerk entfernt) – nichts als fehlend markiert
        case locationLost
        case failed(String)
    }

    public var outcome: Outcome
    public var changes: ScanChanges
    public var insertedIds: [Int64]
    public var changedIds: [Int64]
    public var unreadableFolders: [String]
    public var duration: TimeInterval
}

/// Durchsucht Speicherorte rekursiv nach Videos und gleicht mit dem Index ab.
///
/// - Läuft vollständig im Hintergrund (eigener Task), blockiert nie die Oberfläche.
/// - Abbrechbar (Task-Abbruch); bei Abbruch oder verschwundenem Laufwerk wird NICHTS als fehlend markiert.
/// - Intelligenter Index: Nur neue/geänderte Dateien (Größe/Änderungsdatum) werden später neu geprüft;
///   ein erneuter Durchlauf liest nur Verzeichniseinträge, keine Videodaten.
/// - Pakete (z. B. Fotos-Mediathek, Final-Cut-Bibliotheken), versteckte Ordner und Systemordner werden übersprungen.
public final class LibraryScanner: @unchecked Sendable {
    private let store: LibraryStore

    public init(store: LibraryStore) {
        self.store = store
    }

    /// Nur das Auflisten (für Tests und für den Abgleich): alle Videos unter `root`.
    public struct Listing: Sendable {
        public var files: [FoundFile] = []
        public var unreadable: [String] = []
        public var folders = 0
        public var complete = true
        public var lost = false
    }

    public static func list(root: URL, excluding excluded: [String] = [], progress: ((Int, Int, String) -> Void)? = nil,
                            isCancelled: () -> Bool = { false }) -> Listing {
        var listing = Listing()
        let rootPath = root.standardizedFileURL.path
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey,
                                      .totalFileSizeKey, .contentModificationDateKey, .creationDateKey, .nameKey]
        var unreadable: [String] = []
        let lock = NSLock()
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                              options: [.skipsPackageDescendants],
                                                              errorHandler: { url, _ in
            lock.lock()
            unreadable.append(url.path)
            lock.unlock()
            return true
        }) else {
            listing.complete = false
            listing.lost = !FileManager.default.fileExists(atPath: rootPath)
            return listing
        }
        let excludedSet = Set(excluded)
        var lastReport = Date.distantPast
        var counter = 0
        while let item = enumerator.nextObject() as? URL {
            counter += 1
            if counter % 64 == 0 {
                if isCancelled() { listing.complete = false; break }
                // Laufwerk weg? (z. B. USB-Stick während des Durchsuchens gezogen)
                if !FileManager.default.fileExists(atPath: rootPath) { listing.complete = false; listing.lost = true; break }
            }
            guard let v = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            let name = v.name ?? item.lastPathComponent
            let rel = relativePath(of: item, rootPath: rootPath)
            if v.isDirectory == true {
                if ScanRules.skipDirectory(named: name) || v.isPackage == true || (rel != nil && excludedSet.contains(rel!)) {
                    enumerator.skipDescendants()
                    continue
                }
                listing.folders += 1
                if let progress, Date().timeIntervalSince(lastReport) > 0.12 {
                    lastReport = Date()
                    progress(listing.files.count, listing.folders, rel ?? "")
                }
                continue
            }
            guard v.isRegularFile == true, v.isSymbolicLink != true else { continue }
            guard !ScanRules.skipFile(named: name), !ScanRules.isPartialDownload(name), VideoFormats.isVideo(fileName: name) else { continue }
            guard let rel else { continue }
            let size = Int64(v.fileSize ?? v.totalFileSize ?? 0)
            listing.files.append(FoundFile(relativePath: rel, sizeBytes: size, modifiedAt: v.contentModificationDate,
                                           createdAt: v.creationDate, fileId: inode(of: item)))
        }
        lock.lock()
        listing.unreadable = unreadable.compactMap { relativePath(ofPath: $0, rootPath: rootPath) }
        lock.unlock()
        if listing.complete && !FileManager.default.fileExists(atPath: rootPath) {
            listing.complete = false
            listing.lost = true
        }
        progress?(listing.files.count, listing.folders, "")
        return listing
    }

    static func relativePath(of url: URL, rootPath: String) -> String? {
        relativePath(ofPath: url.standardizedFileURL.path, rootPath: rootPath)
    }

    static func relativePath(ofPath path: String, rootPath: String) -> String? {
        if let rel = RelativePath.relative(path, to: rootPath) { return rel }
        // /private/var ↔ /var und ähnliche Symlinks
        let a = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let b = URL(fileURLWithPath: rootPath).resolvingSymlinksInPath().path
        return RelativePath.relative(a, to: b)
    }

    /// Inode-Nummer (bleibt auf APFS/HFS+ beim Umbenennen und Verschieben innerhalb des Laufwerks gleich)
    static func inode(of url: URL) -> UInt64? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        return UInt64(st.st_ino)
    }

    /// Durchsucht einen Speicherort und schreibt die Änderungen.
    public func scan(location: StorageLocation, root: URL, excluding excluded: [String], heartFavorites: Bool,
                     progress: @escaping @Sendable (ScanProgress) -> Void) async -> ScanReport {
        let started = Date()
        let id = location.id
        progress(ScanProgress(locationId: id, phase: .enumerating))
        let worker = Task.detached(priority: .utility) { () -> Listing in
            LibraryScanner.list(root: root, excluding: excluded, progress: { videos, folders, folder in
                progress(ScanProgress(locationId: id, phase: .enumerating, videosFound: videos, foldersVisited: folders, currentFolder: folder))
            }, isCancelled: { Task.isCancelled })
        }
        // Abbruch des aufrufenden Tasks an den Hintergrund-Task weitergeben
        let listing = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        let cancelled = Task.isCancelled
        if cancelled || !listing.complete {
            let outcome: ScanReport.Outcome = listing.lost ? .locationLost : .cancelled
            progress(ScanProgress(locationId: id, phase: .cancelled, videosFound: listing.files.count, foldersVisited: listing.folders))
            return ScanReport(outcome: outcome, changes: ScanChanges(), insertedIds: [], changedIds: [], unreadableFolders: listing.unreadable,
                              duration: Date().timeIntervalSince(started))
        }
        progress(ScanProgress(locationId: id, phase: .saving, videosFound: listing.files.count, foldersVisited: listing.folders))
        do {
            let existing = try store.indexedFiles(locationId: id)
            let changes = ScanDiff.compute(existing: existing, found: listing.files, protectedPrefixes: listing.unreadable)
            let result = try store.apply(changes, locationId: id, heartFavorites: heartFavorites)
            progress(ScanProgress(locationId: id, phase: .finished, videosFound: listing.files.count, foldersVisited: listing.folders))
            return ScanReport(outcome: .completed, changes: changes, insertedIds: result.insertedIds, changedIds: result.changedIds,
                              unreadableFolders: listing.unreadable, duration: Date().timeIntervalSince(started))
        } catch {
            progress(ScanProgress(locationId: id, phase: .failed(error.localizedDescription)))
            return ScanReport(outcome: .failed(error.localizedDescription), changes: ScanChanges(), insertedIds: [], changedIds: [],
                              unreadableFolders: listing.unreadable, duration: Date().timeIntervalSince(started))
        }
    }
}
