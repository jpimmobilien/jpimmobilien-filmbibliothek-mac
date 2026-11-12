import SwiftUI
import AppKit
import FBCore
import FBStore
import FBServices

/// Kurze Meldung unten im Fenster
struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var systemImage: String = "info.circle"
    var tone: Tone = .info
    enum Tone { case info, success, warning, error }
}

struct AlertInfo: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// Speicherorte der App-Daten (in der Sandbox: ~/Library/Containers/de.privateapp.filmbibliothek/Data/…)
struct AppPaths {
    let dataDirectory: URL
    let database: URL
    let covers: URL

    static func standard() -> AppPaths {
        let fm = FileManager.default
        let base: URL
        if let custom = ProcessInfo.processInfo.environment["FB_DATA_DIR"], !custom.isEmpty {
            base = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            base = (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory)
                .appendingPathComponent("Filmbibliothek", isDirectory: true)
        }
        let caches: URL
        if ProcessInfo.processInfo.environment["FB_DATA_DIR"] != nil {
            caches = base.appendingPathComponent("Caches", isDirectory: true)
        } else {
            caches = (fm.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory)
                .appendingPathComponent("Filmbibliothek", isDirectory: true)
        }
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return AppPaths(dataDirectory: base, database: base.appendingPathComponent("Bibliothek.sqlite"),
                        covers: caches.appendingPathComponent("Covers", isDirectory: true))
    }
}

/// Zentraler Zustand der App (Haupt-Thread). Datenbank-, Datei- und Videozugriffe laufen im Hintergrund.
@MainActor
final class AppModel: ObservableObject {
    enum Route: Hashable {
        case overview
        case library(LibraryScope)
        case locations
        case collections
        case detail(Int64)
    }

    let settings: AppSettings
    let store: LibraryStore
    let covers: CoverStore
    let metadata: MetadataService
    let scanner: LibraryScanner
    let paths: AppPaths
    lazy var player = PlayerCoordinator(model: self)

    // Daten
    @Published private(set) var films: [Film] = []
    @Published private(set) var locations: [StorageLocation] = []
    @Published private(set) var availability: [Int64: LocationAvailability] = [:]
    @Published private(set) var volumeInfo: [Int64: VolumeInfo] = [:]
    @Published private(set) var scanProgress: [Int64: ScanProgress] = [:]
    @Published private(set) var metadataRemaining = 0
    @Published private(set) var collections: [FilmCollection] = []
    @Published private(set) var statistics: LibraryStore.Statistics?
    @Published private(set) var visibleFilms: [Film] = []
    /// Formate im aktuellen Bereich mit Anzahl (Segment-Chips „Alle 22 · MP4 8 · MKV 3“) – ohne Formatfilter gezählt
    @Published private(set) var scopeFormats: [FormatCount] = []
    @Published private(set) var scopeTotal = 0
    @Published private(set) var isBootstrapped = false

    // Oberfläche
    @Published var route: Route = .overview { didSet { if route != oldValue { selection = []; scheduleRecompute() } } }
    @Published private(set) var backStack: [Route] = []
    @Published var searchText = "" { didSet { scheduleRecompute(debounce: 0.12) } }
    @Published var filter = LibraryFilter() { didSet { scheduleRecompute() } }
    @Published var selection: Set<Int64> = []
    @Published var toast: Toast?
    @Published var alert: AlertInfo?
    @Published var startupError: String?
    @Published var sidebarVisible = true
    /// Laufender Player (für den Mini-Player unten) – gesetzt vom PlayerCoordinator
    @Published var playerController: PlayerController?
    /// Leitfarbe des laufenden Films bzw. des Kinobilds auf „Start“ – färbt den Fensterhintergrund dezent
    @Published var playerTint: Color?
    @Published var heroTint: Color?
    /// Zuletzt gewählter Bereich der Navigation (Detailseiten gehören zu ihm)
    @Published private(set) var lastSection: NavSection = .start
    @Published var locationPendingRemoval: StorageLocation?
    @Published var removeMissingRequest: RemoveMissingRequest?
    @Published var collectionNamePrompt: CollectionPrompt?
    @Published var dropTargeted = false

    struct RemoveMissingRequest: Identifiable {
        let id = UUID()
        /// nil = alle Speicherorte
        var locationId: Int64?
        var count: Int
    }

    struct CollectionPrompt: Identifiable {
        let id = UUID()
        var renaming: FilmCollection?
        var addFilms: [Int64] = []
    }

    private var filmIndex: [Int64: Int] = [:]
    private var accesses: [Int64: ScopedAccess] = [:]
    private(set) var roots: [Int64: URL] = [:]
    private var scanTasks: [Int64: Task<Void, Never>] = [:]
    private var metadataTask: Task<Void, Never>?
    private var metadataAgain = false
    private var recomputeTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var resolving: Set<Int64> = []
    private var monitor: VolumeMonitor?

    init(settings: AppSettings) {
        self.settings = settings
        let paths = AppPaths.standard()
        self.paths = paths
        let store: LibraryStore
        var openError: String? = nil
        do {
            store = try LibraryStore(path: paths.database.path)
        } catch {
            // Datenbank defekt oder von neuerer Version: nicht überschreiben, sondern melden; vorübergehend im Speicher arbeiten
            store = try! LibraryStore.inMemory()
            openError = "Die Bibliothek konnte nicht geöffnet werden: \(error.localizedDescription)\nDatei: \(paths.database.path)\nDie Datei wurde nicht verändert. Bis zur Klärung arbeitet die App mit einer leeren, nicht gespeicherten Bibliothek."
        }
        self.store = store
        let covers = CoverStore(directory: paths.covers)
        self.covers = covers
        metadata = MetadataService(store: store, covers: covers)
        scanner = LibraryScanner(store: store)
        startupError = openError
        if !settings.showOverviewOnLaunch { route = .library(.all) }
    }

    // MARK: - Start

    func bootstrap() async {
        guard !isBootstrapped else { return }
        isBootstrapped = true
        QA.log("Start: macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(QA.architecture), \(LiquidGlass.modeDescription), VLCKit: \(VLCSupport.isAvailable), Grafik: \(RenderSafety.gpuName), reduzierte Effekte: \(RenderSafety.reducedEffects)")
        reloadFromStore()
        let m = VolumeMonitor { [weak self] event in self?.handle(event) }
        m.start()
        monitor = m
        await refreshAllAvailability(scanAfter: settings.scanOnLaunch)
        runMetadata()
    }

    // MARK: - Laden

    func reloadFromStore() {
        do {
            locations = try store.locations()
            setFilms(try store.films())
            collections = try store.collections()
            statistics = try? store.statistics()
        } catch {
            alert = AlertInfo(title: "Datenbankfehler", message: error.localizedDescription)
        }
    }

    private func setFilms(_ list: [Film]) {
        films = list
        filmIndex = Dictionary(uniqueKeysWithValues: list.enumerated().map { ($0.element.id, $0.offset) })
        scheduleRecompute()
    }

    private func reloadFilms() {
        if let list = try? store.films() { setFilms(list) }
        statistics = try? store.statistics()
    }

    /// Einen Film aus der Datenbank neu laden (nach Metadaten, Wiedergabe …)
    func refreshFilm(_ id: Int64) {
        guard let f = try? store.film(id: id) else { return }
        if let i = filmIndex[id] {
            films[i] = f
        } else {
            films.append(f)
            filmIndex[id] = films.count - 1
        }
        scheduleRecompute(debounce: 0.25)
    }

    /// Mehrere Filme auf einmal neu laden – EINE Änderung der veröffentlichten Liste statt vieler
    /// (wichtig bei Tausenden Filmen: jede Änderung zeichnet die Oberfläche neu).
    func refreshFilms(_ ids: [Int64]) {
        guard !ids.isEmpty else { return }
        var list = films
        var changed = false
        for id in ids {
            guard let f = try? store.film(id: id) else { continue }
            if let i = filmIndex[id] {
                list[i] = f
            } else {
                list.append(f)
                filmIndex[id] = list.count - 1
            }
            changed = true
        }
        if changed {
            films = list
            scheduleRecompute(debounce: 0.25)
        }
    }

    func film(_ id: Int64) -> Film? { filmIndex[id].map { films[$0] } }

    func location(_ id: Int64) -> StorageLocation? { locations.first { $0.id == id } }

    func locationName(_ id: Int64) -> String { location(id)?.name ?? "Unbekannter Speicherort" }

    func availabilityOf(location id: Int64) -> LocationAvailability { availability[id] ?? .unknown }

    func isAvailable(_ film: Film) -> Bool { !film.isMissing && availabilityOf(location: film.locationId).isAvailable }

    /// Datei-URL eines Films (nur, wenn sein Speicherort erreichbar ist)
    func fileURL(for film: Film) -> URL? {
        guard let root = roots[film.locationId], let path = RelativePath.join(root.path, film.relativePath) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Warum ist ein Film nicht abspielbar? nil = abspielbar
    func unavailableReason(_ film: Film) -> String? {
        if film.isMissing { return "Die Datei wurde am Speicherort nicht mehr gefunden (umbenannt, verschoben oder gelöscht)." }
        switch availabilityOf(location: film.locationId) {
        case .available: return nil
        case .offline:
            let loc = location(film.locationId)
            if loc?.kind == .network { return "Das Netzlaufwerk „\(loc?.volumeName ?? "")“ ist nicht verbunden." }
            return "Das Laufwerk „\(loc?.volumeName.isEmpty == false ? loc!.volumeName : locationName(film.locationId))“ ist nicht angeschlossen."
        case .noAccess: return "macOS erlaubt derzeit keinen Zugriff auf „\(locationName(film.locationId))“. Bitte unter „Speicherorte“ den Zugriff erneut erteilen."
        case .folderMissing: return "Der Ordner „\(locationName(film.locationId))“ wurde auf dem Laufwerk nicht gefunden."
        case .unknown: return "Der Speicherort wird noch geprüft."
        }
    }

    // MARK: - Navigation

    func navigate(_ r: Route) {
        guard r != route else { return }
        if case .detail = r { backStack.append(route) } else { backStack.removeAll() }
        if case .detail = r {} else { lastSection = NavSection.of(r, fallback: lastSection) }
        EntranceClock.shared.newWave()
        route = r
    }

    /// Aktiver Bereich der Navigation oben
    var navSection: NavSection { NavSection.of(route, fallback: lastSection) }

    /// Farbe für den Fensterhintergrund: laufender Film vor Kinobild
    var ambientTint: Color? { playerController != nil ? (playerTint ?? heroTint) : heroTint }

    func goBack() {
        EntranceClock.shared.newWave()
        if let last = backStack.popLast() { route = last } else { route = lastSection.route }
    }

    var currentScope: LibraryScope? {
        if case .library(let s) = route { return s }
        return nil
    }

    // MARK: - Sichtbare Liste (Suche, Filter, Sortierung) – im Hintergrund berechnet

    func scheduleRecompute(debounce: Double = 0) {
        recomputeTask?.cancel()
        let scope = currentScope ?? .all
        let query = SearchQuery(searchText)
        let filter = self.filter
        let order = scope.impliedSort ?? settings.sortOrder
        let films = self.films
        let available = Set(availability.filter { $0.value.isAvailable }.map(\.key))
        let collectionMap = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, Set($0.filmIds)) })
        let names = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0.name) })
        recomputeTask = Task { [weak self] in
            if debounce > 0 { try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000)) }
            if Task.isCancelled { return }
            let (result, formats, total) = await Task.detached(priority: .userInitiated) { () -> ([Film], [FormatCount], Int) in
                let now = Date()
                var counts: [String: Int] = [:]
                var inScope = 0
                var list = films.filter { f in
                    let avail = !f.isMissing && available.contains(f.locationId)
                    guard scope.contains(f, collections: collectionMap, isAvailable: avail, now: now) else { return false }
                    inScope += 1
                    counts[f.fileExtension, default: 0] += 1
                    guard filter.matches(f, isAvailable: avail) else { return false }
                    if !query.isEmpty {
                        return query.matches(normalized: SearchIndex.haystack(for: f, locationName: names[f.locationId] ?? ""))
                    }
                    return true
                }
                list = LibrarySorter.sort(list, by: order)
                let formats = counts.map { FormatCount(ext: $0.key, count: $0.value) }
                    .sorted { $0.count != $1.count ? $0.count > $1.count : $0.ext < $1.ext }
                return (list, formats, inScope)
            }.value
            if Task.isCancelled { return }
            self?.visibleFilms = result
            if self?.scopeFormats != formats { self?.scopeFormats = formats }
            if self?.scopeTotal != total { self?.scopeTotal = total }
        }
    }

    // MARK: - Speicherorte prüfen

    func refreshAllAvailability(scanAfter: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            for loc in locations {
                group.addTask { await self.resolve(loc, scanIfAvailable: scanAfter) }
            }
        }
        scheduleRecompute()
    }

    /// Prüft einen Speicherort im Hintergrund (Laufwerkszugriffe können auf Netzlaufwerken dauern).
    func resolve(_ loc: StorageLocation, scanIfAvailable: Bool) async {
        guard !resolving.contains(loc.id) else { return }
        resolving.insert(loc.id)
        defer { resolving.remove(loc.id) }
        if availability[loc.id] == nil { availability[loc.id] = .unknown }
        let resolution = await Task.detached(priority: .userInitiated) { () -> LocationResolution in
            LocationResolver.resolve(loc, mounted: .current())
        }.value
        guard locations.contains(where: { $0.id == loc.id }) else { return } // inzwischen entfernt
        let before = availability[loc.id]
        switch resolution {
        case .available(let url, let access, let refreshed):
            accesses[loc.id]?.stop()
            accesses[loc.id] = access
            roots[loc.id] = url
            availability[loc.id] = .available
            if let refreshed { try? store.setLocationBookmark(id: loc.id, bookmark: refreshed) }
            try? store.setLocationSeen(id: loc.id, path: url.path)
            let info = await Task.detached { VolumeInspector.volume(for: url) }.value
            volumeInfo[loc.id] = info
            // Selbstheilung: Manche Laufwerke (beobachtet: FAT32 auf Intel-Macs) melden nach erneutem Einbinden eine
            // andere Volume-UUID. Das Lesezeichen hat den Ort trotzdem gefunden → gespeicherte Kennung nachziehen,
            // damit Auswerfen/Einbinden weiter richtig zugeordnet werden.
            if let info, info.key != loc.volumeKey,
               (try? store.location(volumeKey: info.key, pathInVolume: loc.pathInVolume)) == nil,
               let i = locations.firstIndex(where: { $0.id == loc.id }) {
                var updated = locations[i]
                updated.volumeKey = info.key
                updated.volumeName = info.name
                if (try? store.updateLocation(updated)) != nil {
                    locations[i] = updated
                    QA.log("Laufwerkskennung aktualisiert: \(loc.name) \(loc.volumeKey) → \(info.key)")
                }
            }
            if let i = locations.firstIndex(where: { $0.id == loc.id }) {
                locations[i].lastKnownPath = url.path
                locations[i].lastSeenAt = Date()
                if let refreshed { locations[i].bookmark = refreshed }
            }
            QA.log("Speicherort verfügbar: \(loc.name) [\(loc.volumeKey)] → \(url.path)")
            if before != nil && before != .available && before != .unknown {
                showToast("„\(loc.name)“ ist wieder verfügbar.", systemImage: "externaldrive.badge.checkmark", tone: .success)
            }
            if scanIfAvailable { scan(loc.id) }
            runMetadata()
        case .offline, .folderMissing, .noAccess:
            releaseAccess(loc.id)
            availability[loc.id] = resolution.availability
            QA.log("Speicherort \(resolution.availability.label): \(loc.name) [\(loc.volumeKey)]")
        }
        scheduleRecompute()
    }

    private func releaseAccess(_ id: Int64) {
        scanTasks[id]?.cancel()
        accesses[id]?.stop()
        accesses[id] = nil
        roots[id] = nil
    }

    // MARK: - Laufwerksereignisse

    private func locationsOnVolume(_ volumeURL: URL) -> [StorageLocation] {
        let v = volumeURL.standardizedFileURL.path
        return locations.filter { loc in
            guard let root = roots[loc.id]?.standardizedFileURL.path else { return false }
            return root == v || root.hasPrefix(v.hasSuffix("/") ? v : v + "/")
        }
    }

    func handle(_ event: VolumeMonitor.Event) {
        switch event {
        case .mounted(let url):
            QA.log("Laufwerk eingebunden: \(url.path)")
            let candidates = locations.filter { !(availability[$0.id]?.isAvailable ?? false) }
            Task { for loc in candidates { await resolve(loc, scanIfAvailable: settings.scanOnMount) } }
        case .willUnmount(let url):
            // Dateien freigeben, damit macOS das Laufwerk auswerfen kann
            let affected = locationsOnVolume(url)
            QA.log("Laufwerk wird ausgeworfen: \(url.path) – betroffen: \(affected.map(\.name))")
            for loc in affected {
                scanTasks[loc.id]?.cancel()
                player.releaseIfPlaying(locationId: loc.id)
            }
        case .unmounted(let url):
            let affected = locationsOnVolume(url)
            QA.log("Laufwerk ausgeworfen: \(url.path) – betroffen: \(affected.map(\.name))")
            for loc in affected {
                player.releaseIfPlaying(locationId: loc.id)
                releaseAccess(loc.id)
                availability[loc.id] = .offline
            }
            if let first = affected.first {
                let count = films.filter { f in affected.contains { $0.id == f.locationId } }.count
                showToast(affected.count == 1
                          ? "„\(first.name)“ ist nicht mehr verfügbar – \(Fmt.count(count, "Film bleibt", "Filme bleiben")) in der Bibliothek."
                          : "\(affected.count) Speicherorte sind nicht mehr verfügbar – ihre Filme bleiben in der Bibliothek.",
                          systemImage: "externaldrive.badge.minus", tone: .warning)
            }
            scheduleRecompute()
        case .renamed, .didWake:
            Task { await refreshAllAvailability(scanAfter: false) }
        case .periodicCheck:
            periodicCheck()
        }
    }

    /// Erreichbarkeit regelmäßig prüfen (Netzlaufwerke verschwinden ohne Meldung)
    private func periodicCheck() {
        let current = roots
        Task {
            let lost = await Task.detached { () -> [Int64] in
                current.filter { !FileManager.default.fileExists(atPath: $0.value.path) }.map(\.key)
            }.value
            for id in lost {
                QA.log("Speicherort nicht mehr erreichbar (regelmäßige Prüfung): \(locationName(id))")
                player.releaseIfPlaying(locationId: id)
                releaseAccess(id)
                if let loc = location(id) { await resolve(loc, scanIfAvailable: false) }
            }
            // Nicht verfügbare Netzlaufwerke: vielleicht wieder da
            let waiting = locations.filter { $0.kind == .network && !(availability[$0.id]?.isAvailable ?? false) }
            for loc in waiting { await resolve(loc, scanIfAvailable: settings.scanOnMount) }
        }
    }

    // MARK: - Speicherorte hinzufügen / entfernen

    func showAddLocationPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Hinzufügen"
        panel.message = "Wählen Sie Ordner oder ganze Laufwerke mit Filmen. Die Filmbibliothek liest sie nur – es wird nichts verändert."
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in self?.addLocations(urls) }
        }
    }

    /// Zugriff erneut erteilen (z. B. nach einem App-Update ohne Developer-ID-Signatur)
    func regrantAccess(_ loc: StorageLocation) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Zugriff erteilen"
        panel.message = "Bitte den Ordner „\(loc.name)“ auswählen, damit die Filmbibliothek wieder darauf zugreifen darf."
        let last = URL(fileURLWithPath: loc.lastKnownPath)
        panel.directoryURL = last.deletingLastPathComponent()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.addLocations([url]) }
        }
    }

    /// Alle Speicherorte ohne gültige Freigabe nacheinander bestätigen lassen (je ein Auswahlfenster, auf den Ordner gerichtet)
    func regrantAll() {
        let pending = locations.filter { if case .noAccess = availabilityOf(location: $0.id) { return true } else { return false } }
        guard !pending.isEmpty else { return }
        Task { @MainActor in
            for loc in pending {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = "Zugriff erteilen"
                panel.message = "Freigabe erneuern: Bitte „\(loc.name)“ auswählen (\(loc.lastKnownPath))."
                let last = URL(fileURLWithPath: loc.lastKnownPath)
                panel.directoryURL = last.deletingLastPathComponent()
                let response = await withCheckedContinuation { (cont: CheckedContinuation<NSApplication.ModalResponse, Never>) in
                    panel.begin { cont.resume(returning: $0) }
                }
                if response == .OK, let url = panel.url { addLocations([url]) } else { break }
            }
        }
    }

    /// Netzlaufwerk über den Finder verbinden (Zugangsdaten aus dem Schlüsselbund)
    func reconnect(_ loc: StorageLocation) {
        guard let url = LocationResolver.reconnectURL(for: loc) else { return }
        NSWorkspace.shared.open(url)
        showToast("Verbindung zu „\(loc.volumeName)“ wird hergestellt …", systemImage: "network")
    }

    /// Ordner/Laufwerke hinzufügen (Dialog, Ziehen ins Fenster oder auf das Dock-Symbol)
    func addLocations(_ urls: [URL]) {
        var added: [StorageLocation] = []
        var messages: [String] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                if VideoFormats.isVideo(fileName: url.lastPathComponent) {
                    player.playExternal(url: url)
                } else {
                    messages.append("„\(url.lastPathComponent)“ ist kein Ordner.")
                }
                continue
            }
            do {
                let candidate = try LocationResolver.makeLocation(for: url)
                if let existing = try store.location(volumeKey: candidate.volumeKey, pathInVolume: candidate.pathInVolume) {
                    // Gleicher Ort: Zugriff auffrischen (z. B. nach „Zugriff erneut erteilen“)
                    var updated = existing
                    updated.bookmark = candidate.bookmark
                    updated.lastKnownPath = candidate.lastKnownPath
                    updated.volumeName = candidate.volumeName
                    updated.kind = candidate.kind
                    try store.updateLocation(updated)
                    if let i = locations.firstIndex(where: { $0.id == existing.id }) { locations[i] = updated }
                    messages.append("„\(existing.name)“ ist bereits in der Bibliothek – der Zugriff wurde aufgefrischt.")
                    Task { await resolve(updated, scanIfAvailable: true) }
                    continue
                }
                if let parent = locations.first(where: { LocationResolver.isInside(candidate, $0) && $0.pathInVolume != candidate.pathInVolume }) {
                    messages.append("„\(candidate.name)“ gehört bereits zum Speicherort „\(parent.name)“.")
                    continue
                }
                let saved = try store.insertLocation(candidate)
                locations.append(saved)
                locations.sort { LibrarySorter.compareText($0.name, $1.name) == .orderedAscending }
                added.append(saved)
                QA.log("Speicherort hinzugefügt: \(saved.name) [\(saved.volumeKey)] Pfad im Laufwerk: \"\(saved.pathInVolume)\" Art: \(saved.kind.rawValue)")
            } catch {
                messages.append("„\(url.lastPathComponent)“: \(error.localizedDescription)")
            }
        }
        for loc in added { Task { await resolve(loc, scanIfAvailable: true) } }
        if !added.isEmpty {
            showToast(added.count == 1 ? "„\(added[0].name)“ wird durchsucht …" : "\(added.count) Speicherorte werden durchsucht …",
                      systemImage: "plus.circle", tone: .success)
            if case .overview = route {} else if locations.count == added.count { navigate(.library(.all)) }
        }
        if !messages.isEmpty {
            alert = AlertInfo(title: added.isEmpty ? "Nichts hinzugefügt" : "Hinweis", message: messages.joined(separator: "\n"))
        }
    }

    /// Entfernt einen Speicherort aus der Bibliothek (Videodateien bleiben unberührt) – nach Bestätigung.
    func removeLocation(_ loc: StorageLocation) {
        player.releaseIfPlaying(locationId: loc.id)
        scanTasks[loc.id]?.cancel()
        releaseAccess(loc.id)
        let ids = films.filter { $0.locationId == loc.id }.map(\.id)
        do {
            try store.deleteLocation(id: loc.id)
        } catch {
            alert = AlertInfo(title: "Entfernen fehlgeschlagen", message: error.localizedDescription)
            return
        }
        for id in ids { covers.remove(filmId: id) }
        availability[loc.id] = nil
        volumeInfo[loc.id] = nil
        scanProgress[loc.id] = nil
        if case .library(.location(let l)) = route, l == loc.id { route = .library(.all) }
        if case .library(.folder(let l, _)) = route, l == loc.id { route = .library(.all) }
        reloadFromStore()
        showToast("„\(loc.name)“ wurde aus der Bibliothek entfernt. Die Videodateien sind unverändert.", systemImage: "minus.circle")
    }

    func renameLocation(_ loc: StorageLocation, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? store.renameLocation(id: loc.id, name: trimmed)
        if let i = locations.firstIndex(where: { $0.id == loc.id }) { locations[i].name = trimmed }
        scheduleRecompute()
    }

    /// „Fehlende Einträge entfernen“ (bewusste Aktion) – nil = alle Speicherorte
    func removeMissing(locationId: Int64?) {
        let ids = films.filter { $0.isMissing && (locationId == nil || $0.locationId == locationId) }.map(\.id)
        let n = (try? store.removeMissingFilms(locationId: locationId)) ?? 0
        for id in ids { covers.remove(filmId: id) }
        reloadFilms()
        showToast(n == 0 ? "Keine fehlenden Einträge." : "\(Fmt.count(n, "Eintrag", "Einträge")) entfernt.", systemImage: "trash")
    }

    // MARK: - Durchsuchen

    var isScanning: Bool { !scanTasks.isEmpty }

    func scanAll() {
        for loc in locations where availability[loc.id]?.isAvailable == true { scan(loc.id) }
        let unavailable = locations.filter { availability[$0.id]?.isAvailable != true }
        if !unavailable.isEmpty {
            Task { for loc in unavailable { await resolve(loc, scanIfAvailable: true) } }
        }
    }

    func scan(_ id: Int64) {
        guard scanTasks[id] == nil, let loc = location(id), let root = roots[id] else { return }
        let excluded = LocationResolver.excludedSubpaths(for: loc, among: locations)
        let heart = settings.heartFavorites
        scanProgress[id] = ScanProgress(locationId: id, phase: .enumerating)
        QA.log("Durchsuchen beginnt: \(loc.name)")
        scanTasks[id] = Task { [weak self] in
            guard let self else { return }
            let report = await self.scanner.scan(location: loc, root: root, excluding: excluded, heartFavorites: heart) { progress in
                Task { @MainActor [weak self] in
                    guard let self, self.scanTasks[id] != nil else { return }
                    self.scanProgress[id] = progress
                }
            }
            self.scanFinished(id: id, report: report)
        }
    }

    func cancelScan(_ id: Int64) {
        scanTasks[id]?.cancel()
    }

    private func scanFinished(id: Int64, report: ScanReport) {
        scanTasks[id] = nil
        scanProgress[id] = nil
        let name = locationName(id)
        let c = report.changes
        QA.log("Durchsuchen beendet: \(name) – \(report.outcome) neu \(c.inserts.count), geändert \(c.updates.count), verschoben \(c.moves.count), fehlend \(c.newlyMissing.count), wieder da \(c.reappeared.count), unverändert \(c.unchanged), Ordner ohne Zugriff \(report.unreadableFolders.count), \(String(format: "%.2f", report.duration)) s")
        switch report.outcome {
        case .completed:
            if let i = locations.firstIndex(where: { $0.id == id }) { locations[i].lastScanAt = Date() }
            reloadFilms()
            var parts: [String] = []
            if !c.inserts.isEmpty { parts.append(Fmt.count(c.inserts.count, "neuer Film", "neue Filme")) }
            if !c.newlyMissing.isEmpty { parts.append("\(c.newlyMissing.count) nicht mehr gefunden") }
            if !c.moves.isEmpty { parts.append("\(c.moves.count) umbenannt/verschoben") }
            if !parts.isEmpty { showToast("„\(name)“: " + parts.joined(separator: ", "), systemImage: "checkmark.circle", tone: .success) }
            if !report.unreadableFolders.isEmpty {
                showToast("„\(name)“: \(report.unreadableFolders.count) Ordner konnten nicht gelesen werden (keine Berechtigung).", systemImage: "lock", tone: .warning)
            }
            runMetadata()
        case .cancelled:
            break
        case .locationLost:
            showToast("„\(name)“ wurde während des Durchsuchens entfernt – es wurde nichts verändert.", systemImage: "externaldrive.badge.exclamationmark", tone: .warning)
            if let loc = location(id) { Task { await resolve(loc, scanIfAvailable: false) } }
        case .failed(let message):
            alert = AlertInfo(title: "Durchsuchen fehlgeschlagen", message: "„\(name)“: \(message)")
        }
    }

    // MARK: - Metadaten im Hintergrund

    func runMetadata() {
        if metadataTask != nil { metadataAgain = true; return }
        metadataTask = Task { [weak self] in
            await self?.metadataLoop()
            guard let self else { return }
            self.metadataTask = nil
            if self.metadataAgain {
                self.metadataAgain = false
                self.runMetadata()
            }
        }
    }

    private func metadataLoop() async {
        var skipped = Set<Int64>()
        while !Task.isCancelled {
            let available = Array(roots.keys)
            guard !available.isEmpty else { break }
            let batch = ((try? store.filmsNeedingMetadata(currentVersion: MetadataService.currentVersion, locationIds: available, limit: 40)) ?? [])
                .filter { !skipped.contains($0.id) }
            metadataRemaining = films.filter { $0.metadataVersion < MetadataService.currentVersion && !$0.isMissing && roots[$0.locationId] != nil }.count
            guard !batch.isEmpty else { break }
            let rootSnapshot = self.roots
            let preference = settings.coverPreference
            let service = metadata
            var index = 0
            // Oberfläche gebündelt aktualisieren (höchstens alle 0,5 s bzw. je 40 Filme)
            var pending: [Int64] = []
            var remaining = metadataRemaining
            var lastFlush = Date()
            while index < batch.count && !Task.isCancelled {
                let slice = Array(batch[index..<min(index + 2, batch.count)])
                index += slice.count
                await withTaskGroup(of: (Int64, Bool).self) { group in
                    for film in slice {
                        guard let root = rootSnapshot[film.locationId] else { skipped.insert(film.id); continue }
                        group.addTask {
                            let outcome = await service.process(film, locationRoot: root, preference: preference)
                            return (film.id, outcome != nil)
                        }
                    }
                    for await (id, ok) in group {
                        if ok { pending.append(id) } else { skipped.insert(id) }
                        remaining = max(0, remaining - 1)
                    }
                }
                if pending.count >= 40 || Date().timeIntervalSince(lastFlush) > 0.5 {
                    refreshFilms(pending)
                    pending.removeAll()
                    metadataRemaining = remaining
                    lastFlush = Date()
                }
            }
            refreshFilms(pending)
        }
        metadataRemaining = 0
    }

    // MARK: - Nutzeraktionen

    func toggleFavorite(_ ids: [Int64]) {
        let target = !ids.allSatisfy { film($0)?.isFavorite == true }
        try? store.setFavorite(ids: ids, target)
        ids.forEach(refreshFilm)
    }

    func setFinished(_ ids: [Int64], _ on: Bool) {
        try? store.setFinished(ids: ids, on)
        ids.forEach(refreshFilm)
    }

    func clearPlayback(_ ids: [Int64]) {
        try? store.clearPlayback(ids: ids)
        ids.forEach(refreshFilm)
        statistics = try? store.statistics()
    }

    func revealInFinder(_ films: [Film]) {
        let urls = films.compactMap { fileURL(for: $0) }
        if urls.isEmpty {
            showToast("Die Datei ist gerade nicht erreichbar.", systemImage: "exclamationmark.triangle", tone: .warning)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func revealLocation(_ loc: StorageLocation) {
        if let root = roots[loc.id] { NSWorkspace.shared.activateFileViewerSelecting([root]) }
    }

    func play(_ film: Film, in list: [Film]? = nil, fromStart: Bool = false) {
        let queue = (list ?? visibleFilms).filter { isAvailable($0) && $0.playability != .unsupported }
        player.play(film: film, queue: queue.isEmpty ? [film] : queue, fromStart: fromStart)
    }

    /// Zufälligen, verfügbaren und abspielbaren Film aus einer Liste abspielen
    func playRandom(from list: [Film]) {
        let candidates = list.filter { isAvailable($0) && $0.playability != .unsupported }
        guard let film = candidates.randomElement() else {
            showToast("Kein abspielbarer Film in dieser Ansicht", systemImage: "shuffle", tone: .info)
            return
        }
        play(film, in: candidates)
    }

    func playSelection() {
        let selected = visibleFilms.filter { selection.contains($0.id) }
        guard let first = selected.first else { return }
        play(first, in: selected.count > 1 ? selected : visibleFilms)
    }

    /// Nach Wiedergabe-Ereignissen (Position, gesehen …)
    func playbackChanged(_ id: Int64) {
        refreshFilm(id)
        statistics = try? store.statistics()
    }

    // MARK: - Sammlungen

    func createCollection(named name: String, adding ids: [Int64] = []) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let c = try? store.createCollection(name: trimmed) else { return }
        if !ids.isEmpty { try? store.addToCollection(id: c.id, filmIds: ids) }
        collections = (try? store.collections()) ?? collections
        showToast(ids.isEmpty ? "Sammlung „\(trimmed)“ angelegt." : "\(Fmt.count(ids.count, "Film", "Filme")) in „\(trimmed)“.", systemImage: "rectangle.stack.badge.plus", tone: .success)
    }

    func add(_ ids: [Int64], to collection: FilmCollection) {
        try? store.addToCollection(id: collection.id, filmIds: ids)
        collections = (try? store.collections()) ?? collections
        showToast("\(Fmt.count(ids.count, "Film", "Filme")) zu „\(collection.name)“ hinzugefügt.", systemImage: "rectangle.stack.badge.plus", tone: .success)
        scheduleRecompute()
    }

    func remove(_ ids: [Int64], from collection: FilmCollection) {
        try? store.removeFromCollection(id: collection.id, filmIds: ids)
        collections = (try? store.collections()) ?? collections
        scheduleRecompute()
    }

    func rename(_ collection: FilmCollection, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? store.renameCollection(id: collection.id, name: trimmed)
        collections = (try? store.collections()) ?? collections
    }

    func delete(_ collection: FilmCollection) {
        try? store.deleteCollection(id: collection.id)
        collections = (try? store.collections()) ?? collections
        if case .library(.collection(let id)) = route, id == collection.id { route = .library(.all) }
    }

    // MARK: - Meldungen

    func showToast(_ text: String, systemImage: String = "info.circle", tone: Toast.Tone = .info) {
        let t = Toast(text: text, systemImage: systemImage, tone: tone)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = t }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { if self?.toast?.id == t.id { self?.toast = nil } }
        }
    }

    // MARK: - Kennzahlen für Übersicht und Seitenleiste

    var availableLocationCount: Int { locations.filter { availability[$0.id]?.isAvailable == true }.count }

    var totalBytes: Int64 { films.reduce(0) { $0 + $1.sizeBytes } }

    var totalRuntime: Double { films.reduce(0) { $0 + ($1.info.durationSeconds ?? 0) } }

    func count(in scope: LibraryScope) -> Int {
        let collectionMap = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, Set($0.filmIds)) })
        let now = Date()
        return films.reduce(0) { n, f in
            n + (scope.contains(f, collections: collectionMap, isAvailable: isAvailable(f), now: now) ? 1 : 0)
        }
    }

    /// Ablauf beim Beenden: Position sichern, Zugriffe beenden
    func prepareForTermination() {
        player.saveAndClose()
        for (_, a) in accesses { a.stop() }
        accesses.removeAll()
    }
}

/// Anzahl je Dateiformat im aktuellen Bereich
struct FormatCount: Identifiable, Equatable, Sendable {
    let ext: String
    let count: Int
    var id: String { ext }
}
