import SwiftUI
import AppKit
import FBCore
import FBServices

/// Startseite „Übersicht“: großes Kinobild (Weiterschauen), Statusleiste, Reihen und Karten wie in der Vorlage.
struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.palette) private var p
    @Environment(\.contentBottomInset) private var bottomInset

    private var heroFilm: Film? {
        let inProgress = model.films.filter { $0.playbackStatus == .inProgress && model.isAvailable($0) }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        if let f = inProgress.first { return f }
        return model.films.filter { model.isAvailable($0) && $0.coverSource != CoverSource.none }
            .sorted { $0.addedAt > $1.addedAt }.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LargeTitleHeader(title: "Start", subtitle: subtitle) {
                    ToolCapsule {
                        ToolButton(systemImage: "shuffle", help: "Zufälligen Film abspielen") { model.playRandom(from: model.films) }
                            .disabled(model.films.isEmpty)
                        ToolButton(systemImage: "arrow.clockwise", help: "Alle Speicherorte durchsuchen (⌘R)") { model.scanAll() }
                            .disabled(model.locations.isEmpty)
                        ToolDivider()
                        ToolButton(systemImage: "plus", label: "Speicherort", help: "Speicherort hinzufügen (⌘O)") { model.showAddLocationPanel() }
                        ToolButton(systemImage: "gearshape", help: "Einstellungen (⌘,)") { SettingsOpener.open() }
                    }
                }
                if model.locations.isEmpty {
                    WelcomeEmptyState().frame(minHeight: 460)
                } else {
                    if let hero = heroFilm { HeroCard(film: hero) }
                    statusBanner
                    shelf("Weiterschauen", systemImage: "play.circle", color: p.teal, scope: .continueWatching,
                          films: model.films.filter { $0.playbackStatus == .inProgress }
                            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) })
                    shelf("Neu hinzugefügt", systemImage: "sparkle", color: p.yellow, scope: .recentlyAdded,
                          films: Array(model.films.sorted { $0.addedAt > $1.addedAt }.prefix(24)))
                    shelf("Favoriten", systemImage: "heart.fill", color: p.heart, scope: .favorites,
                          films: model.films.filter(\.isFavorite).sorted { LibrarySorter.compareText($0.title, $1.title) == .orderedAscending })
                    cards
                    HintBar(text: "Alles bleibt auf diesem Mac. Die Filmbibliothek liest Ihre Videos nur – sie verändert, verschiebt oder löscht keine Datei, braucht kein Konto und sendet nichts ins Internet.")
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 4)
            .padding(.bottom, bottomInset + 12)
        }
    }

    private var subtitle: String {
        if model.locations.isEmpty { return "Noch keine Speicherorte" }
        var parts = [Fmt.count(model.films.count, "Film", "Filme"), Fmt.bytes(model.totalBytes)]
        parts.append(Fmt.count(model.locations.count, "Speicherort", "Speicherorte"))
        return parts.joined(separator: " · ")
    }

    // MARK: - Statusleiste

    @ViewBuilder
    private var statusBanner: some View {
        let unavailable = model.locations.filter { !(model.availability[$0.id]?.isAvailable ?? false) && model.availability[$0.id] != .unknown }
        if model.isScanning || model.metadataRemaining > 0 || !unavailable.isEmpty {
            HStack(spacing: 14) {
                StatusDot(color: unavailable.isEmpty ? p.teal : p.orange, size: 10, pulsing: model.isScanning || model.metadataRemaining > 0)
                    .padding(10)
                    .background(Circle().fill(p.control))
                VStack(alignment: .leading, spacing: 6) {
                    Text(bannerHeadline(unavailable: unavailable.count)).font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 6) {
                        if model.isScanning {
                            Chip(text: "Durchsuchen: \(Fmt.integer(model.scanProgress.values.reduce(0) { $0 + $1.videosFound })) Videos", dot: p.teal)
                        }
                        if model.metadataRemaining > 0 {
                            Chip(text: "Analyse: noch \(Fmt.integer(model.metadataRemaining))", dot: p.violet)
                        }
                        ForEach(unavailable.prefix(4)) { loc in
                            Chip(text: "\(loc.name): \(model.availabilityOf(location: loc.id).label)",
                                 dot: { if case .noAccess = model.availabilityOf(location: loc.id) { return p.orange } else { return p.textTertiary } }())
                        }
                    }
                }
                Spacer()
                if unavailable.contains(where: { if case .noAccess = model.availabilityOf(location: $0.id) { return true } else { return false } }) {
                    Button { model.regrantAll() } label: { Label("Freigaben erneuern …", systemImage: "lock.open") }
                        .buttonStyle(CapsuleButtonStyle(role: .primary, compact: true))
                        .help("Die Ordner einmal bestätigen – z. B. nach einer neuen App-Version. Bibliothek, Favoriten und Fortschritt bleiben erhalten.")
                }
                if !unavailable.isEmpty {
                    Button { model.navigate(.locations) } label: { Label("Warum?", systemImage: "info.circle") }
                        .buttonStyle(CapsuleButtonStyle(role: .glass, compact: true))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassCard()
        }
    }

    private func bannerHeadline(unavailable: Int) -> String {
        if unavailable > 0 {
            return unavailable == 1 ? "Ein Speicherort ist nicht verfügbar." : "\(unavailable) Speicherorte sind nicht verfügbar."
        }
        if model.isScanning { return "Speicherorte werden durchsucht …" }
        return "Titelbilder und technische Angaben werden ermittelt …"
    }

    // MARK: - Reihen

    @ViewBuilder
    private func shelf(_ title: String, systemImage: String, color: Color, scope: LibraryScope, films: [Film]) -> some View {
        if !films.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    IconBadge(systemImage: systemImage, color: color)
                    Text(title).font(.system(size: 17, weight: .bold))
                    Text(Fmt.integer(films.count)).font(Typo.caption).foregroundColor(p.textTertiary)
                    Spacer()
                    Button("Alle anzeigen") { model.navigate(.library(scope)) }
                        .buttonStyle(CapsuleButtonStyle(role: .plain, compact: true))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 20) {
                        ForEach(Array(films.prefix(20).enumerated()), id: \.element.id) { index, f in
                            FilmTile(film: f)
                                .frame(width: settings.tileShape == .widescreen ? 240 : 164)
                                .entrance(index: index)
                        }
                    }
                    // Luft für Vergrößerung, Neigung und Lichtschein beim Darüberfahren
                    .padding(.vertical, 16)
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    // MARK: - Karten

    private var cards: some View {
        MasonryLayout(minColumnWidth: 300, spacing: 16) {
            libraryCard
            playbackCard
            formatsCard
            ForEach(model.locations) { loc in LocationCard(location: loc, compact: true) }
        }
    }

    private var libraryCard: some View {
        GlassCard(title: "Bibliothek", systemImage: "film.stack", iconColor: p.accent) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.integer(model.films.count)).font(Typo.bigNumber)
                    Text(model.films.count == 1 ? "Film" : "Filme").font(Typo.body).foregroundColor(p.textSecondary)
                }
                let counts = statusCounts
                SegmentBar(segments: [(Double(counts.finished), p.green), (Double(counts.inProgress), p.teal), (Double(counts.unwatched), p.textTertiary.opacity(0.5))])
                HStack(spacing: 14) {
                    legend("Gesehen", counts.finished, p.green)
                    legend("Angefangen", counts.inProgress, p.teal)
                    legend("Offen", counts.unwatched, p.textTertiary)
                }
                Divider().overlay(p.hairline)
                InfoRow(label: "Gesamtgröße", value: Fmt.bytes(model.totalBytes))
                InfoRow(label: "Gesamtlaufzeit", value: Fmt.runtime(model.totalRuntime))
                InfoRow(label: "Favoriten", value: Fmt.integer(model.films.filter(\.isFavorite).count))
            }
        }
    }

    private var statusCounts: (finished: Int, inProgress: Int, unwatched: Int) {
        var a = 0, b = 0, c = 0
        for f in model.films {
            switch f.playbackStatus {
            case .finished: a += 1
            case .inProgress: b += 1
            case .unwatched: c += 1
            }
        }
        return (a, b, c)
    }

    private func legend(_ label: String, _ n: Int, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(Typo.caption).foregroundColor(p.textSecondary)
            Text(Fmt.integer(n)).font(Typo.captionStrong)
        }
    }

    private var playbackCard: some View {
        GlassCard(title: "Wiedergabe", systemImage: "play.rectangle", iconColor: p.teal) {
            VStack(alignment: .leading, spacing: 10) {
                let s = model.statistics
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.number((s?.totalSecondsWatched ?? 0) / 3600, digits: 1)).font(Typo.bigNumber)
                    Text("Stunden angesehen").font(Typo.body).foregroundColor(p.textSecondary)
                }
                InfoRow(label: "Wiedergaben gesamt", value: Fmt.integer(s?.totalPlays ?? 0))
                InfoRow(label: "Letzte 30 Tage", value: Fmt.integer(s?.playsLast30Days ?? 0))
                InfoRow(label: "Zuletzt abgespielt", value: Fmt.relative(model.films.compactMap(\.lastPlayedAt).max()))
            }
        }
    }

    private var formatsCard: some View {
        GlassCard(title: "Formate", systemImage: "square.stack.3d.up", iconColor: p.violet) {
            VStack(alignment: .leading, spacing: 8) {
                let groups = FormatGroup.make(model.films)
                ForEach(groups.prefix(6)) { g in
                    HStack {
                        Text(g.ext.uppercased()).font(Typo.bodyStrong).frame(width: 54, alignment: .leading)
                        Text(engineSummary(native: g.native, vlc: g.vlc, bad: g.unsupported)).font(Typo.caption).foregroundColor(p.textSecondary)
                        Spacer()
                        Text(Fmt.integer(g.count)).font(Typo.bodyStrong)
                    }
                }
                if groups.isEmpty { Text("Noch keine Filme").font(Typo.caption).foregroundColor(p.textTertiary) }
            }
        }
    }

    private func engineSummary(native: Int, vlc: Int, bad: Int) -> String {
        var parts: [String] = []
        if native > 0 { parts.append("AVFoundation \(native)") }
        if vlc > 0 { parts.append("VLCKit \(vlc)") }
        if bad > 0 { parts.append("nicht abspielbar \(bad)") }
        return parts.isEmpty ? "wird geprüft" : parts.joined(separator: " · ")
    }
}

/// Anzahl je Dateiformat und Engine (Karte „Formate“)
struct FormatGroup: Identifiable {
    let ext: String
    var count = 0
    var native = 0
    var vlc = 0
    var unsupported = 0
    var id: String { ext }

    static func make(_ films: [Film]) -> [FormatGroup] {
        var map: [String: FormatGroup] = [:]
        for f in films {
            var g = map[f.fileExtension] ?? FormatGroup(ext: f.fileExtension)
            g.count += 1
            switch f.playability {
            case .native: g.native += 1
            case .vlc: g.vlc += 1
            case .unsupported: g.unsupported += 1
            case .unknown: break
            }
            map[f.fileExtension] = g
        }
        return map.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.ext < $1.ext }
    }
}

/// Großes Kinobild (Vorlage: Apple-Produktseite) – zuletzt angefangener bzw. neuester Film
/// Kinobild auf „Start“: weichgezeichneter, vergrößerter Cover-Hintergrund, großes Plakat mit Tiefe,
/// Titel, Eckdaten, Fortschritt, Abspielen und Favorit. Färbt den Fensterhintergrund in der Coverfarbe.
struct HeroCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.palette) private var p
    @Environment(\.motionFull) private var motionFull
    let film: Film
    @State private var hover = false
    @State private var tint: Color?

    private let height: CGFloat = 330

    var body: some View {
        ZStack(alignment: .leading) {
            // Hintergrund: dasselbe Cover, groß und weich – die Fläche bekommt Farbe, ohne zu dominieren
            CoverImage(film: film, aspect: 21.0 / 9.0, showPlaceholderTitle: false, fill: true, onColor: { c in
                tint = c
                model.heroTint = c
            })
            .scaleEffect(1.25)
            .safeBlur(radius: 34)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            // Ohne Weichzeichner (eingeschränkte Grafik) das Bild stärker abdunkeln, damit die Schrift ruhig lesbar bleibt
            if RenderSafety.reducedEffects { Color.black.opacity(0.45) }
            LinearGradient(colors: [Color.black.opacity(0.72), Color.black.opacity(0.35), Color.black.opacity(0.15)], startPoint: .leading, endPoint: .trailing)
            RadialGradient(colors: [(tint ?? p.accent).opacity(0.35), .clear], center: UnitPoint(x: 0.82, y: 0.5), startRadius: 0, endRadius: 360)
                .blendMode(.plusLighter)
                .opacity(0.8)
            HStack(alignment: .center, spacing: 28) {
                info
                Spacer(minLength: 0)
                poster
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            // Text und Glasknöpfe liegen auf dem dunklen Bild – immer im dunklen Erscheinungsbild zeichnen
            .environment(\.colorScheme, .dark)
            .environment(\.palette, Palette.darkPalette)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
        .safeShadow(color: (tint ?? p.accent).opacity(p.dark ? 0.22 : 0.16), radius: 30, y: 14)
        .safeShadow(color: p.shadow, radius: 16, y: 8)
        .contextMenu { FilmContextMenu(film: film) }
        .onHover { hover = $0 }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(film.playbackStatus == .inProgress ? "WEITERSCHAUEN" : "NEU IN DEINER BIBLIOTHEK")
                .font(.system(size: 11, weight: .bold)).tracking(1.4)
                .foregroundColor(.white.opacity(0.72))
            Text(settings.displayTitle(film))
                .font(Typo.heroTitle)
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .safeShadow(color: .black.opacity(0.45), radius: 14)
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { c in
                    Text(c)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .glassCapsule(kind: .overlay, interactive: false)
                }
            }
            if let progress = film.progress, film.playbackStatus == .inProgress {
                HStack(spacing: 10) {
                    ProgressStrip(fraction: progress, height: 5).frame(width: 220)
                    Text(Fmt.remaining(position: film.positionSeconds, duration: film.info.durationSeconds) ?? "")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.82))
                }
            }
            HStack(spacing: 10) {
                Button { model.play(film, in: [film] + model.films.filter { $0.id != film.id && $0.playbackStatus == .inProgress }) } label: {
                    Label(film.playbackStatus == .inProgress ? "Weiterschauen" : "Abspielen", systemImage: "play.fill")
                }
                .buttonStyle(CapsuleButtonStyle(role: .primary))
                Button { model.navigate(.detail(film.id)) } label: { Label("Details", systemImage: "info.circle") }
                    .buttonStyle(CapsuleButtonStyle(role: .glass))
                Button { model.toggleFavorite([film.id]) } label: {
                    AnimatedHeart(isFavorite: film.isFavorite, size: 13, inactiveColor: .white)
                        .frame(width: 34, height: 34)
                        .glassCapsule(kind: .overlay)
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.9))
                .help(film.isFavorite ? "Aus Favoriten entfernen (⌘L)" : "Zu Favoriten (⌘L)")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    /// Großes Plakat mit Tiefe; neigt sich bei voller Bewegung minimal beim Darüberfahren
    private var poster: some View {
        let widescreen = settings.tileShape == .widescreen
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return CoverImage(film: film, aspect: widescreen ? 16.0 / 9.0 : 2.0 / 3.0)
            .frame(width: widescreen ? 380 : 186)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8))
            .overlay(LinearGradient(colors: [Color.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center).clipShape(shape).allowsHitTesting(false))
            .safeShadow(color: Color.black.opacity(0.5), radius: 22, y: 14)
            .rotation3DEffect(.degrees(motionFull && hover ? -4 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .scaleEffect(motionFull && hover ? 1.02 : 1)
            .animation(Motion.posterSpring, value: hover)
            .onTapGesture { model.navigate(.detail(film.id)) }
            .layoutPriority(-1)
    }

    private var chips: [String] {
        var c: [String] = []
        if let y = TitleCleaner.year(forFileName: film.fileName) { c.append(String(y)) }
        if let d = film.info.durationSeconds { c.append(Fmt.runtime(d)) }
        if let r = film.resolutionClass { c.append(r.label) }
        if let v = film.info.videoCodec { c.append(v) }
        c.append(film.fileExtension.uppercased())
        return c
    }
}

/// Mehrfarbiger Balken (Vorlage: Arbeitsspeicher-Aufteilung)
struct SegmentBar: View {
    @Environment(\.palette) private var p
    let segments: [(Double, Color)]

    var body: some View {
        GeometryReader { geo in
            let total = max(1, segments.reduce(0) { $0 + $1.0 })
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                    if s.0 > 0 {
                        Capsule().fill(s.1).frame(width: max(4, (geo.size.width - 4) * CGFloat(s.0 / total)))
                    }
                }
            }
        }
        .frame(height: 7)
        .background(Capsule().fill(p.control))
    }
}
