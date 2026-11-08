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

    // MARK: - Prüfung durch Dekodieren (MPEG-Programm-/Transportstrom)

    /// Vollständige Prüfung einer Datei, die AVFoundation nicht öffnet.
    ///
    /// 1. Schnelle Vorprüfung (libVLC liest den Container).
    /// 2. Fehlen Bildgröße oder Spuren (typisch für MPEG-Programmstrom .mpg/.mpeg und Transportstrom .ts/.mts/.m2ts,
    ///    deren Spuren erst beim Dekodieren bekannt werden), wird mit dem Vorschaubild-Dienst von VLCKit ein Bild
    ///    dekodiert – über die gemeinsame libVLC, ohne Fenster und ohne Ton. Danach kennt libVLC die Spuren.
    /// Ergebnis: Angaben (nil = nicht abspielbar) und – falls dekodiert – ein Vorschaubild.
    public static func analyze(url: URL) async -> (VideoInfo?, CGImage?) {
        let quick = await probe(url: url)
        if let q = quick, q.width != nil, q.height != nil { return (q, nil) }
        let container = ContainerSniffer.sniff(url: url)
        // Weder libVLC noch die Dateisignatur erkennen ein Video → nicht abspielbar
        guard quick != nil || container != nil else { return (nil, nil) }
        let decoded = await decode(url: url)
        var info = quick ?? VideoInfo()
        if let d = decoded.info {
            info.width = info.width ?? d.width
            info.height = info.height ?? d.height
            info.frameRate = info.frameRate ?? d.frameRate
            info.videoCodec = info.videoCodec ?? d.videoCodec
            info.audioCodec = info.audioCodec ?? d.audioCodec
            info.audioTrackCount = max(info.audioTrackCount, d.audioTrackCount)
            info.subtitleTrackCount = max(info.subtitleTrackCount, d.subtitleTrackCount)
            info.durationSeconds = info.durationSeconds ?? d.durationSeconds
        }
        var image = decoded.image
        if let img = image, let w = info.width, let h = info.height, w > 0, h > 0 {
            image = rescale(img, toAspect: CGFloat(w) / CGFloat(h))
        }
        // Signatur erkannt, aber nichts dekodierbar und keine Vorprüfung → nicht als abspielbar ausgeben
        if quick == nil && decoded.info == nil && image == nil { return (nil, nil) }
        return (info, image)
    }

    /// Dekodiert ein Vorschaubild (erst bei 12 %, sonst am Anfang) und liest danach die Spuren aus.
    @MainActor
    static func decode(url: URL) async -> (image: CGImage?, info: VideoInfo?) {
        for position: Float in [0.12, 0.0] {
            let media = VLCMedia(url: url)
            let image = await ThumbnailJob().run(media: media, position: position, width: 640, height: 360)
            let (info, hasVideo) = readInfo(media)
            if image != nil || hasVideo { return (image, hasVideo ? info : nil) }
        }
        return (nil, nil)
    }

    /// Bringt ein Vorschaubild auf das echte Seitenverhältnis (VLCKit liefert die angefragte Größe).
    static func rescale(_ image: CGImage, toAspect aspect: CGFloat) -> CGImage {
        let current = CGFloat(image.width) / CGFloat(max(1, image.height))
        guard aspect.isFinite, aspect > 0, abs(current - aspect) / aspect > 0.03 else { return image }
        let height = image.height
        let width = max(1, Int((CGFloat(height) * aspect).rounded()))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? image
    }

    /// Vorschaubild mit libVLC (läuft auf dem Haupt-Thread, weil VLCMediaThumbnailer Zeitgeber nutzt).
    @MainActor
    public static func thumbnail(url: URL, position: Float = 0.12, width: CGFloat = 640, height: CGFloat = 360) async -> CGImage? {
        await ThumbnailJob().run(media: VLCMedia(url: url), position: position, width: width, height: height)
    }

    @MainActor
    private final class ThumbnailJob: NSObject, VLCMediaThumbnailerDelegate {
        private var continuation: CheckedContinuation<CGImage?, Never>?
        private var thumbnailer: VLCMediaThumbnailer?
        private var timer: Timer?

        func run(media: VLCMedia, position: Float, width: CGFloat, height: CGFloat) async -> CGImage? {
            await withCheckedContinuation { (cont: CheckedContinuation<CGImage?, Never>) in
                continuation = cont
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
