import Foundation
import AVFoundation
import CoreMedia
import AppKit
import FBCore
import FBStore

/// Kapitelmarke
public struct ChapterMark: Sendable, Equatable, Hashable {
    public var title: String
    public var start: Double
    public init(title: String, start: Double) {
        self.title = title
        self.start = start
    }
}

/// Liest technische Angaben mit AVFoundation (offizielle, asynchrone Lade-Schnittstellen ab macOS 12).
public enum AVProbe {
    public struct Result: Sendable {
        public var info: VideoInfo
        /// AVFoundation kann die Datei abspielen (Container und alle Videospuren)
        public var playable: Bool
        public var artwork: Data?
        public var chapters: [ChapterMark]
    }

    static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    public static func probe(url: URL) async -> Result? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        do {
            let (duration, isPlayable, metadata) = try await asset.load(.duration, .isPlayable, .commonMetadata)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let subtitleTracks = try await asset.loadTracks(withMediaType: .subtitle)
            let captionTracks = try await asset.loadTracks(withMediaType: .closedCaption)

            var info = VideoInfo()
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite && seconds > 0 { info.durationSeconds = seconds }
            var allVideoPlayable = true
            if let v = videoTracks.first {
                let (size, transform, fps) = try await v.load(.naturalSize, .preferredTransform, .nominalFrameRate)
                let (formats, rate, trackPlayable) = try await v.load(.formatDescriptions, .estimatedDataRate, .isPlayable)
                let rect = CGRect(origin: .zero, size: size).applying(transform)
                let w = Int(abs(rect.width).rounded()), h = Int(abs(rect.height).rounded())
                if w > 0 && h > 0 { info.width = w; info.height = h }
                if fps > 0 { info.frameRate = Double(fps) }
                if let f = formats.first { info.videoCodec = Fmt.codecName(fourCC(CMFormatDescriptionGetMediaSubType(f))) }
                if rate > 0 { info.bitRate = Int(rate) }
                allVideoPlayable = trackPlayable
            }
            for t in videoTracks.dropFirst() {
                if !((try? await t.load(.isPlayable)) ?? false) { allVideoPlayable = false }
            }
            info.audioTrackCount = audioTracks.count
            if let a = audioTracks.first, let f = try await a.load(.formatDescriptions).first {
                info.audioCodec = Fmt.codecName(fourCC(CMFormatDescriptionGetMediaSubType(f)))
            }
            info.subtitleTrackCount = subtitleTracks.count + captionTracks.count

            var artwork: Data? = nil
            for item in metadata {
                if item.commonKey == .commonKeyArtwork, artwork == nil {
                    artwork = try? await item.load(.dataValue)
                } else if item.commonKey == .commonKeyTitle, info.embeddedTitle == nil {
                    if let t = try? await item.load(.stringValue), !t.trimmingCharacters(in: .whitespaces).isEmpty { info.embeddedTitle = t }
                }
            }

            let chapters = await chapterMarks(asset)
            info.chapterCount = chapters.count

            let playable = isPlayable && allVideoPlayable && (!videoTracks.isEmpty || !audioTracks.isEmpty)
            return Result(info: info, playable: playable, artwork: artwork, chapters: chapters)
        } catch {
            return nil
        }
    }

    /// Kapitel einer Datei: bevorzugt Deutsch/Englisch, sonst in der Sprache, in der die Datei sie führt
    /// (häufig „und“ = unbestimmt, z. B. bei mit ffmpeg oder HandBrake erzeugten Dateien).
    public static func chapterMarks(_ asset: AVAsset) async -> [ChapterMark] {
        let locales = (try? await asset.load(.availableChapterLocales)) ?? []
        var groups = (try? await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: ["de", "en"] + locales.map(\.identifier))) ?? []
        if groups.isEmpty {
            for locale in locales + [Locale(identifier: "und"), Locale.current] {
                groups = (try? await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [])) ?? []
                if !groups.isEmpty { break }
            }
        }
        var marks: [ChapterMark] = []
        for (i, g) in groups.enumerated() {
            let start = CMTimeGetSeconds(g.timeRange.start)
            var title = "Kapitel \(i + 1)"
            if let item = g.items.first(where: { $0.commonKey == .commonKeyTitle }),
               let t = try? await item.load(.stringValue), !t.isEmpty { title = t }
            if start.isFinite { marks.append(ChapterMark(title: title, start: max(0, start))) }
        }
        return marks
    }

    /// Einzelbild aus dem Video (AVAssetImageGenerator). Vermeidet sehr dunkle Bilder (Abblenden, Vorspann).
    public static func frame(url: URL, duration: Double?, maxPixel: Int = 900) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
        let d = duration ?? 0
        let candidates: [Double] = d > 0 ? [0.12, 0.3, 0.5, 0.05].map { min(d * $0, d - 0.1) } : [1, 0]
        var fallback: CGImage? = nil
        for t in candidates where t >= 0 {
            guard let result = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)) else { continue }
            let image = result.image
            if fallback == nil { fallback = image }
            if CoverStore.averageLuminance(image) > 0.08 { return image }
        }
        return fallback
    }
}

/// Ermittelt Metadaten und Titelbild eines Films (im Hintergrund).
public final class MetadataService: @unchecked Sendable {
    /// Erhöhen, wenn sich die Prüfung ändert → alle Filme werden einmal neu geprüft
    public static let currentVersion = 1

    public enum CoverPreference: String, Sendable, Codable, CaseIterable {
        /// Posterdatei → eingebettetes Cover → Bild aus dem Video
        case posterFirst
        /// Nur Bild aus dem Video
        case frameOnly

        public var label: String {
            switch self {
            case .posterFirst: return "Poster, sonst Bild aus dem Video"
            case .frameOnly: return "Immer Bild aus dem Video"
            }
        }
    }

    private let store: LibraryStore
    public let covers: CoverStore

    public init(store: LibraryStore, covers: CoverStore) {
        self.store = store
        self.covers = covers
    }

    public struct Outcome: Sendable {
        public var info: VideoInfo
        public var playability: Playability
        public var coverSource: CoverSource
        public var coverStamp: Int64
    }

    /// Prüft einen Film. nil = Datei gerade nicht erreichbar (Laufwerk entfernt) → später erneut versuchen,
    /// NICHT als „nicht abspielbar“ markieren.
    public func process(_ film: Film, locationRoot: URL, preference: CoverPreference) async -> Outcome? {
        guard let fileURL = RelativePath.join(locationRoot.path, film.relativePath).map({ URL(fileURLWithPath: $0) }) else { return nil }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        var info = VideoInfo()
        var playability = Playability.unsupported
        var avResult: AVProbe.Result? = nil
        var vlcFrame: CGImage? = nil
        var vlcDecodeTried = false

        if film.sizeBytes > 0 {
            let tryAVFirst = VideoFormats.prefersAVFoundation(film.fileExtension) || !VLCSupport.isAvailable
            if tryAVFirst {
                avResult = await AVProbe.probe(url: fileURL)
                if let r = avResult, r.playable {
                    info = r.info
                    playability = .native
                }
            }
            if playability != .native, VLCSupport.isAvailable {
                let (v, image, decodeTried) = await VLCSupport.analyze(url: fileURL)
                vlcDecodeTried = decodeTried
                if let v {
                    info = v
                    playability = .vlc
                    vlcFrame = image
                }
            }
            if playability == .unsupported, let r = avResult {
                info = r.info // Angaben trotzdem anzeigen (z. B. Dauer), auch wenn nicht abspielbar
            }
        }
        // Laufwerk während der Prüfung verschwunden? Dann nichts speichern.
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        try? store.updateMetadata(id: film.id, info: info, playability: playability, version: Self.currentVersion)

        // Titelbild (ein vorhandenes „zuletzt gesehenes Bild“ bleibt, solange sich die Datei nicht geändert hat)
        var source = film.coverSource
        var stamp = film.coverStamp
        let keepLastFrame = film.coverSource == .lastFrame && covers.hasCover(film.id) && film.metadataVersion > 0
        if !keepLastFrame {
            let made = await makeCover(film: film, fileURL: fileURL, info: info, playability: playability, avResult: avResult,
                                       vlcFrame: vlcFrame, vlcDecodeTried: vlcDecodeTried, preference: preference)
            if let made {
                source = made.0
                stamp = made.1
            } else {
                source = .none
                stamp = 0
                covers.remove(filmId: film.id)
            }
            try? store.updateCover(id: film.id, source: source, stamp: stamp)
        }
        return Outcome(info: info, playability: playability, coverSource: source, coverStamp: stamp)
    }

    private func makeCover(film: Film, fileURL: URL, info: VideoInfo, playability: Playability, avResult: AVProbe.Result?,
                           vlcFrame: CGImage?, vlcDecodeTried: Bool, preference: CoverPreference) async -> (CoverSource, Int64)? {
        if preference == .posterFirst {
            // 1. Posterdatei im Ordner
            let folder = fileURL.deletingLastPathComponent()
            if let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
                let videos = names.filter { VideoFormats.isVideo(fileName: $0) && !ScanRules.skipFile(named: $0) }.count
                if let poster = SidecarFiles.posterCandidate(filmFileName: film.fileName, siblingNames: names, videosInFolder: videos),
                   let stamp = try? covers.save(imageFile: folder.appendingPathComponent(poster), filmId: film.id) {
                    return (.posterFile, stamp)
                }
            }
            // 2. eingebettetes Cover
            if let data = avResult?.artwork, let stamp = try? covers.save(imageData: data, filmId: film.id) {
                return (.embedded, stamp)
            }
        }
        // 3. Bild aus dem Video
        switch playability {
        case .native:
            if let img = await AVProbe.frame(url: fileURL, duration: info.durationSeconds), let stamp = try? covers.save(img, filmId: film.id) {
                return (.videoFrame, stamp)
            }
        case .vlc:
            // Bereits bei der Prüfung dekodiertes Bild (MPEG-Programm-/Transportstrom) – kein zweiter Durchgang
            if let img = vlcFrame, let stamp = try? covers.save(img, filmId: film.id) {
                return (.videoFrame, stamp)
            }
            // Dekodieren wurde bei der Prüfung schon versucht (ohne Bild) → kein zweiter, langsamer Versuch.
            // Das Titelbild entsteht dann beim ersten Abspielen („zuletzt gesehenes Bild“).
            if vlcDecodeTried { return nil }
            var w: CGFloat = 640, h: CGFloat = 360
            if let iw = info.width, let ih = info.height, iw > 0, ih > 0 {
                h = (w * CGFloat(ih) / CGFloat(iw)).rounded()
                if h > 900 { h = 900; w = (h * CGFloat(iw) / CGFloat(ih)).rounded() }
            }
            let width = w, height = h
            if let img = await VLCSupport.thumbnail(url: fileURL, position: 0.12, width: width, height: height),
               let stamp = try? covers.save(img, filmId: film.id) {
                return (.videoFrame, stamp)
            }
        default:
            break
        }
        return nil
    }

    /// „Zuletzt gesehenes Bild“ als Titelbild übernehmen (nur wenn kein Poster/eingebettetes Cover vorhanden ist).
    public func saveLastFrame(_ image: CGImage, film: Film) -> Int64? {
        guard film.coverSource != .posterFile && film.coverSource != .embedded else { return nil }
        guard let stamp = try? covers.save(image, filmId: film.id) else { return nil }
        try? store.updateCover(id: film.id, source: .lastFrame, stamp: stamp)
        return stamp
    }
}
