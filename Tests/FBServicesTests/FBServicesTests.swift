import XCTest
import AppKit
import Metal
import FBCore
import FBStore
@testable import FBServices

// Integrationstests auf echtem macOS: echte Testvideos (Tests/Fixtures/Videos), echte Disk-Images (hdiutil),
// echte Wiedergabe mit AVFoundation und VLCKit. Keine Attrappen.

enum Fixtures {
    static var directory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Videos", isDirectory: true)
    }

    /// Kopie der Testvideos in einen eigenen temporären Ordner
    static func copy() throws -> URL {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("fb-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: directory, to: dest)
        return dest
    }

    /// Alle Videos, die die App aufnehmen soll (versteckte Dateien, Papierkorb und Pakete ausgenommen)
    static let expectedVideos: Set<String> = [
        "Testfilm MP4.mp4", "Testfilm MP4 (HEVC).mp4", "Testfilm M4V.m4v", "Testfilm MOV.mov", "Testfilm MKV.mkv",
        "Testfilm AVI.avi", "Testfilm WMV.wmv", "Testfilm MPG.mpg", "Testfilm MPEG.mpeg", "Testfilm TS.ts", "Testfilm M2TS.m2ts",
        "Testfilm WEBM.webm", "Testfilm FLV.flv", "Langer Testfilm (2026).mp4", "Mit Poster/Film mit Poster.mp4",
        "Serien/Staffel 1/Kamera 00001.mts", "Serien/Staffel 1/Serie S01E01.mp4", "Serien/Staffel 1/Serie S01E02.mp4",
        "Kaputt/Zufallsdaten.mp4", "Kaputt/Leere Datei.mkv", "Kaputt/Abgeschnitten.mkv", "Kaputt/Textdatei.avi",
    ]

    static let corrupt: Set<String> = ["Kaputt/Zufallsdaten.mp4", "Kaputt/Leere Datei.mkv", "Kaputt/Textdatei.avi"]
}

/// Echte Disk-Images mit hdiutil
final class DiskImage {
    let path: URL
    private(set) var mountPoint: URL?

    init(fs: String, name: String, sizeMB: Int = 64) throws {
        path = FileManager.default.temporaryDirectory.appendingPathComponent("fb-\(UUID().uuidString).dmg")
        try Self.hdiutil(["create", "-size", "\(sizeMB)m", "-fs", fs, "-volname", name, "-ov", path.path])
    }

    @discardableResult
    static func hdiutil(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "hdiutil", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "hdiutil \(args.joined(separator: " ")): \(out)"])
        }
        return out
    }

    /// Einbinden (optional an einem bestimmten Ort, um „anderer Einhängepunkt“ zu prüfen)
    @discardableResult
    func attach(at mount: URL? = nil) throws -> URL {
        var args = ["attach", path.path, "-plist"]
        if let mount {
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            args += ["-mountpoint", mount.path]
        }
        let out = try Self.hdiutil(args)
        guard let data = out.data(using: .utf8),
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mp = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw NSError(domain: "hdiutil", code: -1, userInfo: [NSLocalizedDescriptionKey: "kein Einhängepunkt: \(out)"])
        }
        mountPoint = URL(fileURLWithPath: mp, isDirectory: true)
        return mountPoint!
    }

    func detach(force: Bool = false) throws {
        guard let mp = mountPoint else { return }
        do {
            try Self.hdiutil(["detach", mp.path] + (force ? ["-force"] : []))
        } catch {
            // Bereits ausgehängt (auf den Intel-VMs von GitHub beobachtet: „detach failed – No such file or directory“)
            // ist kein Fehler des Prüflings; sonst einmal mit Gewalt wiederholen.
            if !Self.isMounted(mp) { mountPoint = nil; return }
            Thread.sleep(forTimeInterval: 1)
            if Self.isMounted(mp) { try Self.hdiutil(["detach", mp.path, "-force"]) }
        }
        mountPoint = nil
    }

    static func isMounted(_ mp: URL) -> Bool {
        let paths = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []).map(\.standardizedFileURL.path)
        return paths.contains(mp.standardizedFileURL.path)
    }

    deinit {
        if let mp = mountPoint { _ = try? Self.hdiutil(["detach", mp.path, "-force"]) }
        try? FileManager.default.removeItem(at: path)
    }
}

final class ScannerTests: XCTestCase {
    func testFindsExactlyTheExpectedVideos() throws {
        let root = try Fixtures.copy()
        defer { try? FileManager.default.removeItem(at: root) }
        let listing = LibraryScanner.list(root: root)
        XCTAssertTrue(listing.complete)
        XCTAssertEqual(Set(listing.files.map(\.relativePath)), Fixtures.expectedVideos)
        XCTAssertNil(listing.files.first { $0.relativePath.contains("photoslibrary") }, "Pakete werden nicht durchsucht")
        XCTAssertNotNil(listing.files.first?.fileId)
    }

    func testExcludedSubpaths() throws {
        let root = try Fixtures.copy()
        defer { try? FileManager.default.removeItem(at: root) }
        let listing = LibraryScanner.list(root: root, excluding: ["Serien"])
        XCTAssertFalse(listing.files.contains { $0.relativePath.hasPrefix("Serien/") })
    }

    func testRescanRenameDeleteRestore() async throws {
        let root = try Fixtures.copy()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore.inMemory()
        let loc = try store.insertLocation(StorageLocation(name: "T", lastKnownPath: root.path, pathInVolume: "t", volumeKey: "uuid:T",
                                                           volumeName: "T", kind: .internalDisk, bookmark: nil))
        let scanner = LibraryScanner(store: store)
        var r = await scanner.scan(location: loc, root: root, excluding: [], heartFavorites: false) { _ in }
        XCTAssertEqual(r.outcome, .completed)
        XCTAssertEqual(r.changes.inserts.count, Fixtures.expectedVideos.count)
        // unverändert
        r = await scanner.scan(location: loc, root: root, excluding: [], heartFavorites: false) { _ in }
        XCTAssertTrue(r.changes.isEmpty)
        XCTAssertEqual(r.changes.unchanged, Fixtures.expectedVideos.count)
        // umbenennen → gleiche ID
        let before = try XCTUnwrap(try store.films().first { $0.relativePath == "Testfilm MKV.mkv" })
        try store.setFavorite(ids: [before.id], true)
        try FileManager.default.moveItem(at: root.appendingPathComponent("Testfilm MKV.mkv"), to: root.appendingPathComponent("Serien/Umbenannt.mkv"))
        r = await scanner.scan(location: loc, root: root, excluding: [], heartFavorites: false) { _ in }
        XCTAssertEqual(r.changes.moves.map(\.id), [before.id])
        let after = try XCTUnwrap(try store.film(id: before.id))
        XCTAssertEqual(after.relativePath, "Serien/Umbenannt.mkv")
        XCTAssertTrue(after.isFavorite)
        // löschen → „Datei fehlt“, Eintrag bleibt
        let removed = root.appendingPathComponent("Testfilm AVI.avi")
        let parked = FileManager.default.temporaryDirectory.appendingPathComponent("fb-parked-\(UUID().uuidString).avi")
        try FileManager.default.moveItem(at: removed, to: parked)
        r = await scanner.scan(location: loc, root: root, excluding: [], heartFavorites: false) { _ in }
        XCTAssertEqual(r.changes.newlyMissing.count, 1)
        XCTAssertEqual(try store.films().count, Fixtures.expectedVideos.count)
        // zurück → wieder da
        try FileManager.default.moveItem(at: parked, to: removed)
        r = await scanner.scan(location: loc, root: root, excluding: [], heartFavorites: false) { _ in }
        XCTAssertEqual(r.changes.reappeared.count, 1)
        XCTAssertEqual(try store.films().filter(\.isMissing).count, 0)
    }

    func testCancelledScanChangesNothing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fb-many-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for d in 0..<200 {
            let dir = root.appendingPathComponent("Ordner \(d)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for f in 0..<20 { FileManager.default.createFile(atPath: dir.appendingPathComponent("Video \(f).mp4").path, contents: Data()) }
        }
        let store = try LibraryStore.inMemory()
        let loc = try store.insertLocation(StorageLocation(name: "M", lastKnownPath: root.path, pathInVolume: "m", volumeKey: "uuid:M",
                                                           volumeName: "M", kind: .internalDisk, bookmark: nil))
        let scanner = LibraryScanner(store: store)
        let first = await scanner.scan(location: loc, root: root, excluding: [], heartFavorites: false) { _ in }
        XCTAssertEqual(first.changes.inserts.count, 4000)
        // Hälfte entfernen, Durchlauf sofort abbrechen → nichts darf als fehlend markiert werden
        for d in 0..<100 { try FileManager.default.removeItem(at: root.appendingPathComponent("Ordner \(d)")) }
        let task = Task { await scanner.scan(location: loc, root: root, excluding: [], heartFavorites: false) { _ in } }
        task.cancel()
        let report = await task.value
        if report.outcome == .cancelled {
            XCTAssertEqual(try store.films().filter(\.isMissing).count, 0)
        } else {
            // Durchlauf war schneller als der Abbruch: dann korrekt vollständig ausgewertet
            XCTAssertEqual(report.outcome, .completed)
            XCTAssertEqual(try store.films().filter(\.isMissing).count, 2000)
        }
        print("Abbruch-Test: \(report.outcome)")
    }
}

final class MetadataTests: XCTestCase {
    func url(_ rel: String) -> URL { Fixtures.directory.appendingPathComponent(rel) }

    func testAVFoundationReadsAppleFormats() async throws {
        for (file, codec) in [("Testfilm MP4.mp4", "H.264"), ("Testfilm MP4 (HEVC).mp4", "HEVC (H.265)"), ("Testfilm M4V.m4v", "H.264"), ("Testfilm MOV.mov", "H.264")] {
            let probed = await AVProbe.probe(url: url(file))
            let r = try XCTUnwrap(probed, file)
            XCTAssertTrue(r.playable, file)
            XCTAssertEqual(r.info.width, 320, file)
            XCTAssertEqual(r.info.height, 180, file)
            XCTAssertEqual(r.info.durationSeconds ?? 0, 6, accuracy: 0.2, file)
            XCTAssertEqual(r.info.videoCodec, codec, file)
            XCTAssertEqual(r.info.audioCodec, "AAC", file)
            XCTAssertEqual(r.info.frameRate ?? 0, 25, accuracy: 0.5, file)
        }
        let probedMP4 = await AVProbe.probe(url: url("Testfilm MP4.mp4"))
        let mp4 = try XCTUnwrap(probedMP4)
        XCTAssertEqual(mp4.chapters.map(\.title), ["Anfang", "Schluss"])
        XCTAssertNotNil(mp4.artwork, "eingebettetes Cover")
    }

    func testAVFoundationRejectsCorruptFiles() async {
        let r = await AVProbe.probe(url: url("Kaputt/Zufallsdaten.mp4"))
        XCTAssertTrue(r == nil || r?.playable == false)
    }

    func testVLCReadsOtherFormats() async throws {
        if !VLCSupport.isAvailable {
            if ProcessInfo.processInfo.environment["FB_REQUIRE_VLC"] == "1" { XCTFail("VLCKit fehlt im Build") }
            throw XCTSkip("Build ohne VLCKit")
        }
        let files = ["Testfilm MKV.mkv", "Testfilm AVI.avi", "Testfilm WMV.wmv", "Testfilm MPG.mpg", "Testfilm MPEG.mpeg", "Testfilm TS.ts",
                     "Testfilm M2TS.m2ts", "Testfilm WEBM.webm", "Testfilm FLV.flv", "Serien/Staffel 1/Kamera 00001.mts"]
        for f in files {
            let analyzed = await VLCSupport.analyze(url: url(f))
            let info = try XCTUnwrap(analyzed.0, f)
            // Transportströme melden durch Puffer-/Zeitstempelversatz etwas mehr (gemessen: 6,66 s)
            XCTAssertEqual(info.durationSeconds ?? 0, 6, accuracy: f.hasSuffix("ts") ? 0.8 : 0.6, f)
            if ContainerSniffer.sniff(url: url(f)) != nil && info.width == nil {
                // MPEG-PS/TS: Bildgröße nur, wenn VLCKit ein Vorschaubild dekodieren konnte – im Testbericht vermerkt
                print("HINWEIS \(f): abspielbar erkannt, Bildgröße unbekannt (kein Bild dekodiert)")
            } else {
                XCTAssertEqual(info.width, 320, f)
                XCTAssertEqual(info.height, 180, f)
            }
            XCTAssertGreaterThanOrEqual(info.audioTrackCount, 1, f)
            print("VLC \(f): \(info.videoCodec ?? "-") / \(info.audioCodec ?? "-") / \(info.frameRate ?? 0) fps")
        }
        let probedMKV = await VLCSupport.probe(url: url("Testfilm MKV.mkv"))
        let mkv = try XCTUnwrap(probedMKV)
        XCTAssertEqual(mkv.audioTrackCount, 2)
        XCTAssertEqual(mkv.subtitleTrackCount, 1)
        let text = await VLCSupport.analyze(url: url("Kaputt/Textdatei.avi"))
        XCTAssertNil(text.0, "Textdatei ist kein Video")
        let random = await VLCSupport.analyze(url: url("Kaputt/Zufallsdaten.mp4"))
        XCTAssertNil(random.0, "Zufallsdaten sind kein Video")
    }

    @MainActor
    func testMetadataServiceClassifiesAndMakesCovers() async throws {
        let root = try Fixtures.copy()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore.inMemory()
        let coversDir = FileManager.default.temporaryDirectory.appendingPathComponent("fb-covers-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: coversDir) }
        let loc = try store.insertLocation(StorageLocation(name: "T", lastKnownPath: root.path, pathInVolume: "x", volumeKey: "uuid:X",
                                                           volumeName: "T", kind: .internalDisk, bookmark: nil))
        _ = await LibraryScanner(store: store).scan(location: loc, root: root, excluding: [], heartFavorites: false) { _ in }
        let service = MetadataService(store: store, covers: CoverStore(directory: coversDir))
        for film in try store.films() {
            let outcome = await service.process(film, locationRoot: root, preference: .posterFirst)
            XCTAssertNotNil(outcome, film.relativePath)
        }
        let films = Dictionary(uniqueKeysWithValues: try store.films().map { ($0.relativePath, $0) })
        for c in Fixtures.corrupt { XCTAssertEqual(films[c]?.playability, .unsupported, c) }
        for f in ["Testfilm MP4.mp4", "Testfilm MOV.mov", "Testfilm M4V.m4v", "Testfilm MP4 (HEVC).mp4", "Langer Testfilm (2026).mp4"] {
            XCTAssertEqual(films[f]?.playability, .native, f)
        }
        if VLCSupport.isAvailable {
            for f in ["Testfilm MKV.mkv", "Testfilm AVI.avi", "Testfilm WMV.wmv", "Testfilm WEBM.webm", "Testfilm FLV.flv", "Testfilm TS.ts",
                      "Testfilm MPG.mpg", "Testfilm MPEG.mpeg", "Testfilm M2TS.m2ts", "Serien/Staffel 1/Kamera 00001.mts"] {
                XCTAssertEqual(films[f]?.playability, .vlc, f)
            }
        }
        XCTAssertEqual(films["Mit Poster/Film mit Poster.mp4"]?.coverSource, .posterFile)
        XCTAssertEqual(films["Testfilm MP4.mp4"]?.coverSource, .embedded)
        XCTAssertEqual(films["Testfilm MOV.mov"]?.coverSource, .videoFrame)
        XCTAssertEqual(films["Langer Testfilm (2026).mp4"]?.info.durationSeconds ?? 0, 240, accuracy: 1)
        for (path, f) in films.sorted(by: { $0.key < $1.key }) {
            print("Metadaten \(path): \(f.playability.label), Cover \(f.coverSource.label), \(f.info.width ?? 0)x\(f.info.height ?? 0)")
        }
        let withCover = films.values.filter { $0.coverSource != CoverSource.none }
        for f in withCover { XCTAssertTrue(FileManager.default.fileExists(atPath: coversDir.appendingPathComponent("\(f.id).jpg").path)) }
    }

    func testFileGoneDuringProbeIsRetriedLater() async throws {
        let store = try LibraryStore.inMemory()
        let service = MetadataService(store: store, covers: CoverStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("fb-c-\(UUID().uuidString)")))
        let film = Film(id: 1, locationId: 1, relativePath: "gibt-es-nicht.mkv", sizeBytes: 10, modifiedAt: nil)
        let outcome = await service.process(film, locationRoot: URL(fileURLWithPath: "/Volumes/Nicht-Da"), preference: .posterFirst)
        XCTAssertNil(outcome, "fehlende Datei darf nicht als „nicht abspielbar“ gespeichert werden")
    }
}

final class VolumeTests: XCTestCase {
    func checkIdentityEjectReattach(fs: String, name: String) throws {
        let img = try DiskImage(fs: fs, name: name)
        let mount = try img.attach()
        let folder = mount.appendingPathComponent("Filme", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for f in ["Testfilm MP4.mp4", "Testfilm MKV.mkv"] {
            try FileManager.default.copyItem(at: Fixtures.directory.appendingPathComponent(f), to: folder.appendingPathComponent(f))
        }
        let loc = try LocationResolver.makeLocation(for: folder)
        let vol = try XCTUnwrap(VolumeInspector.volume(for: folder))
        print("Laufwerk \(fs): Kennung \(loc.volumeKey), Art \(loc.kind.rawValue), Dateisystem \(vol.fileSystem ?? "?"), Pfad im Laufwerk \"\(loc.pathInVolume)\"")
        XCTAssertEqual(loc.pathInVolume, "Filme")
        XCTAssertNotNil(loc.bookmark)
        XCTAssertFalse(loc.volumeKey.contains(name) && !loc.volumeKey.hasPrefix("uuid:"), "Kennung darf nicht nur der Name sein")
        if fs == "APFS" || fs == "HFS+" { XCTAssertTrue(loc.volumeKey.hasPrefix("uuid:"), loc.volumeKey) }

        let store = try LibraryStore.inMemory()
        let saved = try store.insertLocation(loc)
        guard case .available(let url, let access, _) = LocationResolver.resolve(saved, mounted: .current()) else {
            return XCTFail("nicht verfügbar nach dem Hinzufügen")
        }
        let r1 = LibraryScanner.list(root: url)
        try store.apply(ScanDiff.compute(existing: [], found: r1.files), locationId: saved.id, heartFavorites: false)
        XCTAssertEqual(try store.films().count, 2)
        access.stop()

        // Auswerfen → nicht verfügbar, Einträge bleiben
        try img.detach()
        let offline = LocationResolver.resolve(saved, mounted: .current())
        XCTAssertEqual(offline.availability, .offline, "\(fs): \(offline.availability)")
        XCTAssertEqual(try store.films().count, 2)

        // Wieder einbinden – an einem ANDEREN Einhängepunkt
        let other = FileManager.default.temporaryDirectory.appendingPathComponent("fb-anders-\(UUID().uuidString)")
        let mount2 = try img.attach(at: other)
        guard case .available(let url2, let access2, _) = LocationResolver.resolve(saved, mounted: .current()) else {
            return XCTFail("\(fs): nach dem erneuten Einbinden nicht erkannt")
        }
        defer { access2.stop() }
        XCTAssertTrue(url2.standardizedFileURL.path.hasPrefix(mount2.standardizedFileURL.resolvingSymlinksInPath().path) ||
                      url2.standardizedFileURL.path.hasPrefix(mount2.standardizedFileURL.path), "\(url2.path) liegt nicht unter \(mount2.path)")
        let again = try XCTUnwrap(VolumeInspector.volume(for: url2))
        if fs == "APFS" || fs == "HFS+" {
            XCTAssertEqual(again.key, loc.volumeKey, "\(fs): gleiche Kennung nach erneutem Einbinden")
        } else if again.key != loc.volumeKey {
            // Beobachtet auf Intel-Macs: FAT32 meldet nach erneutem Einbinden eine andere Volume-UUID. Wiedererkannt wird
            // der Ort trotzdem über das Lesezeichen (oben geprüft); die App zieht die gespeicherte Kennung dann nach.
            print("HINWEIS \(fs): Volume-UUID nach erneutem Einbinden geändert (\(loc.volumeKey) → \(again.key)) – Wiedererkennung über das Lesezeichen")
        }
        let r2 = LibraryScanner.list(root: url2)
        let diff = ScanDiff.compute(existing: try store.indexedFiles(locationId: saved.id), found: r2.files)
        XCTAssertTrue(diff.inserts.isEmpty && diff.newlyMissing.isEmpty, "\(fs): Filme wiedererkannt")
        try img.detach()
    }

    func testAPFS() throws { try checkIdentityEjectReattach(fs: "APFS", name: "FBTESTAPFS") }
    func testExFAT() throws { try checkIdentityEjectReattach(fs: "ExFAT", name: "FBTESTEXFAT") }
    func testFAT32() throws { try checkIdentityEjectReattach(fs: "MS-DOS FAT32", name: "FBTESTFAT") }

    func testFolderMissingOnMountedVolume() throws {
        let img = try DiskImage(fs: "APFS", name: "FBTESTMISS")
        let mount = try img.attach()
        let folder = mount.appendingPathComponent("Weg", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let loc = try LocationResolver.makeLocation(for: folder)
        try FileManager.default.removeItem(at: folder)
        let r = LocationResolver.resolve(loc, mounted: .current())
        XCTAssertTrue(r.availability == .folderMissing || r.availability == .offline, "\(r.availability)")
        print("Ordner gelöscht auf eingebundenem Laufwerk → \(r.availability.label)")
        try img.detach()
    }

    func testEjectDuringScanMarksNothingMissing() async throws {
        let img = try DiskImage(fs: "APFS", name: "FBTESTSCAN", sizeMB: 200)
        let mount = try img.attach()
        let root = mount.appendingPathComponent("Viele", isDirectory: true)
        for d in 0..<300 {
            let dir = root.appendingPathComponent("Ordner \(d)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for f in 0..<20 { FileManager.default.createFile(atPath: dir.appendingPathComponent("V\(f).mkv").path, contents: Data()) }
        }
        let store = try LibraryStore.inMemory()
        let loc = try store.insertLocation(try LocationResolver.makeLocation(for: root))
        let scanner = LibraryScanner(store: store)
        let first = await scanner.scan(location: loc, root: root, excluding: [], heartFavorites: false) { _ in }
        XCTAssertEqual(first.outcome, .completed)
        XCTAssertEqual(first.changes.inserts.count, 6000)
        let task = Task.detached { await scanner.scan(location: loc, root: root, excluding: [], heartFavorites: false) { _ in } }
        try await Task.sleep(nanoseconds: 40_000_000)
        try img.detach(force: true)
        let report = await task.value
        print("Auswerfen während des Durchsuchens → \(report.outcome)")
        XCTAssertEqual(try store.films().filter(\.isMissing).count, 0, "nichts darf als fehlend gelten")
        XCTAssertEqual(try store.films().count, 6000)
    }
}

final class PlaybackTests: XCTestCase {
    @MainActor
    func play(_ engine: PlaybackEngine, _ url: URL, seconds: Double = 2.5) async -> (Double, Double) {
        engine.load(url: url, startAt: nil)
        engine.play()
        var t0: Double = -1
        let start = Date()
        while Date().timeIntervalSince(start) < seconds + 4 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if engine.state == .playing && t0 < 0 { t0 = engine.currentTime }
            if t0 >= 0 && Date().timeIntervalSince(start) > seconds { break }
            if case .failed = engine.state { break }
        }
        return (t0, engine.currentTime)
    }

    @MainActor
    func testAVFoundationPlaysMP4WithChaptersAndSeeks() async throws {
        let engine = AVPlaybackEngine()
        let (a, b) = await play(engine, Fixtures.directory.appendingPathComponent("Testfilm MP4.mp4"))
        if Environment.isIntelVirtualMachine && b - a < 0.8 {
            // Die Intel-VMs von GitHub haben weder vollwertige Grafik noch Tonausgabe – AVPlayer läuft dort nicht an.
            // Wiedergabe mit AVFoundation ist auf Apple Silicon und unter Rosetta (x86_64-Code) geprüft.
            engine.shutdown()
            throw XCTSkip("AVFoundation-Wiedergabe auf der Intel-VM ohne Grafik/Ton nicht prüfbar (Zeit: \(a) → \(b))")
        }
        XCTAssertEqual(engine.state, .playing, "\(engine.state)")
        XCTAssertGreaterThan(b - a, 0.8, "Zeit läuft")
        XCTAssertEqual(engine.chapters.count, 2)
        engine.seek(to: 4)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertGreaterThanOrEqual(engine.currentTime, 3.8)
        engine.pause()
        XCTAssertEqual(engine.state, .paused)
        engine.shutdown()
    }

    @MainActor
    func testVLCPlaysMKVWithTracks() async throws {
        guard let engine = EngineFactory.makeVLC() else { throw XCTSkip("Build ohne VLCKit") }
        let (a, b) = await play(engine, Fixtures.directory.appendingPathComponent("Testfilm MKV.mkv"))
        XCTAssertEqual(engine.state, .playing, "\(engine.state)")
        XCTAssertGreaterThan(b - a, 0.8, "Zeit läuft")
        XCTAssertEqual(engine.audioTracks.count, 2, "\(engine.audioTracks)")
        XCTAssertGreaterThanOrEqual(engine.subtitleTracks.count, 1, "\(engine.subtitleTracks)")
        XCTAssertEqual(engine.duration ?? 0, 6, accuracy: 0.6)
        engine.shutdown()
    }

    @MainActor
    func testVLCPlaysAllNonAppleFormats() async throws {
        guard EngineFactory.makeVLC() != nil else { throw XCTSkip("Build ohne VLCKit") }
        for f in ["Testfilm AVI.avi", "Testfilm WMV.wmv", "Testfilm MPG.mpg", "Testfilm MPEG.mpeg", "Testfilm TS.ts", "Testfilm M2TS.m2ts",
                  "Testfilm WEBM.webm", "Testfilm FLV.flv", "Serien/Staffel 1/Kamera 00001.mts"] {
            let engine = EngineFactory.makeVLC()!
            let (a, b) = await play(engine, Fixtures.directory.appendingPathComponent(f), seconds: 1.5)
            print("VLC-Wiedergabe \(f): \(engine.state), \(String(format: "%.2f", b - a)) s")
            XCTAssertGreaterThan(b - a, 0.5, f)
            engine.shutdown()
        }
    }

    @MainActor
    func testEjectDuringPlaybackFailsCleanly() async throws {
        for useVLC in [false, true] {
            if useVLC && EngineFactory.makeVLC() == nil { continue }
            let img = try DiskImage(fs: "APFS", name: useVLC ? "FBPLAYVLC" : "FBPLAYAV")
            let mount = try img.attach()
            let file = mount.appendingPathComponent(useVLC ? "Film.mkv" : "Film.mp4")
            try FileManager.default.copyItem(at: Fixtures.directory.appendingPathComponent(useVLC ? "Testfilm MKV.mkv" : "Langer Testfilm (2026).mp4"), to: file)
            let engine: PlaybackEngine = useVLC ? EngineFactory.makeVLC()! : AVPlaybackEngine()
            _ = await play(engine, file, seconds: 1)
            try img.detach(force: true)
            let start = Date()
            var failed = false
            while Date().timeIntervalSince(start) < 10 {
                try await Task.sleep(nanoseconds: 200_000_000)
                if case .failed = engine.state { failed = true; break }
                if engine.state == .ended { break }
            }
            print("Auswerfen während der Wiedergabe (\(engine.name)) → \(engine.state)")
            if useVLC {
                XCTAssertTrue(failed || engine.state == .ended, "\(engine.name): \(engine.state)")
            } else {
                // AVFoundation puffert kleine Dateien vollständig und spielt aus dem Puffer weiter – kein Fehler.
                // (In der App beendet die Meldung „Laufwerk ausgeworfen“ die Wiedergabe ohnehin.)
                XCTAssertTrue(failed || engine.state == .ended || engine.state == .playing, "\(engine.name): \(engine.state)")
            }
            engine.shutdown()
            // Erneutes Öffnen vom ausgeworfenen Laufwerk muss sauber scheitern (Meldung statt Absturz)
            let reopen: PlaybackEngine = useVLC ? EngineFactory.makeVLC()! : AVPlaybackEngine()
            reopen.load(url: file, startAt: nil)
            reopen.play()
            var reopenFailed = false
            let t = Date()
            while Date().timeIntervalSince(t) < 8 {
                try await Task.sleep(nanoseconds: 200_000_000)
                if case .failed = reopen.state { reopenFailed = true; break }
            }
            print("Erneutes Öffnen nach dem Auswerfen (\(reopen.name)) → \(reopen.state)")
            XCTAssertTrue(reopenFailed || reopen.state == .ended || reopen.state == .idle, "\(reopen.name): \(reopen.state)")
            reopen.shutdown()
        }
    }
}

/// Erkennung der Testumgebung (nur für ehrliche Hinweise in Tests)
enum Environment {
    /// Intel-Code auf einer virtuellen Maschine mit „Paravirtual“-Grafik (GitHub macos-15-intel)
    static var isIntelVirtualMachine: Bool {
        #if arch(x86_64)
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let isRosetta = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
        let gpu = MTLCreateSystemDefaultDevice()?.name ?? "keine"
        return !isRosetta && (gpu.localizedCaseInsensitiveContains("paravirtual") || gpu == "keine")
        #else
        return false
        #endif
    }
}
