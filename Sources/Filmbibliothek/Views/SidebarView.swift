import SwiftUI
import AppKit
import FBCore
import FBServices

/// Schwebende Glas-Seitenleiste (Vorlage: AETHER) – Bereiche in Versalien, Auswahl als blau getönte Pille,
/// unten Einstellungen und eine Live-Statuszeile.
struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    Color.clear.frame(height: 30) // Platz für die Fensterknöpfe
                    SidebarRow(title: "Übersicht", systemImage: "sparkles.tv", color: p.accent,
                               selected: model.route == .overview) { model.navigate(.overview) }

                    SidebarSection("Bibliothek")
                    scopeRow(.all, "Alle Filme", "film.stack", p.accent)
                    scopeRow(.continueWatching, "Weiterschauen", "play.circle", p.teal)
                    scopeRow(.recentlyAdded, "Zuletzt hinzugefügt", "sparkle", p.yellow)
                    scopeRow(.recentlyPlayed, "Zuletzt abgespielt", "clock.arrow.circlepath", p.violet)
                    scopeRow(.favorites, "Favoriten", "heart", p.heart)
                    if model.films.contains(where: { !model.isAvailable($0) }) {
                        scopeRow(.unavailable, "Nicht verfügbar", "externaldrive.badge.xmark", p.textTertiary)
                    }

                    SidebarSection("Sammlungen") {
                        model.collectionNamePrompt = AppModel.CollectionPrompt()
                    }
                    if model.collections.isEmpty {
                        Text("Eigene Listen, z. B. „Filmabend“")
                            .font(Typo.caption)
                            .foregroundColor(p.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                    ForEach(model.collections) { c in
                        SidebarRow(title: c.name, systemImage: "rectangle.stack", color: p.pink,
                                   badge: c.filmIds.count, selected: model.route == .library(.collection(c.id))) {
                            model.navigate(.library(.collection(c.id)))
                        }
                        .contextMenu {
                            Button("Umbenennen …") { model.collectionNamePrompt = AppModel.CollectionPrompt(renaming: c) }
                            Button("Sammlung löschen", role: .destructive) { model.delete(c) }
                        }
                    }

                    SidebarSection("Speicherorte") { model.showAddLocationPanel() }
                    ForEach(model.locations) { loc in
                        LocationSidebarRow(location: loc)
                    }
                    SidebarRow(title: "Speicherorte verwalten", systemImage: "externaldrive.connected.to.line.below", color: p.textSecondary,
                               selected: model.route == .locations) { model.navigate(.locations) }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            footer
        }
        .glass(RoundedRectangle(cornerRadius: 18, style: .continuous), kind: .panel, elevated: true)
    }

    private func scopeRow(_ scope: LibraryScope, _ title: String, _ icon: String, _ color: Color) -> some View {
        SidebarRow(title: title, systemImage: icon, color: color, badge: model.count(in: scope),
                   selected: model.route == .library(scope)) {
            model.navigate(.library(scope))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(p.hairline).frame(height: 0.8).padding(.horizontal, 6)
            SettingsLinkRow()
            HStack(spacing: 14) {
                FooterStat(label: "Filme", value: Fmt.integer(model.films.count), dot: p.accent)
                FooterStat(label: "Orte", value: "\(model.availableLocationCount)/\(model.locations.count)",
                           dot: model.availableLocationCount == model.locations.count ? p.green : p.orange)
                FooterStat(label: model.isScanning ? "Scan" : (model.metadataRemaining > 0 ? "Analyse" : "Status"),
                           value: statusValue, dot: model.isScanning || model.metadataRemaining > 0 ? p.teal : p.green,
                           pulsing: model.isScanning || model.metadataRemaining > 0)
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 14)
        .padding(.top, 2)
    }

    private var statusValue: String {
        if model.isScanning {
            let found = model.scanProgress.values.reduce(0) { $0 + $1.videosFound }
            return Fmt.integer(found)
        }
        if model.metadataRemaining > 0 { return Fmt.integer(model.metadataRemaining) }
        return "Bereit"
    }
}

struct SidebarSection: View {
    @Environment(\.palette) private var p
    let title: String
    var onAdd: (() -> Void)?
    @State private var hover = false

    init(_ title: String, onAdd: (() -> Void)? = nil) {
        self.title = title
        self.onAdd = onAdd
    }

    var body: some View {
        HStack {
            SectionLabel(title)
            Spacer()
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(p.textSecondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(hover ? p.controlHover : .clear))
                }
                .buttonStyle(.plain)
                .onHover { hover = $0 }
                .help(title == "Speicherorte" ? "Speicherort hinzufügen" : "Neue Sammlung")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }
}

struct SidebarRow: View {
    @Environment(\.palette) private var p
    let title: String
    let systemImage: String
    var color: Color
    var badge: Int? = nil
    var selected: Bool
    var trailing: AnyView? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(selected ? p.accent : color.opacity(0.9))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundColor(p.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if let trailing { trailing }
                if let badge, badge > 0 {
                    Text(Fmt.integer(badge))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundColor(p.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? p.accentSoft : (hover ? p.control : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? p.accent.opacity(0.25) : .clear, lineWidth: 0.6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Speicherort in der Seitenleiste: Symbol nach Laufwerksart, Statuspunkt, Fortschrittsring beim Durchsuchen
struct LocationSidebarRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    let location: StorageLocation

    var body: some View {
        let status = model.availabilityOf(location: location.id)
        let scanning = model.scanProgress[location.id] != nil
        SidebarRow(title: location.name, systemImage: location.kind.symbol, color: p.textSecondary,
                   badge: nil, selected: isSelected,
                   trailing: AnyView(trailing(status: status, scanning: scanning))) {
            model.navigate(.library(.location(location.id)))
        }
        .opacity(status.isAvailable || status == .unknown ? 1 : 0.62)
        .help(status.label + (location.lastKnownPath.isEmpty ? "" : " – \(location.lastKnownPath)"))
        .contextMenu { LocationContextMenu(location: location) }
    }

    private var isSelected: Bool {
        switch model.route {
        case .library(.location(let id)): return id == location.id
        case .library(.folder(let id, _)): return id == location.id
        default: return false
        }
    }

    @ViewBuilder
    private func trailing(status: LocationAvailability, scanning: Bool) -> some View {
        if scanning {
            ProgressView().controlSize(.mini).scaleEffect(0.8)
        } else {
            StatusDot(color: color(for: status), size: 6)
        }
    }

    private func color(for s: LocationAvailability) -> Color {
        switch s {
        case .available: return p.green
        case .offline: return p.textTertiary
        case .noAccess: return p.orange
        case .folderMissing: return p.red
        case .unknown: return p.textTertiary.opacity(0.5)
        }
    }
}

/// Kontextmenü eines Speicherorts (Seitenleiste und Speicherorte-Seite)
struct LocationContextMenu: View {
    @EnvironmentObject var model: AppModel
    let location: StorageLocation

    var body: some View {
        let status = model.availabilityOf(location: location.id)
        if model.scanProgress[location.id] != nil {
            Button("Durchsuchen abbrechen") { model.cancelScan(location.id) }
        } else {
            Button("Jetzt durchsuchen") { model.scan(location.id) }.disabled(!status.isAvailable)
        }
        Button("Im Finder zeigen") { model.revealLocation(location) }.disabled(!status.isAvailable)
        if case .noAccess = status { Button("Zugriff erneut erteilen …") { model.regrantAccess(location) } }
        if status == .folderMissing { Button("Ordner neu zuordnen …") { model.regrantAccess(location) } }
        if location.kind == .network && status == .offline { Button("Verbinden") { model.reconnect(location) } }
        Divider()
        Button("Fehlende Einträge entfernen …") {
            let n = model.films.filter { $0.isMissing && $0.locationId == location.id }.count
            model.removeMissingRequest = AppModel.RemoveMissingRequest(locationId: location.id, count: n)
        }
        .disabled(!model.films.contains { $0.isMissing && $0.locationId == location.id })
        Button("Aus der Bibliothek entfernen …", role: .destructive) { model.locationPendingRemoval = location }
    }
}

struct FooterStat: View {
    @Environment(\.palette) private var p
    let label: String
    let value: String
    let dot: Color
    var pulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                StatusDot(color: dot, size: 5, pulsing: pulsing)
                Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.5).foregroundColor(p.textTertiary)
            }
            Text(value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundColor(p.textPrimary)
                .lineLimit(1)
        }
    }
}

/// „Einstellungen“ unten in der Seitenleiste – öffnet das Einstellungsfenster (⌘,)
struct SettingsLinkRow: View {
    @Environment(\.palette) private var p

    var body: some View {
        SidebarRow(title: "Einstellungen", systemImage: "gearshape", color: p.textSecondary, selected: false) {
            SettingsOpener.open()
        }
        .padding(.horizontal, 8)
    }
}

enum SettingsOpener {
    /// macOS 14+: offizielle SwiftUI-Aktion `openSettings` (wird von `SettingsActionBridge` hinterlegt)
    @MainActor static var action: (() -> Void)?

    @MainActor
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        if let action {
            action()
            return
        }
        // macOS 13: Menübefehl „Einstellungen …“ des Settings-Fensters
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

/// Hinterlegt auf macOS 14+ die Aktion zum Öffnen der Einstellungen.
struct SettingsActionBridge: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            Bridge14()
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    @available(macOS 14.0, *)
    private struct Bridge14: View {
        @Environment(\.openSettings) private var openSettings
        var body: some View {
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear { SettingsOpener.action = { openSettings() } }
        }
    }
}
