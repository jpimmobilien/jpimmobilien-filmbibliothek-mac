import SwiftUI
import FBCore

/// Bereiche der schwebenden Navigation (Aufbau wie in der Musikbibliothek).
enum NavSection: Int, CaseIterable, Identifiable {
    case start, films, continueWatching, recent, favorites, collections, locations

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .start: return "Start"
        case .films: return "Filme"
        case .continueWatching: return "Weiterschauen"
        case .recent: return "Neu"
        case .favorites: return "Favoriten"
        case .collections: return "Sammlungen"
        case .locations: return "Speicherorte"
        }
    }

    func icon(selected: Bool) -> String {
        switch self {
        case .start: return selected ? "sparkles.tv.fill" : "sparkles.tv"
        case .films: return selected ? "film.stack.fill" : "film.stack"
        case .continueWatching: return selected ? "play.circle.fill" : "play.circle"
        case .recent: return "sparkle"
        case .favorites: return selected ? "heart.fill" : "heart"
        case .collections: return selected ? "rectangle.stack.fill" : "rectangle.stack"
        case .locations: return selected ? "externaldrive.fill" : "externaldrive"
        }
    }

    var route: AppModel.Route {
        switch self {
        case .start: return .overview
        case .films: return .library(.all)
        case .continueWatching: return .library(.continueWatching)
        case .recent: return .library(.recentlyAdded)
        case .favorites: return .library(.favorites)
        case .collections: return .collections
        case .locations: return .locations
        }
    }

    /// Zu welchem Bereich gehört eine Route (Detailseiten: zum Bereich, aus dem sie geöffnet wurden)
    static func of(_ route: AppModel.Route, fallback: NavSection) -> NavSection {
        switch route {
        case .overview: return .start
        case .collections: return .collections
        case .locations: return .locations
        case .detail: return fallback
        case .library(let scope):
            switch scope {
            case .all, .unavailable: return .films
            case .continueWatching, .recentlyPlayed: return .continueWatching
            case .recentlyAdded: return .recent
            case .favorites: return .favorites
            case .collection: return .collections
            case .location, .folder: return .locations
            }
        }
    }
}

/// Schwebende Glas-Navigation oben in der Mitte, mit gleitender Linse unter dem aktiven Bereich.
/// In schmalen Fenstern zeigt sie nur Symbole – und hält immer Abstand zu den Fensterknöpfen.
struct NavBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @Environment(\.motionFull) private var motionFull
    /// Verfügbare Fensterbreite
    let availableWidth: CGFloat

    static let height: CGFloat = 54
    /// Platz der Fensterknöpfe links (plus Luft)
    static let trafficLightsReserve: CGFloat = 92

    private var compact: Bool { availableWidth < 2 * Self.trafficLightsReserve + 7 * 82 + 10 }
    private var itemWidth: CGFloat { compact ? 46 : 82 }
    private var width: CGFloat { itemWidth * CGFloat(NavSection.allCases.count) + 10 }

    var body: some View {
        let current = model.navSection
        let index = CGFloat(current.rawValue)
        ZStack(alignment: .leading) {
            // Linse
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(p.accentSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [p.edgeLight.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 0.7)
                )
                .frame(width: itemWidth, height: Self.height - 10)
                .offset(x: 5 + itemWidth * index)
                .animation(motionFull ? Motion.lensSpring : Motion.hoverCurve, value: index)
            HStack(spacing: 0) {
                ForEach(NavSection.allCases) { section in
                    NavItem(section: section, selected: section == current, compact: compact) {
                        model.navigate(section.route)
                    }
                    .frame(width: itemWidth, height: Self.height - 10)
                }
            }
            .padding(.horizontal, 5)
        }
        .frame(width: width, height: Self.height)
        .glass(RoundedRectangle(cornerRadius: 25, style: .continuous), kind: .panel, elevated: true)
        .animation(Motion.hoverCurve, value: compact)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bereiche")
    }
}

private struct NavItem: View {
    @Environment(\.palette) private var p
    let section: NavSection
    let selected: Bool
    let compact: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let fg = selected ? p.accent : p.textPrimary.opacity(hover ? 0.92 : 0.70)
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: section.icon(selected: selected))
                    .font(.system(size: compact ? 16 : 15, weight: .medium))
                    .frame(height: 19)
                if !compact {
                    Text(section.label)
                        .font(.system(size: 10, weight: selected ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundColor(fg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.93))
        .onHover { hover = $0 }
        .help("\(section.label) (⇧⌘\(section.rawValue + 1))")
        .accessibilityLabel(section.label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .animation(Motion.hoverCurve, value: hover)
        .animation(Motion.hoverCurve, value: selected)
    }
}
