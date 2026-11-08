import XCTest
@testable import FBCore

final class TitleAndPathTests: XCTestCase {
    func testSceneNameIsCleaned() {
        let r = TitleCleaner.compute("Alien.1979.1080p.BluRay.x264-GROUP.mkv")
        XCTAssertEqual(r.title, "Alien")
        XCTAssertEqual(r.year, 1979)
    }

    func testYearInParentheses() {
        let r = TitleCleaner.compute("Der_Pate_(1972).mp4")
        XCTAssertEqual(r.title, "Der Pate")
        XCTAssertEqual(r.year, 1972)
    }

    func testPlainNameStaysComplete() {
        XCTAssertEqual(TitleCleaner.compute("Urlaub Sommer 2024.mov").title, "Urlaub Sommer 2024")
        XCTAssertNil(TitleCleaner.compute("Urlaub Sommer 2024.mov").year)
        XCTAssertEqual(TitleCleaner.compute("Mein_Urlaub.mp4").title, "Mein Urlaub")
        XCTAssertEqual(TitleCleaner.compute("4K Naturfilm.mp4").title, "4K Naturfilm")
    }

    func testHeartMarker() {
        XCTAssertTrue(HeartMarker.hasMarker(fileName: "MeinVideo_Heart.mp4"))
        XCTAssertTrue(HeartMarker.hasMarker(fileName: "Film 2026HEART.mkv"))
        XCTAssertFalse(HeartMarker.hasMarker(fileName: "Heartbeat.mp4.part"))
        XCTAssertFalse(HeartMarker.hasMarker(fileName: "Heart of Glass.mp4"))
    }

    func testFormats() {
        for ext in ["mp4", "mkv", "mov", "avi", "m4v", "wmv", "mpg", "mpeg", "ts", "mts", "m2ts", "webm", "flv"] {
            XCTAssertTrue(VideoFormats.isVideo(fileName: "x.\(ext.uppercased())"), ext)
        }
        XCTAssertFalse(VideoFormats.isVideo(fileName: "poster.jpg"))
        XCTAssertFalse(VideoFormats.isVideo(fileName: ".mp4"))
        XCTAssertTrue(VideoFormats.prefersAVFoundation("MOV"))
        XCTAssertFalse(VideoFormats.prefersAVFoundation("mkv"))
    }

    func testRelativePaths() {
        XCTAssertEqual(RelativePath.relative("/Volumes/Filme/Sci-Fi/Alien.mkv", to: "/Volumes/Filme"), "Sci-Fi/Alien.mkv")
        XCTAssertEqual(RelativePath.relative("/Volumes/Filme", to: "/Volumes/Filme/"), "")
        XCTAssertNil(RelativePath.relative("/Volumes/Filme2/a.mkv", to: "/Volumes/Filme"))
        XCTAssertEqual(RelativePath.relative("/a/b", to: "/"), "a/b")
        XCTAssertNil(RelativePath.join("/x", "../etc/passwd"))
        XCTAssertNil(RelativePath.join("/x", "/abs"))
        XCTAssertEqual(RelativePath.join("/x", "a/b.mkv"), "/x/a/b.mkv")
        XCTAssertEqual(RelativePath.parent("a/b/c.mkv"), "a/b")
        XCTAssertEqual(RelativePath.fileExtension(".DS_Store"), "")
        XCTAssertEqual(RelativePath.stem("Film.de.srt"), "Film.de")
    }

    func testScanRules() {
        XCTAssertTrue(ScanRules.skipFile(named: "._Film.mp4"))
        XCTAssertTrue(ScanRules.skipFile(named: ".DS_Store"))
        XCTAssertTrue(ScanRules.skipDirectory(named: "$RECYCLE.BIN"))
        XCTAssertTrue(ScanRules.skipDirectory(named: "@eaDir"))
        XCTAssertTrue(ScanRules.skipDirectory(named: ".Trashes"))
        XCTAssertFalse(ScanRules.skipDirectory(named: "Filme"))
        XCTAssertTrue(ScanRules.isPartialDownload("Film.mp4.crdownload"))
    }

    func testResolutionClasses() {
        XCTAssertEqual(ResolutionClass(width: 3840, height: 2160), .uhd4k)
        XCTAssertEqual(ResolutionClass(width: 3840, height: 1600), .uhd4k)
        XCTAssertEqual(ResolutionClass(width: 1920, height: 800), .fullHD)
        XCTAssertEqual(ResolutionClass(width: 1080, height: 1920), .fullHD)
        XCTAssertEqual(ResolutionClass(width: 1280, height: 720), .hd)
        XCTAssertEqual(ResolutionClass(width: 720, height: 576), .sd)
        XCTAssertEqual(ResolutionClass(width: 7680, height: 4320), .uhd8k)
        XCTAssertNil(ResolutionClass(width: nil, height: 100))
    }
}

final class SearchFilterSortTests: XCTestCase {
    func film(_ id: Int64, _ path: String, size: Int64 = 1_000, duration: Double? = nil, w: Int? = nil, h: Int? = nil,
              fav: Bool = false, pos: Double = 0, finished: Bool = false, added: TimeInterval = 0, loc: Int64 = 1) -> Film {
        Film(id: id, locationId: loc, relativePath: path, sizeBytes: size, modifiedAt: nil, addedAt: Date(timeIntervalSince1970: added),
             info: VideoInfo(durationSeconds: duration, width: w, height: h), isFavorite: fav, positionSeconds: pos, finished: finished)
    }

    func testAndSearchWithExclusion() {
        let q = SearchQuery("alien  1979 -director")
        XCTAssertEqual(q.include, ["alien", "1979"])
        XCTAssertEqual(q.exclude, ["director"])
        XCTAssertTrue(q.matches(normalized: SearchQuery.normalize("Alien.1979.Theatrical.mkv")))
        XCTAssertFalse(q.matches(normalized: SearchQuery.normalize("Alien.1979.Directors.Cut.mkv")))
        XCTAssertFalse(q.matches(normalized: SearchQuery.normalize("Aliens.1986.mkv")))
    }

    func testQuotedPhraseAndUnicode() {
        let q = SearchQuery("\"der pate\" teil")
        XCTAssertEqual(q.include, ["der pate", "teil"])
        // NFD (Mac-Dateiname) findet NFC (Tastatur)
        let nfd = "U\u{0308}berraschung.mp4"
        XCTAssertTrue(SearchQuery("überraschung").matches(normalized: SearchQuery.normalize(nfd)))
        XCTAssertTrue(SearchQuery("-").isEmpty)
    }

    func testHaystackContainsFolderLocationAndMetadata() {
        let f = film(1, "Sci-Fi/Alien.1979.mkv", w: 3840, h: 2160)
        let hay = SearchIndex.haystack(for: f, locationName: "Filme SSD")
        for term in ["sci-fi", "alien", "mkv", "filme ssd", "4k", "3840x2160", "1979"] {
            XCTAssertTrue(hay.contains(term), term)
        }
    }

    func testFilters() {
        var filter = LibraryFilter()
        XCTAssertTrue(filter.isEmpty)
        let big = film(1, "a.mkv", size: 5_000_000_000, duration: 7200, w: 1920, h: 1080, fav: true)
        let small = film(2, "b.mp4", size: 100, duration: 600, w: 640, h: 360)
        filter.size = .from4GB
        XCTAssertTrue(filter.matches(big, isAvailable: true))
        XCTAssertFalse(filter.matches(small, isAvailable: true))
        filter = LibraryFilter()
        filter.resolutions = [.fullHD]
        filter.extensions = ["mkv"]
        XCTAssertTrue(filter.matches(big, isAvailable: true))
        XCTAssertFalse(filter.matches(small, isAvailable: true))
        filter = LibraryFilter()
        filter.availability = .unavailable
        XCTAssertTrue(filter.matches(small, isAvailable: false))
        XCTAssertFalse(filter.matches(small, isAvailable: true))
        filter = LibraryFilter()
        filter.duration = .from90to150
        XCTAssertTrue(filter.matches(big, isAvailable: true))
        XCTAssertFalse(filter.matches(film(3, "c.mkv"), isAvailable: true), "unbekannte Dauer passt nur zu „Alle“")
        XCTAssertEqual(filter.activeCount, 1)
    }

    func testPlaybackStatusAndScopes() {
        let started = film(1, "a.mkv", duration: 6000, pos: 1200)
        let nearEnd = film(2, "b.mkv", duration: 6000, pos: 5995)
        let fresh = film(3, "c.mkv", duration: 6000)
        let done = film(4, "d.mkv", duration: 6000, finished: true)
        XCTAssertEqual(started.playbackStatus, .inProgress)
        XCTAssertEqual(nearEnd.playbackStatus, .unwatched)
        XCTAssertEqual(fresh.playbackStatus, .unwatched)
        XCTAssertEqual(done.playbackStatus, .finished)
        XCTAssertTrue(LibraryScope.continueWatching.contains(started, collections: [:], isAvailable: true))
        XCTAssertFalse(LibraryScope.continueWatching.contains(done, collections: [:], isAvailable: true))
        let inFolder = film(5, "Serien/Staffel 1/E1.mkv")
        XCTAssertTrue(LibraryScope.folder(location: 1, path: "Serien").contains(inFolder, collections: [:], isAvailable: true))
        XCTAssertFalse(LibraryScope.folder(location: 1, path: "Seri").contains(inFolder, collections: [:], isAvailable: true))
        XCTAssertTrue(LibraryScope.collection(9).contains(inFolder, collections: [9: [5]], isAvailable: true))
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        XCTAssertTrue(LibraryScope.recentlyAdded.contains(film(6, "x.mkv", added: 99 * 86_400), collections: [:], isAvailable: true, now: now))
        XCTAssertFalse(LibraryScope.recentlyAdded.contains(film(7, "y.mkv", added: 10 * 86_400), collections: [:], isAvailable: true, now: now))
    }

    func testNaturalSortAndTies() {
        let list = [film(1, "Folge 10.mkv"), film(2, "Folge 2.mkv"), film(3, "folge 1.mkv")]
        let sorted = LibrarySorter.sort(list, by: LibrarySortOrder(key: .title, ascending: true))
        XCTAssertEqual(sorted.map(\.id), [3, 2, 1])
        let bySize = LibrarySorter.sort([film(1, "a", size: 5), film(2, "b", size: 9), film(3, "c", size: 5)], by: LibrarySortOrder(key: .size, ascending: false))
        XCTAssertEqual(bySize.map(\.id), [2, 1, 3])
        let byDuration = LibrarySorter.sort([film(1, "a", duration: nil), film(2, "b", duration: 10)], by: LibrarySortOrder(key: .duration, ascending: false))
        XCTAssertEqual(byDuration.map(\.id), [2, 1], "unbekannte Dauer steht absteigend am Ende")
    }
}

final class ResumeAndQueueTests: XCTestCase {
    func testResumeRules() {
        XCTAssertEqual(ResumePolicy.decide(position: 5, duration: 6000, storedSize: nil, currentSize: nil), .startFromBeginning)
        XCTAssertEqual(ResumePolicy.decide(position: 600, duration: 6000, storedSize: 10, currentSize: 10), .offerResume(at: 600))
        XCTAssertEqual(ResumePolicy.decide(position: 600, duration: 6000, storedSize: 10, currentSize: 11), .startFromBeginning, "Datei ersetzt")
        XCTAssertEqual(ResumePolicy.decide(position: 5990, duration: 6000, storedSize: nil, currentSize: nil), .startFromBeginning, "kurz vor Ende")
        XCTAssertTrue(ResumePolicy.isNearEnd(position: 5830, duration: 6000), "letzte 3 %")
        XCTAssertFalse(ResumePolicy.isNearEnd(position: 5700, duration: 6000))
        XCTAssertTrue(ResumePolicy.shouldStore(position: 12, duration: nil))
        XCTAssertEqual(ResumePolicy.decide(position: .nan, duration: 100, storedSize: nil, currentSize: nil), .startFromBeginning)
    }

    func testSeekClamp() {
        XCTAssertEqual(SeekMath.clamp(-20, duration: 100), 0)
        XCTAssertEqual(SeekMath.clamp(500, duration: 100), 99.75)
        XCTAssertEqual(SeekMath.clamp(50, duration: nil), 50)
        XCTAssertEqual(SeekMath.speedLabel(1.25), "1,25×")
        XCTAssertEqual(SeekMath.speedLabel(1), "1,0×")
    }

    func testQueue() {
        var q = PlayQueue(ids: [1, 2, 3], startAt: 2)
        XCTAssertEqual(q.current, 2)
        XCTAssertEqual(q.next(), 3)
        XCTAssertNil(q.next())
        XCTAssertEqual(q.previous(), 2)
        q.repeatMode = .all
        XCTAssertEqual(q.next(), 3)
        XCTAssertEqual(q.next(), 1)
        XCTAssertEqual(q.previous(), 3)
        q.repeatMode = .one
        XCTAssertEqual(q.advanceAfterEnd(), 3)
        q.remove(3)
        XCTAssertEqual(q.order, [1, 2])
    }

    func testShuffleKeepsCurrentFirstAndRestores() {
        var q = PlayQueue(ids: Array(1...20), startAt: 7)
        q.setShuffle(true, seed: 42)
        XCTAssertEqual(q.current, 7)
        XCTAssertEqual(q.order.first, 7)
        XCTAssertEqual(Set(q.order), Set(1...20))
        XCTAssertNotEqual(q.order, [7] + Array(1...20).filter { $0 != 7 })
        q.setShuffle(false)
        XCTAssertEqual(q.order, Array(1...20))
        XCTAssertEqual(q.current, 7)
    }
}

final class ScanDiffTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func idx(_ id: Int64, _ path: String, _ size: Int64 = 100, ino: UInt64? = nil, missing: Bool = false, t: Date? = nil) -> IndexedFile {
        IndexedFile(id: id, relativePath: path, sizeBytes: size, modifiedAt: t ?? t0, fileId: ino, isMissing: missing)
    }

    func found(_ path: String, _ size: Int64 = 100, ino: UInt64? = nil, t: Date? = nil) -> FoundFile {
        FoundFile(relativePath: path, sizeBytes: size, modifiedAt: t ?? t0, createdAt: nil, fileId: ino)
    }

    func testFirstScanInsertsAll() {
        let c = ScanDiff.compute(existing: [], found: [found("a.mkv"), found("b/c.mp4")])
        XCTAssertEqual(c.inserts.count, 2)
        XCTAssertTrue(c.newlyMissing.isEmpty)
    }

    func testUnchangedRescanIsEmpty() {
        let c = ScanDiff.compute(existing: [idx(1, "a.mkv", ino: 5)], found: [found("a.mkv", ino: 5)])
        XCTAssertTrue(c.isEmpty)
        XCTAssertEqual(c.unchanged, 1)
    }

    func testFatTimeToleranceIsUnchanged() {
        let c = ScanDiff.compute(existing: [idx(1, "a.mkv")], found: [found("a.mkv", t: t0.addingTimeInterval(1.5))])
        XCTAssertTrue(c.updates.isEmpty)
    }

    func testChangedContentIsUpdate() {
        let c = ScanDiff.compute(existing: [idx(1, "a.mkv", 100)], found: [found("a.mkv", 200)])
        XCTAssertEqual(c.updates, [ScanUpdate(id: 1, file: found("a.mkv", 200), contentChanged: true)])
    }

    func testRenameDetectedByInode() {
        let c = ScanDiff.compute(existing: [idx(1, "alt.mkv", ino: 77)], found: [found("neu.mkv", ino: 77)])
        XCTAssertEqual(c.moves.map(\.id), [1])
        XCTAssertTrue(c.inserts.isEmpty)
        XCTAssertTrue(c.newlyMissing.isEmpty)
    }

    func testMoveDetectedByNameSizeTime() {
        let c = ScanDiff.compute(existing: [idx(1, "a/Film.mkv", 500, ino: 1)], found: [found("b/Film.mkv", 500, ino: 2)])
        XCTAssertEqual(c.moves.map(\.id), [1])
    }

    func testMissingIsMarkedNotDeleted() {
        let c = ScanDiff.compute(existing: [idx(1, "a.mkv"), idx(2, "b.mkv")], found: [found("a.mkv")])
        XCTAssertEqual(c.newlyMissing, [2])
        let again = ScanDiff.compute(existing: [idx(1, "a.mkv"), idx(2, "b.mkv", missing: true)], found: [found("a.mkv")])
        XCTAssertTrue(again.newlyMissing.isEmpty, "bereits als fehlend markiert")
    }

    func testReappeared() {
        let c = ScanDiff.compute(existing: [idx(2, "b.mkv", missing: true)], found: [found("b.mkv")])
        XCTAssertEqual(c.reappeared, [2])
    }

    func testUnreadableFolderProtectsEntries() {
        let c = ScanDiff.compute(existing: [idx(1, "Privat/a.mkv"), idx(2, "Offen/b.mkv")], found: [found("Offen/b.mkv")], protectedPrefixes: ["Privat"])
        XCTAssertTrue(c.newlyMissing.isEmpty)
        let root = ScanDiff.compute(existing: [idx(1, "a.mkv")], found: [], protectedPrefixes: [""])
        XCTAssertTrue(root.newlyMissing.isEmpty)
    }
}

final class VolumeAndSidecarTests: XCTestCase {
    func testVolumeIdentityPrefersUUID() {
        let f = VolumeIdentity.Facts(uuid: "ab12-cd", remountURL: "smb://x/y", name: "NO NAME", isLocal: true)
        XCTAssertEqual(VolumeIdentity.from(f).key, "uuid:AB12-CD")
        XCTAssertEqual(VolumeIdentity(key: "uuid:AB12-CD"), VolumeIdentity(kind: .uuid, value: "AB12-CD"))
    }

    func testNetworkIdentityWithoutCredentials() {
        let f = VolumeIdentity.Facts(uuid: nil, remountURL: "smb://anna:geheim@NAS.local/Filme/", name: "Filme", isLocal: false)
        let id = VolumeIdentity.from(f)
        XCTAssertEqual(id.kind, .network)
        XCTAssertEqual(id.value, "smb://nas.local/Filme")
        XCTAssertFalse(id.key.contains("geheim"))
    }

    func testFingerprintIsNotNameOnlyWhenFactsExist() {
        let a = VolumeIdentity.from(.init(uuid: nil, name: "NO NAME", totalCapacity: 32_000_000_000, fileSystem: "MS-DOS", creationDate: Date(timeIntervalSince1970: 5)))
        let b = VolumeIdentity.from(.init(uuid: nil, name: "NO NAME", totalCapacity: 64_000_000_000, fileSystem: "MS-DOS", creationDate: Date(timeIntervalSince1970: 5)))
        XCTAssertNotEqual(a, b, "gleicher Name, verschiedene Laufwerke")
        XCTAssertFalse(a.value.contains("NO NAME"))
    }

    func testKinds() {
        XCTAssertEqual(VolumeIdentity.kind(of: .init(isLocal: false)), .network)
        XCTAssertEqual(VolumeIdentity.kind(of: .init(isLocal: true, isInternal: true)), .internalDisk)
        XCTAssertEqual(VolumeIdentity.kind(of: .init(isLocal: true, isInternal: false, isRemovable: true, isEjectable: true)), .removable)
        XCTAssertEqual(VolumeIdentity.kind(of: .init(isLocal: true, isInternal: false, isRemovable: false, isEjectable: true)), .externalDisk)
    }

    func testPosterOnlyForSingleFilmFolders() {
        let names = ["Alien.mkv", "poster.jpg", "Aliens.mkv"]
        XCTAssertNil(SidecarFiles.posterCandidate(filmFileName: "Alien.mkv", siblingNames: names, videosInFolder: 2))
        XCTAssertEqual(SidecarFiles.posterCandidate(filmFileName: "Alien.mkv", siblingNames: ["Alien.mkv", "Poster.JPG"], videosInFolder: 1), "Poster.JPG")
        XCTAssertEqual(SidecarFiles.posterCandidate(filmFileName: "Alien.mkv", siblingNames: names + ["Alien-poster.png"], videosInFolder: 2), "Alien-poster.png")
        XCTAssertEqual(SidecarFiles.posterCandidate(filmFileName: "Alien.mkv", siblingNames: ["alien.jpg", "Alien.mkv"], videosInFolder: 1), "alien.jpg")
    }

    func testSubtitleCandidates() {
        let names = ["Film.mkv", "Film.srt", "Film.de.srt", "Film 2.srt", "Filmabend.srt", "Film.idx", "Film.en.forced.ass"]
        XCTAssertEqual(SidecarFiles.subtitleCandidates(filmFileName: "Film.mkv", siblingNames: names), ["Film.de.srt", "Film.en.forced.ass", "Film.srt"])
        XCTAssertEqual(SidecarFiles.subtitleLanguage(fileName: "Film.de.srt", filmFileName: "Film.mkv"), "de")
        XCTAssertNil(SidecarFiles.subtitleLanguage(fileName: "Film.srt", filmFileName: "Film.mkv"))
    }

    func testSubtitleParser() {
        let srt = "1\r\n00:00:00,500 --> 00:00:02,500\r\n<i>Erster</i> Untertitel\r\n\r\n2\r\n00:00:03,000 --> 00:00:05,500\r\nZweiter {\\an8}Untertitel\r\n"
        let cues = SubtitleParser.parse(srt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0], SubtitleCue(start: 0.5, end: 2.5, text: "Erster Untertitel"))
        XCTAssertEqual(cues[1].text, "Zweiter Untertitel")
        XCTAssertEqual(SubtitleParser.text(at: 1, in: cues), "Erster Untertitel")
        XCTAssertNil(SubtitleParser.text(at: 2.8, in: cues))
        let vtt = "WEBVTT\n\n00:01.000 --> 00:02.000 align:center\nHallo\n"
        XCTAssertEqual(SubtitleParser.parse(vtt), [SubtitleCue(start: 1, end: 2, text: "Hallo")])
        XCTAssertEqual(SubtitleParser.parseTime("01:02:03,250"), 3723.25)
        XCTAssertNil(SubtitleParser.parseTime("abc"))
    }
}

final class FormattingTests: XCTestCase {
    func testClockAndRuntime() {
        XCTAssertEqual(Fmt.clock(3723), "1:02:03")
        XCTAssertEqual(Fmt.clock(65), "1:05")
        XCTAssertEqual(Fmt.clock(nil), "–:––")
        XCTAssertEqual(Fmt.runtime(6720), "1 Std. 52 Min.")
        XCTAssertEqual(Fmt.runtime(2820), "47 Min.")
        XCTAssertEqual(Fmt.runtime(35), "35 Sek.")
        XCTAssertEqual(Fmt.runtime(3600), "1 Std.")
    }

    func testAspectAndCodecs() {
        XCTAssertEqual(Fmt.aspectRatio(1920, 1080), "16:9")
        XCTAssertEqual(Fmt.aspectRatio(1920, 804), "2,39:1")
        XCTAssertEqual(Fmt.aspectRatio(720, 576), "5:4")
        XCTAssertEqual(Fmt.aspectRatio(1000, 333), "3,0:1".replacingOccurrences(of: ",0", with: ""))
        XCTAssertEqual(Fmt.codecName("avc1"), "H.264")
        XCTAssertEqual(Fmt.codecName("hvc1"), "HEVC (H.265)")
        XCTAssertEqual(Fmt.codecName("xyz9"), "XYZ9")
        XCTAssertNil(Fmt.codecName("  "))
        XCTAssertEqual(Fmt.frameRate(23.976), "23,976 fps")
    }
}

final class ContainerSnifferTests: XCTestCase {
    func testProgramStream() {
        XCTAssertEqual(ContainerSniffer.sniff([0, 0, 1, 0xBA, 0x44]), .mpegProgramStream)
        XCTAssertEqual(ContainerSniffer.sniff([0, 0, 1, 0xB3, 0x14]), .mpegProgramStream)
    }

    func testTransportStreams() {
        var ts = [UInt8](repeating: 0, count: 188 * 6)
        for i in 0..<6 { ts[i * 188] = 0x47 }
        XCTAssertEqual(ContainerSniffer.sniff(ts), .mpegTransportStream)
        var m2ts = [UInt8](repeating: 0, count: 192 * 6)
        for i in 0..<6 { m2ts[4 + i * 192] = 0x47 }
        XCTAssertEqual(ContainerSniffer.sniff(m2ts), .m2ts)
    }

    func testOtherDataIsNotRecognized() {
        XCTAssertNil(ContainerSniffer.sniff(Array("Das ist kein Video.".utf8)))
        XCTAssertNil(ContainerSniffer.sniff([]))
        var almost = [UInt8](repeating: 0, count: 188 * 6)
        for i in 0..<4 { almost[i * 188] = 0x47 }
        XCTAssertNil(ContainerSniffer.sniff(almost), "4 Sync-Bytes reichen nicht")
    }
}
