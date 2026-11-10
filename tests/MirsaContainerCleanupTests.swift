import XCTest
import Darwin
@testable import Mirsa

final class MirsaContainerCleanupTests: XCTestCase {
    private let fm = FileManager.default
    private var base: URL!
    private var tmp: URL!
    private var cache: URL!
    override func setUpWithError() throws {
        base = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("container-clean-" + UUID().uuidString)
        tmp = base.appendingPathComponent("tmp")
        cache = base.appendingPathComponent("Caches")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
    }
    override func tearDown() { try? fm.removeItem(at: base) }
    @discardableResult private func file(_ relative: String, under root: URL? = nil, bytes: Int = 31) throws -> URL {
        let url = (root ?? tmp!).appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
        return url
    }
    private func scan(_ root: URL? = nil, scope: MirsaContainerCleanup.Scope = .temporary,
                      delete: Bool = true, protected: Set<String> = [],
                      cutoff: Date = Date().addingTimeInterval(60),
                      race: ((URL) -> Void)? = nil) -> MirsaContainerCleanup.Result {
        MirsaContainerCleanup.scan(root: root ?? tmp, scope: scope, delete: delete,
            cutoff: cutoff, protectedPaths: protected, now: Date().addingTimeInterval(120), beforeDelete: race)
    }
    func testWholeTmpCountsRootHiddenIPAsAndNestedUnzipSigningLeftovers() throws {
        let files = try [file("old.ipa", bytes: 101), file(".abandoned.zip", bytes: 102),
                         file("unzip/Payload/App.app/executable", bytes: 103),
                         file("sign-previous/out.ipa", bytes: 104)]
        XCTAssertEqual(scan(delete: false).bytes, 410)
        XCTAssertEqual(scan().removed, 4)
        files.forEach { XCTAssertFalse(fm.fileExists(atPath: $0.path)) }
        XCTAssertEqual(scan(delete: false).bytes, 0)
    }
    func testOnlyDisposableCachesAndNoSystemDatabases() throws {
        let ipa = try file("old.ipa", under: cache, bytes: 100)
        let extracted = try file("unzip-old/Payload/App.app/bin", under: cache, bytes: 200)
        let saved = try file("com.apple.URLSession/Cache.db", under: cache)
        let wal = try file("Cache.db-wal", under: cache)
        let unknown = try file("unknown-service/file", under: cache)
        let webkit = try file("WebKit/data", under: cache)
        XCTAssertEqual(scan(cache, scope: .caches, delete: false).bytes, 300)
        XCTAssertEqual(scan(cache, scope: .caches).removed, 2)
        for url in [saved, wal, unknown, webkit] { XCTAssertTrue(fm.fileExists(atPath: url.path)) }
        for url in [ipa, extracted] { XCTAssertFalse(fm.fileExists(atPath: url.path)) }
    }
    func testPersistentLibraryProjectsSavedIPAsAndColdLaunchInboxSurvive() throws {
        var protectedFiles: [URL] = []
        for name in ["Library", "Documents", "Projects", "SavedIPAs", "Downloads", "Originals",
                     "MirsaSignedExports", "com.alaa.mirsa-Inbox", "Backups", "AirCardApps",
                     "CFNetworkDownload_pending.tmp", "NSIRD_pending", "MirsaPersonalApps", "MirsaTweakLibrary"] {
            protectedFiles.append(try file(name + "/keep.ipa"))
        }
        let actualLibrary = try file("Library/Application Support/MirsaProjects/project.ipa", under: base)
        XCTAssertEqual(scan(delete: false).bytes, 0)
        XCTAssertEqual(scan().removed, 0)
        for url in protectedFiles + [actualLibrary] { XCTAssertEqual(try Data(contentsOf: url).count, 31) }
    }
    func testActiveAndConsumerLeasesProtectWholeSubtree() throws {
        let active = try file("job/nested/file.ipa")
        let other = try file("inactive.ipa")
        let lease = active.deletingLastPathComponent().deletingLastPathComponent().path
        XCTAssertEqual(scan(protected: [lease]).removed, 1)
        XCTAssertTrue(fm.fileExists(atPath: active.path)); XCTAssertFalse(fm.fileExists(atPath: other.path))
        XCTAssertEqual(scan(protected: [active.path]).removed, 0)
        XCTAssertEqual(scan().removed, 1)
    }
    func testUnregisteredCurrentProcessFilesFailClosedDespiteOldMtime() throws {
        let new = try file("legacy-operation/out.ipa")
        try fm.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: new.path)
        XCTAssertEqual(scan(cutoff: Date.distantPast).removed, 0)
        XCTAssertTrue(fm.fileExists(atPath: new.path))
    }
    func testOpenInUseFileIsNotUnlinked() throws {
        let inUse = try file("active-download.ipa")
        let descriptor = open(inUse.path, O_RDONLY)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        XCTAssertEqual(scan().removed, 0)
        XCTAssertTrue(fm.fileExists(atPath: inUse.path))
    }
    func testOutsideSymlinkTargetsAndAncestorLinksFailClosed() throws {
        let outside = try file("outside/keep.ipa", under: base, bytes: 1_000)
        try fm.createSymbolicLink(at: tmp.appendingPathComponent("escape"), withDestinationURL: outside.deletingLastPathComponent())
        let own = try file("real.ipa", bytes: 10)
        XCTAssertEqual(scan(delete: false).bytes, 10)
        XCTAssertEqual(scan().removed, 1)
        XCTAssertFalse(fm.fileExists(atPath: own.path))
        XCTAssertEqual(try Data(contentsOf: outside).count, 1_000)
        XCTAssertEqual(scan(tmp.appendingPathComponent("escape")).removed, 0)
        XCTAssertEqual(scan(tmp.appendingPathComponent("escape")).bytes, 0)
    }
    func testFileReplacementRaceDoesNotDeleteSymlinkOrOutsideTarget() throws {
        let victim = try file("stale.ipa")
        let outside = try file("outside.ipa", under: base, bytes: 99)
        var raced = false
        XCTAssertEqual(scan(race: { url in
            guard url == victim else { return }
            try! self.fm.removeItem(at: url)
            try! self.fm.createSymbolicLink(at: url, withDestinationURL: outside)
            raced = true
        }).removed, 0)
        XCTAssertTrue(raced)
        XCTAssertEqual(try Data(contentsOf: outside).count, 99)
    }
    func testModifiedFileRaceFailsClosed() throws {
        let victim = try file("stale.ipa")
        XCTAssertEqual(scan(race: { url in
            if url == victim { try! Data(count: 42).write(to: url) }
        }).removed, 0)
        XCTAssertEqual(try Data(contentsOf: victim).count, 42)
    }
    func testMovedAncestorRaceDoesNotSweepDetachedTree() throws {
        let victim = try file("extract/file.ipa")
        let parent = victim.deletingLastPathComponent()
        let moved = base.appendingPathComponent("moved")
        XCTAssertEqual(scan(race: { url in
            if url == victim { try! self.fm.moveItem(at: parent, to: moved) }
        }).removed, 0)
        XCTAssertTrue(fm.fileExists(atPath: moved.appendingPathComponent("file.ipa").path))
    }
    func testClockRollbackAndRootSymlinkAreNeverCleaned() throws {
        let original = try file("old.ipa")
        let rootLink = base.appendingPathComponent("tmp-link")
        try fm.createSymbolicLink(at: rootLink, withDestinationURL: tmp)
        XCTAssertEqual(scan(rootLink).removed, 0)
        let result = MirsaContainerCleanup.scan(root: tmp, scope: .temporary, delete: true,
            cutoff: Date().addingTimeInterval(60), protectedPaths: [], now: Date.distantPast)
        XCTAssertEqual(result.removed, 0)
        XCTAssertTrue(fm.fileExists(atPath: original.path))
    }
}
