import SwiftUI
import FBCore

/// Filter-Popover: Speicherort, Format, Auflösung, Größe, Laufzeit, Favoriten, Wiedergabestatus, Verfügbarkeit.
struct FilterPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    private var formatsInLibrary: [String] {
        Array(Set(model.films.map(\.fileExtension))).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Filter").font(.system(size: 16, weight: .bold))
                    Spacer()
                    if !model.filter.isEmpty {
                        Button("Zurücksetzen") { model.filter = LibraryFilter() }
                            .buttonStyle(CapsuleButtonStyle(role: .plain, compact: true))
                    }
                }

                group("Wiedergabe") {
                    toggleChip("Nur Favoriten", on: model.filter.favoritesOnly, icon: "heart.fill", color: p.heart) {
                        model.filter.favoritesOnly.toggle()
                    }
                    ForEach(PlaybackStatus.allCases, id: \.self) { s in
                        toggleChip(s.label, on: model.filter.playback.contains(s), icon: icon(for: s), color: p.teal) {
                            if model.filter.playback.contains(s) { model.filter.playback.remove(s) } else { model.filter.playback.insert(s) }
                        }
                    }
                }

                group("Verfügbarkeit") {
                    ForEach(AvailabilityFilter.allCases, id: \.self) { a in
                        toggleChip(a.label, on: model.filter.availability == a, icon: nil, color: p.green) { model.filter.availability = a }
                    }
                }

                if !model.locations.isEmpty {
                    group("Speicherort") {
                        ForEach(model.locations) { loc in
                            toggleChip(loc.name, on: model.filter.locationIds.contains(loc.id), icon: loc.kind.symbol, color: p.accent) {
                                if model.filter.locationIds.contains(loc.id) { model.filter.locationIds.remove(loc.id) } else { model.filter.locationIds.insert(loc.id) }
                            }
                        }
                    }
                }

                if !formatsInLibrary.isEmpty {
                    group("Format") {
                        ForEach(formatsInLibrary, id: \.self) { ext in
                            toggleChip(ext.uppercased(), on: model.filter.extensions.contains(ext), icon: nil, color: p.violet) {
                                if model.filter.extensions.contains(ext) { model.filter.extensions.remove(ext) } else { model.filter.extensions.insert(ext) }
                            }
                        }
                    }
                }

                group("Auflösung") {
                    ForEach(ResolutionClass.allCases.reversed(), id: \.self) { r in
                        toggleChip(r.label, on: model.filter.resolutions.contains(r), icon: nil, color: p.yellow) {
                            if model.filter.resolutions.contains(r) { model.filter.resolutions.remove(r) } else { model.filter.resolutions.insert(r) }
                        }
                    }
                }

                group("Größe") {
                    ForEach(SizeFilter.allCases, id: \.self) { s in
                        toggleChip(s.label, on: model.filter.size == s, icon: nil, color: p.orange) { model.filter.size = s }
                    }
                }

                group("Laufzeit") {
                    ForEach(DurationFilter.allCases, id: \.self) { d in
                        toggleChip(d.label, on: model.filter.duration == d, icon: nil, color: p.pink) { model.filter.duration = d }
                    }
                }
            }
            .padding(18)
        }
        .frame(width: 380, height: 520)
    }

    private func icon(for s: PlaybackStatus) -> String {
        switch s {
        case .unwatched: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .finished: return "checkmark.circle"
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            FlowLayout(spacing: 6) { content() }
        }
    }

    private func toggleChip(_ title: String, on: Bool, icon: String?, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .semibold)) }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(on ? p.onAccent : p.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(on ? color.opacity(0.9) : p.control))
            .overlay(Capsule().strokeBorder(on ? Color.white.opacity(0.2) : p.hairline, lineWidth: 0.6))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Aktive Filter als einzeln entfernbare Chips
struct FilterChips: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    /// Format-Chips zeigen (aus, wenn die Segment-Chips das Format schon zeigen)
    var includeExtensions = true

    var body: some View {
        let f = model.filter
        if f.favoritesOnly { Chip(text: "Favoriten", dot: p.heart) { model.filter.favoritesOnly = false } }
        ForEach(Array(f.playback).sorted { $0.rawValue < $1.rawValue }, id: \.self) { s in
            Chip(text: s.label, dot: p.teal) { model.filter.playback.remove(s) }
        }
        if f.availability != .any { Chip(text: f.availability.label, dot: p.green) { model.filter.availability = .any } }
        ForEach(Array(f.locationIds).sorted(), id: \.self) { id in
            Chip(text: model.locationName(id), dot: p.accent) { model.filter.locationIds.remove(id) }
        }
        if includeExtensions {
            ForEach(Array(f.extensions).sorted(), id: \.self) { e in
                Chip(text: e.uppercased(), dot: p.violet) { model.filter.extensions.remove(e) }
            }
        }
        ForEach(Array(f.resolutions).sorted(), id: \.self) { r in
            Chip(text: r.label, dot: p.yellow) { model.filter.resolutions.remove(r) }
        }
        if f.size != .any { Chip(text: f.size.label, dot: p.orange) { model.filter.size = .any } }
        if f.duration != .any { Chip(text: f.duration.label, dot: p.pink) { model.filter.duration = .any } }
    }
}

/// Einfaches Umbruch-Layout für Chips (Layout-Protokoll, macOS 13+)
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: min(maxWidth, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
