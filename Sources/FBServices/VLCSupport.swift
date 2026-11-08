import Foundation
import AppKit
import FBCore

#if canImport(VLCKit)
import VLCKit

/// VLCKit (libVLC 3, LGPL 2.1) – nur für Formate, die AVFoundation nicht öffnet (MKV, AVI, WMV, MPEG-PS/TS, WebM, FLV …).
public enum VLCSupport {
    public static let isAvailable = true

    /// Version der eingebundenen libVLC (für „Über“)
    public static var versionString: String {
        let lib = VLCLibrary.shared()
        return "\(lib.version) (\(lib.changeset))"
    }

    /// FourCC von libVLC (niederwertiges Byte zuerst) → Text
    static func fourCC(_ value: UInt32) -> String {
        let bytes = [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
        let s = String(bytes: bytes, encoding: .ascii) ?? ""
        return s.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    }

    /// Prüft eine Datei mit libVLC (lokal, ohne Netzwerk). nil = libVLC kann die Datei nicht lesen.
    public static func probe(url: URL, timeout: TimeInterval = 10) async -> VideoInfo? {
        let media = VLCMedia(url: url)
        // Optionen: 0 = nur lokal parsen (VLCMediaParseLocal)
        _ = media.parse(options: VLCMediaParsingOptions(rawValue: 0), timeout: Int32(timeout * 1000))
        let deadline = Date().addingTimeInterval(timeout + 1)
        // Status: 0 init, 1 skipped, 2 failed, 3 timeout, 4 done
        while media.parsedStatus.rawValue < 2 && Date() < deadline {
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        guard media.parsedStatus.rawValue == 4 else { return nil }
        let (info, hasVideo) = readInfo(media)
        // Ohne Video- und Tonspur und ohne Dauer ist das (für die Vorprüfung) keine abspielbare Datei
        guard hasVideo || info.audioTrackCount > 0 || info.durationSeconds != nil else { return nil }
        return info
    }

    /// Spuren, Dauer, Titel aus einem VLCMedia
    static func readInfo(_ media: VLCMedia) -> (VideoInfo, Bool) {
        var info = VideoInfo()
        let ms = media.length.intValue
        if ms > 0 { info.durationSeconds = Double(ms) / 1000 }
        var hasVideo = false
        for case let track as [String: Any] in media.tracksInformation {
            let type = track[VLCMediaTracksInformationType] as? String
            let codec = (track[VLCMediaTracksInformationCodec] as? NSNumber).map { fourCC($0.uint32Value) }
            if type == VLCMediaTracksInformationTypeVideo {
                if !hasVideo {
                    hasVideo = true
                    info.width = (track[VLCMediaTracksInformationVideoWidth] as? NSNumber)?.intValue
                    info.height = (track[VLCMediaTracksInformationVideoHeight] as? NSNumber)?.intValue
                    if let num = (track[VLCMediaTracksInformationFrameRate] as? NSNumber)?.doubleValue,
                       let den = (track[VLCMediaTracksInformationFrameRateDenominator] as? NSNumber)?.doubleValue, den > 0, num > 0 {
                        info.frameRate = num / den
                    }
                    info.videoCodec = Fmt.codecName(codec)
                }
            } else if type == VLCMediaTracksInformationTypeAudio {
                info.audioTrackCount += 1
                if info.audioCodec == nil { info.audioCodec = Fmt.codecName(codec) }
            } else if type == VLCMediaTracksInformationTypeText {
                info.subtitleTrackCount += 1
            }
        }
        if let w = info.width, let h = info.height, w <= 0 || h <= 0 { info.width = nil; info.height = nil }
        if let t = media.metadata(forKey: VLCMetaInformationTitle), !t.isEmpty { info.embeddedTitle = t }
        return (info, hasVideo)
    }

    // MARK: - Gründliche Prüfung durch kurzes, stummes Abspielen

    /// Eigener libVLC-Player mit Attrappen-Ausgabe (kein Bild, kein Ton) – nur für die Prüfung.
    @MainActor private static var probePlayer: VLCMediaPlayer?
    @MainActor private static var probeBusy = false

    /// Manche Container (z. B. MPEG-Programmstrom .mpg/.mpeg, Transportstrom .ts) verraten Spuren und Bildgröße erst
    /// beim Dekodieren. Dann wird die Datei ohne Bild- und Tonausgabe (Attrappen-Module) kurz abgespielt.
    /// Ergebnis: Angaben (nil = nicht abspielbar) und – wenn möglich – ein Einzelbild.
    @MainActor
    public static func deepProbe(url: URL, maxSeconds: Double = 5) async -> (VideoInfo?, CGImage?) {
        while probeBusy { try? await Task.sleep(nanoseconds: 50_000_000) }
        probeBusy = true
        defer { probeBusy = false }
        let player = probePlayer ?? VLCMediaPlayer(options: ["--aout=dummy", "--vout=dummy", "--no-osd", "--no-spu", "--no-video-title-show", "--no-stats"])
        probePlayer = player
        let media = VLCMedia(url: url)
        player.media = media
        player.play()
        let start = Date()
        var playing = false
        while Date().timeIntervalSince(start) < maxSeconds {
            try? await Task.sleep(nanoseconds: 100_000_000)
            let st = player.state.rawValue   // 0 gestoppt, 1 öffnet, 2 puffert, 3 Ende, 4 Fehler, 5 spielt, 6 pausiert
            if st == 4 { break }
            if st == 5 || player.isPlaying { playing = true }
            if st == 3 { break }
            if playing && player.time.intValue > 700 { break }
            if !playing && st == 0 && Date().timeIntervalSince(start) > 2 { break }
        }
        var result: VideoInfo? = nil
        var image: CGImage? = nil
        if playing || player.time.intValue > 0 {
            var (info, hasVideo) = readInfo(media)
            let size = player.videoSize
            if size.width > 0 && size.height > 0 {
                info.width = Int(size.width)
                info.height = Int(size.height)
                hasVideo = true
            }
            if info.durationSeconds == nil, let ms = player.media?.length.intValue, ms > 0 { info.durationSeconds = Double(ms) / 1000 }
            if hasVideo || info.audioTrackCount > 0 {
                result = info
                if hasVideo {
                    let path = FileManager.default.temporaryDirectory.appendingPathComponent("fb-probe-\(UUID().uuidString).png").path
                    player.saveVideoSnapshot(at: path, withWidth: 0, andHeight: 0)
                    for _ in 0..<15 {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        if let img = NSImage(contentsOfFile: path), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                            image = cg
                            break
                        }
                    }
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
        }
        player.stop()
        player.media = nil
        return (result, image)
    }

    /// Vollständige Prüfung: schnelle Vorprüfung, bei fehlenden Angaben gründliche Prüfung.
    public static func analyze(url: URL) async -> (VideoInfo?, CGImage?) {
        let quick = await probe(url: url)
        if let q = quick, q.width != nil, q.height != nil { return (q, nil) }
        let (deep, image) = await deepProbe(url: url)
        guard var merged = deep else { return (quick, nil) }
        if let q = quick {
            merged.videoCodec = merged.videoCodec ?? q.videoCodec
            merged.audioCodec = merged.audioCodec ?? q.audioCodec
            merged.audioTrackCount = max(merged.audioTrackCount, q.audioTrackCount)
            merged.subtitleTrackCount = max(merged.subtitleTrackCount, q.subtitleTrackCount)
            merged.durationSeconds = q.durationSeconds ?? merged.durationSeconds
            merged.frameRate = merged.frameRate ?? q.frameRate
            merged.embeddedTitle = merged.embeddedTitle ?? q.embeddedTitle
        }
        return (merged, image)
    }

    /// Vorschaubild mit libVLC (läuft auf dem Haupt-Thread, weil VLCMediaThumbnailer Zeitgeber nutzt).
    @MainActor
    public static func thumbnail(url: URL, position: Float = 0.12, width: CGFloat = 640, height: CGFloat = 360) async -> CGImage? {
        let job = ThumbnailJob()
        return await job.run(url: url, position: position, width: width, height: height)
    }

    @MainActor
    private final class ThumbnailJob: NSObject, VLCMediaThumbnailerDelegate {
        private var continuation: CheckedContinuation<CGImage?, Never>?
        private var thumbnailer: VLCMediaThumbnailer?
        private var timer: Timer?

        func run(url: URL, position: Float, width: CGFloat, height: CGFloat) async -> CGImage? {
            await withCheckedContinuation { (cont: CheckedContinuation<CGImage?, Never>) in
                continuation = cont
                let media = VLCMedia(url: url)
                let t = VLCMediaThumbnailer(media: media, andDelegate: self)
                t.thumbnailWidth = width
                t.thumbnailHeight = height
                t.snapshotPosition = position
                thumbnailer = t
                // Eigene Obergrenze zusätzlich zur VLCKit-Zeitüberschreitung
                timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.finish(nil) }
                }
                t.fetchThumbnail()
            }
        }

        private func finish(_ image: CGImage?) {
            timer?.invalidate()
            timer = nil
            guard let c = continuation else { return }
            continuation = nil
            thumbnailer = nil
            c.resume(returning: image)
        }

        nonisolated func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
            Task { @MainActor in self.finish(nil) }
        }

        nonisolated func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
            let image = thumbnail
            Task { @MainActor in self.finish(image) }
        }
    }
}

#else

/// Build ohne VLCKit: nur AVFoundation.
public enum VLCSupport {
    public static let isAvailable = false
    public static var versionString: String { "nicht enthalten" }
    public static func probe(url: URL, timeout: TimeInterval = 10) async -> VideoInfo? { nil }
    public static func analyze(url: URL) async -> (VideoInfo?, CGImage?) { (nil, nil) }
    @MainActor public static func thumbnail(url: URL, position: Float = 0.12, width: CGFloat = 640, height: CGFloat = 360) async -> CGImage? { nil }
}

#endif
