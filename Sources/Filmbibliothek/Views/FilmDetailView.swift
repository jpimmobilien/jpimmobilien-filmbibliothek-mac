import SwiftUI
import AppKit
import FBCore
import FBServices

/// Detailseite eines Films: Kinobild, großer Titel, Chips, Aktionen, Infokarten (Vorlage: „Hardware“-Seite).
struct FilmDetailView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.palette) private var p
    let film: Film

    var body: some View {
        let available = model.isAvailable(film)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button { model.goBack() } label: { Label("Zurück", systemImage: "chevron.left") }
                        .buttonStyle(CapsuleButtonStyle(role: .glass, compact: true))
                        .keyboardShortcut("[", modifiers: .command)
                    Spacer()
                }
                hero(available: available)
                if let reason = model.unavailableReason(film) {
                    HintBar(text: reason + " Titelbild, Angaben und Fortschritt bleiben erhalten.", systemImage: "externaldrive.badge.exclamationmark", color: p.orange)
                }
                if film.playability == .unsupported {
                    HintBar(text: "Weder AVFoundation noch VLCKit können diese Datei öffnen. Sie ist vermutlich beschädigt, unvollständig oder in einem nicht unterstützten Format. Mit „Im Finder zeigen“ können Sie sie prüfen.", systemImage: "exclamationmark.triangle", color: p.orange)
                }
                infoCards
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)
            .padding(.bottom, 36)
        }
    }

    // MARK: - Kopf

    private func hero(available: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 26) {
            CoverImage(film: film, aspect: settings.tileShape.aspect)
                .frame(width: settings.tileShape == .widescreen ? 380 : 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8))
                .safeShadow(color: p.shadow, radius: 20, y: 10)
                .saturation(available ? 1 : 0.2)
            VStack(alignment: .leading, spacing: 10) {
                Text(model.locationName(film.locationId).uppercased() + (film.folder.isEmpty ? "" : " · " + film.folder.uppercased()))
                    .font(.system(size: 10.5, weight: .bold)).tracking(1.1)
                    .foregroundColor(p.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(settings.displayTitle(film))
                    .font(.system(size: 38, weight: .bold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .textSelection(.enabled)
                if settings.titleSource == .cleaned && film.title != film.fileName {
                    Text(film.fileName).font(Typo.body).foregroundColor(p.textSecondary).lineLimit(2).textSelection(.enabled)
                }
                FlowLayout(spacing: 6) {
                    ForEach(chips, id: \.self) { c in Chip(text: c) }
                }
                statusLine
                actions(available: available)
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .background(
            CoverImage(film: film, aspect: 3, showPlaceholderTitle: false, fill: true)
                .safeBlur(radius: 50)
                .opacity(p.dark ? 0.35 : 0.25)
                .clipped()
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassCard(cornerRadius: 24)
    }

    private var chips: [String] {
        var c: [String] = []
        if let y = TitleCleaner.year(forFileName: film.fileName) { c.append(String(y)) }
        if let d = film.info.durationSeconds { c.append(Fmt.runtime(d)) }
        if let r = film.resolutionClass { c.append(r.label) }
        if let v = film.info.videoCodec { c.append(v) }
        if let a = film.info.audioCodec { c.append(a) }
        c.append(film.fileExtension.uppercased())
        c.append(Fmt.bytes(film.sizeBytes))
        return c
    }

    @ViewBuilder
    private var statusLine: some View {
        switch film.playbackStatus {
        case .inProgress:
            HStack(spacing: 10) {
                CapsuleBar(fraction: film.progress ?? 0, height: 5).frame(width: 220)
                Text("Bei \(Fmt.clock(film.positionSeconds))" + (Fmt.remaining(position: film.positionSeconds, duration: film.info.durationSeconds).map { " · \($0)" } ?? ""))
                    .font(Typo.caption).foregroundColor(p.textSecondary)
            }
        case .finished:
            Label("Gesehen", systemImage: "checkmark.circle.fill").font(Typo.captionStrong).foregroundColor(p.green)
        case .unwatched:
            EmptyView()
        }
    }

    private func actions(available: Bool) -> some View {
        HStack(spacing: 8) {
            Button { model.play(film) } label: {
                Label(film.playbackStatus == .inProgress ? "Weiterschauen" : "Abspielen", systemImage: "play.fill")
            }
            .buttonStyle(CapsuleButtonStyle(role: .primary))
            .disabled(!available || film.playability == .unsupported)
            .keyboardShortcut(.return, modifiers: [])
            if film.playbackStatus == .inProgress {
                Button("Von Anfang an") { model.play(film, fromStart: true) }
                    .buttonStyle(CapsuleButtonStyle(role: .glass))
                    .disabled(!available)
            }
            Button { model.toggleFavorite([film.id]) } label: {
                Image(systemName: film.isFavorite ? "heart.fill" : "heart").foregroundColor(film.isFavorite ? p.heart : p.textPrimary)
            }
            .buttonStyle(GlassIconButtonStyle(size: 34))
            .help(film.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten")
            Button { model.setFinished([film.id], !film.finished) } label: {
                Image(systemName: film.finished ? "checkmark.circle.fill" : "checkmark.circle").foregroundColor(film.finished ? p.green : p.textPrimary)
            }
            .buttonStyle(GlassIconButtonStyle(size: 34))
            .help(film.finished ? "Als nicht gesehen markieren" : "Als gesehen markieren")
            Menu {
                ForEach(model.collections) { c in Button(c.name) { model.add([film.id], to: c) } }
                if !model.collections.isEmpty { Divider() }
                Button("Neue Sammlung …") { model.collectionNamePrompt = AppModel.CollectionPrompt(addFilms: [film.id]) }
            } label: {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .tint(p.textPrimary)
            .frame(width: 34, height: 34)
            .glass(Circle(), kind: .control, interactive: true)
            .help("Zur Sammlung hinzufügen")
            Button { model.revealInFinder([film]) } label: { Image(systemName: "folder") }
                .buttonStyle(GlassIconButtonStyle(size: 34))
                .disabled(!available)
                .help("Im Finder zeigen")
        }
    }

    // MARK: - Infokarten

    private var infoCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 700), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
            GlassCard(title: "Video", systemImage: "film", iconColor: p.accent) {
                VStack(spacing: 9) {
                    InfoRow(label: "Auflösung", value: Fmt.resolution(film.info.width, film.info.height).map { r in film.resolutionClass.map { "\(r) (\($0.label))" } ?? r } ?? "–")
                    InfoRow(label: "Seitenverhältnis", value: Fmt.aspectRatio(film.info.width, film.info.height) ?? "–")
                    InfoRow(label: "Bildrate", value: Fmt.frameRate(film.info.frameRate) ?? "–")
                    InfoRow(label: "Videocodec", value: film.info.videoCodec ?? "–")
                    InfoRow(label: "Datenrate", value: Fmt.bitRate(film.info.bitRate) ?? "–")
                    InfoRow(label: "Laufzeit", value: film.info.durationSeconds.map { "\(Fmt.clock($0)) (\(Fmt.runtime($0)))" } ?? "–")
                }
            }
            GlassCard(title: "Ton, Untertitel, Kapitel", systemImage: "waveform", iconColor: p.teal) {
                VStack(spacing: 9) {
                    InfoRow(label: "Tonspuren", value: Fmt.integer(film.info.audioTrackCount))
                    InfoRow(label: "Audiocodec", value: film.info.audioCodec ?? "–")
                    InfoRow(label: "Untertitelspuren", value: Fmt.integer(film.info.subtitleTrackCount))
                    InfoRow(label: "Kapitel", value: film.info.chapterCount > 0 ? Fmt.integer(film.info.chapterCount) : (film.playability == .vlc ? "beim Abspielen" : "–"))
                    if let t = film.info.embeddedTitle { InfoRow(label: "Titel in der Datei", value: t) }
                }
            }
            GlassCard(title: "Datei", systemImage: "doc", iconColor: p.orange) {
                VStack(spacing: 9) {
                    InfoRow(label: "Name", value: film.fileName)
                    InfoRow(label: "Ordner", value: film.folder.isEmpty ? "(oberste Ebene)" : film.folder)
                    InfoRow(label: "Speicherort", value: model.locationName(film.locationId))
                    InfoRow(label: "Format", value: VideoFormats.format(forExtension: film.fileExtension).map { "\($0.name) (.\(film.fileExtension))" } ?? film.fileExtension.uppercased())
                    InfoRow(label: "Größe", value: "\(Fmt.bytes(film.sizeBytes)) (\(Fmt.integer(Int(film.sizeBytes))) Byte)")
                    InfoRow(label: "Geändert", value: Fmt.date(film.modifiedAt))
                    InfoRow(label: "Erstellt", value: Fmt.date(film.createdAt))
                }
            }
            GlassCard(title: "Wiedergabe", systemImage: "play.circle", iconColor: p.green) {
                VStack(spacing: 9) {
                    InfoRow(label: "Wiedergabe mit", value: film.playability.label,
                            valueColor: film.playability == .unsupported ? p.orange : nil)
                    InfoRow(label: "Status", value: film.playbackStatus.label)
                    InfoRow(label: "Position", value: film.positionSeconds > 0 ? Fmt.clock(film.positionSeconds) : "–")
                    InfoRow(label: "Zuletzt abgespielt", value: film.lastPlayedAt.map { Fmt.date($0) } ?? "nie")
                    InfoRow(label: "Wiedergaben", value: Fmt.integer(film.playCount))
                    InfoRow(label: "In der Bibliothek seit", value: Fmt.date(film.addedAt))
                    InfoRow(label: "Titelbild", value: film.coverSource.label)
                }
            }
        }
    }
}
