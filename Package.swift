// swift-tools-version:5.9
//
// Filmbibliothek für macOS – Swift-Paket.
//
// Aufbau (siehe docs/ARCHITEKTUR.md):
//   FBCore        reine Logik ohne Apple-Oberflächen (Modelle, Formate, Suche, Filter, Sortierung,
//                 Fortsetzen-Regeln, Warteschlange, Speicherort-Erkennung, Untertitel-Parser)
//   FBStore       SQLite-Datenbank (Speicherorte, Filme, Favoriten, Fortschritt, Sammlungen, Verlauf)
//   FBServices    macOS-Dienste ohne Oberfläche: Lesezeichen und Sandbox-Zugriff, Laufwerksüberwachung,
//                 Scanner, Metadaten (AVFoundation/VLCKit), Cover, Wiedergabe-Engines
//   Filmbibliothek  die App (SwiftUI + AppKit)
//
// VLCKit (LGPL 2.1, offizielle VideoLAN-Binärdatei) wird von scripts/fetch_vlckit.sh nach Vendor/ geladen
// (Prüfsumme festgelegt). Fehlt es, baut das Paket ohne VLCKit – dann spielt die App nur, was AVFoundation kann.
import PackageDescription
import Foundation

let vlcKitPath = "Vendor/VLCKit.xcframework"
let hasVLCKit = FileManager.default.fileExists(atPath: Context.packageDirectory + "/" + vlcKitPath)

var serviceDependencies: [Target.Dependency] = ["FBCore", "FBStore"]
// Bibliotheken für das Xcode-Projekt (project.yml → Filmbibliothek.xcodeproj); die App selbst ist ein eigenes Ziel
var products: [Product] = [
    .library(name: "FBCore", targets: ["FBCore"]),
    .library(name: "FBStore", targets: ["FBStore"]),
]
var targets: [Target] = [
    .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
    .target(name: "FBCore", path: "Sources/FBCore"),
    .target(name: "FBStore", dependencies: ["FBCore", "CSQLite"], path: "Sources/FBStore"),
    .testTarget(name: "FBCoreTests", dependencies: ["FBCore"], path: "Tests/FBCoreTests"),
    .testTarget(name: "FBStoreTests", dependencies: ["FBStore"], path: "Tests/FBStoreTests"),
]

#if os(macOS)
if hasVLCKit {
    targets.append(.binaryTarget(name: "VLCKit", path: vlcKitPath))
    serviceDependencies.append("VLCKit")
}
targets.append(
    .target(
        name: "FBServices",
        dependencies: serviceDependencies,
        path: "Sources/FBServices",
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("AVFoundation"),
            .linkedFramework("CoreMedia"),
            .linkedFramework("ImageIO"),
            .linkedFramework("UniformTypeIdentifiers"),
        ]
    )
)
products.append(.library(name: "FBServices", targets: ["FBServices"]))
targets.append(
    .executableTarget(
        name: "Filmbibliothek",
        dependencies: ["FBCore", "FBStore", "FBServices"],
        path: "Sources/Filmbibliothek",
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("AVKit"),
            .linkedFramework("AVFoundation"),
            .linkedFramework("IOKit"),
        ]
    )
)
targets.append(
    .testTarget(
        name: "FBServicesTests",
        dependencies: ["FBServices"],
        path: "Tests/FBServicesTests"
    )
)
#endif

let package = Package(
    name: "Filmbibliothek",
    defaultLocalization: "de",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
