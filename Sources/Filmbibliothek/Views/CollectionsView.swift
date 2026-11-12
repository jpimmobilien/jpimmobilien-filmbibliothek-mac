import SwiftUI
import FBCore

/// Bereich „Sammlungen“: eigene Listen als Karten mit Cover-Mosaik.
struct CollectionsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @Environment(\.contentBottomInset) private var bottomInset

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LargeTitleHeader(title: "Sammlungen", subtitle: Fmt.count(model.collections.count, "Sammlung", "Sammlungen")) {
                ToolCapsule {
                    ToolButton(systemImage: "plus", label: "Neue Sammlung", help: "Neue Sammlung anlegen") {
                        model.collectionNamePrompt = AppModel.CollectionPrompt()
                    }
                    ToolButton(systemImage: "gearshape", help: "Einstellungen (⌘,)") { SettingsOpener.open() }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 4)
            .padding(.bottom, 16)

            if model.collections.isEmpty {
                EmptyStateView(systemImage: "rectangle.stack", title: "Noch keine Sammlungen",
                               message: "Stelle eigene Listen zusammen – z. B. „Filmabend“ oder „Klassiker“. Filme fügst du über das Kontextmenü „Zur Sammlung hinzufügen“ hinzu.") {
                    Button("Sammlung anlegen") { model.collectionNamePrompt = AppModel.CollectionPrompt() }
                        .buttonStyle(CapsuleButtonStyle(role: .primary))
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 24)], alignment: .leading, spacing: 28) {
                        ForEach(Array(model.collections.enumerated()), id: \.element.id) { index, c in
                            CollectionCard(collection: c)
                                .entrance(index: index)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 6)
                    .padding(.bottom, bottomInset + 12)
                }
            }
        }
    }
}

private struct CollectionCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @Environment(\.motionFull) private var motionFull
    let collection: FilmCollection
    @State private var hover = false

    private var films: [Film] { collection.filmIds.prefix(4).compactMap { model.film($0) } }

    var body: some View {
        Button { model.navigate(.library(.collection(collection.id))) } label: {
            VStack(alignment: .leading, spacing: 10) {
                mosaic
                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.name)
                        .font(Typo.tileTitle)
                        .foregroundColor(p.textPrimary)
                        .lineLimit(1)
                    Text(meta)
                        .font(Typo.tileMeta)
                        .foregroundColor(p.textTertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .onHover { hover = $0 }
        .contextMenu {
            Button("Umbenennen …") { model.collectionNamePrompt = AppModel.CollectionPrompt(renaming: collection) }
            Button("Alle abspielen") {
                let list = collection.filmIds.compactMap { model.film($0) }
                if let first = list.first(where: { model.isAvailable($0) }) { model.play(first, in: list) }
            }
            Divider()
            Button("Sammlung löschen", role: .destructive) { model.delete(collection) }
        }
        .animation(Motion.posterSpring, value: hover)
    }

    private var meta: String {
        let all = collection.filmIds.compactMap { model.film($0) }
        var parts = [Fmt.count(all.count, "Film", "Filme")]
        let runtime = all.reduce(0.0) { $0 + ($1.info.durationSeconds ?? 0) }
        if runtime > 0 { parts.append(Fmt.runtime(runtime)) }
        return parts.joined(separator: " · ")
    }

    private var mosaic: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ZStack {
            p.card
            if films.isEmpty {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 34, weight: .light))
                    .foregroundColor(p.textTertiary)
            } else {
                let cells = films
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        cell(cells, 0)
                        cell(cells, 1)
                    }
                    HStack(spacing: 2) {
                        cell(cells, 2)
                        cell(cells, 3)
                    }
                }
            }
            LinearGradient(colors: [Color.white.opacity(hover ? 0.14 : 0.06), .clear], startPoint: .top, endPoint: .center)
                .allowsHitTesting(false)
            if motionFull { LightSweep(trigger: hover, intensity: 0.18) }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(shape)
        .overlay(shape.strokeBorder((p.dark ? Color.white : Color.black).opacity(hover ? 0.22 : 0.08), lineWidth: 0.8))
        .safeShadow(color: p.shadow.opacity(hover ? 1 : 0.7), radius: hover ? 16 : 8, y: hover ? 9 : 4)
        .scaleEffect(hover ? (motionFull ? 1.025 : 1.01) : 1)
    }

    @ViewBuilder
    private func cell(_ films: [Film], _ i: Int) -> some View {
        if i < films.count {
            CoverImage(film: films[i], aspect: 16 / 10, showPlaceholderTitle: false, fill: true)
        } else {
            p.control
        }
    }
}
