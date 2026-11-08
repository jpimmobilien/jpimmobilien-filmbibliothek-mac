import SwiftUI
import AppKit

// MARK: - Knöpfe

/// Kapsel-Knopf im Glas-Stil („Im Finder zeigen“) bzw. primär in Apple-Blau („Analyse starten“)
struct CapsuleButtonStyle: ButtonStyle {
    enum Role { case glass, primary, destructive, plain }
    var role: Role = .glass
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        CapsuleButtonBody(configuration: configuration, role: role, compact: compact)
    }

    private struct CapsuleButtonBody: View {
        @Environment(\.palette) private var p
        @Environment(\.isEnabled) private var enabled
        let configuration: Configuration
        let role: Role
        let compact: Bool
        @State private var hover = false

        var body: some View {
            let label = configuration.label
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, compact ? 11 : 15)
                .padding(.vertical, compact ? 5 : 7.5)
                .contentShape(Capsule())
            Group {
                switch role {
                case .primary:
                    label
                        .foregroundColor(p.onAccent)
                        .background(Capsule(style: .continuous).fill(p.accent.opacity(hover ? 1 : 0.92)))
                        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6))
                        .shadow(color: p.accent.opacity(0.35), radius: hover ? 10 : 6, y: 2)
                case .destructive:
                    label
                        .foregroundColor(p.red)
                        .glassCapsule(hovered: hover)
                case .glass:
                    label
                        .foregroundColor(p.textPrimary)
                        .glassCapsule(hovered: hover)
                case .plain:
                    label
                        .foregroundColor(p.textSecondary)
                        .background(Capsule().fill(hover ? p.control : .clear))
                }
            }
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hover = $0 }
        }
    }
}

/// Runder Glas-Symbolknopf (Werkzeugleiste, Player)
struct GlassIconButtonStyle: ButtonStyle {
    var size: CGFloat = 30
    var active = false
    var overlay = false

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, size: size, active: active, overlay: overlay)
    }

    private struct IconButtonBody: View {
        @Environment(\.palette) private var p
        @Environment(\.isEnabled) private var enabled
        let configuration: Configuration
        let size: CGFloat
        let active: Bool
        let overlay: Bool
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundColor(active ? p.accent : (overlay ? .white : p.textPrimary))
                .frame(width: size, height: size)
                .contentShape(Circle())
                .glass(Circle(), kind: overlay ? .overlay : .control, tint: active ? p.accentSoft : nil, interactive: true, hovered: hover)
                .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .onHover { hover = $0 }
        }
    }
}

/// Plus-Kapsel wie auf der Apple-Produktseite („⊕ Abmessungen und Gewichte“)
struct DisclosureCapsule: View {
    @Environment(\.palette) private var p
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(p.textPrimary.opacity(0.85), lineWidth: 1.4))
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .padding(.leading, 10)
            .padding(.trailing, 18)
            .padding(.vertical, 9)
            .contentShape(Capsule())
            .glassCapsule(hovered: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Chips, Punkte, Symbole

/// Chip mit Farbpunkt („● CPU 11 %“) bzw. entfernbarer Filter-Chip
struct Chip: View {
    @Environment(\.palette) private var p
    let text: String
    var dot: Color? = nil
    var systemImage: String? = nil
    var onRemove: (() -> Void)? = nil
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .semibold)).foregroundColor(p.textSecondary) }
            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(p.textPrimary)
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(p.textSecondary)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(hover ? p.controlHover : .clear))
                }
                .buttonStyle(.plain)
                .help("Filter entfernen")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(Capsule(style: .continuous).fill(p.control))
        .overlay(Capsule(style: .continuous).strokeBorder(p.hairline, lineWidth: 0.6))
        .onHover { hover = $0 }
    }
}

/// Kleines farbiges Symbol vor Kartentiteln
struct IconBadge: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(color)
            .frame(width: size + 6)
    }
}

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 7
    var pulsing = false
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.7), radius: pulsing ? (on ? 5 : 1) : 2)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

// MARK: - Karten

/// Glas-Karte mit Symbol, Titel und optionaler Zusatzangabe rechts
struct GlassCard<Content: View, Accessory: View>: View {
    @Environment(\.palette) private var p
    let title: String
    let systemImage: String
    let iconColor: Color
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconBadge(systemImage: systemImage, color: iconColor)
                Text(title).font(Typo.cardTitle).foregroundColor(p.textPrimary)
                Spacer(minLength: 8)
                accessory()
            }
            content()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

extension GlassCard where Accessory == EmptyView {
    init(title: String, systemImage: String, iconColor: Color, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, systemImage: systemImage, iconColor: iconColor, accessory: { EmptyView() }, content: content)
    }
}

/// Zeile „Bezeichnung ……… Wert“ wie in den Infokarten der Vorlage
struct InfoRow: View {
    @Environment(\.palette) private var p
    let label: String
    let value: String
    var valueColor: Color? = nil
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(Typo.body).foregroundColor(p.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .system(size: 12.5, weight: .semibold, design: .monospaced) : Typo.bodyStrong)
                .foregroundColor(valueColor ?? p.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

/// Hinweisleiste mit Schild-Symbol (Datenschutz-/Sicherheitshinweis am Seitenende)
struct HintBar: View {
    @Environment(\.palette) private var p
    let text: String
    var systemImage = "checkmark.shield"
    var color: Color? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color ?? p.accent)
            Text(text)
                .font(Typo.caption)
                .foregroundColor(p.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.control.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(p.hairline, lineWidth: 0.6))
    }
}

/// Dünner Fortschritts-/Belegungsbalken in Kapselform
struct CapsuleBar: View {
    @Environment(\.palette) private var p
    let fraction: Double
    var color: Color? = nil
    var height: CGFloat = 6
    var track: Color? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track ?? p.control)
                Capsule()
                    .fill(color ?? p.accent)
                    .frame(width: max(height, geo.size.width * CGFloat(min(1, max(0, fraction)))))
                    .opacity(fraction > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
    }
}

/// Leerer Zustand (z. B. noch keine Speicherorte)
struct EmptyStateView<Actions: View>: View {
    @Environment(\.palette) private var p
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(LinearGradient(colors: [p.accent, p.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(22)
                .glass(Circle(), kind: .card)
            Text(title).font(.system(size: 20, weight: .bold)).foregroundColor(p.textPrimary)
            Text(message)
                .font(Typo.body)
                .foregroundColor(p.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) { actions() }.padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Suchfeld

struct GlassSearchField: View {
    @Environment(\.palette) private var p
    @Binding var text: String
    var prompt = "Suchen"
    var focus: FocusState<Bool>.Binding
    @State private var hover = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(p.textSecondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(focus)
                .frame(minWidth: 120)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundColor(p.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Suche leeren")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassCapsule(hovered: hover || focus.wrappedValue)
        .overlay(Capsule().strokeBorder(focus.wrappedValue ? p.accent.opacity(0.7) : .clear, lineWidth: 1.2))
        .onHover { hover = $0 }
    }
}

// MARK: - Platzhalter-Cover (kein Bild vorhanden): gestaltete Fläche mit Titel – kein erfundenes Bild

struct PosterPlaceholder: View {
    @Environment(\.palette) private var p
    let title: String
    let ext: String
    var seed: Int

    private var colors: [Color] {
        let sets: [[Color]] = [
            [Color(rgb: 0x2B3A8C), Color(rgb: 0x5B2C83)], [Color(rgb: 0x16566B), Color(rgb: 0x23306E)],
            [Color(rgb: 0x5A2348), Color(rgb: 0x2A2E6E)], [Color(rgb: 0x2D4F3F), Color(rgb: 0x1F3357)],
            [Color(rgb: 0x5C3A1E), Color(rgb: 0x3B2350)], [Color(rgb: 0x23415E), Color(rgb: 0x46265E)],
        ]
        return sets[abs(seed) % sets.count]
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "film")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundColor(.white.opacity(0.22))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 3) {
                Text(ext.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.6))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(3)
            }
            .padding(10)
        }
    }
}
