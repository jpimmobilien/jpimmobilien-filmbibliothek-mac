import Foundation
import AppKit
import AVFoundation
import CoreMedia
import FBCore

/// Ton- oder Untertitelspur zur Auswahl.
public struct TrackOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public enum EngineState: Equatable, Sendable {
    case idle, loading, ready, playing, paused, ended
    case failed(String)
}

/// Gemeinsame Schnittstelle der Wiedergabe-Engines (AVFoundation und VLCKit).
@MainActor
public protocol PlaybackEngine: AnyObject {
    var name: String { get }
    var videoView: NSView { get }
    /// Wird bei jeder Änderung (Zeit, Zustand, Spuren) gerufen
    var onChange: (() -> Void)? { get set }
    var state: EngineState { get }
    var currentTime: Double { get }
    var duration: Double? { get }
    var videoSize: CGSize? { get }
    var rate: Double { get set }
    /// 0…1
    var volume: Double { get set }
    var isMuted: Bool { get set }
    var audioTracks: [TrackOption] { get }
    var selectedAudioTrack: String? { get }
    var subtitleTracks: [TrackOption] { get }
    var selectedSubtitleTrack: String? { get }
    var chapters: [ChapterMark] { get }
    /// Lädt externe Untertitel selbst (VLC). AVFoundation: false → die App zeigt sie über eine eigene Ebene.
    var supportsExternalSubtitles: Bool { get }

    func load(url: URL, startAt: Double?)
    func play()
    func pause()
    func seek(to seconds: Double)
    func selectAudioTrack(_ id: String?)
    func selectSubtitleTrack(_ id: String?)
    @discardableResult func addSubtitleFile(_ url: URL) -> Bool
    func snapshot() async -> CGImage?
    func shutdown()
}

public extension PlaybackEngine {
    var isPlaying: Bool { state == .playing }
}

/// Fläche für AVPlayerLayer
final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht verwendet") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - AVFoundation

@MainActor
public final class AVPlaybackEngine: NSObject, PlaybackEngine {
    public let name = "AVFoundation"
    private let player = AVPlayer()
    private let view = PlayerLayerView()
    private var item: AVPlayerItem?
    private var url: URL?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var notes: [NSObjectProtocol] = []
    private var audibleGroup: AVMediaSelectionGroup?
    private var legibleGroup: AVMediaSelectionGroup?
    private var stalledSince: Date?
    private var pendingStart: Double?
    private var wantsPlay = false

    public var onChange: (() -> Void)?
    public private(set) var state: EngineState = .idle { didSet { if state != oldValue { onChange?() } } }
    public private(set) var duration: Double?
    public private(set) var videoSize: CGSize?
    public private(set) var audioTracks: [TrackOption] = []
    public private(set) var subtitleTracks: [TrackOption] = []
    public private(set) var chapters: [ChapterMark] = []
    public let supportsExternalSubtitles = false

    public override init() {
        super.init()
        view.playerLayer.player = player
        player.allowsExternalPlayback = false
    }

    public var videoView: NSView { view }

    public var currentTime: Double {
        let t = CMTimeGetSeconds(player.currentTime())
        return t.isFinite ? max(0, t) : 0
    }

    public var rate: Double = 1 {
        didSet {
            if #available(macOS 13.0, *) { player.defaultRate = Float(rate) }
            if state == .playing { player.rate = Float(rate) }
        }
    }

    public var volume: Double {
        get { Double(player.volume) }
        set { player.volume = Float(min(1, max(0, newValue))) }
    }

    public var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }

    public var selectedAudioTrack: String? {
        guard let g = audibleGroup, let o = item?.currentMediaSelection.selectedMediaOption(in: g) else { return nil }
        return g.options.firstIndex(of: o).map { "a\($0)" }
    }

    public var selectedSubtitleTrack: String? {
        guard let g = legibleGroup, let o = item?.currentMediaSelection.selectedMediaOption(in: g) else { return nil }
        return g.options.firstIndex(of: o).map { "s\($0)" }
    }

    public func load(url: URL, startAt: Double?) {
        cleanup()
        self.url = url
        state = .loading
        pendingStart = startAt
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        self.item = item
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in self?.statusChanged(item) }
        }
        let nc = NotificationCenter.default
        notes.append(nc.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.state = .ended }
        })
        notes.append(nc.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] n in
            let err = (n.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError)?.localizedDescription
            Task { @MainActor in self?.fail(err) }
        })
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        player.replaceCurrentItem(with: item)
        Task { [weak self] in await self?.loadDetails(asset: asset) }
    }

    private func loadDetails(asset: AVURLAsset) async {
        if let g = try? await asset.loadMediaSelectionGroup(for: .audible) {
            audibleGroup = g
            audioTracks = g.options.enumerated().map { TrackOption(id: "a\($0.offset)", title: Self.title(for: $0.element, index: $0.offset)) }
        }
        if let g = try? await asset.loadMediaSelectionGroup(for: .legible) {
            legibleGroup = g
            subtitleTracks = g.options.enumerated().map { TrackOption(id: "s\($0.offset)", title: Self.title(for: $0.element, index: $0.offset)) }
        }
        if let v = try? await asset.loadTracks(withMediaType: .video).first,
           let geometry = try? await v.load(.naturalSize, .preferredTransform) {
            let r = CGRect(origin: .zero, size: geometry.0).applying(geometry.1)
            videoSize = CGSize(width: abs(r.width), height: abs(r.height))
        }
        let groups = (try? await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: ["de", "en"])) ?? []
        var marks: [ChapterMark] = []
        for (i, g) in groups.enumerated() {
            let s = CMTimeGetSeconds(g.timeRange.start)
            var title = "Kapitel \(i + 1)"
            if let it = g.items.first(where: { $0.commonKey == .commonKeyTitle }), let t = try? await it.load(.stringValue), !t.isEmpty { title = t }
            if s.isFinite { marks.append(ChapterMark(title: title, start: max(0, s))) }
        }
        chapters = marks
        onChange?()
    }

    private static func title(for option: AVMediaSelectionOption, index: Int) -> String {
        var parts: [String] = []
        let name = option.displayName
        parts.append(name.isEmpty ? "Spur \(index + 1)" : name)
        if let lang = option.extendedLanguageTag ?? option.locale?.identifier,
           let local = Locale(identifier: "de_DE").localizedString(forIdentifier: lang), !name.localizedCaseInsensitiveContains(local) {
            parts.append(local)
        }
        return parts.joined(separator: " · ")
    }

    private func statusChanged(_ item: AVPlayerItem) {
        guard item === self.item else { return }
        switch item.status {
        case .readyToPlay:
            let d = CMTimeGetSeconds(item.duration)
            duration = d.isFinite && d > 0 ? d : nil
            if state == .loading {
                state = .ready
                if let s = pendingStart, s > 0 {
                    pendingStart = nil
                    player.seek(to: CMTime(seconds: SeekMath.clamp(s, duration: duration), preferredTimescale: 600),
                                toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                        Task { @MainActor in if self?.wantsPlay == true { self?.play() } }
                    }
                } else if wantsPlay {
                    play()
                }
            }
        case .failed:
            fail(item.error?.localizedDescription)
        default:
            break
        }
    }

    private func fail(_ message: String?) {
        let fileGone = url.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false
        if fileGone {
            state = .failed("Die Datei ist nicht mehr erreichbar – wurde das Laufwerk entfernt?")
        } else {
            state = .failed(message ?? "AVFoundation kann diese Datei nicht abspielen.")
        }
        player.pause()
    }

    private func tick() {
        // Datei während der Wiedergabe verschwunden (Laufwerk abgezogen)? AVPlayer wartet dann oft endlos.
        if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            if stalledSince == nil { stalledSince = Date() }
            if let s = stalledSince, Date().timeIntervalSince(s) > 2.5, let url, !FileManager.default.fileExists(atPath: url.path) {
                fail(nil)
            }
        } else {
            stalledSince = nil
        }
        onChange?()
    }

    public func play() {
        wantsPlay = true
        guard state != .loading, item?.status == .readyToPlay else { return }
        if state == .ended { player.seek(to: .zero) }
        player.playImmediately(atRate: Float(rate))
        state = .playing
    }

    public func pause() {
        wantsPlay = false
        player.pause()
        if state == .playing || state == .ready { state = .paused }
    }

    public func seek(to seconds: Double) {
        let target = SeekMath.clamp(seconds, duration: duration)
        if state == .loading { pendingStart = target; return }
        if state == .ended { state = .paused }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: 600),
                    toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: 600))
        onChange?()
    }

    public func selectAudioTrack(_ id: String?) {
        guard let g = audibleGroup, let item else { return }
        if let id, let i = Int(id.dropFirst()), g.options.indices.contains(i) { item.select(g.options[i], in: g) }
        onChange?()
    }

    public func selectSubtitleTrack(_ id: String?) {
        guard let g = legibleGroup, let item else { return }
        if let id, let i = Int(id.dropFirst()), g.options.indices.contains(i) {
            item.select(g.options[i], in: g)
        } else {
            item.select(nil, in: g)
        }
        onChange?()
    }

    public func addSubtitleFile(_ url: URL) -> Bool { false }

    public func snapshot() async -> CGImage? {
        guard let asset = item?.asset else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 900, height: 900)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        return try? await generator.image(at: player.currentTime()).image
    }

    private func cleanup() {
        if let t = timeObserver { player.removeTimeObserver(t) }
        timeObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        notes.forEach { NotificationCenter.default.removeObserver($0) }
        notes.removeAll()
        audibleGroup = nil
        legibleGroup = nil
        audioTracks = []
        subtitleTracks = []
        chapters = []
        duration = nil
        videoSize = nil
        stalledSince = nil
    }

    public func shutdown() {
        player.pause()
        cleanup()
        player.replaceCurrentItem(with: nil)
        item = nil
        url = nil
        state = .idle
    }
}

/// Wählt die passende Engine für einen Film.
@MainActor
public enum EngineFactory {
    public static func make(for playability: Playability, fileExtension: String) -> PlaybackEngine {
        switch playability {
        case .native: return AVPlaybackEngine()
        case .vlc: return makeVLC() ?? AVPlaybackEngine()
        case .unknown, .unsupported:
            // Noch nicht geprüft: Apple-Formate mit AVFoundation, sonst VLC
            if VideoFormats.prefersAVFoundation(fileExtension) { return AVPlaybackEngine() }
            return makeVLC() ?? AVPlaybackEngine()
        }
    }

    public static func makeVLC() -> PlaybackEngine? {
        #if canImport(VLCKit)
        return VLCPlaybackEngine()
        #else
        return nil
        #endif
    }
}
