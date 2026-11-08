import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import FBCore

/// Titelbilder im Cache der App (`~/Library/Containers/…/Caches/Covers/<Film-ID>.jpg`).
///
/// Es werden nur verkleinerte Kopien gespeichert (lange Seite höchstens 900 Pixel) – nie etwas neben den Filmen.
/// Fehlt ein Laufwerk, bleiben die Titelbilder trotzdem sichtbar.
public final class CoverStore: @unchecked Sendable {
    public let directory: URL
    private let memory = NSCache<NSString, NSImage>()
    public static let maxPixel = 900

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 600
    }

    public func fileURL(for filmId: Int64) -> URL {
        directory.appendingPathComponent("\(filmId).jpg")
    }

    public func hasCover(_ filmId: Int64) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: filmId).path)
    }

    private static func stampNow() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// Speichert ein Bild als Titelbild; gibt den neuen Zeitstempel zurück.
    @discardableResult
    public func save(_ image: CGImage, filmId: Int64) throws -> Int64 {
        let scaled = Self.downscale(image, maxPixel: Self.maxPixel) ?? image
        let target = fileURL(for: filmId)
        let temp = directory.appendingPathComponent(".\(filmId)-\(UUID().uuidString).jpg")
        guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: temp)
            throw CocoaError(.fileWriteUnknown)
        }
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: target)
        }
        invalidate(filmId)
        return Self.stampNow()
    }

    /// Speichert Bilddaten (z. B. eingebettetes Cover, Posterdatei)
    @discardableResult
    public func save(imageData: Data, filmId: Int64) throws -> Int64 {
        guard let image = Self.decode(data: imageData) else { throw CocoaError(.fileReadCorruptFile) }
        return try save(image, filmId: filmId)
    }

    @discardableResult
    public func save(imageFile url: URL, filmId: Int64) throws -> Int64 {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let image = Self.thumbnail(src) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try save(image, filmId: filmId)
    }

    public func remove(filmId: Int64) {
        try? FileManager.default.removeItem(at: fileURL(for: filmId))
        invalidate(filmId)
    }

    private func invalidate(_ filmId: Int64) {
        // alle Stempel dieses Films aus dem Speicher werfen
        memory.removeAllObjects()
    }

    /// Titelbild laden (Speicher → Datei). `stamp` sorgt dafür, dass ein neues Bild neu geladen wird.
    public func image(filmId: Int64, stamp: Int64) -> NSImage? {
        let key = "\(filmId)-\(stamp)" as NSString
        if let hit = memory.object(forKey: key) { return hit }
        let url = fileURL(for: filmId)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        memory.setObject(image, forKey: key)
        return image
    }

    // MARK: - Bildwerkzeuge

    static func decode(data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(src)
    }

    static func thumbnail(_ src: CGImageSource) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    public static func downscale(_ image: CGImage, maxPixel: Int) -> CGImage? {
        let w = image.width, h = image.height
        let longSide = max(w, h)
        guard longSide > maxPixel, w > 0, h > 0 else { return image }
        let scale = Double(maxPixel) / Double(longSide)
        let nw = max(1, Int(Double(w) * scale)), nh = max(1, Int(Double(h) * scale))
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage()
    }

    /// Mittlere Helligkeit 0…1 (zum Vermeiden schwarzer Vorschaubilder, z. B. Abblenden am Anfang)
    public static func averageLuminance(_ image: CGImage) -> Double {
        let size = 16
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = ctx.data else { return 1 }
        let p = data.bindMemory(to: UInt8.self, capacity: size * size * 4)
        var sum = 0.0
        for i in 0..<(size * size) {
            let r = Double(p[i * 4]), g = Double(p[i * 4 + 1]), b = Double(p[i * 4 + 2])
            sum += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
        }
        return sum / Double(size * size)
    }
}
