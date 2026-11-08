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
        backgroundStops: [Color(rgb: 0x151C36), Color(rgb: 0x16122E), Color(rgb: 0x0E121D)],
        glows: [Color(rgb: 0x3A3290).opacity(0.34), Color(rgb: 0x1C6274).opacity(0.30), Color(rgb: 0x52237A).opacity(0.26)],
        panel: Color(rgb: 0x1B2037).opacity(0.78),
        card: Color(rgb: 0x1C2138).opacity(0.72),
        cardHover: Color(rgb: 0x232A47).opacity(0.80),
        control: Color.white.opacity(0.075),
        controlHover: Color.white.opacity(0.12),
        edgeLight: Color.white.opacity(0.13),
        edgeDark: Color.white.opacity(0.035),
        hairline: Color.white.opacity(0.08),
        shadow: Color.black.opacity(0.45),
        textPrimary: Color.white.opacity(0.95),
        textSecondary: Color(rgb: 0xA4A8C4),
        textTertiary: Color(rgb: 0x737896),
        sectionLabel: Color(rgb: 0x737896),
        accent: Color(rgb: 0x5C8DF6),
        accentSoft: Color(rgb: 0x5C8DF6).opacity(0.26),
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
        backgroundStops: [Color(rgb: 0xF1F3FA), Color(rgb: 0xEAEAF6), Color(rgb: 0xE6EEF3)],
        glows: [Color(rgb: 0x9FA8FF).opacity(0.30), Color(rgb: 0x8FD8E6).opacity(0.28), Color(rgb: 0xE2B3F2).opacity(0.24)],
        panel: Color.white.opacity(0.62),
        card: Color.white.opacity(0.66),
        cardHover: Color.white.opacity(0.82),
        control: Color.black.opacity(0.05),
        controlHover: Color.black.opacity(0.085),
        edgeLight: Color.white.opacity(0.95),
        edgeDark: Color.black.opacity(0.07),
        hairline: Color.black.opacity(0.07),
        shadow: Color(rgb: 0x2A2F55).opacity(0.13),
        textPrimary: Color(rgb: 0x161A2E),
        textSecondary: Color(rgb: 0x5D627C),
        textTertiary: Color(rgb: 0x8A8FA8),
        sectionLabel: Color(rgb: 0x8A8FA8),
        accent: Color(rgb: 0x2F6BEA),
        accentSoft: Color(rgb: 0x2F6BEA).opacity(0.14),
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

    func body(content: Content) -> some View {
        let p = Palette.for(scheme)
        content
            .environment(\.palette, p)
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
    static let pageTitle = Font.system(size: 26, weight: .bold)
    static let heroTitle = Font.system(size: 50, weight: .bold)
    static let pageSubtitle = Font.system(size: 13, weight: .regular)
    static let cardTitle = Font.system(size: 13.5, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    static let caption = Font.system(size: 11.5)
    static let captionStrong = Font.system(size: 11.5, weight: .semibold)
    static let sectionLabel = Font.system(size: 10.5, weight: .semibold)
    static let bigNumber = Font.system(size: 30, weight: .semibold, design: .rounded)
    static let tileTitle = Font.system(size: 12.5, weight: .semibold)
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
