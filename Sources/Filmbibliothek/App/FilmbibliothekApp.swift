import SwiftUI
import AppKit
import FBCore
import FBServices

@main
struct FilmbibliothekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Filmbibliothek", id: "main") {
            MainView()
                .environmentObject(delegate.model)
                .environmentObject(delegate.settings)
                .filmTheme()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 860)
        .commands { AppCommands(model: delegate.model, settings: delegate.settings) }

        Settings {
            SettingsView()
                .environmentObject(delegate.model)
                .environmentObject(delegate.settings)
                .filmTheme()
        }
        .windowStyle(.hiddenTitleBar)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: AppSettings
    let model: AppModel
    private var pendingOpen: [URL] = []
    private var launched = false
    private var keyMonitor: Any?

    override init() {
        let s = AppSettings()
        settings = s
        model = AppModel(settings: s)
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        settings.applyAppearance()
        if SnapshotRunner.isRequested { NSApp.setActivationPolicy(.regular) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launched = true
        installLibraryKeys()
        if !pendingOpen.isEmpty {
            let urls = pendingOpen
            pendingOpen = []
            model.addLocations(urls)
        }
        if SnapshotRunner.isRequested {
            Task { await SnapshotRunner.run(model: model, settings: settings) }
        } else if QAScenario.isRequested {
            Task { await QAScenario.run(model: model) }
        }
    }

    /// Ordner/Laufwerke aufs Dock-Symbol gezogen bzw. „Öffnen mit …“ → Sandbox-Zugriff wird von macOS gewährt
    func application(_ application: NSApplication, open urls: [URL]) {
        QA.log("Öffnen-Ereignis: \(urls.map(\.path))")
        if launched { model.addLocations(urls) } else { pendingOpen.append(contentsOf: urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { for w in sender.windows where w.canBecomeMain { w.makeKeyAndOrderFront(nil); return false } }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.prepareForTermination()
        QA.log("Beendet")
    }

    /// Pfeiltasten im Raster/in der Liste des Hauptfensters (ohne aktives Textfeld)
    private func installLibraryKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, let window = event.window, window.identifier?.rawValue.contains("main") == true || window.title == "Filmbibliothek" else { return event }
            if window.firstResponder is NSTextView { return event }
            guard case .library = self.model.route else { return event }
            let flags = event.modifierFlags.intersection([.command, .option, .control])
            guard flags.isEmpty else { return event }
            let list = self.model.visibleFilms
            guard !list.isEmpty else { return event }
            let current = self.model.selection.count == 1 ? list.firstIndex { $0.id == self.model.selection.first } : nil
            let columns = self.model.settings.viewMode == .list ? 1 : max(1, Int((window.frame.width - 300) / (self.model.settings.viewMode == .compactGrid ? 180 : 250)))
            var target: Int?
            switch event.keyCode {
            case 123: target = (current ?? 1) - 1          // ←
            case 124: target = (current ?? -1) + 1         // →
            case 125: target = (current ?? -columns) + columns  // ↓
            case 126: target = (current ?? columns) - columns   // ↑
            case 49: // Leertaste: Informationen
                if let c = current { self.model.navigate(.detail(list[c].id)); return nil }
                return event
            default: return event
            }
            if let t = target {
                let i = min(max(0, t), list.count - 1)
                self.model.selection = [list[i].id]
                return nil
            }
            return event
        }
    }
}

/// Menüleiste mit Tastaturkurzbefehlen
struct AppCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    private var selectedFilms: [Film] { model.selection.compactMap { model.film($0) } }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Speicherort hinzufügen …") { model.showAddLocationPanel() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Alle Speicherorte durchsuchen") { model.scanAll() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.locations.isEmpty)
        }
        CommandGroup(after: .sidebar) {
            Button(model.sidebarVisible ? "Seitenleiste ausblenden" : "Seitenleiste einblenden") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.sidebarVisible.toggle() }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            Divider()
            ForEach(Array(AppSettings.ViewMode.allCases.enumerated()), id: \.offset) { i, mode in
                Button(mode.label) { settings.viewMode = mode }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            Divider()
            Button("Übersicht") { model.navigate(.overview) }.keyboardShortcut("1", modifiers: [.command, .shift])
            Button("Alle Filme") { model.navigate(.library(.all)) }.keyboardShortcut("2", modifiers: [.command, .shift])
            Button("Weiterschauen") { model.navigate(.library(.continueWatching)) }.keyboardShortcut("3", modifiers: [.command, .shift])
            Button("Favoriten") { model.navigate(.library(.favorites)) }.keyboardShortcut("4", modifiers: [.command, .shift])
            Button("Speicherorte") { model.navigate(.locations) }.keyboardShortcut("5", modifiers: [.command, .shift])
            Divider()
        }
        CommandMenu("Film") {
            Button("Abspielen") { model.playSelection() }
                .disabled(selectedFilms.isEmpty)
            Button("Informationen") { if let f = selectedFilms.first { model.navigate(.detail(f.id)) } }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(selectedFilms.isEmpty)
            Divider()
            Button("Favorit an/aus") { model.toggleFavorite(selectedFilms.map(\.id)) }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(selectedFilms.isEmpty)
            Button("Als gesehen markieren") { model.setFinished(selectedFilms.map(\.id), true) }
                .disabled(selectedFilms.isEmpty)
            Button("Als nicht gesehen markieren") { model.setFinished(selectedFilms.map(\.id), false) }
                .disabled(selectedFilms.isEmpty)
            Divider()
            Button("Im Finder zeigen") { model.revealInFinder(selectedFilms) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(selectedFilms.isEmpty)
            Button("Alle auswählen") { model.selection = Set(model.visibleFilms.map(\.id)) }
                .keyboardShortcut("a", modifiers: .command)
            Divider()
            Button("Zurück") { model.goBack() }
                .keyboardShortcut("[", modifiers: .command)
        }
        CommandMenu("Wiedergabe") {
            Button("Wiedergabe/Pause") { model.player.togglePlay() }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(!model.player.isOpen)
            Button("Nächster Film") { model.player.controller?.playNext() }
                .disabled(!model.player.isOpen)
            Button("Vorheriger Film") { model.player.controller?.playPrevious() }
                .disabled(!model.player.isOpen)
            Divider()
            Button("Untertitel an/aus") { model.player.controller?.toggleSubtitles() }
                .disabled(!model.player.isOpen)
            Button("Untertiteldatei laden …") { model.player.controller?.loadSubtitleFile() }
                .disabled(!model.player.isOpen)
        }
        CommandGroup(replacing: .help) {
            Button("Hilfe zur Filmbibliothek") {
                if let url = Bundle.main.url(forResource: "Anleitung", withExtension: "html") { NSWorkspace.shared.open(url) }
            }
        }
    }
}
