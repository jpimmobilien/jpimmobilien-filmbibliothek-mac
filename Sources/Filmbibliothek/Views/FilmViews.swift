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
    /// Füllt den vom Aufrufer vorgegebenen Rahmen (Kinobild, Hintergrund) statt ein Seitenverhältnis vorzugeben
    var fill = false
    /// Meldet die (einmal berechnete, zwischengespeicherte) Leitfarbe des Titelbilds – für Lichtschein und Hintergrund
    var onColor: ((Color) -> Void)? = nil
    @State private var image: NSImage?
    @State private var loadedKey: String?

    private var key: String { "\(film.id)-\(film.coverStamp)" }

    var body: some View {
        Group {
            if fill {
                Color.clear.overlay(content)
            } else {
                Color.clear.aspectRatio(aspect, contentMode: .fit).overlay(content)
            }
        }
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
                    Image(nsImage: image).resizable().scaledToFill().safeBlur(radius: 18).opacity(0.75)
                    Color.black.opacity(0.18)
                    Image(nsImage: image).resizable().scaledToFit().safeShadow(color: .black.opacity(0.4), radius: 8)
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
        let wantsColor = onColor != nil
        let colorKey = key
        let (img, tint) = await Task.detached(priority: .utility) { () -> (NSImage?, NSColor?) in
            let i = covers.image(filmId: id, stamp: stamp)
            let c = wantsColor ? i.flatMap { CoverColors.leadingColor(of: $0, key: colorKey) } : nil
            return (i, c)
        }.value
        if !Task.isCancelled {
            image = img
            loadedKey = key
            if let tint { onColor?(Color(nsColor: tint)) }
        }
    }
}

// MARK: - Raster

struct FilmGridView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    let films: [Film]
    let compact: Bool
    /// Zusätzlicher Abstand unten (Mini-Player)
    var bottomInset: CGFloat = 40

    private var minWidth: CGFloat {
        switch (settings.tileShape, compact) {
        case (.widescreen, false): return 240
        case (.widescreen, true): return 170
        case (.poster, false): return 176
        case (.poster, true): return 124
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth, maximum: minWidth * 1.6), spacing: compact ? 16 : 24)],
                          alignment: .leading, spacing: compact ? 20 : 30) {
                    ForEach(Array(films.enumerated()), id: \.element.id) { index, film in
                        FilmTile(film: film, compact: compact)
                            .entrance(index: index)
                            .id(film.id)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 10)
                .padding(.bottom, bottomInset)
            }
            .onChange(of: model.selection) { sel in
                if sel.count == 1, let id = sel.first { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) } }
            }
        }
    }
}

/// Kinoplakat-Karte: Tiefe, weicher Schatten, Lichtschein in der Coverfarbe, beim Darüberfahren minimale
/// Vergrößerung, wandernder Lichtreflex und eine leichte Neigung zur Maus hin (nur bei voller Bewegung).
struct FilmTile: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.palette) private var p
    @Environment(\.motionFull) private var motionFull
    let film: Film
    var compact = false
    @State private var hover = false
    @State private var tilt = CGSize.zero
    @State private var posterSize = CGSize(width: 1, height: 1)
    @State private var glow: Color?

    private var selected: Bool { model.selection.contains(film.id) }
    private var available: Bool { model.isAvailable(film) }
    private var radius: CGFloat { compact ? 10 : 13 }
    /// Neu hinzugefügt (7 Tage) und noch nie abgespielt
    private var isNew: Bool { film.lastPlayedAt == nil && film.addedAt > Date().addingTimeInterval(-7 * 86_400) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            poster
            caption
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 1).onEnded { select() })
        .onTapGesture(count: 2) { model.play(film) }
        .contextMenu { FilmContextMenu(film: film) }
        .help(film.fileName)
        .zIndex(hover ? 1 : 0)
    }

    // MARK: Plakat

    private var poster: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let lifted = hover && available
        return ZStack {
            CoverImage(film: film, aspect: settings.tileShape.aspect, onColor: { glow = $0 })
                .saturation(available ? 1 : 0.12)
                .brightness(available ? 0 : -0.14)
            // Glanzkante oben (Glas-Licht) – sehr zart
            LinearGradient(colors: [Color.white.opacity(lifted ? 0.16 : 0.07), .clear], startPoint: .top, endPoint: .center)
                .allowsHitTesting(false)
            if motionFull { LightSweep(trigger: lifted, intensity: 0.20) }
            overlays
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(selected ? p.accent : (p.dark ? Color.white : Color.black).opacity(lifted ? 0.24 : (p.dark ? 0.10 : 0.07)),
                               lineWidth: selected ? 2.2 : 0.8)
        )
        // Lichtschein in der Coverfarbe (dezent; stärker bei Hover/Auswahl)
        .safeShadow(color: (selected ? p.accent : (glow ?? p.accent)).opacity(selected ? 0.55 : (lifted ? (p.dark ? 0.42 : 0.30) : (p.dark ? 0.14 : 0.08))),
                    radius: lifted || selected ? 24 : 16, y: lifted ? 12 : 8)
        // Kontaktschatten
        .safeShadow(color: p.shadow.opacity(lifted ? 1 : 0.75), radius: lifted ? 14 : 7, y: lifted ? 9 : 4)
        .rotation3DEffect(.degrees(motionFull && lifted ? Double(-tilt.height) * 4.5 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
        .rotation3DEffect(.degrees(motionFull && lifted ? Double(tilt.width) * 4.5 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .scaleEffect(lifted ? (motionFull ? 1.035 : 1.015) : 1)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { posterSize = g.size }
                .onChange(of: g.size) { posterSize = $0 }
        })
        .onContinuousHover { phase in
            switch phase {
            case .active(let pt):
                if !hover { withAnimation(Motion.posterSpring) { hover = true } }
                guard motionFull else { return }
                let nx = max(-1, min(1, (pt.x / max(1, posterSize.width)) * 2 - 1))
                let ny = max(-1, min(1, (pt.y / max(1, posterSize.height)) * 2 - 1))
                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9)) { tilt = CGSize(width: nx, height: ny) }
            case .ended:
                withAnimation(Motion.posterSpring) {
                    hover = false
                    tilt = .zero
                }
            }
        }
    }

    // MARK: Beschriftung

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(settings.displayTitle(film))
                .font(compact ? .system(size: 11.5, weight: .semibold) : Typo.tileTitle)
                .foregroundColor(available ? p.textPrimary : p.textSecondary)
                .lineLimit(compact ? 1 : 2)
                .multilineTextAlignment(.leading)
            if !compact || !metaLine.isEmpty {
                Text(metaLine)
                    .font(compact ? .system(size: 10.5) : Typo.tileMeta)
                    .foregroundColor(p.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 2)
        .offset(y: hover && available && motionFull ? 3 : 0)
        .animation(Motion.posterSpring, value: hover)
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

    // MARK: Auflagen

    @ViewBuilder
    private var overlays: some View {
        let lifted = hover && available
        ZStack {
            // Unten: weicher Schleier mit Abspielen und Eckdaten – nur beim Darüberfahren
            if lifted {
                LinearGradient(colors: [.clear, Color.black.opacity(0.62)], startPoint: .center, endPoint: .bottom)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                VStack {
                    Spacer()
                    HStack(spacing: 7) {
                        Button { model.play(film) } label: {
                            Image(systemName: "play.fill").offset(x: 1)
                        }
                        .buttonStyle(GlassIconButtonStyle(size: compact ? 28 : 34, overlay: true))
                        .help("Abspielen")
                        if !compact, let d = film.info.durationSeconds {
                            Text(film.progress != nil && !film.finished ? (Fmt.remaining(position: film.positionSeconds, duration: d) ?? Fmt.runtime(d)) : Fmt.runtime(d))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.92))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .padding(.bottom, film.progress != nil && !film.finished ? 15 : 9)
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
            // Oben: Format, Neu, Herz, gesehen
            VStack {
                HStack(spacing: 5) {
                    if settings.showFormatBadges {
                        badge(film.fileExtension.uppercased(), fill: Color.black.opacity(0.46))
                    }
                    if isNew && available && !compact {
                        badge("NEU", fill: p.accent.opacity(0.92))
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
                    if film.isFavorite || lifted {
                        Button { model.toggleFavorite([film.id]) } label: {
                            AnimatedHeart(isFavorite: film.isFavorite, size: 10, inactiveColor: .white)
                                .background(Circle().fill(Color.black.opacity(0.42)).frame(width: 20, height: 20))
                                .frame(width: 20, height: 20)
                                .contentShape(Circle())
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.85))
                        .help(film.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten")
                        .transition(.opacity)
                    }
                }
                .padding(7)
                Spacer()
            }
            if !available {
                Text(film.isMissing ? "Datei fehlt" : "Nicht verfügbar")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCapsule(kind: .overlay, interactive: false)
            }
            // Unten: Fortschritt (Verlauf, gut sichtbar)
            if let progress = film.progress, !film.finished {
                VStack {
                    Spacer()
                    ProgressStrip(fraction: progress)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 7)
                }
            }
        }
        .animation(Motion.posterSpring, value: hover)
    }

    private func badge(_ text: String, fill: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundColor(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
    }
}

/// Fortschritt eines Films: dünne Spur mit Verlauf (Akzent → Violett-Rosa) und weichem Lichtpunkt am Ende.
struct ProgressStrip: View {
    @Environment(\.palette) private var p
    let fraction: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let w = max(0, min(1, fraction)) * geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.45))
                Capsule()
                    .fill(LinearGradient(colors: [p.accent, p.pink.opacity(0.95)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, w))
                Circle()
                    .fill(Color.white)
                    .frame(width: height + 2, height: height + 2)
                    .safeShadow(color: p.pink.opacity(0.8), radius: 4)
                    .offset(x: max(0, w - height - 1))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Liste

struct FilmListView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.palette) private var p
    @Environment(\.contentBottomInset) private var bottomInset
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
            .padding(.bottom, bottomInset + 12)
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
