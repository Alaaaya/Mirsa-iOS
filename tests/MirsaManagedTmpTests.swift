import XCTest
@testable import Mirsa

final class MirsaManagedTmpTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default
    override func setUp() {
        root = fm.temporaryDirectory.appendingPathComponent("mt-test-" + UUID().uuidString, isDirectory: true)
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? fm.removeItem(at: root) }
    private func age(_ u: URL, hours: Double) {
        try! fm.setAttributes([.modificationDate: Date().addingTimeInterval(-hours * 3600)], ofItemAtPath: u.path)
    }
    private func exists(_ u: URL) -> Bool { fm.fileExists(atPath: u.path) }

    func testDownloadCleanupPreservesPendingOriginalAcrossDarwinAliases() throws {
        let download = try MirsaManagedTmp.begin("url-regression")
        let pending = try MirsaManagedTmp.begin("import-regression")
        defer { MirsaManagedTmp.end(download); MirsaManagedTmp.end(pending) }
        let ipa = pending.appendingPathComponent("original.ipa")
        try Data("pending archive".utf8).write(to: ipa)
        let canonical = MirsaContainerCleanup.canonicalDarwinPath(pending)
        XCTAssertTrue(MirsaManagedTmp.isActive(canonical))
        if canonical.hasPrefix("/private/var/") {
            XCTAssertTrue(MirsaManagedTmp.isActive(String(canonical.dropFirst("/private".count))))
        }
        MirsaManagedTmp.end(download)
        MirsaManagedTmp.cleanNow()
        XCTAssertEqual(try Data(contentsOf: ipa), Data("pending archive".utf8))
    }

    func testSuccessAndThrowingFailureReleaseOwnership() throws {
        let success = try MirsaManagedTmp.begin("ok", root: root)
        MirsaManagedTmp.end(success, root: root)
        XCTAssertFalse(exists(success))
        var failed: URL?
        func operation() throws {
            let d = try MirsaManagedTmp.begin("fail", root: root); failed = d
            defer { MirsaManagedTmp.end(d, root: root) }
            try Data(count: 100).write(to: d.appendingPathComponent("file"))
            throw CocoaError(.fileReadCorruptFile)
        }
        XCTAssertThrowsError(try operation())
        XCTAssertFalse(exists(try XCTUnwrap(failed)))
        MirsaManagedTmp.end(success, root: root)
    }

    func testCancellationUnwindsAfterConsumerStops() async throws {
        let d = try MirsaManagedTmp.begin("cancel", root: root)
        let started = expectation(description: "started")
        let task = Task {
            defer { MirsaManagedTmp.end(d, root: root) }
            started.fulfill()
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
        await fulfillment(of: [started], timeout: 5)
        MirsaManagedTmp.sweep(maxAge: -1, root: root)
        XCTAssertTrue(exists(d))
        task.cancel()
        do { try await task.value; XCTFail("must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(exists(d))
    }

    func testActiveAndSeparatelyServedExpiry() throws {
        let active = try MirsaManagedTmp.begin("active", root: root); age(active, hours: 5)
        let served = try MirsaManagedTmp.begin("served", root: root); age(served, hours: 5)
        let now = Date()
        MirsaManagedTmp.markServed(served, until: now.addingTimeInterval(600), root: root)
        XCTAssertEqual(MirsaManagedTmp.sweep(maxAge: -1, now: now, root: root), 0)
        XCTAssertEqual(MirsaManagedTmp.sweep(maxAge: -1, now: now.addingTimeInterval(601), root: root), 1)
        XCTAssertTrue(exists(active)); XCTAssertFalse(exists(served))
        MirsaManagedTmp.end(active, root: root)
    }

    func testConcurrentBeginSweepAndEnd() throws {
        let base = root!
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            do {
                let d = try MirsaManagedTmp.begin("concurrent", root: base)
                defer { MirsaManagedTmp.end(d, root: base) }
                try Data(count: 100).write(to: d.appendingPathComponent("f"))
                MirsaManagedTmp.sweep(maxAge: -1, root: base)
                XCTAssertTrue(exists(d))
            } catch { XCTFail("workspace failed: \(error)") }
        }
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: base.path).count, 0)
    }

    func testRootAndAncestorSymlinksFailClosed() throws {
        let user = root.appendingPathComponent("Projects")
        try fm.createDirectory(at: user, withIntermediateDirectories: true)
        let precious = user.appendingPathComponent("archive.ipa")
        try Data(count: 300).write(to: precious)
        let link = root.appendingPathComponent("root-link")
        try fm.createSymbolicLink(at: link, withDestinationURL: user)
        XCTAssertThrowsError(try MirsaManagedTmp.begin("bad", root: link))
        XCTAssertThrowsError(try MirsaManagedTmp.begin("bad", root: link.appendingPathComponent("nested")))
        XCTAssertEqual(MirsaManagedTmp.sweep(maxAge: -1, root: link), 0)
        XCTAssertEqual(MirsaManagedTmp.size(root: link), 0)
        MirsaManagedTmp.end(precious, root: link)
        XCTAssertEqual(try Data(contentsOf: precious).count, 300)
    }

    func testChildLinksAndSizeNeverFollowUserTargets() throws {
        let user = fm.temporaryDirectory.appendingPathComponent("user-" + UUID().uuidString)
        try fm.createDirectory(at: user, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: user) }
        let precious = user.appendingPathComponent("library.ipa")
        try Data(count: 50_000).write(to: precious)
        let d = try MirsaManagedTmp.begin("owned", root: root)
        defer { MirsaManagedTmp.end(d, root: root) }
        try Data(count: 20).write(to: d.appendingPathComponent("actual"))
        try fm.createSymbolicLink(at: d.appendingPathComponent("nested"), withDestinationURL: user)
        let link = root.appendingPathComponent("direct-link")
        try fm.createSymbolicLink(at: link, withDestinationURL: user)
        XCTAssertFalse(MirsaManagedTmp.isOwned(link, root: root))
        XCTAssertEqual(MirsaManagedTmp.size(root: root), 20)
        MirsaManagedTmp.end(user, root: root)
        MirsaManagedTmp.end(link, root: root)
        MirsaManagedTmp.sweep(maxAge: -1, root: root)
        XCTAssertEqual(try Data(contentsOf: precious).count, 50_000)
    }

    func testSizeCountsNestedSiblingsBesideLinksInAnyCreationOrder() throws {
        let user = fm.temporaryDirectory.appendingPathComponent("user-" + UUID().uuidString)
        try fm.createDirectory(at: user, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: user) }
        try Data(count: 50_000).write(to: user.appendingPathComponent("original.ipa"))
        for linkFirst in [true, false] {
            let d = try MirsaManagedTmp.begin("size-order", root: root)
            let link = d.appendingPathComponent("link")
            if linkFirst { try fm.createSymbolicLink(at: link, withDestinationURL: user) }
            let nested = d.appendingPathComponent("nested/deeper")
            try fm.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data(count: 31).write(to: nested.appendingPathComponent("file"))
            try Data(count: 20).write(to: d.appendingPathComponent("sibling"))
            if !linkFirst { try fm.createSymbolicLink(at: link, withDestinationURL: user) }
            XCTAssertEqual(MirsaManagedTmp.size(root: root), 51)
            MirsaManagedTmp.end(d, root: root)
            XCTAssertEqual(MirsaManagedTmp.size(root: root), 0)
            XCTAssertEqual(try Data(contentsOf: user.appendingPathComponent("original.ipa")).count, 50_000)
        }
    }

    func testStalePersistenceAndDistinctRootOwnership() throws {
        let old = root.appendingPathComponent("old-run")
        try fm.createDirectory(at: old, withIntermediateDirectories: true); age(old, hours: 2)
        let d = try MirsaManagedTmp.begin("new", root: root)
        defer { MirsaManagedTmp.end(d, root: root) }
        MirsaManagedTmp.end(d, root: root.appendingPathComponent("wrong-root"))
        XCTAssertTrue(MirsaManagedTmp.isActive(d.path))
        XCTAssertEqual(MirsaManagedTmp.sweep(root: root), 1)
        XCTAssertTrue(exists(d)); XCTAssertFalse(exists(old))
    }

    func testRetainedOTAArchiveSurvivesCleaning() throws {
        let work = try MirsaManagedTmp.begin("retain-fixture")
        defer { MirsaManagedTmp.end(work) }
        let input = work.appendingPathComponent("Fixture.ipa")
        try Data(count: 200).write(to: input)
        let retained = try CertificateInstall.retain(input)
        defer { try? fm.removeItem(at: retained.deletingLastPathComponent()) }
        XCTAssertFalse(exists(work))
        MirsaManagedTmp.cleanNow()
        XCTAssertEqual(try Data(contentsOf: retained).count, 200)
        XCTAssertFalse(MirsaManagedTmp.isOwned(retained.deletingLastPathComponent()))
    }

    @MainActor
    func testFailedImportKeepsSourceAndReleasesWorkspace() async throws {
        let store = AppsStore.shared
        let source = root.appendingPathComponent("user-original.ipa")
        try Data("not an archive".utf8).write(to: source)
        // The app's discovery tasks share the global root and can legitimately
        // create/end their own workspaces while import awaits its worker.
        // Snapshot only this operation type, never unrelated global tmp state.
        func importWorkspaces() -> Set<String> {
            Set(((try? fm.contentsOfDirectory(atPath: MirsaManagedTmp.root.path)) ?? [])
                .filter { $0.hasPrefix("import-") })
        }
        let unrelated = try MirsaManagedTmp.begin("discovery-test")
        defer { MirsaManagedTmp.end(unrelated) }
        let before = importWorkspaces()
        await store.importIPA(from: source)
        XCTAssertNotNil(store.error); XCTAssertNil(store.pending)
        XCTAssertTrue(exists(source))
        let after = importWorkspaces()
        XCTAssertEqual(before, after)
        XCTAssertTrue(exists(unrelated))
        XCTAssertTrue(MirsaManagedTmp.isActive(unrelated.path))
        XCTAssertEqual(try Data(contentsOf: source), Data("not an archive".utf8))
        store.error = nil
    }

    @MainActor
    func testPendingCancelAndFailedCommitReleaseAndBusyEditorIsProtected() async throws {
        let store = AppsStore.shared
        XCTAssertNil(store.pending); XCTAssertNil(store.busy)
        let d = try MirsaManagedTmp.begin("pending-test")
        let pending = PendingImport(id: UUID(), originalIPA: d.appendingPathComponent("missing.ipa"),
            extractedApp: d.appendingPathComponent("missing.app"), workDir: d,
            bundleID: "test.mirsa." + UUID().uuidString.lowercased(), name: "Fixture", version: "1",
            icon: nil, wantsNotifications: false, hasExtensions: false, sizeBytes: 0)
        store.pending = pending
        store.busy = "editing"
        store.cancelPending()
        await store.commitPending(to: .container, vm: nil)
        MirsaManagedTmp.cleanNow()
        XCTAssertEqual(store.pending?.id, pending.id); XCTAssertTrue(exists(d))
        store.busy = nil
        store.cancelPending()
        XCTAssertNil(store.pending); XCTAssertFalse(exists(d))
        let fail = try MirsaManagedTmp.begin("commit-failure")
        store.pending = PendingImport(id: UUID(), originalIPA: fail.appendingPathComponent("missing.ipa"),
            extractedApp: fail.appendingPathComponent("missing.app"), workDir: fail,
            bundleID: pending.bundleID, name: "Fixture", version: "1", icon: nil,
            wantsNotifications: false, hasExtensions: false, sizeBytes: 0)
        await store.commitPending(to: .container, vm: nil)
        XCTAssertNil(store.pending); XCTAssertFalse(exists(fail)); XCTAssertNotNil(store.error)
        XCTAssertTrue(store.errorOffersReimport)
        XCTAssertFalse(store.error?.contains("MIRSA_SOURCE_IPA_MISSING") ?? true)
        store.error = nil
        XCTAssertFalse(store.errorOffersReimport)
    }
    func testFreshInactiveWaitsOneHourAndUnmanagedSiblingIsUntouched() throws {
        let inactive = root.appendingPathComponent("previous-run")
        try fm.createDirectory(at: inactive, withIntermediateDirectories: true)
        let now = Date()
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-3599)], ofItemAtPath: inactive.path)
        let unmanaged = root.deletingLastPathComponent().appendingPathComponent("old-user-" + UUID().uuidString)
        try fm.createDirectory(at: unmanaged, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: unmanaged) }
        let archive = unmanaged.appendingPathComponent("original.ipa")
        try Data(count: 91).write(to: archive)
        age(unmanaged, hours: 10)
        XCTAssertEqual(MirsaManagedTmp.sweep(now: now, root: root), 0)
        XCTAssertTrue(exists(inactive))
        XCTAssertEqual(MirsaManagedTmp.sweep(now: now.addingTimeInterval(2), root: root), 1)
        XCTAssertEqual(try Data(contentsOf: archive).count, 91)
    }

}
