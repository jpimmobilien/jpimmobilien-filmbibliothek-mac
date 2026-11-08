import SwiftUI
import AppKit
import FBCore
import FBServices

/// Dauerhafte Einstellungen (UserDefaults im Container der App).
@MainActor
final class AppSettings: ObservableObject {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, dark, light
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "Wie System"
            case .dark: return "Dunkel"
            case .light: return "Hell"
            }
        }
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case largeGrid, compactGrid, list
        var id: String { rawValue }
        var label: String {
            switch self {
            case .largeGrid: return "Große Poster"
            case .compactGrid: return "Kompakte Poster"
            case .list: return "Liste"
            }
        }
        var symbol: String {
            switch self {
            case .largeGrid: return "square.grid.2x2"
            case .compactGrid: return "square.grid.3x3"
            case .list: return "list.bullet"
            }
        }
    }

    enum TileShape: String, CaseIterable, Identifiable {
        case widescreen, poster
        var id: String { rawValue }
        var label: String { self == .widescreen ? "Breitbild (16:9)" : "Filmposter (2:3)" }
        var aspect: CGFloat { self == .widescreen ? 16.0 / 9.0 : 2.0 / 3.0 }
    }

    enum ResumeBehavior: String, CaseIterable, Identifiable {
        case ask, always, never
        var id: String { rawValue }
        var label: String {
            switch self {
            case .ask: return "Nachfragen"
            case .always: return "Immer fortsetzen"
            case .never: return "Immer von vorn"
            }
        }
    }

    enum TitleSource: String, CaseIterable, Identifiable {
        case cleaned, fileName
        var id: String { rawValue }
        var label: String { self == .cleaned ? "Bereinigter Titel" : "Vollständiger Dateiname" }
    }

    private let defaults = UserDefaults.standard

    @Published var appearance: Appearance { didSet { save("appearance", appearance.rawValue); applyAppearance() } }
    @Published var viewMode: ViewMode { didSet { save("viewMode", viewMode.rawValue) } }
    @Published var tileShape: TileShape { didSet { save("tileShape", tileShape.rawValue) } }
    @Published var titleSource: TitleSource { didSet { save("titleSource", titleSource.rawValue) } }
    @Published var showFormatBadges: Bool { didSet { save("showFormatBadges", showFormatBadges) } }
    @Published var sortKey: SortKey { didSet { save("sortKey", sortKey.rawValue) } }
    @Published var sortAscending: Bool { didSet { save("sortAscending", sortAscending) } }
    @Published var scanOnLaunch: Bool { didSet { save("scanOnLaunch", scanOnLaunch) } }
    @Published var scanOnMount: Bool { didSet { save("scanOnMount", scanOnMount) } }
    @Published var heartFavorites: Bool { didSet { save("heartFavorites", heartFavorites) } }
    @Published var coverPreference: MetadataService.CoverPreference { didSet { save("coverPreference", coverPreference.rawValue) } }
    @Published var lastFrameAsCover: Bool { didSet { save("lastFrameAsCover", lastFrameAsCover) } }
    @Published var resumeBehavior: ResumeBehavior { didSet { save("resumeBehavior", resumeBehavior.rawValue) } }
    @Published var autoplayNext: Bool { didSet { save("autoplayNext", autoplayNext) } }
    @Published var seekStep: Double { didSet { save("seekStep", seekStep) } }
    @Published var controlsHideDelay: Double { didSet { save("controlsHideDelay", controlsHideDelay) } }
    @Published var playerVolume: Double { didSet { save("playerVolume", playerVolume) } }
    @Published var subtitlesOnByDefault: Bool { didSet { save("subtitlesOnByDefault", subtitlesOnByDefault) } }
    @Published var startFullScreen: Bool { didSet { save("startFullScreen", startFullScreen) } }
    @Published var showOverviewOnLaunch: Bool { didSet { save("showOverviewOnLaunch", showOverviewOnLaunch) } }

    init() {
        let d = UserDefaults.standard
        func str(_ k: String) -> String? { d.string(forKey: k) }
        func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) == nil ? def : d.bool(forKey: k) }
        func dbl(_ k: String, _ def: Double) -> Double { d.object(forKey: k) == nil ? def : d.double(forKey: k) }
        appearance = str("appearance").flatMap(Appearance.init(rawValue:)) ?? .system
        viewMode = str("viewMode").flatMap(ViewMode.init(rawValue:)) ?? .largeGrid
        tileShape = str("tileShape").flatMap(TileShape.init(rawValue:)) ?? .widescreen
        titleSource = str("titleSource").flatMap(TitleSource.init(rawValue:)) ?? .cleaned
        showFormatBadges = bool("showFormatBadges", true)
        sortKey = str("sortKey").flatMap(SortKey.init(rawValue:)) ?? .title
        sortAscending = bool("sortAscending", true)
        scanOnLaunch = bool("scanOnLaunch", true)
        scanOnMount = bool("scanOnMount", true)
        heartFavorites = bool("heartFavorites", false)
        coverPreference = str("coverPreference").flatMap(MetadataService.CoverPreference.init(rawValue:)) ?? .posterFirst
        lastFrameAsCover = bool("lastFrameAsCover", true)
        resumeBehavior = str("resumeBehavior").flatMap(ResumeBehavior.init(rawValue:)) ?? .ask
        autoplayNext = bool("autoplayNext", true)
        seekStep = dbl("seekStep", 10)
        controlsHideDelay = dbl("controlsHideDelay", 3)
        playerVolume = dbl("playerVolume", 1)
        subtitlesOnByDefault = bool("subtitlesOnByDefault", false)
        startFullScreen = bool("startFullScreen", false)
        showOverviewOnLaunch = bool("showOverviewOnLaunch", true)
    }

    private func save(_ key: String, _ value: Any) { defaults.set(value, forKey: key) }

    var sortOrder: SortOrder {
        get { SortOrder(key: sortKey, ascending: sortAscending) }
        set { sortKey = newValue.key; sortAscending = newValue.ascending }
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        }
    }

    func displayTitle(_ film: Film) -> String {
        titleSource == .cleaned ? film.title : film.fileName
    }

    /// Alles auf Standard (Speicherorte und Bibliothek bleiben)
    func resetToDefaults() {
        for key in ["appearance", "viewMode", "tileShape", "titleSource", "showFormatBadges", "sortKey", "sortAscending", "scanOnLaunch",
                    "scanOnMount", "heartFavorites", "coverPreference", "lastFrameAsCover", "resumeBehavior", "autoplayNext", "seekStep",
                    "controlsHideDelay", "playerVolume", "subtitlesOnByDefault", "startFullScreen", "showOverviewOnLaunch"] {
            defaults.removeObject(forKey: key)
        }
        let fresh = AppSettings()
        appearance = fresh.appearance
        viewMode = fresh.viewMode
        tileShape = fresh.tileShape
        titleSource = fresh.titleSource
        showFormatBadges = fresh.showFormatBadges
        sortKey = fresh.sortKey
        sortAscending = fresh.sortAscending
        scanOnLaunch = fresh.scanOnLaunch
        scanOnMount = fresh.scanOnMount
        heartFavorites = fresh.heartFavorites
        coverPreference = fresh.coverPreference
        lastFrameAsCover = fresh.lastFrameAsCover
        resumeBehavior = fresh.resumeBehavior
        autoplayNext = fresh.autoplayNext
        seekStep = fresh.seekStep
        controlsHideDelay = fresh.controlsHideDelay
        playerVolume = fresh.playerVolume
        subtitlesOnByDefault = fresh.subtitlesOnByDefault
        startFullScreen = fresh.startFullScreen
        showOverviewOnLaunch = fresh.showOverviewOnLaunch
    }
}
