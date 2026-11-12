import SwiftUI
import AppKit
import FBCore
import FBServices

/// Player-Oberfläche: Video, schwebende Glas-Kapsel mit allen Bedienelementen, Untertitel, Rückfragen.
struct PlayerView: View {
    @ObservedObject var controller: PlayerController
    @Environment(\.palette) private var p

    var body: some View {
        ZStack {
            Color.black
            VideoSurface(view: controller.engineView)
                .allowsHitTesting(false)

            // Klickfläche: einmal = Wiedergabe/Pause, doppelt = Vollbild
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { controller.window?.toggleFullScreen(nil) }
                .onTapGesture(count: 1) { controller.togglePlay() }

            if let text = controller.subtitleText {
                VStack {
                    Spacer()
                    Text(text)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .safeShadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 1)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
                        .padding(.bottom, controller.controlsVisible ? 140 : 48)
                }
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.3), value: controller.controlsVisible)
            }

            if controller.state == .loading || (controller.state == .ready && controller.time == 0 && controller.resumePrompt == nil && controller.errorMessage == nil) {
                ProgressView().controlSize(.large).colorScheme(.dark)
                    .allowsHitTesting(false)
            }

            if let feedback = controller.seekFeedback {
                Text(feedback)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .glassCapsule(kind: .overlay, interactive: false)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .allowsHitTesting(false)
            }

            if controller.controlsVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    controlCapsule
                        .onHover { controller.pointerOnControls = $0 }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 22)
                }
                .transition(.opacity.combined(with: .offset(y: 8)))
            }

            // Großer Wiedergabe-Knopf in der Bildmitte, solange pausiert – verschwindet beim Start weich
            if controller.state == .paused && controller.resumePrompt == nil && controller.errorMessage == nil {
                PlayPauseButton(isPlaying: false, size: 84, overlayStyle: true) { controller.togglePlay() }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            if let at = controller.resumePrompt { resumeCard(at) }
            if let message = controller.errorMessage { errorCard(message) }
        }
        .onContinuousHover { phase in
            if case .active = phase { controller.userActivity() }
        }
        .animation(.easeOut(duration: 0.2), value: controller.seekFeedback)
        .animation(Motion.detailCurve, value: controller.state == .paused)
        .frame(minWidth: 480, minHeight: 270)
    }

    // MARK: - Oben: Titel

    private var topBar: some View {
        HStack {
            Spacer(minLength: 90) // Platz für die Fensterknöpfe
            VStack(spacing: 2) {
                Text(controller.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(controller.subtitle + (controller.engineName.isEmpty ? "" : " · \(controller.engineName)"))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .glassCapsule(kind: .overlay, interactive: false)
            Spacer(minLength: 90)
        }
        .padding(.top, 10)
    }

    // MARK: - Unten: Glas-Kapsel

    private var controlCapsule: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text(Fmt.clock(controller.scrubbing ?? controller.time))
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.9))
                    .frame(minWidth: 52, alignment: .trailing)
                Scrubber(controller: controller)
                    .frame(height: 18)
                Text(remainingLabel)
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.65))
                    .frame(minWidth: 58, alignment: .leading)
            }
            HStack(spacing: 10) {
                // links: Lautstärke
                VolumeSlider(volume: Binding(get: { controller.volume }, set: { controller.volume = $0 }),
                             muted: Binding(get: { controller.muted }, set: { controller.muted = $0 }), onDark: true)
                    .frame(width: 140, alignment: .leading)
                    .help("Lautstärke (↑/↓), Ton aus/an (M)")

                Spacer(minLength: 8)

                // Mitte: Transport
                GlassGroup(spacing: 10) {
                    HStack(spacing: 12) {
                        Button { controller.playPrevious() } label: { Image(systemName: "backward.end.fill") }
                            .buttonStyle(GlassIconButtonStyle(size: 34, overlay: true))
                            .help("Zurück (⌘←)")
                        Button { controller.seek(by: -controller.seekStep) } label: { Image(systemName: "gobackward.\(Int(controller.seekStep))") }
                            .buttonStyle(GlassIconButtonStyle(size: 38, overlay: true))
                            .help("\(Int(controller.seekStep)) Sekunden zurück (←)")
                        PlayPauseButton(isPlaying: controller.isPlaying, size: 52, overlayStyle: true) { controller.togglePlay() }
                        Button { controller.seek(by: controller.seekStep) } label: { Image(systemName: "goforward.\(Int(controller.seekStep))") }
                            .buttonStyle(GlassIconButtonStyle(size: 38, overlay: true))
                            .help("\(Int(controller.seekStep)) Sekunden vor (→)")
                        Button { controller.playNext() } label: { Image(systemName: "forward.end.fill") }
                            .buttonStyle(GlassIconButtonStyle(size: 34, overlay: true))
                            .disabled(!controller.hasNext)
                            .help("Nächster Film (⌘→)")
                    }
                }

                Spacer(minLength: 8)

                // rechts: Optionen
                HStack(spacing: 8) {
                    speedMenu
                    tracksMenu
                    if !controller.chapters.isEmpty { chaptersMenu }
                    Button { controller.window?.toggleFullScreen(nil) } label: {
                        Image(systemName: controller.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(GlassIconButtonStyle(size: 30, overlay: true))
                    .help("Vollbild (F)")
                }
                .frame(width: 180, alignment: .trailing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 820)
        .glass(RoundedRectangle(cornerRadius: 26, style: .continuous), kind: .overlay, elevated: true)
    }

    private var remainingLabel: String {
        guard let d = controller.duration else { return "–:––" }
        return "−" + Fmt.clock(max(0, d - (controller.scrubbing ?? controller.time)))
    }

    private func menuLabel(_ systemImage: String, active: Bool = false) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(active ? p.accent : .white)
    }

    private var speedMenu: some View {
        Menu {
            ForEach(SeekMath.speeds, id: \.self) { s in
                Button {
                    controller.rate = s
                } label: {
                    if abs(controller.rate - s) < 0.01 { Label(SeekMath.speedLabel(s), systemImage: "checkmark") } else { Text(SeekMath.speedLabel(s)) }
                }
            }
        } label: {
            Text(SeekMath.speedLabel(controller.rate))
                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tint(abs(controller.rate - 1) > 0.01 ? p.accent : .white)
        .frame(width: 34, height: 30)
        .glass(Capsule(), kind: .overlay, interactive: true)
        .help("Geschwindigkeit ([ und ])")
    }

    private var tracksMenu: some View {
        Menu {
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
                    if controller.selectedSubtitle == nil && controller.activeExternalSubtitle == nil { Label("Aus", systemImage: "checkmark") } else { Text("Aus") }
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
                Button("Untertiteldatei laden …") { controller.loadSubtitleFile() }
            }
            Section("Warteschlange") {
                Button(controller.queue.shuffled ? "Zufall aus" : "Zufällige Reihenfolge") { controller.setShuffle(!controller.queue.shuffled) }
                Button(controller.queue.repeatMode.label + " – ändern") { controller.cycleRepeat() }
            }
        } label: {
            menuLabel("captions.bubble", active: controller.selectedSubtitle != nil || controller.activeExternalSubtitle != nil)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tint(controller.selectedSubtitle != nil || controller.activeExternalSubtitle != nil ? p.accent : .white)
        .frame(width: 30, height: 30)
        .glass(Circle(), kind: .overlay, interactive: true)
        .help("Ton, Untertitel und Warteschlange")
    }

    private var chaptersMenu: some View {
        Menu {
            ForEach(Array(controller.chapters.enumerated()), id: \.offset) { i, c in
                Button("\(i + 1). \(c.title) – \(Fmt.clock(c.start))") { controller.jump(toChapter: c) }
            }
        } label: {
            menuLabel("list.bullet.rectangle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tint(.white)
        .frame(width: 30, height: 30)
        .glass(Circle(), kind: .overlay, interactive: true)
        .help("Kapitel (, und .)")
    }

    // MARK: - Rückfragen

    private func resumeCard(_ at: Double) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "play.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(.white.opacity(0.9))
            Text("Weiterschauen?")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            Text("Du warst bei \(Fmt.clock(at))\(controller.duration.map { " von \(Fmt.clock($0))" } ?? "").")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
            HStack(spacing: 10) {
                Button("Von Anfang an") { controller.resume(false) }
                    .buttonStyle(CapsuleButtonStyle(role: .glass))
                Button("Fortsetzen") { controller.resume(true) }
                    .buttonStyle(CapsuleButtonStyle(role: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 28)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous), kind: .overlay, elevated: true)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(p.orange)
            Text("Wiedergabe nicht möglich")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Im Finder zeigen") { controller.revealInFinder() }
                    .buttonStyle(CapsuleButtonStyle(role: .glass))
                Button("Mit anderer App öffnen") { controller.openInDefaultApp() }
                    .buttonStyle(CapsuleButtonStyle(role: .glass))
                if controller.hasNext {
                    Button("Nächster Film") { controller.playNext() }
                        .buttonStyle(CapsuleButtonStyle(role: .primary))
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 28)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous), kind: .overlay, elevated: true)
    }
}

/// Zeitleiste mit Kapitelmarken und Vorschau-Zeit beim Ziehen
struct Scrubber: View {
    @ObservedObject var controller: PlayerController
    @State private var hoverX: CGFloat?
    @Environment(\.palette) private var p

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let d = controller.duration ?? 0
            let t = controller.scrubbing ?? controller.time
            let fraction = d > 0 ? CGFloat(min(1, max(0, t / d))) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18)).frame(height: hoverX != nil || controller.scrubbing != nil ? 7 : 5)
                // Verlauf Akzent → Rosa mit weichem Lichtschein (dezent, gut sichtbar)
                Capsule().fill(LinearGradient(colors: [p.accent, p.pink], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(5, w * fraction), height: hoverX != nil || controller.scrubbing != nil ? 7 : 5)
                    .safeShadow(color: p.accent.opacity(0.55), radius: hoverX != nil ? 8 : 4)
                ForEach(controller.chapters.filter { $0.start > 0.5 }, id: \.self) { c in
                    if d > 0 {
                        Rectangle().fill(Color.black.opacity(0.55)).frame(width: 2, height: 7)
                            .offset(x: w * CGFloat(c.start / d) - 1)
                    }
                }
                Circle().fill(Color.white).frame(width: 13, height: 13)
                    .safeShadow(color: .black.opacity(0.4), radius: 3)
                    .offset(x: w * fraction - 6.5)
                    .opacity(hoverX != nil || controller.scrubbing != nil ? 1 : 0)
                if let x = hoverX, d > 0 {
                    Text(Fmt.clock(Double(x / w) * d))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                        .offset(x: min(max(0, x - 22), w - 46), y: -20)
                }
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let pt): hoverX = min(max(0, pt.x), w)
                case .ended: hoverX = nil
                }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard d > 0 else { return }
                    controller.scrubbing = Double(min(max(0, g.location.x), w) / w) * d
                    controller.userActivity()
                }
                .onEnded { g in
                    guard d > 0 else { return }
                    let target = Double(min(max(0, g.location.x), w) / w) * d
                    controller.scrubbing = nil
                    controller.seek(to: target)
                })
            .animation(.easeOut(duration: 0.12), value: hoverX != nil)
        }
    }
}

/// Kleiner Schieberegler (Lautstärke)
struct MiniSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2)).frame(height: 4)
                Capsule().fill(Color.white.opacity(0.9)).frame(width: max(4, w * CGFloat(value)), height: 4)
                Circle().fill(Color.white).frame(width: 11, height: 11).offset(x: w * CGFloat(value) - 5.5)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                value = Double(min(max(0, g.location.x), w) / w)
            })
        }
        .help("Lautstärke (↑ und ↓)")
    }
}
