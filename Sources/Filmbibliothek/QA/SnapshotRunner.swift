import SwiftUI
import AppKit
import FBCore
import FBServices

/// Vorschaubilder der Oberfläche für die Sichtprüfung in der CI.
///
/// Aufruf (nur außerhalb der Sandbox, mit eigenem Datenordner):
///   FB_DATA_DIR=/tmp/fb-daten Filmbibliothek --snapshot <Ausgabeordner> --library <Ordner mit Testvideos>
///
/// Ablauf mit echten Funktionen: Testordner hinzufügen → durchsuchen → analysieren → zwei Favoriten setzen →
/// einen längeren Testfilm 12 s tatsächlich abspielen (→ „Weiterschauen“) → Ansichten in Hell und Dunkel aufnehmen.
@MainActor
enum SnapshotRunner {
    static var isRequested: Bool { CommandLine.arguments.contains("--snapshot") }

    static func argument(_ name: String) -> String? {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
        return nil
    }

    struct Shot {
        let name: String
        let size: CGSize
        let prepare: @MainActor (AppModel, AppSettings) async -> Void
        var window: WindowKind = .main
    }

    enum WindowKind { case main, settings, player }

    static func run(model: AppModel, settings: AppSettings) async {
        guard let outPath = argument("--snapshot") else { return }
        let out = URL(fileURLWithPath: outPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var manifest: [[String: String]] = []
        print("[Snapshot] Ausgabe: \(out.path)")

        if let lib = argument("--library") {
            model.addLocations([URL(fileURLWithPath: lib, isDirectory: true)])
        }
        let idle = await QAScenario.waitUntilIdle(model, timeout: 300)
        print("[Snapshot] Bibliothek bereit: \(idle), \(model.films.count) Filme")
        QAScenario.report(model)

        // Echte Nutzeraktionen
        let sorted = model.films.sorted { $0.relativePath < $1.relativePath }
        let favs = sorted.filter { $0.playability != .unsupported }.prefix(3).map(\.id)
        if !favs.isEmpty { model.toggleFavorite(Array(favs)) }
        if let long = sorted.first(where: { ($0.info.durationSeconds ?? 0) > 60 && model.isAvailable($0) }) {
            model.play(long, in: [long], fromStart: true)
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            if let c = model.player.controller {
                c.togglePlay() // Pause → Position wird gespeichert
                try? await Task.sleep(nanoseconds: 500_000_000)
                await c.close()
            }
            NSApp.windows.filter { $0.title.contains("Wiedergabe") }.forEach { $0.close() }
            print("[Snapshot] Wiedergabe für „Weiterschauen“: \(long.fileName)")
        }
        if let short = sorted.first(where: { $0.playability == .native && ($0.info.durationSeconds ?? 0) < 60 }) {
            model.setFinished([short.id], true)
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let firstNative = sorted.first { $0.playability == .native && $0.coverSource != CoverSource.none }
        let firstVLC = sorted.first { $0.playability == .vlc }
        let main = CGSize(width: 1440, height: 900)
        var shots: [Shot] = [
            Shot(name: "01-uebersicht", size: main) { m, _ in m.navigate(.overview) },
            Shot(name: "02-alle-filme-gross", size: main) { m, s in s.viewMode = .largeGrid; m.navigate(.library(.all)) },
            Shot(name: "03-alle-filme-kompakt", size: main) { m, s in s.viewMode = .compactGrid; m.navigate(.library(.all)) },
            Shot(name: "04-alle-filme-liste", size: main) { m, s in s.viewMode = .list; m.navigate(.library(.all)) },
            Shot(name: "05-poster-2zu3", size: main) { m, s in s.viewMode = .largeGrid; s.tileShape = .poster; m.navigate(.library(.all)) },
            Shot(name: "06-weiterschauen", size: main) { m, s in s.tileShape = .widescreen; m.navigate(.library(.continueWatching)) },
            Shot(name: "07-suche-filter", size: main) { m, s in
                s.viewMode = .largeGrid
                m.navigate(.library(.all))
                m.searchText = "testfilm -mp4"
                var f = LibraryFilter()
                f.availability = .available
                m.filter = f
            },
            Shot(name: "08-speicherorte", size: main) { m, _ in m.searchText = ""; m.filter = LibraryFilter(); m.navigate(.locations) },
            Shot(name: "10-kleines-fenster", size: CGSize(width: 960, height: 640)) { m, _ in m.navigate(.library(.all)) },
            Shot(name: "20-einstellungen", size: CGSize(width: 860, height: 640), prepare: { _, _ in SettingsOpener.open() }, window: .settings),
        ]
        if let f = firstNative {
            shots.insert(Shot(name: "09-details", size: main) { m, _ in m.navigate(.detail(f.id)) }, at: 8)
        }
        if let f = firstVLC {
            shots.append(Shot(name: "30-player-vlc", size: CGSize(width: 1280, height: 720), prepare: { m, _ in
                m.play(f, in: [f], fromStart: true)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                m.player.controller?.togglePlay()
                m.player.controller?.showControlsBriefly()
            }, window: .player))
        }
        if let f = firstNative {
            shots.append(Shot(name: "31-player-avfoundation", size: CGSize(width: 1280, height: 720), prepare: { m, _ in
                m.play(f, in: [f], fromStart: true)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                m.player.controller?.togglePlay()
                m.player.controller?.showControlsBriefly()
            }, window: .player))
        }

        for dark in [true, false] {
            settings.appearance = dark ? .dark : .light
            for shot in shots {
                await shot.prepare(model, settings)
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard let window = findWindow(shot.window) else {
                    print("[Snapshot] Fenster fehlt für \(shot.name)")
                    manifest.append(["file": "", "name": shot.name, "method": "failed"])
                    continue
                }
                if shot.window != .player || !window.styleMask.contains(.fullScreen) {
                    window.setContentSize(shot.size)
                    if let screen = NSScreen.main {
                        let v = screen.visibleFrame
                        window.setFrameTopLeftPoint(NSPoint(x: v.minX + 10, y: v.maxY - 10))
                    }
                }
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                let file = out.appendingPathComponent("\(shot.name)-\(dark ? "dunkel" : "hell").png")
                let method = capture(window, to: file)
                print("[Snapshot] \(file.lastPathComponent): \(method)")
                manifest.append(["file": file.lastPathComponent, "name": shot.name, "method": method, "appearance": dark ? "dunkel" : "hell"])
                if shot.window == .player {
                    model.player.controller?.closeImmediately()
                    window.close()
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
                if shot.window == .settings { window.close() }
            }
        }
        let info: [String: Any] = [
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "architecture": QA.architecture,
            "rosetta": QA.isTranslated,
            "glass": LiquidGlass.modeDescription,
            "vlckit": VLCSupport.isAvailable ? VLCSupport.versionString : "nein",
            "films": model.films.count,
            "images": manifest,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: out.appendingPathComponent("manifest.json"))
        }
        print("[Snapshot] fertig: \(manifest.count) Bilder")
        fflush(stdout)
        NSApp.terminate(nil)
    }

    static func findWindow(_ kind: WindowKind) -> NSWindow? {
        let windows = NSApp.windows.filter { $0.isVisible && $0.canBecomeKey }
        switch kind {
        case .player: return windows.first { $0.title.contains("Wiedergabe") }
        case .settings: return windows.first { $0.identifier?.rawValue.lowercased().contains("settings") == true || $0.title.contains("Einstellungen") || $0.title.contains("Settings") }
        case .main: return windows.first { $0.identifier?.rawValue.contains("main") == true || $0.title == "Filmbibliothek" } ?? windows.first
        }
    }

    /// Fensterbild über den WindowServer (mit echter Unschärfe/Liquid Glass), sonst die Ansicht selbst
    static func capture(_ window: NSWindow, to url: URL) -> String {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let fn = unsafeBitCast(sym, to: CreateImage.self)
            // kCGWindowListOptionIncludingWindow = 1 << 3; kCGWindowImageBoundsIgnoreFraming = 1 << 0, BestResolution = 1 << 3
            if let img = fn(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue(), img.width > 10 {
                let rep = NSBitmapImageRep(cgImage: img)
                if let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil { return "window-server" }
            }
        }
        if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
                return "cache-display"
            }
        }
        return "failed"
    }
}
