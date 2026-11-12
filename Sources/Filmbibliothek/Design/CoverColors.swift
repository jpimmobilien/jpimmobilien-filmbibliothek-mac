import AppKit
import SwiftUI

/// Leitfarbe eines Titelbilds – lokal, ohne externe Dienste, einmal je Bild berechnet und zwischengespeichert.
///
/// Verfahren: Das Bild wird auf 12 × 12 Bildpunkte verkleinert; Bildpunkte zählen umso mehr, je farbiger und
/// mittelheller sie sind (graue, fast schwarze oder weiße Flächen prägen ein Plakat kaum). Das Ergebnis wird
/// gedämpft, damit ein Lichtschein nie neonartig wirkt.
enum CoverColors {
    private static let cache: NSCache<NSString, NSColor> = {
        let c = NSCache<NSString, NSColor>()
        c.countLimit = 4000
        return c
    }()

    /// Zwischengespeicherte Farbe (ohne Berechnung)
    static func cached(_ key: String) -> NSColor? { cache.object(forKey: key as NSString) }

    /// Leitfarbe (thread-sicher; NSCache ist thread-sicher). Aufruf außerhalb des Haupt-Threads.
    static func leadingColor(of image: NSImage, key: String) -> NSColor? {
        if let hit = cache.object(forKey: key as NSString) { return hit }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        guard let color = compute(cg) else { return nil }
        cache.setObject(color, forKey: key as NSString)
        return color
    }

    static func compute(_ image: CGImage) -> NSColor? {
        let side = 12
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var r = 0.0, g = 0.0, b = 0.0, weight = 0.0
        var ar = 0.0, ag = 0.0, ab = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let pr = Double(pixels[i]) / 255, pg = Double(pixels[i + 1]) / 255, pb = Double(pixels[i + 2]) / 255
            ar += pr; ag += pg; ab += pb
            let maxC = max(pr, pg, pb), minC = min(pr, pg, pb)
            let sat = maxC > 0 ? (maxC - minC) / maxC : 0
            // Mittelhelle, farbige Bildpunkte bevorzugen
            let lightness = 1 - abs(maxC - 0.6) / 0.6
            let w = pow(sat, 1.6) * max(0.05, lightness)
            r += pr * w; g += pg * w; b += pb * w; weight += w
        }
        let n = Double(side * side)
        var color: NSColor
        if weight > 0.6 {
            color = NSColor(srgbRed: r / weight, green: g / weight, blue: b / weight, alpha: 1)
        } else {
            // Fast farbloses Bild (z. B. Schwarz-Weiß): neutrale, leicht kühle Variante
            color = NSColor(srgbRed: ar / n, green: ag / n, blue: min(1, ab / n + 0.05), alpha: 1)
        }
        // Dämpfen: Sättigung 0,30–0,70, Helligkeit 0,55–0,85
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        (color.usingColorSpace(.sRGB) ?? color).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        let sat = weight > 0.6 ? min(0.70, max(0.30, s)) : min(0.18, s)
        color = NSColor(hue: h, saturation: sat, brightness: min(0.85, max(0.55, v)), alpha: 1)
        return color
    }
}
