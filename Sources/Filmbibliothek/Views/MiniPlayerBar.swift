import SwiftUI
import FBCore
import FBServices

/// Schwebende Mini-Player-Kapsel unten im Hauptfenster (wie in der Musikbibliothek), solange ein Film läuft.
/// Steuert das Player-Fenster: Wiedergabe/Pause, Sprünge, nächster Film, Zeitleiste, Lautstärke.
struct MiniPlayerBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @ObservedObject var controller: PlayerController

    private var isPlaying: Bool { controller.state == .playing }

    var body: some View {
        HStack(spacing: 16) {
            cover
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(controller.title.isEmpty ? "Film" : controller.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(p.textPrimary)
                        .lineLimit(1)
                    if !controller.engineName.isEmpty {
                        Text(controller.engineName)
                            .font(.system(size: 9.5, weight: .bold))
                            .tracking(0.4)
                            .foregroundColor(p.textTertiary)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(p.hairline, lineWidth: 0.8))
                    }
                }
                if !controller.subtitle.isEmpty {
                    Text(controller.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(p.textSecondary)
                        .lineLimit(1)
                }
                timeline
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            transport
            trailing
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(height: Chrome.miniPlayerHeight)
        .glass(RoundedRectangle(cornerRadius: 28, style: .continuous), kind: .panel, elevated: true)
        .safeShadow(color: p.shadow, radius: 22, y: 10)
    }

    // MARK: Cover

    @ViewBuilder
    private var cover: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            if let film = controller.film {
                CoverImage(film: film, aspect: 16 / 9, onColor: { model.playerTint = $0 })
            } else {
                PosterPlaceholder(title: controller.title, ext: "", seed: 0)
            }
        }
        .frame(width: 118, height: 66)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8))
        .safeShadow(color: Color.black.opacity(0.35), radius: 8, y: 4)
        .onTapGesture { model.player.bringToFront() }
        .help("Player-Fenster zeigen")
    }

    // MARK: Zeitleiste

    private var timeline: some View {
        HStack(spacing: 10) {
            Text(Fmt.clock(controller.time))
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundColor(p.textSecondary)
                .frame(minWidth: 38, alignment: .trailing)
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

    private var transport: some View {
        HStack(spacing: 10) {
            Button { controller.playPrevious() } label: { Image(systemName: "backward.end.fill") }
                .buttonStyle(GlassIconButtonStyle(size: 30))
                .help("Vorheriger Film")
                .disabled(!controller.queue.hasPrevious)
            Button { controller.seek(by: -(model.settings.seekStep)) } label: { Image(systemName: "gobackward.10") }
                .buttonStyle(GlassIconButtonStyle(size: 32))
                .help("Zurückspringen")
            PlayPauseButton(isPlaying: isPlaying, size: 46) { controller.togglePlay() }
            Button { controller.seek(by: model.settings.seekStep) } label: { Image(systemName: "goforward.10") }
                .buttonStyle(GlassIconButtonStyle(size: 32))
                .help("Vorspringen")
            Button { controller.playNext() } label: { Image(systemName: "forward.end.fill") }
                .buttonStyle(GlassIconButtonStyle(size: 30))
                .help("Nächster Film")
                .disabled(!controller.queue.hasNext)
        }
    }

    private var trailing: some View {
        HStack(spacing: 8) {
            VolumeSlider(volume: Binding(get: { controller.volume }, set: { controller.volume = $0 }),
                         muted: Binding(get: { controller.muted }, set: { controller.muted = $0 }))
                .frame(width: 110)
            Button { model.player.bringToFront() } label: { Image(systemName: "rectangle.on.rectangle") }
                .buttonStyle(GlassIconButtonStyle(size: 30))
                .help("Player-Fenster zeigen")
            Button { Task { await controller.close() } } label: { Image(systemName: "xmark") }
                .buttonStyle(GlassIconButtonStyle(size: 30))
                .help("Wiedergabe beenden (Position wird gespeichert)")
        }
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
                    .foregroundColor(onDark ? .white.opacity(0.85) : p.textSecondary)
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
