import SwiftUI
import AppKit

// =============================================================================================
// Liquid Glass
//
// macOS 26 (Tahoe) und mit dem macOS-26-SDK gebaut: echtes Liquid Glass über die offizielle SwiftUI-
// Schnittstelle `glassEffect(_:in:)` und `GlassEffectContainer`.
// macOS 13–15: gleichwertige Nachbildung mit offiziellen AppKit-Mitteln – echte Unschärfe des Fensterinhalts
// (NSVisualEffectView), Tönung, Glanz von oben und feine Lichtkante. Es werden keine privaten Schnittstellen
// verwendet und keine nicht existierenden APIs vorausgesetzt.
// =============================================================================================

enum LiquidGlass {
    /// Echtes Liquid Glass verfügbar?
    static var isAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return !forceFallback }
        #endif
        return false
    }

    /// Für Vergleichsbilder: Nachbildung auch unter macOS 26 erzwingen (Umgebungsvariable FB_FORCE_GLASS_FALLBACK=1)
    static let forceFallback = ProcessInfo.processInfo.environment["FB_FORCE_GLASS_FALLBACK"] == "1"

    static var modeDescription: String {
        isAvailable ? "Liquid Glass (macOS 26)" : "Glas-Nachbildung (NSVisualEffectView)"
    }
}

/// Unschärfe des Fensterinhalts dahinter
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.isEmphasized = false
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// Art der Glasfläche
enum GlassKind {
    /// Schwebende Seitenleiste
    case panel
    /// Inhaltskarte
    case card
    /// Kapsel-Knopf, Suchfeld, Chip
    case control
    /// Dunkle Glasfläche über Video (Player-Steuerung)
    case overlay
}

struct GlassSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.palette) private var p
    let shape: S
    var kind: GlassKind = .card
    var tint: Color? = nil
    var interactive = false
    var hovered = false
    var elevated = false

    private var fill: Color {
        if let tint { return tint }
        switch kind {
        case .panel: return p.panel
        case .card: return hovered ? p.cardHover : p.card
        case .control: return hovered ? p.controlHover : p.control
        case .overlay: return Color.black.opacity(0.42)
        }
    }

    func body(content: Content) -> some View {
        if LiquidGlass.isAvailable {
            native(content)
        } else {
            fallback(content)
        }
    }

    @ViewBuilder
    private func native(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glassTint: Color = {
                switch kind {
                case .panel: return p.dark ? Color(rgb: 0x1A1F38).opacity(0.45) : Color.white.opacity(0.35)
                case .card: return p.dark ? Color(rgb: 0x1C2140).opacity(hovered ? 0.30 : 0.42) : Color.white.opacity(hovered ? 0.30 : 0.42)
                case .control: return tint ?? (p.dark ? Color.white.opacity(hovered ? 0.10 : 0.04) : Color.white.opacity(hovered ? 0.4 : 0.25))
                case .overlay: return Color.black.opacity(0.28)
                }
            }()
            let glass = interactive ? Glass.regular.tint(glassTint).interactive() : Glass.regular.tint(glassTint)
            content
                .glassEffect(glass, in: shape)
                .safeShadow(color: elevated ? p.shadow : .clear, radius: elevated ? 18 : 0, y: elevated ? 8 : 0)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(
                ZStack {
                    VisualEffectBlur(material: kind == .overlay ? .hudWindow : (p.dark ? .hudWindow : .popover))
                        .opacity(kind == .card ? 0.85 : 1)
                    shape.fill(fill)
                    // Glanz von oben, ein Hauch Tiefe nach unten
                    LinearGradient(stops: [
                        .init(color: Color.white.opacity(p.dark ? 0.055 : 0.35), location: 0),
                        .init(color: .clear, location: 0.45),
                        .init(color: Color.black.opacity(p.dark ? 0.10 : 0.02), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .clipShape(shape)
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [p.edgeLight, p.edgeDark, p.edgeLight.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: kind == .overlay ? 0.6 : 0.8
                )
            )
            .safeCompositingGroup()
            .safeShadow(color: elevated ? p.shadow : .clear, radius: elevated ? 18 : 0, x: 0, y: elevated ? 8 : 0)
    }
}

extension View {
    func glass<S: InsettableShape>(_ shape: S, kind: GlassKind = .card, tint: Color? = nil, interactive: Bool = false,
                                   hovered: Bool = false, elevated: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, kind: kind, tint: tint, interactive: interactive, hovered: hovered, elevated: elevated))
    }

    func glassCard(cornerRadius: CGFloat = 16, hovered: Bool = false, elevated: Bool = false) -> some View {
        glass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), kind: .card, hovered: hovered, elevated: elevated)
    }

    func glassCapsule(kind: GlassKind = .control, tint: Color? = nil, hovered: Bool = false, interactive: Bool = true) -> some View {
        glass(Capsule(style: .continuous), kind: kind, tint: tint, interactive: interactive, hovered: hovered)
    }
}

/// Gruppiert Glasflächen (macOS 26: verschmelzende Formen, sonst ohne Wirkung)
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), LiquidGlass.isAvailable {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

/// Atmosphärischer Fensterhintergrund: Verlauf mit drei weichen Lichtinseln (nur Verläufe, keine Last).
struct AmbientBackground: View {
    @Environment(\.palette) private var p
    /// Optional: Farbe des aktuellen Films (Startseite) – färbt eine Lichtinsel dezent ein
    var accentGlow: Color? = nil

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1), h = max(geo.size.height, 1)
            let r = max(w, h) * 0.62
            ZStack {
                LinearGradient(colors: p.backgroundStops, startPoint: .topLeading, endPoint: .bottomTrailing)
                if !RenderSafety.reducedEffects {
                    RadialGradient(colors: [p.glows[0], .clear], center: UnitPoint(x: 0.12, y: 0.0), startRadius: 0, endRadius: r)
                    RadialGradient(colors: [accentGlow?.opacity(p.dark ? 0.32 : 0.22) ?? p.glows[1], .clear], center: UnitPoint(x: 0.95, y: 0.05), startRadius: 0, endRadius: r * 0.9)
                    RadialGradient(colors: [p.glows[2], .clear], center: UnitPoint(x: 0.35, y: 1.05), startRadius: 0, endRadius: r)
                }
            }
            .animation(.easeInOut(duration: 1.0), value: accentGlow)
        }
        .ignoresSafeArea()
    }
}
