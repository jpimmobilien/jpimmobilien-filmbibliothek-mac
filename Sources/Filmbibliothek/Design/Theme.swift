import SwiftUI
import AppKit

// =============================================================================================
// Gestaltung der Filmbibliothek – „Liquid Glass“ in der Sprache der Vorlage (AETHER / Apple-Produktseite):
//  - tiefer Nachtblau-/Indigo-Verlauf mit weichen Lichtinseln (Hell: Perlweiß mit Pastell-Lichtern)
//  - schwebende Glasflächen mit feiner Lichtkante, abgerundet (Seitenleiste 18 pt, Karten 16 pt)
//  - große, fette Titel mit grauer Unterzeile; Abschnitts-Überschriften in Versalien mit Sperrung
//  - Chips mit Farbpunkt, Kapsel-Knöpfe (Glas bzw. Primär in Apple-Blau)
// Alle Farben sind hier zentral festgelegt.
// =============================================================================================

struct Palette {
    let dark: Bool

    // Hintergrund (Verlauf + Lichtinseln)
    let backgroundStops: [Color]
    let glows: [Color]

    // Flächen
    let panel: Color          // Seitenleiste
    let card: Color           // Karten
    let cardHover: Color
    let control: Color        // Kapsel-Knöpfe, Suchfeld, Chips
    let controlHover: Color
    let edgeLight: Color      // Lichtkante oben/links
    let edgeDark: Color       // Kante unten/rechts
    let hairline: Color
    let shadow: Color

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let sectionLabel: Color

    // Akzente
    let accent: Color         // Apple-Blau (Primärknopf, Auswahl)
    let accentSoft: Color     // Auswahl-Pille
    let onAccent: Color
    let green: Color
    let orange: Color
    let red: Color
    let heart: Color
    let teal: Color
    let violet: Color
    let pink: Color
    let yellow: Color

    static let darkPalette = Palette(
        dark: true,
        backgroundStops: [Color(rgb: 0x17121F), Color(rgb: 0x120F1A), Color(rgb: 0x0B0A10)],
        glows: [Color(rgb: 0x5B2BA0).opacity(0.30), Color(rgb: 0x2A2F7A).opacity(0.26), Color(rgb: 0x7A2A6E).opacity(0.20)],
        panel: Color(rgb: 0x1E1828).opacity(0.78),
        card: Color(rgb: 0x1D1826).opacity(0.70),
        cardHover: Color(rgb: 0x261F33).opacity(0.80),
        control: Color.white.opacity(0.075),
        controlHover: Color.white.opacity(0.12),
        edgeLight: Color.white.opacity(0.13),
        edgeDark: Color.white.opacity(0.035),
        hairline: Color.white.opacity(0.08),
        shadow: Color.black.opacity(0.45),
        textPrimary: Color.white.opacity(0.95),
        textSecondary: Color(rgb: 0xB0A8C2),
        textTertiary: Color(rgb: 0x7E7792),
        sectionLabel: Color(rgb: 0x7E7792),
        accent: Color(rgb: 0x9D74FF),
        accentSoft: Color(rgb: 0x9D74FF).opacity(0.26),
        onAccent: .white,
        green: Color(rgb: 0x3DDC84),
        orange: Color(rgb: 0xF5A524),
        red: Color(rgb: 0xFF5C66),
        heart: Color(rgb: 0xFF4D63),
        teal: Color(rgb: 0x37C8E6),
        violet: Color(rgb: 0xA77BFF),
        pink: Color(rgb: 0xF25FB4),
        yellow: Color(rgb: 0xFFD25C)
    )

    static let lightPalette = Palette(
        dark: false,
        backgroundStops: [Color(rgb: 0xF6F3FB), Color(rgb: 0xF0EBF8), Color(rgb: 0xEEEDF5)],
        glows: [Color(rgb: 0xC3A8FF).opacity(0.32), Color(rgb: 0xA9B8FF).opacity(0.24), Color(rgb: 0xF2B8DA).opacity(0.22)],
        panel: Color.white.opacity(0.62),
        card: Color.white.opacity(0.66),
        cardHover: Color.white.opacity(0.82),
        control: Color.black.opacity(0.05),
        controlHover: Color.black.opacity(0.085),
        edgeLight: Color.white.opacity(0.95),
        edgeDark: Color.black.opacity(0.07),
        hairline: Color.black.opacity(0.07),
        shadow: Color(rgb: 0x2E1F55).opacity(0.14),
        textPrimary: Color(rgb: 0x1A1526),
        textSecondary: Color(rgb: 0x625A75),
        textTertiary: Color(rgb: 0x8F88A3),
        sectionLabel: Color(rgb: 0x8F88A3),
        accent: Color(rgb: 0x7438E0),
        accentSoft: Color(rgb: 0x7438E0).opacity(0.13),
        onAccent: .white,
        green: Color(rgb: 0x16A35A),
        orange: Color(rgb: 0xD9800B),
        red: Color(rgb: 0xE03A45),
        heart: Color(rgb: 0xE5484D),
        teal: Color(rgb: 0x0E93B0),
        violet: Color(rgb: 0x7B4FE0),
        pink: Color(rgb: 0xD63A92),
        yellow: Color(rgb: 0xC79300)
    )

    static func `for`(_ scheme: ColorScheme) -> Palette { scheme == .dark ? darkPalette : lightPalette }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.darkPalette
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Setzt die Palette passend zum aktuellen Erscheinungsbild.
struct ThemeRoot: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var motion = MotionPreferences.shared

    func body(content: Content) -> some View {
        let p = Palette.for(scheme)
        content
            .environment(\.palette, p)
            .environment(\.motionFull, motion.full)
            .tint(p.accent)
            .foregroundColor(p.textPrimary)
    }
}

extension View {
    func filmTheme() -> some View { modifier(ThemeRoot()) }
}

extension Color {
    init(rgb: UInt32) {
        self.init(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255, opacity: 1)
    }
}

// MARK: - Schrift

enum Typo {
    static let pageTitle = Font.system(size: 34, weight: .bold)
    static let heroTitle = Font.system(size: 50, weight: .bold)
    static let pageSubtitle = Font.system(size: 13, weight: .regular)
    static let cardTitle = Font.system(size: 13.5, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    static let caption = Font.system(size: 11.5)
    static let captionStrong = Font.system(size: 11.5, weight: .semibold)
    static let sectionLabel = Font.system(size: 10.5, weight: .semibold)
    static let bigNumber = Font.system(size: 30, weight: .semibold, design: .rounded)
    static let tileTitle = Font.system(size: 13, weight: .semibold)
    static let tileMeta = Font.system(size: 11)
}

/// Abschnitts-Überschrift in Versalien mit Sperrung („LEISTUNG“, „BIBLIOTHEK“)
struct SectionLabel: View {
    @Environment(\.palette) private var p
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Typo.sectionLabel)
            .tracking(0.9)
            .foregroundColor(p.sectionLabel)
    }
}

/// Großer Seitentitel mit Unterzeile
struct PageHeader<Trailing: View>: View {
    @Environment(\.palette) private var p
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typo.pageTitle)
                    .foregroundColor(p.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Typo.pageSubtitle)
                        .foregroundColor(p.textSecondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}
