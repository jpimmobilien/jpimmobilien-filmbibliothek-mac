import SwiftUI
import AppKit
import FBCore
import FBServices

/// Bibliotheksansicht: Kopf mit großem Titel und Glas-Werkzeugleiste, Filter-Chips, Raster bzw. Liste.
struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.palette) private var p
    let scope: LibraryScope
    @FocusState private var searchFocused: Bool
    @State private var showFilters = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 30)
                .padding(.top, 26)
                .padding(.bottom, 12)
            if !model.filter.isEmpty || !model.searchText.isEmpty || folderPath != nil {
                chipsRow
                    .padding(.horizontal, 30)
                    .padding(.bottom, 10)
            }
            if let banner = locationBanner {
                banner.padding(.horizontal, 30).padding(.bottom, 12)
            }
            contentArea
        }
        .background(KeyboardShortcutsForLibrary(searchFocused: $searchFocused))
    }

    // MARK: - Kopf

    private var title: String {
        switch scope {
        case .all: return "Alle Filme"
        case .continueWatching: return "Weiterschauen"
        case .recentlyAdded: return "Zuletzt hinzugefügt"
        case .recentlyPlayed: return "Zuletzt abgespielt"
        case .favorites: return "Favoriten"
        case .unavailable: return "Nicht verfügbar"
        case .collection(let id): return model.collections.first { $0.id == id }?.name ?? "Sammlung"
        case .location(let id), .folder(let id, _): return model.locationName(id)
        }
    }

    private var subtitle: String {
        let list = model.visibleFilms
        var parts = [Fmt.count(list.count, "Film", "Filme")]
        let bytes = list.reduce(Int64(0)) { $0 + $1.sizeBytes }
        if bytes > 0 { parts.append(Fmt.bytes(bytes)) }
        let runtime = list.reduce(0.0) { $0 + ($1.info.durationSeconds ?? 0) }
        if runtime > 0 { parts.append(Fmt.runtime(runtime)) }
        switch scope {
        case .location(let id), .folder(let id, _):
            parts.append(model.availabilityOf(location: id).label)
        case .recentlyAdded:
            parts.append("letzte \(LibraryScope.recentlyAddedDays) Tage")
        default: break
        }
        return parts.joined(separator: " · ")
    }

    private var folderPath: String? {
        if case .folder(_, let path) = scope, !path.isEmpty { return path }
        return nil
    }

    private var header: some View {
        PageHeader(title: title, subtitle: subtitle) {
            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    GlassSearchField(text: $model.searchText, prompt: "Titel, Datei, Ordner, Codec …", focus: $searchFocused)
                        .frame(width: 250)
                    viewModePicker
                    sortMenu
                    filterButton
                    Button { model.showAddLocationPanel() } label: { Image(systemName: "plus") }
                        .buttonStyle(GlassIconButtonStyle(size: 32))
                        .help("Speicherort hinzufügen (⌘O)")
                }
            }
        }
    }

    private var viewModePicker: some View {
        HStack(spacing: 2) {
            ForEach(AppSettings.ViewMode.allCases) { mode in
                Button { settings.viewMode = mode } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(settings.viewMode == mode ? p.textPrimary : p.textSecondary)
                        .frame(width: 30, height: 26)
                        .background(Capsule().fill(settings.viewMode == mode ? p.controlHover : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(mode.label)
            }
        }
        .padding(3)
        .glassCapsule()
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortKey.allCases, id: \.self) { key in
                Button {
                    if settings.sortKey == key { settings.sortAscending.toggle() } else { settings.sortKey = key; settings.sortAscending = key.defaultAscending }
                    model.scheduleRecompute()
                } label: {
                    if settings.sortKey == key {
                        Label(key.label, systemImage: settings.sortAscending ? "chevron.up" : "chevron.down")
                    } else {
                        Text(key.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 11, weight: .semibold))
                Text(scope.impliedSort == nil ? settings.sortKey.label : "Automatisch").font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundColor(p.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .glassCapsule()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(scope.impliedSort != nil)
        .help(scope.impliedSort == nil ? "Sortierung" : "Dieser Bereich ist nach Datum sortiert")
    }

    private var filterButton: some View {
        Button { showFilters.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 11, weight: .semibold))
                Text("Filter").font(.system(size: 12.5, weight: .semibold))
                if model.filter.activeCount > 0 {
                    Text("\(model.filter.activeCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(p.onAccent)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Circle().fill(p.accent))
                }
            }
            .foregroundColor(p.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .glassCapsule(tint: model.filter.activeCount > 0 ? p.accentSoft : nil)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showFilters, arrowEdge: .bottom) {
            FilterPanel().environmentObject(model).filmTheme()
        }
        .help("Filtern nach Speicherort, Format, Auflösung, Größe, Laufzeit, Status")
    }

    // MARK: - Chips

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let folderPath, case .folder(let loc, _) = scope {
                    Button { model.navigate(.library(.location(loc))) } label: {
                        Chip(text: model.locationName(loc), systemImage: "externaldrive")
                    }.buttonStyle(.plain)
                    ForEach(Array(RelativePath.components(folderPath).enumerated()), id: \.offset) { i, part in
                        let sub = RelativePath.components(folderPath).prefix(i + 1).joined(separator: "/")
                        Button { model.navigate(.library(.folder(location: loc, path: sub))) } label: {
                            Chip(text: part, systemImage: "folder")
                        }.buttonStyle(.plain)
                    }
                }
                if !model.searchText.isEmpty {
                    Chip(text: "Suche: \(model.searchText)", dot: p.accent) { model.searchText = "" }
                }
                FilterChips()
                if !model.filter.isEmpty {
                    Button("Alle Filter entfernen") { model.filter = LibraryFilter() }
                        .buttonStyle(CapsuleButtonStyle(role: .plain, compact: true))
                }
            }
        }
    }

    // MARK: - Hinweis bei nicht verfügbarem Speicherort

    private var locationBanner: AnyView? {
        let id: Int64
        switch scope {
        case .location(let l), .folder(let l, _): id = l
        default: return nil
        }
        guard let loc = model.location(id) else { return nil }
        let status = model.availabilityOf(location: id)
        guard !status.isAvailable, status != .unknown else { return nil }
        return AnyView(LocationStatusBanner(location: loc, status: status))
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var contentArea: some View {
        if model.locations.isEmpty {
            WelcomeEmptyState()
        } else if model.visibleFilms.isEmpty {
            emptyForScope
        } else {
            switch settings.viewMode {
            case .largeGrid: FilmGridView(films: model.visibleFilms, compact: false)
            case .compactGrid: FilmGridView(films: model.visibleFilms, compact: true)
            case .list: FilmListView(films: model.visibleFilms)
            }
        }
    }

    @ViewBuilder
    private var emptyForScope: some View {
        if !model.searchText.isEmpty || !model.filter.isEmpty {
            EmptyStateView(systemImage: "magnifyingglass", title: "Keine Treffer",
                           message: "Kein Film passt zu Suche und Filtern. Mehrere Wörter müssen alle vorkommen; „-wort“ schließt aus.") {
                Button("Suche und Filter zurücksetzen") { model.searchText = ""; model.filter = LibraryFilter() }
                    .buttonStyle(CapsuleButtonStyle(role: .glass))
            }
        } else if model.isScanning {
            EmptyStateView(systemImage: "magnifyingglass", title: "Wird durchsucht …", message: "Gefundene Filme erscheinen hier, sobald der Durchlauf abgeschlossen ist.") { EmptyView() }
        } else {
            switch scope {
            case .continueWatching:
                EmptyStateView(systemImage: "play.circle", title: "Nichts angefangen", message: "Filme, die du nicht zu Ende gesehen hast, erscheinen hier mit ihrer Position.") { EmptyView() }
            case .favorites:
                EmptyStateView(systemImage: "heart", title: "Noch keine Favoriten", message: "Markiere Filme mit dem Herz (⌘L) – sie erscheinen dann hier.") { EmptyView() }
            case .collection:
                EmptyStateView(systemImage: "rectangle.stack", title: "Sammlung ist leer", message: "Füge Filme über das Kontextmenü „Zur Sammlung hinzufügen“ hinzu.") { EmptyView() }
            case .recentlyPlayed:
                EmptyStateView(systemImage: "clock", title: "Noch nichts abgespielt", message: "Hier erscheinen die zuletzt gesehenen Filme.") { EmptyView() }
            default:
                EmptyStateView(systemImage: "film", title: "Keine Filme", message: "In diesem Bereich wurden keine Videos gefunden.") {
                    Button("Jetzt durchsuchen") { model.scanAll() }.buttonStyle(CapsuleButtonStyle(role: .glass))
                }
            }
        }
    }
}

/// Willkommens-Zustand (noch kein Speicherort) – große Typografie wie auf der Apple-Produktseite
struct WelcomeEmptyState: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("Deine Filme.\nAlle an einem Ort.")
                .font(.system(size: 46, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(LinearGradient(colors: [p.textPrimary, p.textPrimary.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            Text("Füge Ordner, externe SSDs, USB-Sticks, SD-Karten oder Netzlaufwerke hinzu. Die Filmbibliothek findet alle Videos, merkt sich Laufwerke auch nach dem Abziehen und verändert nie eine Datei.")
                .font(.system(size: 15))
                .foregroundColor(p.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            HStack(spacing: 12) {
                Button { model.showAddLocationPanel() } label: { Label("Speicherort hinzufügen", systemImage: "plus") }
                    .buttonStyle(CapsuleButtonStyle(role: .primary))
            }
            .padding(.top, 6)
            Text("oder einen Ordner bzw. ein Laufwerk aus dem Finder hierher ziehen")
                .font(Typo.caption)
                .foregroundColor(p.textTertiary)
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Hinweis-Banner für nicht erreichbare Speicherorte (Vorlage: „Wenig freier Speicher …“ mit „Warum?“)
struct LocationStatusBanner: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    let location: StorageLocation
    let status: LocationAvailability

    var body: some View {
        HStack(spacing: 14) {
            StatusDot(color: status == .offline ? p.textTertiary : p.orange, size: 10)
                .padding(10)
                .background(Circle().fill(p.control))
            VStack(alignment: .leading, spacing: 4) {
                Text(headline).font(.system(size: 15, weight: .semibold))
                Text(detail).font(Typo.caption).foregroundColor(p.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            actions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCard()
    }

    private var headline: String {
        switch status {
        case .offline: return location.kind == .network ? "Netzlaufwerk nicht verbunden" : "Laufwerk nicht angeschlossen"
        case .noAccess: return "Kein Zugriff"
        case .folderMissing: return "Ordner nicht gefunden"
        default: return status.label
        }
    }

    private var detail: String {
        switch status {
        case .offline:
            return "„\(location.volumeName.isEmpty ? location.name : location.volumeName)“ – Filme, Titelbilder und Fortschritt bleiben erhalten. Nach dem Anschließen wird das Laufwerk an seiner Kennung erkannt, auch unter anderem Namen."
        case .noAccess(let m):
            return "macOS erlaubt den Zugriff auf diesen Ordner derzeit nicht (\(m)). Mit „Zugriff erteilen“ den Ordner einmal bestätigen."
        case .folderMissing:
            return "Das Laufwerk ist da, aber der Ordner „\(location.pathInVolume)“ fehlt – umbenannt oder verschoben? Mit „Neu zuordnen“ den Ordner wählen."
        default: return ""
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch status {
        case .offline:
            if location.kind == .network {
                Button("Verbinden") { model.reconnect(location) }.buttonStyle(CapsuleButtonStyle(role: .primary, compact: true))
            }
            Button("Erneut prüfen") { Task { await model.resolve(location, scanIfAvailable: true) } }
                .buttonStyle(CapsuleButtonStyle(role: .glass, compact: true))
        case .noAccess:
            Button("Zugriff erteilen …") { model.regrantAccess(location) }.buttonStyle(CapsuleButtonStyle(role: .primary, compact: true))
        case .folderMissing:
            Button("Neu zuordnen …") { model.regrantAccess(location) }.buttonStyle(CapsuleButtonStyle(role: .primary, compact: true))
        default:
            EmptyView()
        }
    }
}

/// Tastenkürzel der Bibliothek (Suche, Abspielen) – unsichtbare Knöpfe mit keyboardShortcut
struct KeyboardShortcutsForLibrary: View {
    @EnvironmentObject var model: AppModel
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        ZStack {
            Button("") { searchFocused.wrappedValue = true }.keyboardShortcut("f", modifiers: .command)
            Button("") { model.playSelection() }.keyboardShortcut(.return, modifiers: [])
                .disabled(model.selection.isEmpty || searchFocused.wrappedValue)
            Button("") { if searchFocused.wrappedValue { searchFocused.wrappedValue = false } else { model.selection = [] } }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
