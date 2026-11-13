import SwiftUI
import AppKit
import FBCore
import FBServices

/// Automatische Abläufe für die CI (GitHub Actions). Nur aktiv mit dem Startargument `--qa-scenario <Name>`.
///
/// Die Abläufe benutzen ausschließlich die normalen Funktionen der App (Speicherort über Öffnen-Ereignis,
/// Durchsuchen, Metadaten, Wiedergabe) und schreiben Ergebniszeilen „QA-RESULT …“ ins macOS-Protokoll
/// (und bei FB_QA=1 auf die Standardausgabe). Es werden keine Daten erfunden.
@MainActor
enum QAScenario {
    static var isRequested: Bool { CommandLine.arguments.contains("--qa-scenario") }

    static var name: String {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--qa-scenario"), i + 1 < a.count { return a[i + 1] }
        return "report"
    }

    static var quitWhenDone: Bool { CommandLine.arguments.contains("--qa-quit") }

    static func result(_ s: String) { QA.log("QA-RESULT " + s) }

    /// Wartet, bis Durchsuchen und Analyse fertig sind (höchstens `timeout` Sekunden)
    static func waitUntilIdle(_ model: AppModel, timeout: Double = 240) async -> Bool {
        let start = Date()
        // kurz warten, damit Öffnen-Ereignisse und Prüfungen anlaufen
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        while Date().timeIntervalSince(start) < timeout {
            let unknown = model.locations.contains { model.availabilityOf(location: $0.id) == .unknown }
            if !model.isScanning && model.metadataRemaining == 0 && !unknown {
                // noch einmal kurz warten (letzte Metadaten-Runde)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if !model.isScanning && model.metadataRemaining == 0 { return true }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    static func report(_ model: AppModel) {
        result("sandbox=\(QA.isSandboxed) arch=\(QA.architecture) translated=\(QA.isTranslated) glass=\(LiquidGlass.isAvailable) vlckit=\(VLCSupport.isAvailable)")
        for loc in model.locations {
            let films = model.films.filter { $0.locationId == loc.id }
            result("location name=\"\(loc.name)\" key=\(loc.volumeKey) kind=\(loc.kind.rawValue) status=\(model.availabilityOf(location: loc.id).label) films=\(films.count) missing=\(films.filter(\.isMissing).count) bookmark=\(loc.bookmark != nil)")
        }
        let f = model.films
        result("films total=\(f.count) native=\(f.filter { $0.playability == .native }.count) vlc=\(f.filter { $0.playability == .vlc }.count) unsupported=\(f.filter { $0.playability == .unsupported }.count) unknown=\(f.filter { $0.playability == .unknown }.count) covers=\(f.filter { $0.coverSource != CoverSource.none }.count)")
        for film in f.sorted(by: { $0.relativePath < $1.relativePath }) {
            result("film path=\"\(film.relativePath)\" engine=\(film.playability.label) duration=\(film.info.durationSeconds.map { String(format: "%.2f", $0) } ?? "-") size=\(film.info.width ?? 0)x\(film.info.height ?? 0) fps=\(film.info.frameRate.map { String(format: "%.2f", $0) } ?? "-") vcodec=\(film.info.videoCodec ?? "-") acodec=\(film.info.audioCodec ?? "-") audio=\(film.info.audioTrackCount) subs=\(film.info.subtitleTrackCount) chapters=\(film.info.chapterCount) cover=\(film.coverSource.label) missing=\(film.isMissing)")
        }
    }

    private static weak var controlledModel: AppModel?

    /// Steuerung von außen (nur im QA-Modus) über Darwin-Benachrichtigungen:
    /// `notifyutil -p de.privateapp.filmbibliothek.qa.quit` bzw. `… .qa.report`
    static func installRemoteControl(_ model: AppModel) {
        controlledModel = model
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in ["de.privateapp.filmbibliothek.qa.quit", "de.privateapp.filmbibliothek.qa.report"] {
            CFNotificationCenterAddObserver(center, nil, { _, _, cfName, _, _ in
                guard let raw = cfName?.rawValue else { return }
                let n = raw as String
                Task { @MainActor in QAScenario.handleRemote(n) }
            }, name as CFString, nil, .deliverImmediately)
        }
    }

    static func handleRemote(_ name: String) {
        if name.hasSuffix(".qa.quit") {
            result("quit-request")
            NSApp.terminate(nil)
        } else if name.hasSuffix(".qa.report"), let model = controlledModel {
            Task { @MainActor in
                _ = await waitUntilIdle(model, timeout: 120)
                report(model)
                result("report-done")
            }
        }
    }

    static func run(model: AppModel) async {
        installRemoteControl(model)
        result("scenario=\(name) start")
        let idle = await waitUntilIdle(model)
        result("idle=\(idle)")
        report(model)
        if name == "playback" { await playback(model) }
        result("scenario=\(name) done")
        if quitWhenDone {
            try? await Task.sleep(nanoseconds: 800_000_000)
            NSApp.terminate(nil)
        }
    }

    /// Spielt je Engine einen Film einige Sekunden ab und prüft, dass die Zeit fortschreitet.
    static func playback(_ model: AppModel) async {
        var picks: [Film] = []
        if let n = model.films.first(where: { $0.playability == .native && model.isAvailable($0) }) { picks.append(n) }
        if let v = model.films.first(where: { $0.playability == .vlc && model.isAvailable($0) }) { picks.append(v) }
        if let u = model.films.first(where: { $0.playability == .unsupported }) { picks.append(u) }
        for film in picks {
            model.play(film, in: [film], fromStart: true)
            var samples: [Double] = []
            for _ in 0..<12 {
                try? await Task.sleep(nanoseconds: 400_000_000)
                samples.append(model.player.controller?.time ?? -1)
            }
            let c = model.player.controller
            let advanced = (samples.last ?? 0) - (samples.first ?? 0)
            // Ohne Maus und Tastatur muss sich die Steuerung nach der eingestellten Zeit ausblenden
            if c?.state == .playing {
                try? await Task.sleep(nanoseconds: UInt64((model.settings.controlsHideDelay - 4.8 + 2.5) * 1_000_000_000))
            }
            let controls = c?.controlsVisible == false ? "aus" : "an"
            result("playback path=\"\(film.relativePath)\" engine=\(c?.engineName ?? "-") state=\(String(describing: c?.state ?? .idle)) advanced=\(String(format: "%.2f", advanced)) controls=\(controls) error=\(c?.errorMessage ?? "-")")
            c?.closeImmediately()
        }
        NSApp.windows.filter { $0.title.contains("Wiedergabe") }.forEach { $0.close() }
    }
}
