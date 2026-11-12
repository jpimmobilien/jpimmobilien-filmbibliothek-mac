import SwiftUI
import FBCore
import FBServices

/// Schwebender Mini-Player unten im Hauptfenster – Aufbau wie in der Musikbibliothek: großes Titelbild links,
/// rechts Titel, Eckdaten und Zeitleiste, darunter Lautstärke, Wiedergabe-Steuerung in der Mitte und Ton/Tempo.
/// Steuert das Player-Fenster; erscheint, solange ein Film läuft.
struct MiniPlayerBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @ObservedObject var controller: PlayerController
    /// Verfügbare Breite – unter 860 pt rückt alles enger zusammen
    var width: CGFloat = 1040

    private var isPlaying: Bool { controller.state == .playing }
    private var compact: Bool { width < 860 }
    /// Aktueller Stand des Films aus der Bibliothek (Favorit kann sich während der Wiedergabe ändern)
    private var film: Film? { controller.film.flatMap { model.film($0.id) } ?? controller.film }

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 14 : 20) {
            cover
            VStack(alignment: .leading, spacing: compact ? 6 : 9) {
                header
                timeline
                controlsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 14)
        .padding(.trailing, compact ? 14 : 18)
        .padding(.vertical, 12)
        .frame(height: Chrome.miniPlayerHeight)
        .glass(RoundedRectangle(cornerRadius: 30, style: .continuous), kind: .panel, elevated: true)
        .safeShadow(color: p.shadow, radius: 24, y: 12)
    }

    // MARK: Titelbild

    private var cover: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let w: CGFloat = compact ? 150 : 214
        return ZStack {
            if let film = controller.film {
                CoverImage(film: film, aspect: 16 / 9, showPlaceholderTitle: false, fill: true, onColor: { model.playerTint = $0 })
            } else {
                PosterPlaceholder(title: controller.title, ext: "", seed: 0)
            }
        }
        .frame(width: w, height: w * 9 / 16)
        .clipShape(shape)
        .overlay(LinearGradient(colors: [Color.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center)
            .clipShape(shape).allowsHitTesting(false))
        .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8))
        .safeShadow(color: (model.playerTint ?? p.accent).opacity(p.dark ? 0.45 : 0.3), radius: 18, y: 8)
        .onTapGesture { model.player.bringToFront() }
        .help("Player-Fenster zeigen")
    }

    // MARK: Kopfzeile

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.title.isEmpty ? "Film" : controller.title)
                    .font(.system(size: compact ? 15 : 17, weight: .bold))
                    .foregroundColor(p.textPrimary)
                    .lineLimit(1)
                if !accentLine.isEmpty {
                    Text(accentLine)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(p.accent)
                        .lineLimit(1)
                }
                if !compact && !secondaryLine.isEmpty {
                    Text(secondaryLine)
                        .font(.system(size: 11.5))
                        .foregroundColor(p.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                if let film {
                    Button { model.toggleFavorite([film.id]) } label: {
                        AnimatedHeart(isFavorite: film.isFavorite, size: 13, inactiveColor: p.textSecondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.88))
                    .help(film.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten")
                }
                tracksMenu
                Button { model.player.bringToFront() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(GlassIconButtonStyle(size: 30))
                    .help("Player-Fenster zeigen")
                Button { Task { await controller.close() } } label: { Image(systemName: "xmark") }
                    .buttonStyle(GlassIconButtonStyle(size: 30))
                    .help("Wiedergabe beenden (Position wird gespeichert)")
            }
        }
    }

    /// Eckdaten in Akzentfarbe (wie der Interpret in der Musikbibliothek): Jahr · Auflösung · Laufzeit
    private var accentLine: String {
        guard let film else { return "" }
        var parts: [String] = []
        if let y = TitleCleaner.year(forFileName: film.fileName) { parts.append(String(y)) }
        if let r = film.resolutionClass { parts.append(r.label) }
        if let d = film.info.durationSeconds ?? controller.duration { parts.append(Fmt.runtime(d)) }
        return parts.joined(separator: " · ")
    }

    /// Speicherort, Ordner, Format, Wiedergabe-Technik und Position in der Warteschlange
    private var secondaryLine: String {
        var parts: [String] = []
        if !controller.subtitle.isEmpty { parts.append(controller.subtitle) }
        if !controller.engineName.isEmpty { parts.append(controller.engineName) }
        let q = controller.queue
        if q.order.count > 1 { parts.append("Film \(q.index + 1) von \(q.order.count)") }
        return parts.joined(separator: " · ")
    }

    // MARK: Zeitleiste

    private var timeline: some View {
        HStack(spacing: 10) {
            Text(Fmt.clock(controller.time))
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundColor(p.textSecondary)
                .frame(minWidth: 40, alignment: .trailing)
            ScrubBar(time: controller.time, duration: controller.duration, chapters: controller.chapters.map(\.start)) { t in
                controller.seek(to: t)
            }
            Text(controller.duration.map { "−" + Fmt.clock(max(0, $0 - controller.time)) } ?? "–:––")
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundColor(p.textSecondary)
                .frame(minWidth: 44, alignment: .leading)
        }
    }

    // MARK: Steuerung

    private var controlsRow: some View {
        let side: CGFloat = compact ? 110 : 170
        return HStack(spacing: 0) {
            VolumeSlider(volume: Binding(get: { controller.volume }, set: { controller.volume = $0 }),
                         muted: Binding(get: { controller.muted }, set: { controller.muted = $0 }))
                .frame(width: side - 12)
                .frame(width: side, alignment: .leading)
            Spacer(minLength: 0)
            transport
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if !compact { speedMenu }
            }
            .frame(width: side, alignment: .trailing)
        }
    }

    private var transport: some View {
        HStack(spacing: compact ? 6 : 10) {
            Button { controller.playPrevious() } label: { Image(systemName: "backward.end.fill") }
                .buttonStyle(GlassIconButtonStyle(size: 30))
                .help("Vorheriger Film")
                .disabled(!controller.queue.hasPrevious)
            Button { controller.seek(by: -(model.settings.seekStep)) } label: { Image(systemName: "gobackward.10") }
                .buttonStyle(GlassIconButtonStyle(size: 32))
                .help("Zurückspringen")
            PlayPauseButton(isPlaying: isPlaying, size: compact ? 42 : 46) { controller.togglePlay() }
            Button { controller.seek(by: model.settings.seekStep) } label: { Image(systemName: "goforward.10") }
                .buttonStyle(GlassIconButtonStyle(size: 32))
                .help("Vorspringen")
            Button { controller.playNext() } label: { Image(systemName: "forward.end.fill") }
                .buttonStyle(GlassIconButtonStyle(size: 30))
                .help("Nächster Film")
                .disabled(!controller.queue.hasNext)
        }
    }

    /// Ton- und Untertitelspuren (wie im Player-Fenster)
    private var tracksMenu: some View {
        let active = controller.selectedSubtitle != nil || controller.activeExternalSubtitle != nil
        return Menu {
            Section("Tonspur") {
                if controller.audioTracks.isEmpty { Text("Keine Auswahl verfügbar") }
                ForEach(controller.audioTracks) { t in
                    Button { controller.selectAudio(t.id) } label: {
                        if controller.selectedAudio == t.id { Label(t.title, systemImage: "checkmark") } else { Text(t.title) }
                    }
                }
            }
            Section("Untertitel") {
                Button { controller.selectSubtitle(nil) } label: {
                    if !active { Label("Aus", systemImage: "checkmark") } else { Text("Aus") }
                }
                ForEach(controller.subtitleTracks) { t in
                    Button { controller.selectSubtitle(t.id) } label: {
                        if controller.selectedSubtitle == t.id && controller.activeExternalSubtitle == nil { Label(t.title, systemImage: "checkmark") } else { Text(t.title) }
                    }
                }
                ForEach(controller.externalSubtitles, id: \.self) { u in
                    Button { controller.activateExternalSubtitle(u) } label: {
                        if controller.activeExternalSubtitle == u { Label(u.lastPathComponent, systemImage: "checkmark") } else { Text(u.lastPathComponent) }
                    }
                }
            }
        } label: {
            Image(systemName: "captions.bubble")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(active ? p.accent : p.textPrimary.opacity(0.8))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 30, height: 30)
        .help("Ton und Untertitel")
    }

    /// Geschwindigkeit als Glas-Kapsel (wie „Equalizer“ / „Tonhöhe“ in der Musikbibliothek)
    private var speedMenu: some View {
        Menu {
            ForEach(SeekMath.speeds, id: \.self) { s in
                Button { controller.rate = s } label: {
                    if abs(controller.rate - s) < 0.01 { Label(SeekMath.speedLabel(s), systemImage: "checkmark") } else { Text(SeekMath.speedLabel(s)) }
                }
            }
        } label: {
            Label("Tempo \(SeekMath.speedLabel(controller.rate))", systemImage: "speedometer")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(abs(controller.rate - 1) > 0.01 ? p.accent : p.textPrimary.opacity(0.85))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule(style: .continuous).fill(p.control))
        .glassCapsule(kind: .control)
        .help("Wiedergabe-Geschwindigkeit")
    }
}

/// Zentraler Wiedergabe-Knopf: Akzent-Kreis mit weichem Lichtschein bei Hover; Play und Pause gehen
/// ineinander über (Überblendung mit leichter Drehung statt hartem Wechsel).
struct PlayPauseButton: View {
    @Environment(\.palette) private var p
    @Environment(\.motionFull) private var motionFull
    let isPlaying: Bool
    var size: CGFloat = 46
    var overlayStyle = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(overlayStyle ? Color.white.opacity(hover ? 0.28 : 0.2) : p.accent)
                Circle()
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                Image(systemName: "pause.fill")
                    .opacity(isPlaying ? 1 : 0)
                    .scaleEffect(isPlaying ? 1 : 0.6)
                    .rotationEffect(.degrees(isPlaying || !motionFull ? 0 : -45))
                Image(systemName: "play.fill")
                    .offset(x: size * 0.035)
                    .opacity(isPlaying ? 0 : 1)
                    .scaleEffect(isPlaying ? 0.6 : 1)
                    .rotationEffect(.degrees(!isPlaying || !motionFull ? 0 : 45))
            }
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundColor(overlayStyle ? .white : p.onAccent)
            .frame(width: size, height: size)
            .scaleEffect(hover ? 1.06 : 1)
            .safeShadow(color: (overlayStyle ? Color.white : p.accent).opacity(hover ? 0.55 : 0.25), radius: hover ? 16 : 8)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .onHover { hover = $0 }
        .animation(Motion.hoverCurve, value: hover)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isPlaying)
        .help(isPlaying ? "Pause (Leertaste)" : "Wiedergabe (Leertaste)")
    }
}

/// Zeitleiste mit Verlauf, präzisem Abspielpunkt, Kapitelmarken und Zeit-Vorschau beim Darüberfahren.
struct ScrubBar: View {
    @Environment(\.palette) private var p
    let time: Double
    let duration: Double?
    var chapters: [Double] = []
    var onDark = false
    let onSeek: (Double) -> Void
    @State private var hoverX: CGFloat?
    @State private var dragFraction: Double?

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let d = duration ?? 0
            let fraction = dragFraction ?? (d > 0 ? min(1, max(0, time / d)) : 0)
            let active = hoverX != nil || dragFraction != nil
            let h: CGFloat = active ? 6 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(onDark ? Color.white.opacity(0.22) : p.control)
                    .frame(height: h)
                Capsule()
                    .fill(LinearGradient(colors: [p.accent, p.pink], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(h, w * fraction), height: h)
                ForEach(chapters.filter { $0 > 0.5 && d > 0 }, id: \.self) { c in
                    Rectangle()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 1.5, height: h)
                        .offset(x: w * min(1, c / d))
                }
                Circle()
                    .fill(Color.white)
                    .frame(width: active ? 13 : 9, height: active ? 13 : 9)
                    .safeShadow(color: p.accent.opacity(0.6), radius: active ? 6 : 3)
                    .offset(x: w * fraction - (active ? 6.5 : 4.5))
                if let x = hoverX, d > 0 {
                    Text(Fmt.clock(Double(x / w) * d))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.72)))
                        .fixedSize()
                        .offset(x: min(max(0, x - 22), w - 44), y: -18)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 16)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let pt): hoverX = min(max(0, pt.x), w)
                case .ended: hoverX = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in dragFraction = Double(min(max(0, v.location.x), w) / w) }
                    .onEnded { v in
                        let f = Double(min(max(0, v.location.x), w) / w)
                        dragFraction = nil
                        if d > 0 { onSeek(f * d) }
                    }
            )
            .animation(Motion.hoverCurve, value: active)
        }
        .frame(height: 18)
        .disabled((duration ?? 0) <= 0)
    }
}

/// Lautstärke: Glas-Spur mit gefülltem Verlauf und präzisem Regler; Lautsprecher-Symbol schaltet stumm.
struct VolumeSlider: View {
    @Environment(\.palette) private var p
    @Binding var volume: Double
    @Binding var muted: Bool
    var onDark = false
    @State private var active = false

    var body: some View {
        HStack(spacing: 7) {
            Button { muted.toggle() } label: {
                Image(systemName: muted || volume == 0 ? "speaker.slash.fill" : (volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(onDark ? Color.white.opacity(0.85) : p.textSecondary)
                    .frame(width: 18)
            }
            .buttonStyle(PressScaleStyle(scale: 0.85))
            .help(muted ? "Ton an" : "Ton aus")
            GeometryReader { geo in
                let w = max(1, geo.size.width)
                let v = muted ? 0 : min(1, max(0, volume))
                ZStack(alignment: .leading) {
                    Capsule().fill(onDark ? Color.white.opacity(0.22) : p.control)
                        .overlay(Capsule().strokeBorder(onDark ? Color.white.opacity(0.12) : p.hairline, lineWidth: 0.6))
                        .frame(height: active ? 6 : 4.5)
                    Capsule().fill(onDark ? Color.white.opacity(0.9) : p.accent)
                        .frame(width: max(4, w * v), height: active ? 6 : 4.5)
                    Circle().fill(Color.white)
                        .frame(width: active ? 13 : 10, height: active ? 13 : 10)
                        .safeShadow(color: Color.black.opacity(0.3), radius: 3, y: 1)
                        .offset(x: w * v - (active ? 6.5 : 5))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        active = true
                        muted = false
                        volume = Double(min(max(0, g.location.x), w) / w)
                    }
                    .onEnded { _ in active = false })
                .onHover { active = $0 }
                .animation(Motion.hoverCurve, value: active)
            }
            .frame(height: 16)
        }
        .help("Lautstärke")
    }
}
