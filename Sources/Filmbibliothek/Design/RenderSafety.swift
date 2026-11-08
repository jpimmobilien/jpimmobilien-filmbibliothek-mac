import SwiftUI
import Metal

/// Schutz für Macs ohne vollwertige Metal-Grafik (z. B. virtuelle Maschinen mit „Paravirtual“-GPU):
/// Dort kann die SwiftUI-Darstellung von Schatten und Weichzeichnern in Apples Grafik-Bibliotheken abbrechen
/// (beobachtet auf den Intel-VMs von GitHub). Echte Macs – auch Intel-Macs mit Grafikchip – sind nicht betroffen.
/// In diesem Fall verzichtet die App auf Schatten und Weichzeichner; alles andere bleibt gleich.
enum RenderSafety {
    static let gpuName: String = MTLCreateSystemDefaultDevice()?.name ?? "keine Metal-Grafik"

    /// Nur Intel-Code auf einer virtuellen Grafik (beobachteter Absturz) bzw. ganz ohne Metal. Apple-Silicon-VMs
    /// (ebenfalls „Paravirtual“) zeichnen Schatten und Unschärfe fehlerfrei – dort bleibt das volle Glas aktiv.
    static let reducedEffects: Bool = {
        if ProcessInfo.processInfo.environment["FB_REDUCED_EFFECTS"] == "1" { return true }
        guard let device = MTLCreateSystemDefaultDevice() else { return true }
        #if arch(x86_64)
        return device.name.localizedCaseInsensitiveContains("paravirtual")
        #else
        return false
        #endif
    }()
}

extension View {
    /// Schatten – entfällt bei eingeschränkter Grafik
    @ViewBuilder
    func safeShadow(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        if RenderSafety.reducedEffects {
            self
        } else {
            self.shadow(color: color, radius: radius, x: x, y: y)
        }
    }

    /// Weichzeichner – entfällt bei eingeschränkter Grafik
    @ViewBuilder
    func safeBlur(radius: CGFloat) -> some View {
        if RenderSafety.reducedEffects {
            self
        } else {
            self.blur(radius: radius)
        }
    }

    /// Zusammenfassen für Schatten – entfällt bei eingeschränkter Grafik
    @ViewBuilder
    func safeCompositingGroup() -> some View {
        if RenderSafety.reducedEffects {
            self
        } else {
            self.compositingGroup()
        }
    }
}
