import SwiftUI
import AppKit
import FBCore
import FBStore
import FBServices

/// Einstellungsfenster (⌘,) im selben Glas-Stil: links Bereiche, rechts Karten.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.palette) private var p
    @State private var section: Pane = .appearance

    enum Pane: String, CaseIterable, Identifiable {
        case appearance, library, locations, scanning, playback, shortcuts, privacy, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .appearance: return "Darstellung"
            case .library: return "Bibliothek"
            case .locations: return "Speicherorte"
            case .scanning: return "Durchsuchen"
            case .playback: return "Wiedergabe"
            case .shortcuts: return "Tastaturkurzbefehle"
            case .privacy: return "Datenschutz"
            case .about: return "Über"
            }
        }
        var symbol: String {
            switch self {
            case .appearance: return "paintbrush"
            case .library: return "film.stack"
            case .locations: return "externaldrive"
            case .scanning: return "magnifyingglass"
            case .playback: return "play.rectangle"
            case .shortcuts: return "keyboard"
            case .privacy: return "lock.shield"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Color.clear.frame(height: 30)
                    ForEach(Pane.allCases) { s in
                        SidebarRow(title: s.title, systemImage: s.symbol, color: p.textSecondary, selected: section == s) { section = s }
                    }
                    Spacer()
                }
                .padding(8)
                .frame(width: 210)
                .glass(RoundedRectangle(cornerRadius: 18, style: .continuous), kind: .panel)
                .padding(10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        PageHeader(title: section.title, subtitle: subtitle)
                        content
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 22)
                    .padding(.bottom, 30)
                }
            }
        }
        .toggleStyle(.switch)
        .frame(minWidth: 820, idealWidth: 860, minHeight: 600, idealHeight: 640)
    }

    private var subtitle: String {
        switch section {
        case .appearance: return "Erscheinungsbild, Ansicht und Kacheln"
        case .library: return "Titel, Favoriten und Titelbilder"
        case .locations: return "Hinzugefügte Ordner und Laufwerke"
        case .scanning: return "Wann nach neuen Filmen gesucht wird"
        case .playback: return "Player, Fortsetzen, Untertitel"
        case .shortcuts: return "Bedienung mit der Tastatur"
        case .privacy: return "Was gespeichert wird – und was nicht"
        case .about: return "Version, Technik und Lizenzen"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .appearance: appearance
        case .library: library
        case .locations: locations
        case .scanning: scanning
        case .playback: playback
        case .shortcuts: shortcuts
        case .privacy: privacy
        case .about: AboutPanel()
        }
    }

    // MARK: - Bereiche

    private var appearance: some View {
        VStack(spacing: 16) {
            GlassCard(title: "Erscheinungsbild", systemImage: "circle.lefthalf.filled", iconColor: p.accent) {
                SegmentedChoice(options: AppSettings.Appearance.allCases, selection: $settings.appearance) { $0.label }
                Text("„Wie System“ folgt der Einstellung von macOS (Hell/Dunkel/Automatisch). Der Player ist immer dunkel.")
                    .font(Typo.caption).foregroundColor(p.textSecondary)
            }
            GlassCard(title: "Standardansicht", systemImage: "square.grid.2x2", iconColor: p.violet) {
                SegmentedChoice(options: AppSettings.ViewMode.allCases, selection: $settings.viewMode) { $0.label }
                SegmentedChoice(options: AppSettings.TileShape.allCases, selection: $settings.tileShape) { $0.label }
                Toggle("Dateiformat auf den Kacheln zeigen", isOn: $settings.showFormatBadges)
                Toggle("Beim Start die Übersicht zeigen", isOn: $settings.showOverviewOnLaunch)
            }
            GlassCard(title: "Bewegung und Effekte", systemImage: "sparkles", iconColor: p.pink) {
                Toggle("Leichte Effekte (ohne Neigung, Lichtreflexe und gestaffeltes Einblenden)", isOn: $settings.lightEffects)
                Text(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                     ? "„Bewegung reduzieren“ ist in den Bedienungshilfen von macOS eingeschaltet – die App verzichtet deshalb auf Neigung, Morphing und Hintergrundbewegung."
                     : "Auf Intel-Macs mit integrierter Grafik ist „Leicht“ voreingestellt. „Bewegung reduzieren“ in den Bedienungshilfen von macOS wird immer beachtet.")
                    .font(Typo.caption).foregroundColor(p.textSecondary)
            }
            GlassCard(title: "Liquid Glass", systemImage: "drop", iconColor: p.teal) {
                InfoRow(label: "Darstellung", value: LiquidGlass.modeDescription)
                Text(LiquidGlass.isAvailable
                     ? "Diese Glasflächen nutzen das Liquid Glass von macOS 26."
                     : "Liquid Glass gibt es ab macOS 26. Auf diesem System wird es mit den Glasmaterialien von macOS nachgebildet (gleicher Aufbau). „Transparenz reduzieren“ in den Bedienungshilfen wird beachtet.")
                    .font(Typo.caption).foregroundColor(p.textSecondary)
            }
        }
    }

    private var library: some View {
        VStack(spacing: 16) {
            GlassCard(title: "Titel", systemImage: "textformat", iconColor: p.accent) {
                SegmentedChoice(options: AppSettings.TitleSource.allCases, selection: $settings.titleSource) { $0.label }
                Text("Bereinigt: „Alien.1979.1080p.BluRay.x264.mkv“ wird zu „Alien“ (1979). Gesucht wird immer im vollständigen Dateinamen.")
                    .font(Typo.caption).foregroundColor(p.textSecondary)
            }
            GlassCard(title: "Favoriten aus dem Dateinamen", systemImage: "heart", iconColor: p.heart) {
                Toggle("Endet der Name auf „Heart“ (z. B. „Film_Heart.mp4“), als Favorit übernehmen", isOn: $settings.heartFavorites)
                Text("Gilt für Filme, die ab jetzt gefunden werden (wie in der Android-App). Dateinamen werden nie verändert.")
                    .font(Typo.caption).foregroundColor(p.textSecondary)
            }
            GlassCard(title: "Titelbilder", systemImage: "photo", iconColor: p.orange) {
                SegmentedChoice(options: MetadataService.CoverPreference.allCases, selection: $settings.coverPreference) { $0.label }
                Toggle("Zuletzt gesehenes Bild als Titelbild (nur ohne Poster/eingebettetes Cover)", isOn: $settings.lastFrameAsCover)
                Text("Poster werden im Ordner des Films gesucht: „Film.jpg“, „Film-poster.jpg“ sowie „poster.jpg“/„folder.jpg“/„cover.jpg“, wenn der Ordner nur einen Film enthält. Titelbilder liegen als verkleinerte Kopie im Cache der App – neben den Filmen wird nie etwas gespeichert.")
                    .font(Typo.caption).foregroundColor(p.textSecondary)
            }
            GlassCard(title: "Online-Metadaten", systemImage: "network.slash", iconColor: p.textSecondary) {
                Text("Nicht enthalten. Die Filmbibliothek arbeitet vollständig offline und hat keine Netzwerkberechtigung. Kostenlose Filmdatenbanken (z. B. TMDb) verlangen einen persönlichen API-Schlüssel – eine optionale Anbindung wäre eine spätere Erweiterung.")
                    .font(Typo.caption).foregroundColor(p.textSecondary)
            }
        }
    }

    private var locations: some View {
        VStack(spacing: 16) {
            ForEach(model.locations) { loc in LocationCard(location: loc, compact: true) }
            HStack {
                Button { model.showAddLocationPanel() } label: { Label("Speicherort hinzufügen", systemImage: "plus") }
                    .buttonStyle(CapsuleButtonStyle(role: .primary))
                Button("Im Hauptfenster verwalten") {
                    model.navigate(.locations)
                    NSApp.windows.first { $0.identifier?.rawValue.contains("main") == true || $0.title == "Filmbibliothek" }?.makeKeyAndOrderFront(nil)
                }
                .buttonStyle(CapsuleButtonStyle(role: .glass))
                Spacer()
            }
        }
    }

    private var scanning: some View {
        VStack(spacing: 16) {
            GlassCard(title: "Automatisch durchsuchen", systemImage: "arrow.clockwise", iconColor: p.accent) {
                Toggle("Beim Start nach neuen und geänderten Filmen suchen", isOn: $settings.scanOnLaunch)
                Toggle("Wenn ein Laufwerk angeschlossen wird", isOn: $settings.scanOnMount)
                Text("Intelligenter Index: Beim Durchsuchen werden nur Verzeichniseinträge gelesen. Technische Angaben und Titelbilder werden nur für neue oder geänderte Dateien (Größe/Änderungsdatum) neu ermittelt.")
                    .font(Typo.caption).foregroundColor(p.textSecondary)
            }
            GlassCard(title: "Erkannte Formate", systemImage: "film", iconColor: p.violet) {
                FlowLayout(spacing: 6) {
                    ForEach(VideoFormats.all, id: \.ext) { f in Chip(text: f.ext.uppercased()) }
                }
                Text("Übersprungen werden versteckte Dateien, macOS-Begleitdateien („._Name“), Papierkörbe, Systemordner, NAS-Hilfsordner (@eaDir, #recycle) und Pakete wie die Fotos-Mediathek.")
                    .font(Typo.caption).foregroundColor(p.textSecondary)
            }
            HStack {
                Button("Jetzt alle durchsuchen") { model.scanAll() }.buttonStyle(CapsuleButtonStyle(role: .primary))
                Spacer()
            }
        }
    }

    private var playback: some View {
        VStack(spacing: 16) {
            GlassCard(title: "Weiterschauen", systemImage: "play.circle", iconColor: p.teal) {
                SegmentedChoice(options: AppSettings.ResumeBehavior.allCases, selection: $settings.resumeBehavior) { $0.label }
                Text("Positionen ab 10 Sekunden werden gespeichert; die letzten 15 Sekunden bzw. 3 % gelten als „gesehen“.")
                    .font(Typo.caption).foregroundColor(p.textSecondary)
                Toggle("Nächsten Film automatisch abspielen", isOn: $settings.autoplayNext)
                Toggle("Im Vollbild starten", isOn: $settings.startFullScreen)
            }
            GlassCard(title: "Bedienung", systemImage: "slider.horizontal.3", iconColor: p.accent) {
                HStack {
                    Text("Sprungweite (← →)").font(Typo.body)
                    Spacer()
                    SegmentedChoice(options: [5.0, 10.0, 15.0, 30.0, 60.0], selection: $settings.seekStep) { "\(Int($0)) s" }
                        .frame(maxWidth: 320)
                }
                HStack {
                    Text("Steuerung ausblenden nach").font(Typo.body)
                    Spacer()
                    SegmentedChoice(options: [2.0, 3.0, 5.0, 8.0], selection: $settings.controlsHideDelay) { "\(Int($0)) s" }
                        .frame(maxWidth: 260)
                }
                Toggle("Untertitel standardmäßig einschalten (externe Datei, falls vorhanden)", isOn: $settings.subtitlesOnByDefault)
            }
            GlassCard(title: "Wiedergabe-Engines", systemImage: "cpu", iconColor: p.green) {
                InfoRow(label: "MP4, M4V, MOV", value: "AVFoundation (macOS)")
                InfoRow(label: "MKV, AVI, WMV, MPG, TS, MTS, M2TS, WEBM, FLV", value: VLCSupport.isAvailable ? "VLCKit \(VLCSupport.versionString)" : "nicht enthalten")
                Text("Welche Engine eine Datei nutzt, wird beim Analysieren durch echtes Öffnen geprüft. Scheitert AVFoundation, versucht der Player automatisch VLCKit.")
                    .font(Typo.caption).foregroundColor(p.textSecondary)
            }
        }
    }

    private var shortcuts: some View {
        VStack(spacing: 16) {
            GlassCard(title: "Bibliothek", systemImage: "film.stack", iconColor: p.accent) {
                shortcut("Speicherort hinzufügen", "⌘O")
                shortcut("Alle Speicherorte durchsuchen", "⌘R")
                shortcut("Suchen", "⌘F")
                shortcut("Abspielen (Auswahl)", "↩")
                shortcut("Informationen", "⌘I")
                shortcut("Favorit an/aus", "⌘L")
                shortcut("Im Finder zeigen", "⇧⌘R")
                shortcut("Große Poster / Kompakt / Liste", "⌘1 / ⌘2 / ⌘3")
                shortcut("Übersicht / Alle Filme", "⇧⌘1 / ⇧⌘2")
                shortcut("Seitenleiste ein/aus", "⌃⌘S")
                shortcut("Zurück", "⌘[")
            }
            GlassCard(title: "Player", systemImage: "play.rectangle", iconColor: p.teal) {
                shortcut("Wiedergabe/Pause", "Leertaste oder K")
                shortcut("Zurück/Vor (Sprungweite)", "← → oder J L")
                shortcut("60 Sekunden zurück/vor", "⇧← ⇧→")
                shortcut("Vorheriger/Nächster Film", "⌘← ⌘→ oder P N")
                shortcut("Lautstärke", "↑ ↓")
                shortcut("Ton aus/an", "M")
                shortcut("Vollbild", "F, Doppelklick oder ⌃⌘F")
                shortcut("Untertitel an/aus", "C")
                shortcut("Geschwindigkeit", "[ ]")
                shortcut("Kapitel zurück/vor", ", .")
                shortcut("An den Anfang", "0")
                shortcut("Vollbild beenden", "Esc")
            }
        }
    }

    private func shortcut(_ label: String, _ keys: String) -> some View {
        InfoRow(label: label, value: keys, monospaced: false)
    }

    private var privacy: some View {
        VStack(spacing: 16) {
            GlassCard(title: "Grundsätze", systemImage: "checkmark.shield", iconColor: p.green) {
                InfoRow(label: "Konto, Cloud, Server", value: "keine")
                InfoRow(label: "Netzwerkzugriff", value: "keiner (keine Berechtigung)")
                InfoRow(label: "Telemetrie, Analyse, Werbung", value: "keine")
                InfoRow(label: "Zugriff auf Dateien", value: "nur gewählte Ordner, nur lesen")
                InfoRow(label: "Festplattenvollzugriff", value: "nicht nötig")
            }
            GlassCard(title: "Gespeicherte Daten", systemImage: "internaldrive", iconColor: p.accent) {
                InfoRow(label: "Bibliothek (SQLite)", value: model.paths.database.path, monospaced: true)
                InfoRow(label: "Titelbilder (Cache)", value: model.paths.covers.path, monospaced: true)
                HStack(spacing: 8) {
                    Button("Wiedergabeverlauf aller Filme löschen") { model.clearPlayback(model.films.map(\.id)) }
                        .buttonStyle(CapsuleButtonStyle(role: .destructive, compact: true))
                    Button("Ordner im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([model.paths.database]) }
                        .buttonStyle(CapsuleButtonStyle(role: .glass, compact: true))
                    Spacer()
                }
            }
            GlassCard(title: "Einstellungen", systemImage: "arrow.counterclockwise", iconColor: p.orange) {
                HStack {
                    Text("Alle Einstellungen auf Standard zurücksetzen (Bibliothek und Speicherorte bleiben).").font(Typo.caption).foregroundColor(p.textSecondary)
                    Spacer()
                    Button("Zurücksetzen") { settings.resetToDefaults() }.buttonStyle(CapsuleButtonStyle(role: .glass, compact: true))
                }
            }
        }
    }
}

/// Auswahl als Glas-Segmentleiste
struct SegmentedChoice<T: Hashable>: View {
    @Environment(\.palette) private var p
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                Button { selection = o } label: {
                    Text(label(o))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(selection == o ? p.textPrimary : p.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(selection == o ? p.accentSoft : .clear))
                        .overlay(Capsule().strokeBorder(selection == o ? p.accent.opacity(0.35) : .clear, lineWidth: 0.6))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(p.control))
        .overlay(Capsule().strokeBorder(p.hairline, lineWidth: 0.6))
    }
}

/// „Über“: Version, Architektur, Technik, Lizenzen
struct AboutPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @State private var licenseText: String?

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 16) {
            GlassCard(title: "Filmbibliothek für macOS", systemImage: "film", iconColor: p.accent) {
                InfoRow(label: "Version", value: version)
                InfoRow(label: "Läuft als", value: QA.architecture + (QA.isTranslated ? " (über Rosetta)" : " (nativ)"))
                InfoRow(label: "Enthaltene Architekturen", value: "Apple Silicon (arm64) und Intel (x86_64)")
                InfoRow(label: "macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                InfoRow(label: "Glas", value: LiquidGlass.modeDescription)
                InfoRow(label: "App-Sandbox", value: QA.isSandboxed ? "aktiv" : "nicht aktiv")
            }
            GlassCard(title: "Technik", systemImage: "cpu", iconColor: p.teal) {
                InfoRow(label: "Oberfläche", value: "SwiftUI + AppKit")
                InfoRow(label: "Wiedergabe", value: "AVFoundation · VLCKit \(VLCSupport.isAvailable ? VLCSupport.versionString : "(nicht enthalten)")")
                InfoRow(label: "Datenbank", value: "SQLite (macOS)")
            }
            GlassCard(title: "Lizenzen", systemImage: "doc.text", iconColor: p.violet) {
                Text("VLCKit/libVLC stehen unter der GNU Lesser General Public License 2.1 (dynamisch eingebundenes Framework; Quelltext: code.videolan.org/videolan/VLCKit). Die Lizenztexte liegen in der App unter Contents/Resources/Licenses.")
                    .font(Typo.caption).foregroundColor(p.textSecondary)
                HStack {
                    Button("Lizenztexte anzeigen") { loadLicenses() }.buttonStyle(CapsuleButtonStyle(role: .glass, compact: true))
                    Spacer()
                }
                if let licenseText {
                    ScrollView {
                        Text(licenseText).font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 220)
                }
            }
        }
    }

    private func loadLicenses() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Licenses"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            licenseText = "Keine Lizenzdateien im App-Paket gefunden."
            return
        }
        licenseText = files.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { u in
            (try? String(contentsOf: u, encoding: .utf8)).map { "=== \(u.lastPathComponent) ===\n\n\($0)" }
        }.joined(separator: "\n\n")
    }
}
