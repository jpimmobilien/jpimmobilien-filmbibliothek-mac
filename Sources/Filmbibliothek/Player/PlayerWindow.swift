import SwiftUI
import AppKit
import FBCore
import FBServices

/// Verwaltet das (eine) Player-Fenster.
@MainActor
final class PlayerCoordinator {
    private weak var model: AppModel?
    private var windowController: PlayerWindowController?

    init(model: AppModel) {
        self.model = model
    }

    var controller: PlayerController? { windowController?.controller }
    var currentFilmId: Int64? { controller?.film?.id }

    private func ensureWindow() -> PlayerWindowController {
        if let wc = windowController { return wc }
        let wc = PlayerWindowController(controller: PlayerController(model: model)) { [weak self] in
            self?.windowController = nil
        }
        windowController = wc
        return wc
    }

    func play(film: Film, queue: [Film], fromStart: Bool) {
        let wc = ensureWindow()
        wc.controller.open(film: film, queue: queue, fromStart: fromStart)
        wc.present(videoSize: film.info.width.flatMap { w in film.info.height.map { CGSize(width: w, height: $0) } },
                   fullScreen: model?.settings.startFullScreen ?? false)
    }

    func playExternal(url: URL) {
        let wc = ensureWindow()
        wc.controller.open(externalURL: url)
        wc.present(videoSize: nil, fullScreen: model?.settings.startFullScreen ?? false)
    }

    /// Laufwerk wird ausgeworfen bzw. Speicherort entfernt: Datei sofort freigeben
    func releaseIfPlaying(locationId: Int64) {
        guard let c = controller, let f = c.film, f.locationId == locationId else { return }
        c.releaseForEject()
    }

    func saveAndClose() {
        controller?.closeImmediately()
    }

    func togglePlay() { controller?.togglePlay() }
    var isOpen: Bool { windowController != nil }
}

/// Fenster des Players: randlos schwarz, Inhalt bis unter die (unsichtbare) Titelleiste, Vollbild-fähig.
@MainActor
final class PlayerWindowController: NSWindowController, NSWindowDelegate {
    let controller: PlayerController
    private let onClose: () -> Void
    private var keyMonitor: Any?
    private var cancellableVisibility: NSKeyValueObservation?
    private var closing = false

    init(controller: PlayerController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.minSize = NSSize(width: 480, height: 270)
        window.title = "Filmbibliothek – Wiedergabe"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("PlayerWindow")
        super.init(window: window)
        window.delegate = self
        controller.window = window
        let root = PlayerView(controller: controller)
            .environment(\.colorScheme, .dark)
            .filmTheme()
        window.contentView = NSHostingView(rootView: root)
        installKeyHandling()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht verwendet") }

    func present(videoSize: CGSize?, fullScreen: Bool) {
        guard let window else { return }
        if !window.isVisible {
            if let size = videoSize, size.width > 0, size.height > 0, let screen = NSScreen.main {
                let maxW = screen.visibleFrame.width * 0.72, maxH = screen.visibleFrame.height * 0.72
                let scale = min(maxW / size.width, maxH / size.height, 1.5)
                window.setContentSize(NSSize(width: max(640, size.width * scale), height: max(360, size.height * scale)))
            }
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if fullScreen && !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
    }

    // MARK: - Tastatur

    private func installKeyHandling() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let c = controller
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let step = c.seekStep
        // Pfeiltasten & Co. über Tastencodes (unabhängig vom Tastaturlayout)
        switch event.keyCode {
        case 49: // Leertaste
            c.togglePlay(); return true
        case 123: // ←
            if flags.contains(.command) { c.playPrevious() } else { c.seek(by: flags.contains(.shift) ? -60 : -step) }
            return true
        case 124: // →
            if flags.contains(.command) { c.playNext() } else { c.seek(by: flags.contains(.shift) ? 60 : step) }
            return true
        case 126: // ↑
            c.changeVolume(by: 0.1); return true
        case 125: // ↓
            c.changeVolume(by: -0.1); return true
        case 53: // Esc
            if let w = window, w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil); return true }
            if c.resumePrompt != nil { c.resume(false); return true }
            return false
        case 36, 76: // Return / Enter
            if c.resumePrompt != nil { c.resume(true); return true }
            return false
        default:
            break
        }
        guard flags.isEmpty || flags == .shift, let chars = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch chars {
        case "f": window?.toggleFullScreen(nil); return true
        case "m": c.muted.toggle(); return true
        case "k": c.togglePlay(); return true
        case "j": c.seek(by: -step); return true
        case "l": c.seek(by: step); return true
        case "c", "s": c.toggleSubtitles(); return true
        case "n": c.playNext(); return true
        case "p": c.playPrevious(); return true
        case "]": c.cycleSpeed(up: true); return true
        case "[": c.cycleSpeed(up: false); return true
        case "0": c.seek(to: 0); return true
        case ".": c.nextChapter(); return true
        case ",": c.previousChapter(); return true
        default: return false
        }
    }

    // MARK: - Fenster

    func windowWillClose(_ notification: Notification) {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        let c = controller
        Task { @MainActor in
            await c.close()
        }
        onClose()
    }

    func windowDidEnterFullScreen(_ notification: Notification) { controller.setFullScreen(true) }
    func windowDidExitFullScreen(_ notification: Notification) { controller.setFullScreen(false) }

    func windowDidResignKey(_ notification: Notification) {
        controller.saveProgress(final: false)
    }
}

/// Bindet die NSView der Engine (AVPlayerLayer bzw. VLCVideoView) in SwiftUI ein.
struct VideoSurface: NSViewRepresentable {
    let view: NSView?

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        attach(view, to: host)
        return host
    }

    func updateNSView(_ host: NSView, context: Context) {
        if host.subviews.first !== view { attach(view, to: host) }
    }

    private func attach(_ view: NSView?, to host: NSView) {
        host.subviews.forEach { $0.removeFromSuperview() }
        guard let view else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
    }
}
