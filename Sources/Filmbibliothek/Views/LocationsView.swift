import SwiftUI
import AppKit
import FBCore
import FBServices

/// „Speicherorte verwalten“ – Karten wie „Volumes“ in der Vorlage: Status, Belegung, Aktionen.
struct LocationsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Speicherorte", subtitle: subtitle) {
                    HStack(spacing: 8) {
                        Button { model.scanAll() } label: { Label("Alle durchsuchen", systemImage: "arrow.clockwise") }
                            .buttonStyle(CapsuleButtonStyle(role: .glass))
                            .disabled(model.locations.isEmpty)
                        Button { model.showAddLocationPanel() } label: { Label("Speicherort hinzufügen", systemImage: "plus") }
                            .buttonStyle(CapsuleButtonStyle(role: .primary))
                    }
                }
                if model.locations.isEmpty {
                    WelcomeEmptyState().frame(minHeight: 420)
                } else {
                    ForEach(model.locations) { loc in LocationCard(location: loc, compact: false) }
                }
                kindsCard
                HintBar(text: "Die Filmbibliothek sieht nur Ordner, die Sie hier hinzufügen, und darf sie nur lesen (App-Sandbox). macOS merkt sich die Freigabe dauerhaft. Wird ein Laufwerk abgezogen, bleiben seine Filme mit Titelbild und Fortschritt erhalten und werden beim nächsten Anschließen an der Laufwerkskennung wiedererkannt.")
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)
            .padding(.bottom, 36)
        }
    }

    private var subtitle: String {
        "\(model.availableLocationCount) von \(model.locations.count) verfügbar"
    }

    private var kindsCard: some View {
        GlassCard(title: "Unterstützte Speicherorte", systemImage: "externaldrive.connected.to.line.below", iconColor: p.teal) {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Interne SSD", value: "Ordner wählen")
                InfoRow(label: "Externe SSD/Festplatte, USB-Stick, SD-Karte", value: "Ordner oder ganzes Laufwerk")
                InfoRow(label: "NAS/Netzlaufwerk (SMB, AFP, NFS)", value: "im Finder verbinden, dann Ordner wählen")
                InfoRow(label: "Hinzufügen", value: "＋, ⌘O oder aus dem Finder ziehen")
            }
        }
    }
}

struct LocationCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    let location: StorageLocation
    let compact: Bool
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        let status = model.availabilityOf(location: location.id)
        let info = model.volumeInfo[location.id]
        let films = model.films.filter { $0.locationId == location.id }
        let missing = films.filter(\.isMissing).count
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: location.kind.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(status.isAvailable ? p.orange : p.textTertiary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if renaming {
                            TextField("Name", text: $newName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: 220)
                                .onSubmit { model.renameLocation(location, to: newName); renaming = false }
                        } else {
                            Text(location.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        }
                        Chip(text: status.label, dot: color(for: status))
                        if !compact {
                            Chip(text: location.kind.label)
                            if let fs = info?.fileSystem { Chip(text: fs) }
                            if location.isWholeVolume { Chip(text: "Ganzes Laufwerk") }
                        }
                    }
                    Text(location.lastKnownPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(p.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if let total = info?.totalBytes, let free = info?.availableBytes, status.isAvailable {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Fmt.bytes(free)) verfügbar").font(Typo.bodyStrong)
                        Text("von \(Fmt.bytes(total))").font(Typo.caption).foregroundColor(p.textSecondary)
                    }
                }
            }
            if let total = info?.totalBytes, let free = info?.availableBytes, total > 0, status.isAvailable {
                CapsuleBar(fraction: Double(total - free) / Double(total), color: p.orange, height: 7)
            }
            if let progress = model.scanProgress[location.id] {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(scanText(progress)).font(Typo.caption).foregroundColor(p.textSecondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Abbrechen") { model.cancelScan(location.id) }.buttonStyle(CapsuleButtonStyle(role: .glass, compact: true))
                }
            }
            HStack(spacing: 14) {
                legend(Fmt.count(films.count, "Film", "Filme"), p.accent)
                legend(Fmt.bytes(films.reduce(0) { $0 + $1.sizeBytes }), p.violet)
                if missing > 0 { legend("\(missing) fehlen", p.red) }
                legend("Durchsucht: " + (location.lastScanAt.map { Fmt.relative($0) } ?? "nie"), p.textTertiary)
                Spacer()
                if !compact { actionButtons(status: status, missing: missing) }
            }
            if compact && !status.isAvailable && status != .unknown {
                HStack { Spacer(); actionButtons(status: status, missing: 0) }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .glassCard()
        .opacity(status.isAvailable || status == .unknown ? 1 : 0.85)
        .contextMenu { LocationContextMenu(location: location) }
        .onTapGesture(count: 2) { model.navigate(.library(.location(location.id))) }
    }

    @ViewBuilder
    private func actionButtons(status: LocationAvailability, missing: Int) -> some View {
        HStack(spacing: 6) {
            switch status {
            case .available:
                if !compact {
                    Button("Filme zeigen") { model.navigate(.library(.location(location.id))) }
                        .buttonStyle(CapsuleButtonStyle(role: .glass, compact: true))
                    Button("Durchsuchen") { model.scan(location.id) }
                        .buttonStyle(CapsuleButtonStyle(role: .glass, compact: true))
                        .disabled(model.scanProgress[location.id] != nil)
                    Button("Im Finder zeigen") { model.revealLocation(location) }
                        .buttonStyle(CapsuleButtonStyle(role: .glass, compact: true))
                }
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
            case .unknown:
                EmptyView()
            }
            if !compact {
                Menu {
                    Button("Umbenennen") { newName = location.name; renaming = true }
                    Button("Fehlende Einträge entfernen …") {
                        model.removeMissingRequest = AppModel.RemoveMissingRequest(locationId: location.id, count: missing)
                    }
                    .disabled(missing == 0)
                    Divider()
                    Button("Aus der Bibliothek entfernen …", role: .destructive) { model.locationPendingRemoval = location }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .tint(p.textPrimary)
                .frame(width: 28, height: 28)
                .glass(Circle(), kind: .control, interactive: true)
            }
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(Typo.caption).foregroundColor(p.textSecondary)
        }
    }

    private func scanText(_ s: ScanProgress) -> String {
        switch s.phase {
        case .enumerating:
            return "Durchsuche … \(Fmt.count(s.videosFound, "Video", "Videos")) in \(Fmt.count(s.foldersVisited, "Ordner", "Ordnern"))" + (s.currentFolder.isEmpty ? "" : " – \(s.currentFolder)")
        case .saving: return "Speichere \(Fmt.count(s.videosFound, "Video", "Videos")) …"
        case .finished: return "Fertig"
        case .cancelled: return "Abgebrochen"
        case .failed(let m): return "Fehler: \(m)"
        }
    }

    private func color(for s: LocationAvailability) -> Color {
        switch s {
        case .available: return p.green
        case .offline: return p.textTertiary
        case .noAccess: return p.orange
        case .folderMissing: return p.red
        case .unknown: return p.textTertiary
        }
    }
}
