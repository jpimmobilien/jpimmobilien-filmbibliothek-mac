import SwiftUI
import AppKit

// =============================================================================================
// Bewegungs-System der Filmbibliothek – EINE Quelle für Zeiten, Kurven und Interaktionen.
//
// Richtwerte (Briefing „Visual Experience“): Druck 100–160 ms, Hover 150–220 ms, Poster-Hover 180–280 ms,
// Popover 180–260 ms, Detailansicht 250–400 ms, Hintergrund 300–500 ms.
// Grundsätze: keine Dauer-Animationen, keine Zeitgeber, nichts außerhalb des sichtbaren Bereichs.
// „Bewegung reduzieren“ (macOS) bzw. die leichte Darstellung schalten Neigung, Morphing, Lichtreflexe und
// Einblend-Staffelung ab – die App sieht ohne sie genauso hochwertig aus.
// =============================================================================================

enum Motion {
    static let press: Double = 0.12
    static let hover: Double = 0.18
    static let posterHover: Double = 0.24
    static let popover: Double = 0.22
    static let detail: Double = 0.34
    static let background: Double = 0.45

    static let pressCurve = Animation.easeOut(duration: press)
    static let hoverCurve = Animation.easeOut(duration: hover)
    /// Weiche, gedämpfte Feder für Poster (kein Nachschwingen)
    static let posterSpring = Animation.spring(response: posterHover, dampingFraction: 0.86)
    /// Gleitende Linse der Navigation
    static let lensSpring = Animation.spring(response: 0.36, dampingFraction: 0.84)
    static let detailCurve = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: detail)
    static let backgroundCurve = Animation.easeInOut(duration: background)
    /// Herz: kurzer, federnder Puls
    static let heartSpring = Animation.spring(response: 0.28, dampingFraction: 0.52)

    /// Animation nur, wenn Bewegung erlaubt ist
    static func when(_ allowed: Bool, _ animation: Animation) -> Animation? { allowed ? animation : nil }
}

/// Ob aufwendige Bewegung erlaubt ist (Systemeinstellung „Bewegung reduzieren“, App-Einstellung, schwache Grafik).
@MainActor
final class MotionPreferences: ObservableObject {
    static let shared = MotionPreferences()

    @Published private(set) var systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    /// App-Einstellung „Effekte: Voll / Leicht“ (wird von AppSettings gesetzt)
    @Published var lightEffects = false
    private var observer: NSObjectProtocol?

    private init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        }
    }

    /// Volle Bewegung (Neigung, Lichtreflex, Staffelung, Morphing)
    var full: Bool { !systemReduceMotion && !lightEffects && !RenderSafety.reducedEffects }
    /// Leichte Übergänge (Einblenden, Farbwechsel) – auch bei reduzierter Bewegung erlaubt, nur kürzer
    var transitions: Bool { true }
}

private struct MotionFullKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// Volle Bewegung erlaubt? (siehe MotionPreferences)
    var motionFull: Bool {
        get { self[MotionFullKey.self] }
        set { self[MotionFullKey.self] = newValue }
    }
}

// MARK: - Druck- und Hover-Verhalten für Knöpfe

/// Kurze Druckbewegung (Skalierung) – unmittelbar, ohne Nachschwingen.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.pressCurve, value: configuration.isPressed)
    }
}

// MARK: - Lichtreflex

/// Ein weicher Lichtstreif, der einmal diagonal über eine Fläche wandert (bei Hover bzw. Aktivierung).
/// Kein Zeitgeber: Die Bewegung läuft nur, wenn sich `trigger` ändert.
struct LightSweep: View {
    var trigger: Bool
    var intensity: Double = 0.22
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(colors: [.clear, Color.white.opacity(intensity), Color.white.opacity(intensity * 0.35), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: max(40, w * 0.55))
                .rotationEffect(.degrees(18))
                .offset(x: phase * (w * 1.3))
                .frame(width: w, height: geo.size.height, alignment: .center)
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { on in
            guard on else { return }
            phase = -1
            withAnimation(.easeOut(duration: 0.75)) { phase = 1 }
        }
    }
}

// MARK: - Gestaffeltes Einblenden

/// Ordnet Einblend-Wellen: Nach einem Wechsel der Inhalte (Bereich, Suche, Sortierung) blenden die sichtbaren
/// Karten gestaffelt ein; Karten, die später beim Scrollen erscheinen, kommen ohne Verzögerung.
@MainActor
final class EntranceClock: ObservableObject {
    static let shared = EntranceClock()
    private(set) var waveStart = Date.distantPast
    private(set) var waveId = 0

    func newWave() {
        waveStart = Date()
        waveId &+= 1
    }

    /// Verzögerung für die n-te Karte – nur in den ersten 0,6 s einer Welle, höchstens 24 Karten gestaffelt
    func delay(for index: Int) -> Double? {
        let age = Date().timeIntervalSince(waveStart)
        guard age < 0.6 else { return nil }
        return Double(min(index, 24)) * 0.018
    }
}

/// Weiches Einblenden mit leichter Bewegung nach oben und minimaler Skalierung.
struct EntranceEffect: ViewModifier {
    @Environment(\.motionFull) private var motionFull
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || !motionFull ? 0 : 10)
            .scaleEffect(shown || !motionFull ? 1 : 0.97)
            .onAppear {
                guard !shown else { return }
                if let d = EntranceClock.shared.delay(for: index) {
                    withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: motionFull ? 0.42 : 0.2).delay(motionFull ? d : 0)) { shown = true }
                } else {
                    shown = true
                }
            }
    }
}

extension View {
    func entrance(index: Int) -> some View { modifier(EntranceEffect(index: index)) }
}

// MARK: - Herz

/// Herz mit Puls und kleinem Funkenkranz beim Favorisieren (nur beim Wechsel, nie dauerhaft).
struct AnimatedHeart: View {
    @Environment(\.motionFull) private var motionFull
    @Environment(\.palette) private var p
    let isFavorite: Bool
    var size: CGFloat = 14
    var inactiveColor: Color? = nil
    @State private var pulse = false
    @State private var burst = false

    var body: some View {
        ZStack {
            if motionFull {
                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .fill(p.heart)
                        .frame(width: size * 0.18, height: size * 0.18)
                        .offset(y: burst ? -size * 1.05 : -size * 0.3)
                        .rotationEffect(.degrees(Double(i) * 60))
                        .opacity(burst ? 0 : (pulse ? 0.9 : 0))
                }
            }
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(isFavorite ? p.heart : (inactiveColor ?? p.textSecondary))
                .scaleEffect(pulse ? 1.28 : 1)
        }
        .frame(width: size * 1.6, height: size * 1.6)
        .onChange(of: isFavorite) { now in
            guard now else { return }
            burst = false
            withAnimation(Motion.heartSpring) { pulse = true }
            withAnimation(.easeOut(duration: 0.5)) { burst = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(Motion.heartSpring) { pulse = false }
            }
        }
    }
}

// MARK: - Filmstreifen (Identitäts-Detail)

/// Dezenter Filmstreifen: Perforation oben und unten. `moving` lässt ihn langsam laufen (nur im Leerzustand
/// und während des Durchsuchens – nie dauerhaft im Hintergrund).
struct FilmstripView: View {
    @Environment(\.palette) private var p
    @Environment(\.motionFull) private var motionFull
    var moving = false
    var height: CGFloat = 34
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let hole: CGFloat = height * 0.18
            let step = hole * 2.2
            let count = Int(geo.size.width / step) + 4
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(p.dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                VStack {
                    perforation(count: count, hole: hole, step: step)
                    Spacer()
                    perforation(count: count, hole: hole, step: step)
                }
                .padding(.vertical, hole * 0.45)
                .offset(x: offset)
            }
            .clipped()
            .onAppear {
                guard moving && motionFull else { return }
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { offset = -step }
            }
        }
        .frame(height: height)
    }

    private func perforation(count: Int, hole: CGFloat, step: CGFloat) -> some View {
        HStack(spacing: step - hole) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: hole * 0.25, style: .continuous)
                    .fill(p.dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12))
                    .frame(width: hole, height: hole * 0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
