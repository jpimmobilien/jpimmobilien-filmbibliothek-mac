import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FBCore
import FBServices

/// Abstände der schwebenden Leisten (Inhalte beginnen darunter und laufen weich darunter aus).
enum Chrome {
    static let topPadding: CGFloat = 10
    /// Oberkante der Inhalte unter der Navigation
    static let contentTop: CGFloat = topPadding + NavBar.height + 16
    /// Höhe des Mini-Players
    static let miniPlayerHeight: CGFloat = 164
    static func contentBottom(miniPlayer: Bool) -> CGFloat { miniPlayer ? miniPlayerHeight + 36 : 28 }
}

/// Hauptfenster (Aufbau wie die Musikbibliothek): Hintergrund in der Farbe des aktuellen Films, schwebende
/// Glas-Navigation oben, Inhalt darunter, Mini-Player-Kapsel unten, solange ein Film läuft.
struct MainView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.palette) private var p
    /// Start: Inhalt blendet einmal weich ein (kein Dauereffekt)
    @State private var launched = false

    var body: some View {
        GeometryReader { geo in
            let showMini = model.playerController != nil
            ZStack(alignment: .top) {
                AmbientBackground(accentGlow: model.ambientTint)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, Chrome.contentTop)
                    .opacity(launched ? 1 : 0)
                    .onAppear { withAnimation(.easeOut(duration: 0.5).delay(0.05)) { launched = true } }
                    .environment(\.contentBottomInset, Chrome.contentBottom(miniPlayer: showMini))

                // Inhalte laufen weich unter die Navigation
                EdgeFade(top: true)
                    .frame(height: Chrome.contentTop + 4)
                    .allowsHitTesting(false)
                NavBar(availableWidth: geo.size.width)
                    .padding(.top, Chrome.topPadding)
                ScanBanner()
                    .padding(.top, Chrome.contentTop - 8)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    EdgeFade(top: false)
                        .frame(height: showMini ? Chrome.miniPlayerHeight + 50 : 30)
                        .allowsHitTesting(false)
                }
                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    if let c = model.playerController {
                        MiniPlayerBar(controller: c, width: min(1040, geo.size.width - 36))
                            .frame(maxWidth: 1040)
                            .padding(.horizontal, 18)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 14)
                .animation(Motion.detailCurve, value: showMini)
                if model.dropTargeted { dropOverlay }
            }
            // Bis an die Fensteroberkante (die Fensterknöpfe liegen frei links oben)
            .ignoresSafeArea(.container, edges: .top)
        }
        .overlay(alignment: .bottom) { toastView }
        .background(WindowConfigurator())
        .background(SettingsActionBridge())
        .onDrop(of: [UTType.fileURL], isTargeted: $model.dropTargeted) { providers in
            handleDrop(providers)
        }
        .alert(item: $model.alert) { a in
            Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog(removalTitle, isPresented: Binding(get: { model.locationPendingRemoval != nil },
                                                                set: { if !$0 { model.locationPendingRemoval = nil } }),
                            titleVisibility: .visible) {
            Button("Aus der Bibliothek entfernen", role: .destructive) {
                if let loc = model.locationPendingRemoval { model.removeLocation(loc) }
                model.locationPendingRemoval = nil
            }
            Button("Abbrechen", role: .cancel) { model.locationPendingRemoval = nil }
        } message: {
            Text("Die Einträge, Titelbilder, Favoriten und der Fortschritt der Filme dieses Speicherorts werden aus der Bibliothek entfernt. Die Videodateien selbst bleiben unverändert.")
        }
        .confirmationDialog("Fehlende Einträge entfernen?", isPresented: Binding(get: { model.removeMissingRequest != nil },
                                                                                set: { if !$0 { model.removeMissingRequest = nil } }),
                            titleVisibility: .visible) {
            Button("\(model.removeMissingRequest?.count ?? 0) Einträge entfernen", role: .destructive) {
                if let r = model.removeMissingRequest { model.removeMissing(locationId: r.locationId) }
                model.removeMissingRequest = nil
            }
            Button("Abbrechen", role: .cancel) { model.removeMissingRequest = nil }
        } message: {
            Text("Nur Einträge, deren Datei auf einem erreichbaren Speicherort nicht mehr gefunden wurde. Filme auf nicht angeschlossenen Laufwerken bleiben immer erhalten.")
        }
        .sheet(item: $model.collectionNamePrompt) { prompt in
            CollectionNameSheet(prompt: prompt)
                .environmentObject(model)
                .filmTheme()
        }
        .sheet(isPresented: Binding(get: { model.startupError != nil }, set: { if !$0 { model.startupError = nil } })) {
            StartupErrorSheet(message: model.startupError ?? "")
                .filmTheme()
        }
        .task { await model.bootstrap() }
    }

    private var removalTitle: String {
        "„\(model.locationPendingRemoval?.name ?? "")“ aus der Bibliothek entfernen?"
    }

    @ViewBuilder
    private var content: some View {
        switch model.route {
        case .overview:
            OverviewView()
        case .collections:
            CollectionsView()
        case .library(let scope):
            LibraryView(scope: scope)
        case .locations:
            LocationsView()
        case .detail(let id):
            if let film = model.film(id) {
                FilmDetailView(film: film)
            } else {
                EmptyStateView(systemImage: "film", title: "Film nicht gefunden", message: "Dieser Eintrag existiert nicht mehr.") {
                    Button("Zurück") { model.goBack() }.buttonStyle(CapsuleButtonStyle(role: .glass))
                }
            }
        }
    }

    private var dropOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.rectangle.on.folder")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(p.accent)
            Text("Ordner oder Laufwerk loslassen")
                .font(.system(size: 20, weight: .bold))
            Text("Er wird als Speicherort hinzugefügt und durchsucht. Es wird nichts kopiert oder verändert.")
                .font(Typo.body)
                .foregroundColor(p.textSecondary)
        }
        .padding(40)
        .glassCard(cornerRadius: 28, elevated: true)
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(p.dark ? 0.35 : 0.12))
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var toastView: some View {
        if let t = model.toast {
            HStack(spacing: 10) {
                Image(systemName: t.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color(for: t.tone))
                Text(t.text)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(p.textPrimary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .glassCapsule(kind: .card, interactive: false)
            .safeShadow(color: p.shadow, radius: 16, y: 6)
            .padding(.bottom, model.playerController != nil ? Chrome.miniPlayerHeight + 34 : 22)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onTapGesture { model.toast = nil }
        }
    }

    private func color(for tone: Toast.Tone) -> Color {
        switch tone {
        case .info: return p.accent
        case .success: return p.green
        case .warning: return p.orange
        case .error: return p.red
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let collected = urls
            Task { @MainActor in model.addLocations(collected) }
        }
        return !providers.isEmpty
    }
}

/// Fenster-Feinheiten, die SwiftUI unter macOS 13 nicht anbietet (verschiebbar über den Hintergrund, Mindestgröße).
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isMovableByWindowBackground = true
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.minSize = NSSize(width: 720, height: 560)
            w.setFrameAutosaveName("Hauptfenster")
            w.tabbingMode = .disallowed
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct StartupErrorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                IconBadge(systemImage: "exclamationmark.triangle.fill", color: p.orange, size: 18)
                Text("Bibliothek nicht geöffnet").font(.system(size: 18, weight: .bold))
            }
            Text(message).font(Typo.body).foregroundColor(p.textSecondary).textSelection(.enabled)
            HStack {
                Spacer()
                Button("Verstanden") { dismiss() }.buttonStyle(CapsuleButtonStyle(role: .primary)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 480)
        .background(AmbientBackground())
    }
}

struct CollectionNameSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p
    let prompt: AppModel.CollectionPrompt
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prompt.renaming == nil ? "Neue Sammlung" : "Sammlung umbenennen")
                .font(.system(size: 18, weight: .bold))
            if !prompt.addFilms.isEmpty {
                Text(Fmt.count(prompt.addFilms.count, "Film wird", "Filme werden") + " hinzugefügt.")
                    .font(Typo.body).foregroundColor(p.textSecondary)
            }
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .glassCapsule(interactive: false)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }.buttonStyle(CapsuleButtonStyle(role: .glass)).keyboardShortcut(.cancelAction)
                Button(prompt.renaming == nil ? "Anlegen" : "Umbenennen", action: save)
                    .buttonStyle(CapsuleButtonStyle(role: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(26)
        .frame(width: 420)
        .background(AmbientBackground())
        .onAppear { name = prompt.renaming?.name ?? "" }
    }

    private func save() {
        if let c = prompt.renaming {
            model.rename(c, to: name)
        } else {
            model.createCollection(named: name, adding: prompt.addFilms)
        }
        dismiss()
    }
}
