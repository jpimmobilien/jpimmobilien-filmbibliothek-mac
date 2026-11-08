import SwiftUI
import AppKit
import FBCore
import FBServices

// MARK: - Titelbild

/// Lädt das Titelbild im Hintergrund aus dem Cache; ohne Bild eine gestaltete Fläche mit Titel.
struct CoverImage: View {
    @EnvironmentObject var model: AppModel
    let film: Film
    var aspect: CGFloat
    var showPlaceholderTitle = true
    @State private var image: NSImage?
    @State private var loadedKey: String?

    private var key: String { "\(film.id)-\(film.coverStamp)" }

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay(content)
            .clipped()
            .task(id: key) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let image, film.coverSource != CoverSource.none {
            let imgAspect = image.size.height > 0 ? image.size.width / image.size.height : aspect
            if abs(imgAspect - aspect) / aspect > 0.28 {
                // Poster im Breitbild (bzw. umgekehrt): unscharfer Hintergrund + ganzes Bild
                ZStack {
                    Image(nsImage: image).resizable().scaledToFill().blur(radius: 18).opacity(0.75)
                    Color.black.opacity(0.18)
                    Image(nsImage: image).resizable().scaledToFit().shadow(color: .black.opacity(0.4), radius: 8)
                }
            } else {
                Image(nsImage: image).resizable().scaledToFill()
            }
        } else {
            PosterPlaceholder(title: showPlaceholderTitle ? model.settings.displayTitle(film) : "", ext: film.fileExtension, seed: Int(film.id))
        }
    }

    private func load() async {
        guard film.coverSource != CoverSource.none, film.coverStamp != 0 else { image = nil; return }
        let covers = model.covers
        let id = film.id, stamp = film.coverStamp
        let img = await Task.detached(priority: .utility) { covers.image(filmId: id, stamp: stamp) }.value
        if !Task.isCancelled { image = img; loadedKey = key }
    }
}

// MARK: - Raster

struct FilmGridView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    let films: [Film]
    let compact: Bool

    private var minWidth: CGFloat {
        switch (settings.tileShape, compact) {
        case (.widescreen, false): return 230
        case (.widescreen, true): return 165
        case (.poster, false): return 168
        case (.poster, true): return 120
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth, maximum: minWidth * 1.6), spacing: compact ? 14 : 20)],
                          alignment: .leading, spacing: compact ? 18 : 26) {
                    ForEach(films) { film in
                        FilmTile(film: film, compact: compact)
                            .id(film.id)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 6)
                .padding(.bottom, 40)
            }
            .onChange(of: model.selection) { sel in
                if sel.count == 1, let id = sel.first { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) } }
            }
        }
    }
}

struct FilmTile: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.palette) private var p
    let film: Film
    var compact = false
    @State private var hover = false

    private var selected: Bool { model.selection.contains(film.id) }
    private var available: Bool { model.isAvailable(film) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                CoverImage(film: film, aspect: settings.tileShape.aspect)
                    .saturation(available ? 1 : 0.15)
                    .brightness(available ? 0 : -0.12)
                overlays
            }
            .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 10 : 13, style: .continuous)
                    .strokeBorder(selected ? p.accent : Color.white.opacity(hover ? 0.28 : 0.10), lineWidth: selected ? 2.4 : 0.8)
            )
            .shadow(color: p.shadow.opacity(hover ? 1 : 0.7), radius: hover ? 16 : 9, y: hover ? 8 : 4)
            .scaleEffect(hover ? 1.015 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hover)

            VStack(alignment: .leading, spacing: 2) {
                Text(settings.displayTitle(film))
                    .font(compact ? .system(size: 11.5, weight: .semibold) : Typo.tileTitle)
                    .foregroundColor(available ? p.textPrimary : p.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !compact || !metaLine.isEmpty {
                    Text(metaLine)
                        .font(compact ? .system(size: 10.5) : Typo.tileMeta)
                        .foregroundColor(p.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .simultaneousGesture(TapGesture(count: 1).onEnded { select() })
        .onTapGesture(count: 2) { model.play(film) }
        .contextMenu { FilmContextMenu(film: film) }
        .help(film.fileName)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let y = TitleCleaner.year(forFileName: film.fileName) { parts.append(String(y)) }
        if let d = film.info.durationSeconds { parts.append(Fmt.runtime(d)) }
        if let r = film.resolutionClass { parts.append(r.label) }
        if parts.isEmpty { parts.append(Fmt.bytes(film.sizeBytes)) }
        return parts.joined(separator: " · ")
    }

    private func select() {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selected { model.selection.remove(film.id) } else { model.selection.insert(film.id) }
        } else if flags.contains(.shift), let anchor = model.selection.first,
                  let a = model.visibleFilms.firstIndex(where: { $0.id == anchor }),
                  let b = model.visibleFilms.firstIndex(where: { $0.id == film.id }) {
            let range = min(a, b)...max(a, b)
            model.selection = Set(model.visibleFilms[range].map(\.id))
        } else {
            model.selection = [film.id]
        }
    }

    @ViewBuilder
    private var overlays: some View {
        ZStack {
            // Oben: Format, Herz, gesehen
            VStack {
                HStack(spacing: 5) {
                    if settings.showFormatBadges {
                        Text(film.fileExtension.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                    }
                    if film.playability == .unsupported {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(p.orange)
                            .padding(4)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                            .help("Nicht abspielbar")
                    }
                    Spacer()
                    if film.finished {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(p.green.opacity(0.9)))
                            .help("Gesehen")
                    }
                    if film.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(p.heart)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                }
                .padding(7)
                Spacer()
            }
            // Mitte: nicht verfügbar / Abspielen beim Darüberfahren
            if !available {
                Text(film.isMissing ? "Datei fehlt" : "Nicht verfügbar")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCapsule(kind: .overlay, interactive: false)
            } else if hover {
                Button { model.play(film) } label: {
                    Image(systemName: "play.fill").offset(x: 1.5)
                }
                .buttonStyle(GlassIconButtonStyle(size: compact ? 34 : 44, overlay: true))
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            // Unten: Fortschritt
            if let progress = film.progress, !film.finished {
                VStack {
                    Spacer()
                    CapsuleBar(fraction: progress, color: p.accent, height: 4, track: Color.black.opacity(0.45))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 7)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

// MARK: - Liste

struct FilmListView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.palette) private var p
    let films: [Film]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerRow
                Rectangle().fill(p.hairline).frame(height: 0.8)
                LazyVStack(spacing: 0) {
                    ForEach(films) { film in
                        FilmRow(film: film)
                    }
                }
            }
            .padding(.vertical, 6)
            .glassCard()
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 64, height: 1)
            header("Titel", .title).frame(maxWidth: .infinity, alignment: .leading)
            header("Laufzeit", .duration).frame(width: 92, alignment: .leading)
            header("Auflösung", .resolution).frame(width: 96, alignment: .leading)
            header("Format", .format).frame(width: 58, alignment: .leading)
            header("Größe", .size).frame(width: 74, alignment: .trailing)
            header("Hinzugefügt", .dateAdded).frame(width: 96, alignment: .trailing)
            Color.clear.frame(width: 44, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func header(_ title: String, _ key: SortKey) -> some View {
        Button {
            if settings.sortKey == key { settings.sortAscending.toggle() } else { settings.sortKey = key; settings.sortAscending = key.defaultAscending }
            model.scheduleRecompute()
        } label: {
            HStack(spacing: 3) {
                Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6)
                if settings.sortKey == key {
                    Image(systemName: settings.sortAscending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundColor(settings.sortKey == key ? p.textPrimary : p.sectionLabel)
        }
        .buttonStyle(.plain)
    }
}

struct FilmRow: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.palette) private var p
    let film: Film
    @State private var hover = false

    private var selected: Bool { model.selection.contains(film.id) }

    var body: some View {
        let available = model.isAvailable(film)
        HStack(spacing: 12) {
            CoverImage(film: film, aspect: 16.0 / 9.0, showPlaceholderTitle: false)
                .frame(width: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .saturation(available ? 1 : 0.15)
                .overlay(alignment: .bottom) {
                    if let pr = film.progress, !film.finished {
                        CapsuleBar(fraction: pr, height: 2.5, track: Color.black.opacity(0.4)).padding(.horizontal, 4).padding(.bottom, 3)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.displayTitle(film))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(available ? p.textPrimary : p.textSecondary)
                    .lineLimit(1)
                Text(film.relativePath)
                    .font(.system(size: 11))
                    .foregroundColor(p.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(film.info.durationSeconds.map { Fmt.clock($0) } ?? "–")
                .font(.system(size: 12).monospacedDigit()).foregroundColor(p.textSecondary)
                .frame(width: 92, alignment: .leading)
            Text(resolutionText)
                .font(.system(size: 12)).foregroundColor(p.textSecondary)
                .frame(width: 96, alignment: .leading)
            Text(film.fileExtension.uppercased())
                .font(.system(size: 11, weight: .semibold)).foregroundColor(p.textSecondary)
                .frame(width: 58, alignment: .leading)
            Text(Fmt.bytes(film.sizeBytes))
                .font(.system(size: 12).monospacedDigit()).foregroundColor(p.textSecondary)
                .frame(width: 74, alignment: .trailing)
            Text(Fmt.day(film.addedAt))
                .font(.system(size: 12)).foregroundColor(p.textSecondary)
                .frame(width: 96, alignment: .trailing)
            HStack(spacing: 5) {
                if film.isFavorite { Image(systemName: "heart.fill").foregroundColor(p.heart) }
                if film.finished { Image(systemName: "checkmark.circle.fill").foregroundColor(p.green) }
                if !available { Image(systemName: "externaldrive.badge.xmark").foregroundColor(p.textTertiary) }
                if film.playability == .unsupported { Image(systemName: "exclamationmark.triangle.fill").foregroundColor(p.orange) }
            }
            .font(.system(size: 11))
            .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? p.accentSoft : (hover ? p.control : .clear))
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .simultaneousGesture(TapGesture(count: 1).onEnded {
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) {
                if selected { model.selection.remove(film.id) } else { model.selection.insert(film.id) }
            } else {
                model.selection = [film.id]
            }
        })
        .onTapGesture(count: 2) { model.play(film) }
        .contextMenu { FilmContextMenu(film: film) }
    }

    private var resolutionText: String {
        guard let w = film.info.width, let h = film.info.height else { return "–" }
        return "\(film.resolutionClass?.label ?? "") \(w)×\(h)".trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Kontextmenü

struct FilmContextMenu: View {
    @EnvironmentObject var model: AppModel
    let film: Film

    /// Aktion gilt für die Auswahl, wenn der Film dazugehört – sonst nur für ihn
    private var targets: [Int64] {
        model.selection.contains(film.id) ? Array(model.selection) : [film.id]
    }

    var body: some View {
        let available = model.isAvailable(film)
        Button("Abspielen") { model.play(film) }.disabled(!available)
        if film.positionSeconds > 0 {
            Button("Von Anfang an abspielen") { model.play(film, fromStart: true) }.disabled(!available)
        }
        Button("Informationen") { model.navigate(.detail(film.id)) }
        Divider()
        Button(film.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten") { model.toggleFavorite(targets) }
        Button(film.finished ? "Als nicht gesehen markieren" : "Als gesehen markieren") { model.setFinished(targets, !film.finished) }
        if film.positionSeconds > 0 || film.lastPlayedAt != nil {
            Button("Wiedergabeverlauf zurücksetzen") { model.clearPlayback(targets) }
        }
        Menu("Zur Sammlung hinzufügen") {
            ForEach(model.collections) { c in
                Button(c.name) { model.add(targets, to: c) }
            }
            if !model.collections.isEmpty { Divider() }
            Button("Neue Sammlung …") { model.collectionNamePrompt = AppModel.CollectionPrompt(addFilms: targets) }
        }
        if case .library(.collection(let cid)) = model.route, let c = model.collections.first(where: { $0.id == cid }) {
            Button("Aus „\(c.name)“ entfernen") { model.remove(targets, from: c) }
        }
        Divider()
        Button("Im Finder zeigen") { model.revealInFinder(targets.compactMap { model.film($0) }) }.disabled(!available)
        Button("Ordner in der Bibliothek zeigen") { model.navigate(.library(.folder(location: film.locationId, path: film.folder))) }
        Button("Pfad kopieren") {
            let path = model.fileURL(for: film)?.path ?? (model.location(film.locationId).map { RelativePath.join($0.lastKnownPath, film.relativePath) ?? film.relativePath } ?? film.relativePath)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
    }
}
