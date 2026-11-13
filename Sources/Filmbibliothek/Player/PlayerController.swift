import SwiftUI
import AppKit
import IOKit.pwr_mgt
import FBCore
import FBStore
import FBServices

/// Steuerung einer Wiedergabe: Engine-Wahl, Fortsetzen, Warteschlange, Speichern der Position, Untertitel.
@MainActor
final class PlayerController: ObservableObject {
    // Anzeige
    @Published private(set) var title = ""
    @Published private(set) var subtitle = ""
    @Published private(set) var film: Film?
    @Published private(set) var state: EngineState = .idle
    @Published private(set) var time: Double = 0
    @Published private(set) var duration: Double?
    @Published private(set) var chapters: [ChapterMark] = []
    @Published private(set) var audioTracks: [TrackOption] = []
    @Published private(set) var subtitleTracks: [TrackOption] = []
    @Published private(set) var selectedAudio: String?
    @Published private(set) var selectedSubtitle: String?
    @Published private(set) var externalSubtitles: [URL] = []
    @Published private(set) var activeExternalSubtitle: URL?
    @Published private(set) var subtitleText: String?
    @Published private(set) var engineName = ""
    @Published var controlsVisible = true { didSet { if controlsVisible != oldValue { updateWindowButtons() } } }
    @Published var resumePrompt: Double?
    @Published var errorMessage: String?
    @Published var seekFeedback: String?
    @Published var scrubbing: Double?
    @Published private(set) var queue = PlayQueue(ids: [], startAt: nil)
    @Published private(set) var isFullScreen = false
    @Published var rate: Double = 1 { didSet { engine?.rate = rate } }
    @Published var volume: Double = 1 { didSet { engine?.volume = volume; model?.settings.playerVolume = volume } }
    @Published var muted = false { didSet { engine?.isMuted = muted } }

    private(set) var engine: PlaybackEngine?
    @Published private(set) var engineView: NSView?
    private weak var model: AppModel?
    private var queueFilms: [Int64: Film] = [:]
    private var url: URL?
    private var cues: [SubtitleCue] = []
    private var playedSeconds: Double = 0
    private var lastTick: Date?
    private var counted = false
    private var historyEntry: Int64?
    private var lastSave = Date.distantPast
    private var hideTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var sleepAssertion: IOPMAssertionID = 0
    private var triedFallback = false
    private var pendingFromStart = false
    weak var window: NSWindow?

    init(model: AppModel?) {
        self.model = model
        volume = model?.settings.playerVolume ?? 1
    }

    var isPlaying: Bool { state == .playing }
    var seekStep: Double { model?.settings.seekStep ?? 10 }

    // MARK: - Öffnen

    func open(film: Film, queue films: [Film], fromStart: Bool) {
        saveProgress(final: true)
        queueFilms = Dictionary(uniqueKeysWithValues: films.map { ($0.id, $0) })
        queue = PlayQueue(ids: films.map(\.id), startAt: film.id, shuffle: queue.shuffled, repeatMode: queue.repeatMode)
        start(film, fromStart: fromStart)
    }

    /// Einzelne Datei abspielen, die nicht zur Bibliothek gehört (Öffnen mit …, auf das Dock-Symbol gezogen)
    func open(externalURL: URL) {
        saveProgress(final: true)
        film = nil
        queueFilms = [:]
        queue = PlayQueue(ids: [], startAt: nil)
        title = TitleCleaner.title(forFileName: externalURL.lastPathComponent)
        subtitle = externalURL.deletingLastPathComponent().lastPathComponent + " · " + externalURL.pathExtension.uppercased()
        url = externalURL
        let ext = externalURL.pathExtension.lowercased()
        setEngine(EngineFactory.make(for: .unknown, fileExtension: ext))
        findExternalSubtitles(for: externalURL)
        engine?.load(url: externalURL, startAt: nil)
        engine?.play()
    }

    private func start(_ film: Film, fromStart: Bool) {
        resetSession()
        self.film = film
        guard let model else { return }
        let display = model.settings.displayTitle(film)
        title = display
        var parts = [model.locationName(film.locationId)]
        if !film.folder.isEmpty { parts.append(film.folder) }
        parts.append(film.fileExtension.uppercased())
        subtitle = parts.joined(separator: " · ")
        if let reason = model.unavailableReason(film) {
            show(error: reason)
            return
        }
        guard let fileURL = model.fileURL(for: film) else {
            show(error: "Die Datei ist gerade nicht erreichbar.")
            return
        }
        if film.playability == .unsupported {
            show(error: "„\(film.fileName)“ kann weder mit AVFoundation noch mit VLCKit geöffnet werden – die Datei ist beschädigt oder das Format wird nicht unterstützt.")
            return
        }
        url = fileURL
        setEngine(EngineFactory.make(for: film.playability, fileExtension: film.fileExtension))
        findExternalSubtitles(for: fileURL)
        // Fortsetzen?
        let storedSize = try? model.store.positionFileSize(id: film.id)
        let decision = ResumePolicy.decide(position: film.positionSeconds, duration: film.info.durationSeconds,
                                           storedSize: storedSize ?? nil, currentSize: film.sizeBytes)
        if fromStart { load(at: nil); return }
        switch (decision, model.settings.resumeBehavior) {
        case (.offerResume(let at), .always):
            load(at: at)
        case (.offerResume(let at), .ask):
            resumePrompt = at
            state = .idle
        default:
            load(at: nil)
        }
        QA.log("Wiedergabe: \(film.fileName) mit \(engine?.name ?? "?")")
    }

    func resume(_ yes: Bool) {
        let at = resumePrompt
        resumePrompt = nil
        load(at: yes ? at : nil)
    }

    private func load(at position: Double?) {
        guard let url else { return }
        engine?.load(url: url, startAt: position)
        if let s = position { time = s }
        engine?.play()
        if let first = externalSubtitles.first, model?.settings.subtitlesOnByDefault == true { activateExternalSubtitle(first) }
        showControlsBriefly()
    }

    private func setEngine(_ new: PlaybackEngine) {
        engine?.shutdown()
        engine = new
        engineName = new.name
        new.rate = rate
        new.volume = volume
        new.isMuted = muted
        new.onChange = { [weak self] in self?.engineChanged() }
        engineView = new.videoView
    }

    private func resetSession() {
        errorMessage = nil
        resumePrompt = nil
        playedSeconds = 0
        lastTick = nil
        counted = false
        historyEntry = nil
        cues = []
        subtitleText = nil
        activeExternalSubtitle = nil
        externalSubtitles = []
        triedFallback = false
        time = 0
        duration = nil
        chapters = []
    }

    private func show(error: String) {
        engine?.shutdown()
        errorMessage = error
        state = .failed(error)
        controlsVisible = true
        QA.log("Wiedergabe nicht möglich: \(error)")
    }

    // MARK: - Ereignisse der Engine

    private func engineChanged() {
        guard let engine else { return }
        let previousState = state
        let newState = engine.state
        if case .failed(let message) = newState, state != newState {
            // AVFoundation gescheitert? Einmal mit VLCKit versuchen (z. B. MP4 mit nicht unterstütztem Codec)
            if engine.name == "AVFoundation", !triedFallback, let url, let vlc = EngineFactory.makeVLC(),
               FileManager.default.fileExists(atPath: url.path) {
                triedFallback = true
                QA.log("AVFoundation gescheitert (\(message)) – neuer Versuch mit VLCKit")
                setEngine(vlc)
                vlc.load(url: url, startAt: time > 1 ? time : nil)
                vlc.play()
                if let film { try? model?.store.updatePlayability(id: film.id, .vlc); model?.refreshFilm(film.id) }
                return
            }
            saveProgress(final: true)
            errorMessage = message
        }
        if newState == .ended && state != .ended {
            didReachEnd()
        }
        state = newState
        if scrubbing == nil { time = engine.currentTime }
        duration = engine.duration ?? film?.info.durationSeconds
        if chapters != engine.chapters { chapters = engine.chapters }
        if audioTracks != engine.audioTracks { audioTracks = engine.audioTracks }
        if subtitleTracks != engine.subtitleTracks { subtitleTracks = engine.subtitleTracks }
        selectedAudio = engine.selectedAudioTrack
        selectedSubtitle = engine.selectedSubtitleTrack
        if !cues.isEmpty { subtitleText = SubtitleParser.text(at: engine.currentTime, in: cues) }
        trackPlayback()
        updateSleepAssertion()
        // Nur bei einem Wechsel des Zustands: Die Engines melden die Zeit mehrmals pro Sekunde – würde hier jedes Mal
        // neu geplant, liefe die Wartezeit nie ab und die Steuerung bliebe dauerhaft sichtbar.
        if newState == .playing && previousState != .playing {
            scheduleHide()
        } else if newState == .paused && previousState != .paused {
            controlsVisible = true
            hideTask?.cancel()
        }
    }

    /// Zählt tatsächliche Wiedergabezeit (für „abgespielt“ nach 3 s und die Statistik) und speichert regelmäßig.
    private func trackPlayback() {
        let now = Date()
        if state == .playing, let last = lastTick {
            playedSeconds += min(1, now.timeIntervalSince(last)) * rate
        }
        lastTick = state == .playing ? now : nil
        guard let film, let store = model?.store else { return }
        if !counted && playedSeconds >= ResumePolicy.countAsPlayedAfter {
            counted = true
            historyEntry = try? store.recordPlay(id: film.id)
            model?.playbackChanged(film.id)
        }
        if state == .playing && now.timeIntervalSince(lastSave) >= ResumePolicy.saveInterval {
            saveProgress(final: false)
        }
    }

    private func didReachEnd() {
        guard let film, let model else { return }
        try? model.store.markFinishedAfterPlayback(id: film.id)
        if let h = historyEntry { try? model.store.updateHistory(entryId: h, secondsWatched: playedSeconds) }
        model.playbackChanged(film.id)
        QA.log("Film zu Ende: \(film.fileName)")
        if queue.repeatMode == .one {
            engine?.seek(to: 0)
            engine?.play()
            return
        }
        if model.settings.autoplayNext, let nextId = queue.next(), let next = queueFilms[nextId] {
            start(next, fromStart: true)
        } else {
            controlsVisible = true
        }
    }

    /// Position sichern (beim Pausieren, Schließen, Wechsel, Beenden und alle 10 s)
    func saveProgress(final: Bool) {
        guard let film, let engine, let model else { return }
        lastSave = Date()
        let t = engine.currentTime
        let d = engine.duration ?? film.info.durationSeconds
        if engine.state == .ended || (final && ResumePolicy.isNearEnd(position: t, duration: d) && t > 0) {
            if engine.state != .ended { try? model.store.markFinishedAfterPlayback(id: film.id) }
        } else if ResumePolicy.shouldStore(position: t, duration: d) {
            try? model.store.savePosition(id: film.id, seconds: t, fileSize: film.sizeBytes)
        }
        if let h = historyEntry { try? model.store.updateHistory(entryId: h, secondsWatched: playedSeconds) }
        if final { model.playbackChanged(film.id) }
    }

    /// „Zuletzt gesehenes Bild“ als Titelbild sichern (beim Schließen bzw. Wechsel)
    private func captureLastFrame() async {
        guard let film, let model, model.settings.lastFrameAsCover, let engine, counted else { return }
        guard engine.currentTime > 2, let image = await engine.snapshot() else { return }
        if model.metadata.saveLastFrame(image, film: film) != nil { model.refreshFilm(film.id) }
    }

    // MARK: - Bedienung

    func togglePlay() {
        guard let engine else { return }
        if resumePrompt != nil { resume(true); return }
        if engine.state == .playing {
            engine.pause()
            saveProgress(final: false)
        } else {
            engine.play()
        }
        showControlsBriefly()
    }

    func seek(by delta: Double) {
        guard let engine else { return }
        engine.seek(to: engine.currentTime + delta)
        time = engine.currentTime
        flash(delta > 0 ? "+\(Int(delta)) s" : "−\(Int(-delta)) s")
        showControlsBriefly()
    }

    func seek(to seconds: Double) {
        engine?.seek(to: seconds)
        time = seconds
        showControlsBriefly()
    }

    func jump(toChapter c: ChapterMark) { seek(to: c.start + 0.05) }

    func nextChapter() {
        if let c = chapters.first(where: { $0.start > time + 1 }) { jump(toChapter: c) }
    }

    func previousChapter() {
        if let c = chapters.last(where: { $0.start < time - 3 }) { jump(toChapter: c) } else { seek(to: 0) }
    }

    func changeVolume(by delta: Double) {
        volume = min(1, max(0, volume + delta))
        if muted && delta > 0 { muted = false }
        flash("Lautstärke \(Int((volume * 100).rounded())) %")
    }

    func cycleSpeed(up: Bool) {
        let speeds = SeekMath.speeds
        let i = speeds.firstIndex(where: { abs($0 - rate) < 0.01 }) ?? 2
        let j = min(speeds.count - 1, max(0, i + (up ? 1 : -1)))
        rate = speeds[j]
        flash("Geschwindigkeit " + SeekMath.speedLabel(rate))
    }

    func selectAudio(_ id: String?) { engine?.selectAudioTrack(id); engineChanged() }

    func selectSubtitle(_ id: String?) {
        deactivateExternalSubtitle()
        engine?.selectSubtitleTrack(id)
        engineChanged()
    }

    func toggleSubtitles() {
        if activeExternalSubtitle != nil || selectedSubtitle != nil {
            deactivateExternalSubtitle()
            engine?.selectSubtitleTrack(nil)
            flash("Untertitel aus")
        } else if let first = subtitleTracks.first {
            selectSubtitle(first.id)
            flash("Untertitel: \(first.title)")
        } else if let ext = externalSubtitles.first {
            activateExternalSubtitle(ext)
            flash("Untertitel: \(ext.lastPathComponent)")
        } else {
            flash("Keine Untertitel vorhanden")
        }
        engineChanged()
    }

    private func findExternalSubtitles(for fileURL: URL) {
        let folder = fileURL.deletingLastPathComponent()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        externalSubtitles = SidecarFiles.subtitleCandidates(filmFileName: fileURL.lastPathComponent, siblingNames: names)
            .map { folder.appendingPathComponent($0) }
    }

    func activateExternalSubtitle(_ url: URL) {
        guard let engine else { return }
        engine.selectSubtitleTrack(nil)
        if engine.supportsExternalSubtitles {
            if engine.addSubtitleFile(url) { activeExternalSubtitle = url; cues = [] }
        } else {
            // AVFoundation: SRT/WebVTT selbst einlesen und als eigene Ebene zeigen
            guard let data = try? Data(contentsOf: url) else { return }
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            let parsed = SubtitleParser.parse(text)
            if parsed.isEmpty {
                flash("Untertiteldatei nicht lesbar (unterstützt: SRT, WebVTT)")
                return
            }
            cues = parsed
            activeExternalSubtitle = url
        }
        engineChanged()
    }

    private func deactivateExternalSubtitle() {
        cues = []
        subtitleText = nil
        if activeExternalSubtitle != nil, engine?.supportsExternalSubtitles == true { engine?.selectSubtitleTrack(nil) }
        activeExternalSubtitle = nil
    }

    func loadSubtitleFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.message = "Untertiteldatei wählen (SRT, WebVTT; mit VLCKit auch ASS/SSA)"
        panel.prompt = "Laden"
        if let window {
            panel.beginSheetModal(for: window) { [weak self] r in
                guard r == .OK, let u = panel.url else { return }
                Task { @MainActor in
                    guard let self else { return }
                    if !self.externalSubtitles.contains(u) { self.externalSubtitles.append(u) }
                    self.activateExternalSubtitle(u)
                }
            }
        }
    }

    var hasPrevious: Bool { queue.hasPrevious }
    var hasNext: Bool { queue.hasNext }

    func playNext() {
        guard let id = queue.next(), let f = queueFilms[id] else { return }
        Task { await captureLastFrame() }
        saveProgress(final: true)
        start(f, fromStart: false)
    }

    func playPrevious() {
        // Erst an den Anfang, beim zweiten Mal zum vorherigen Film (wie in Apple-Playern)
        if time > 5 { seek(to: 0); return }
        guard let id = queue.previous(), let f = queueFilms[id] else { seek(to: 0); return }
        saveProgress(final: true)
        start(f, fromStart: false)
    }

    func setShuffle(_ on: Bool) {
        queue.setShuffle(on)
    }

    func cycleRepeat() {
        switch queue.repeatMode {
        case .off: queue.repeatMode = .all
        case .all: queue.repeatMode = .one
        case .one: queue.repeatMode = .off
        }
        flash(queue.repeatMode.label)
    }

    func openInDefaultApp() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    func revealInFinder() {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Steuerelemente ein-/ausblenden

    func userActivity() {
        if !controlsVisible { withAnimation(.easeOut(duration: 0.2)) { controlsVisible = true } }
        scheduleHide()
    }

    func showControlsBriefly() {
        withAnimation(.easeOut(duration: 0.2)) { controlsVisible = true }
        scheduleHide()
    }

    /// Fensterknöpfe (Schließen, Minimieren, Zoomen) zusammen mit der Steuerung ein- und ausblenden – wie im
    /// QuickTime Player. Im Vollbild blendet macOS die Titelleiste ohnehin selbst aus.
    private func updateWindowButtons() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let visible = controlsVisible
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = visible ? 0.2 : 0.45
            for b in buttons { b.animator().alphaValue = visible ? 1 : 0 }
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard state == .playing, resumePrompt == nil, errorMessage == nil else { return }
        let delay = model?.settings.controlsHideDelay ?? 5
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.state == .playing, self.scrubbing == nil else { return }
            withAnimation(.easeInOut(duration: 0.45)) { self.controlsVisible = false }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func flash(_ text: String) {
        seekFeedback = text
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.seekFeedback = nil }
        }
    }

    func setFullScreen(_ on: Bool) {
        isFullScreen = on
        // Nach dem Vollbild die Fensterknöpfe wieder zum Zustand der Steuerung passend zeigen
        if !on { updateWindowButtons() }
    }

    // MARK: - Ruhezustand während der Wiedergabe verhindern (VLCKit macht das nicht selbst)

    private func updateSleepAssertion() {
        if state == .playing {
            guard sleepAssertion == 0 else { return }
            var id: IOPMAssertionID = 0
            let reason = "Filmbibliothek spielt ein Video ab" as CFString
            if IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString,
                                           IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &id) == kIOReturnSuccess {
                sleepAssertion = id
            }
        } else if sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
    }

    // MARK: - Ende

    /// Laufwerk wird ausgeworfen: Datei freigeben (Position sichern), Hinweis zeigen
    func releaseForEject() {
        guard engine != nil else { return }
        saveProgress(final: true)
        engine?.shutdown()
        show(error: "Das Laufwerk wurde ausgeworfen. Die Position wurde gespeichert – nach dem erneuten Anschließen geht es dort weiter.")
        updateSleepAssertion()
    }

    func close() async {
        await captureLastFrame()
        saveProgress(final: true)
        engine?.shutdown()
        engine = nil
        engineView = nil
        state = .idle
        updateSleepAssertion()
        hideTask?.cancel()
    }

    func closeImmediately() {
        saveProgress(final: true)
        engine?.shutdown()
        engine = nil
        engineView = nil
        state = .idle
        updateSleepAssertion()
    }
}
