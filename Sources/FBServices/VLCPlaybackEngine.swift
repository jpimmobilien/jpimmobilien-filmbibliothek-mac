import Foundation
import AppKit
import FBCore

#if canImport(VLCKit)
import VLCKit

/// Wiedergabe mit VLCKit (libVLC 3) für Formate, die AVFoundation nicht öffnet.
///
/// Zustand und Zeit werden alle 0,2 s abgefragt (statt Delegate-Rückrufen aus libVLC-Threads) –
/// einfach, threadsicher und unabhängig von Feinheiten der Objective-C-Schnittstelle.
@MainActor
public final class VLCPlaybackEngine: NSObject, PlaybackEngine {
    public let name = "VLCKit"
    private let player = VLCMediaPlayer()
    private let view = VLCVideoView()
    private var url: URL?
    private var timer: Timer?
    private var wantsPlay = false
    private var started = false
    private var storedVolume: Int32 = 100
    private var muted = false
    private var lastErrorCheck = Date.distantPast

    public var onChange: (() -> Void)?
    public private(set) var state: EngineState = .idle { didSet { if state != oldValue { onChange?() } } }
    public private(set) var chapters: [ChapterMark] = []
    public let supportsExternalSubtitles = true

    public override init() {
        super.init()
        view.backColor = .black
        view.fillScreen = false
        player.drawable = view
    }

    public var videoView: NSView { view }

    public var currentTime: Double {
        let ms = player.time.intValue
        return ms > 0 ? Double(ms) / 1000 : 0
    }

    public var duration: Double? {
        guard let ms = player.media?.length.intValue, ms > 0 else { return nil }
        return Double(ms) / 1000
    }

    public var videoSize: CGSize? {
        let s = player.videoSize
        return s.width > 0 && s.height > 0 ? s : nil
    }

    public var rate: Double = 1 {
        didSet { player.rate = Float(rate) }
    }

    public var volume: Double {
        get { Double(storedVolume) / 100 }
        set {
            storedVolume = Int32((min(1, max(0, newValue)) * 100).rounded())
            if !muted { player.audio?.volume = storedVolume }
        }
    }

    public var isMuted: Bool {
        get { muted }
        set {
            muted = newValue
            player.audio?.volume = newValue ? 0 : storedVolume
        }
    }

    private static func options(names: [Any]?, indexes: [Any]?, prefix: String) -> [TrackOption] {
        let n = names ?? [], idx = indexes ?? []
        var result: [TrackOption] = []
        for (i, raw) in idx.enumerated() {
            guard let number = raw as? NSNumber, number.intValue >= 0 else { continue }
            let title = (i < n.count ? n[i] as? String : nil) ?? "Spur \(number.intValue)"
            result.append(TrackOption(id: "\(prefix)\(number.intValue)", title: title))
        }
        return result
    }

    public var audioTracks: [TrackOption] { Self.options(names: player.audioTrackNames, indexes: player.audioTrackIndexes, prefix: "a") }
    public var subtitleTracks: [TrackOption] { Self.options(names: player.videoSubTitlesNames, indexes: player.videoSubTitlesIndexes, prefix: "s") }

    public var selectedAudioTrack: String? {
        let i = player.currentAudioTrackIndex
        return i >= 0 ? "a\(i)" : nil
    }

    public var selectedSubtitleTrack: String? {
        let i = player.currentVideoSubTitleIndex
        return i >= 0 ? "s\(i)" : nil
    }

    public func load(url: URL, startAt: Double?) {
        stopTimer()
        if player.media != nil { player.stop() }
        self.url = url
        started = false
        chapters = []
        state = .loading
        let media = VLCMedia(url: url)
        if let s = startAt, s > 0 { media.addOption(":start-time=\(String(format: "%.3f", s))") }
        player.media = media
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        state = .ready
    }

    private func poll() {
        // VLCMediaPlayerState: 0 gestoppt, 1 öffnet, 2 puffert, 3 Ende, 4 Fehler, 5 spielt, 6 pausiert, 7 Spur hinzugefügt
        let raw = player.state.rawValue
        switch raw {
        case 3:
            if started { state = .ended }
        case 4:
            fail()
        case 5:
            started = true
            state = .playing
        case 6:
            state = .paused
        default:
            if player.isPlaying { started = true; state = .playing }
        }
        if chapters.isEmpty && started { loadChapters() }
        // Datei weg (Laufwerk entfernt)? libVLC meldet das nicht immer als Fehler
        if Date().timeIntervalSince(lastErrorCheck) > 2 {
            lastErrorCheck = Date()
            if let url, !FileManager.default.fileExists(atPath: url.path), state != .ended {
                fail()
            }
        }
        onChange?()
    }

    private func loadChapters() {
        let list: [Any] = player.chapterDescriptions(ofTitle: player.currentTitleIndex)
        var marks: [ChapterMark] = []
        for (i, entry) in list.enumerated() {
            guard let d = entry as? [String: Any] else { continue }
            let name = (d[VLCChapterDescriptionName] as? String) ?? "Kapitel \(i + 1)"
            let offset = (d[VLCChapterDescriptionTimeOffset] as? NSNumber)?.doubleValue ?? 0
            marks.append(ChapterMark(title: name.isEmpty ? "Kapitel \(i + 1)" : name, start: offset / 1000))
        }
        if !marks.isEmpty { chapters = marks; onChange?() }
    }

    private func fail() {
        let gone = url.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false
        state = .failed(gone ? "Die Datei ist nicht mehr erreichbar – wurde das Laufwerk entfernt?"
                             : "VLCKit kann diese Datei nicht abspielen (beschädigt oder nicht unterstütztes Format).")
        player.stop()
        stopTimer()
    }

    public func play() {
        wantsPlay = true
        if state == .ended { player.time = VLCTime(int: 0) }
        player.play()
        player.rate = Float(rate)
        if !muted { player.audio?.volume = storedVolume }
    }

    public func pause() {
        wantsPlay = false
        if player.canPause { player.pause() }
        state = .paused
    }

    public func seek(to seconds: Double) {
        let target = SeekMath.clamp(seconds, duration: duration)
        player.time = VLCTime(int: Int32(target * 1000))
        if state == .ended { state = .paused }
        onChange?()
    }

    public func selectAudioTrack(_ id: String?) {
        guard let id, let i = Int32(id.dropFirst()) else { return }
        player.currentAudioTrackIndex = i
        onChange?()
    }

    public func selectSubtitleTrack(_ id: String?) {
        if let id, let i = Int32(id.dropFirst()) {
            player.currentVideoSubTitleIndex = i
        } else {
            player.currentVideoSubTitleIndex = -1
        }
        onChange?()
    }

    @discardableResult
    public func addSubtitleFile(_ url: URL) -> Bool {
        guard let type = VLCMediaPlaybackSlaveType(rawValue: 0) else { return false }
        return player.addPlaybackSlave(url, type: type, enforce: true) == 0
    }

    public func snapshot() async -> CGImage? {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("fb-snapshot-\(UUID().uuidString).png").path
        player.saveVideoSnapshot(at: path, withWidth: 0, andHeight: 0)
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if FileManager.default.fileExists(atPath: path), let img = NSImage(contentsOfFile: path),
               let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                try? FileManager.default.removeItem(atPath: path)
                return cg
            }
        }
        try? FileManager.default.removeItem(atPath: path)
        return nil
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    public func shutdown() {
        stopTimer()
        player.stop()
        player.media = nil
        url = nil
        state = .idle
    }
}
#endif
