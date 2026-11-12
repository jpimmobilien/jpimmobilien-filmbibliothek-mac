import SwiftUI
import FBCore
import FBServices

// MARK: - Unterer Abstand (Mini-Player)

private struct ContentBottomInsetKey: EnvironmentKey { static let defaultValue: CGFloat = 28 }

extension EnvironmentValues {
    /// Platz, den Inhalte unten freilassen (wächst, wenn der Mini-Player sichtbar ist)
    var contentBottomInset: CGFloat {
        get { self[ContentBottomInsetKey.self] }
        set { self[ContentBottomInsetKey.self] = newValue }
    }
}

// MARK: - Weicher Auslauf unter Navigation und Mini-Player

struct EdgeFade: View {
    @Environment(\.palette) private var p
    let top: Bool

    var body: some View {
        let base = top ? p.backgroundStops[0] : p.backgroundStops[p.backgroundStops.count - 1]
        LinearGradient(colors: [base.opacity(p.dark ? 0.94 : 0.9), base.opacity(p.dark ? 0.62 : 0.55), base.opacity(0)],
                       startPoint: top ? .top : .bottom, endPoint: top ? .bottom : .top)
    }
}

// MARK: - Durchsuchen / Analyse – nur echte Werte

/// Schwebende Glas-Kapsel unter der Navigation, solange durchsucht oder analysiert wird.
/// Zeigt ausschließlich echte Zahlen aus dem Scanner (gefundene Videos, besuchte Ordner) bzw. der Analyse.
struct ScanBanner: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @Environment(\.motionFull) private var motionFull

    private var activeScan: ScanProgress? {
        model.scanProgress.values.first { $0.phase == .enumerating || $0.phase == .saving }
    }

    var body: some View {
        Group {
            if let scan = activeScan {
                banner(icon: "magnifyingglass",
                       title: "Durchsuche „\(model.locationName(scan.locationId))“",
                       detail: "\(Fmt.count(scan.videosFound, "Video", "Videos")) gefunden · \(Fmt.count(scan.foldersVisited, "Ordner", "Ordner"))",
                       cancel: { model.cancelScan(scan.locationId) })
            } else if model.metadataRemaining > 0 {
                banner(icon: "film",
                       title: "Filme werden analysiert",
                       detail: "noch \(Fmt.integer(model.metadataRemaining)) · Titelbilder und technische Angaben",
                       cancel: nil)
            }
        }
        .animation(Motion.detailCurve, value: activeScan != nil)
        .animation(Motion.detailCurve, value: model.metadataRemaining > 0)
    }

    private func banner(icon: String, title: String, detail: String, cancel: (() -> Void)?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(p.accent.opacity(0.18), lineWidth: 2.4)
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(p.accent)
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(p.accent)
                    .opacity(0)   // Platzhalter für gleichmäßige Höhe
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(p.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(p.textSecondary)
                    .lineLimit(1)
            }
            if motionFull {
                FilmstripView(moving: true, height: 22)
                    .frame(width: 70)
                    .opacity(0.8)
            }
            if let cancel {
                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(GlassIconButtonStyle(size: 24))
                .help("Durchsuchen abbrechen")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .glassCapsule(kind: .card, interactive: false)
        .safeShadow(color: p.shadow, radius: 14, y: 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Großer Seitenkopf (wie in der Musikbibliothek)

/// Großer Titel links, Werkzeug-Kapsel rechts; darunter optional Suche und Unterzeile.
struct LargeTitleHeader<Tools: View, Below: View>: View {
    @Environment(\.palette) private var p
    let title: String
    var subtitle: String = ""
    @ViewBuilder var tools: () -> Tools
    @ViewBuilder var below: () -> Below

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                Text(title)
                    .font(Typo.pageTitle)
                    .foregroundColor(p.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Spacer(minLength: 12)
                tools()
            }
            below()
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundColor(p.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, 2)
            }
        }
    }
}

extension LargeTitleHeader where Below == EmptyView {
    init(title: String, subtitle: String = "", @ViewBuilder tools: @escaping () -> Tools) {
        self.init(title: title, subtitle: subtitle, tools: tools, below: { EmptyView() })
    }
}

/// Werkzeug-Kapsel (Glas) – Gruppe kleiner Symbol-Knöpfe mit Trennlinien
struct ToolCapsule<Content: View>: View {
    @Environment(\.palette) private var p
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 2) { content() }
            .padding(.horizontal, 6)
            .frame(height: 40)
            .glass(Capsule(style: .continuous), kind: .panel, elevated: true)
    }
}

/// Symbol-Knopf in der Werkzeug-Kapsel (Hover: Aufhellung, Druck: kurze Skalierung)
struct ToolButton: View {
    @Environment(\.palette) private var p
    let systemImage: String
    var label: String? = nil
    var selected = false
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                if let label {
                    Text(label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundColor(selected ? p.accent : p.textPrimary.opacity(hover ? 0.95 : 0.78))
            .padding(.horizontal, label == nil ? 0 : 10)
            .frame(minWidth: 32, minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(selected ? p.accentSoft : (hover ? p.controlHover : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.92))
        .onHover { hover = $0 }
        .help(help)
        .animation(Motion.hoverCurve, value: hover)
        .animation(Motion.hoverCurve, value: selected)
    }
}

struct ToolDivider: View {
    @Environment(\.palette) private var p
    var body: some View {
        Rectangle().fill(p.hairline).frame(width: 1, height: 18).padding(.horizontal, 4)
    }
}
