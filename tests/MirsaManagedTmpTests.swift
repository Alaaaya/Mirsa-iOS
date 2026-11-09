import XCTest
@testable import Mirsa

final class MirsaManagedTmpTests: XCTestCase {
    private var root: URL!
    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mt-test-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func age(_ u: URL, hours: Double) {
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-hours * 3600)], ofItemAtPath: u.path)
    }

    func testSuccessAndFailureAndCancelAllClean() {
        for label in ["ok", "fail", "cancel"] {
            let d = MirsaManagedTmp.begin(label, root: root)
            try? Data(repeating: 1, count: 100).write(to: d.appendingPathComponent("f"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: d.path))
            MirsaManagedTmp.end(d, root: root)
            XCTAssertFalse(FileManager.default.fileExists(atPath: d.path))
            MirsaManagedTmp.end(d, root: root) // idempotent
        }
    }

    func testStaleSweptActiveAndServedKept() {
        let stale = root.appendingPathComponent("stale-1"); try? FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true); age(stale, hours: 2)
        let fresh = root.appendingPathComponent("fresh-1"); try? FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        let active = MirsaManagedTmp.begin("act", root: root); age(active, hours: 5)
        let served = MirsaManagedTmp.begin("ota", root: root); age(served, hours: 5)
        MirsaManagedTmp.markServed(served, until: Date().addingTimeInterval(600))
        // served dir is also still active until end(); release the active flag by name via end-less check
        XCTAssertEqual(MirsaManagedTmp.sweep(root: root), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: served.path))
        MirsaManagedTmp.end(active, root: root); MirsaManagedTmp.end(served, root: root)
    }

    func testConcurrentOperationsDoNotCollide() {
        let exp = expectation(description: "c"); exp.expectedFulfillmentCount = 20
        let q = DispatchQueue(label: "t", attributes: .concurrent)
        for _ in 0..<20 {
            q.async {
                let d = MirsaManagedTmp.begin("c", root: self.root)
                try? Data(count: 10).write(to: d.appendingPathComponent("x"))
                MirsaManagedTmp.sweep(maxAge: -1, root: self.root)
                XCTAssertTrue(FileManager.default.fileExists(atPath: d.path), "active dir must survive concurrent sweep")
                MirsaManagedTmp.end(d, root: self.root)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 20)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: root.path))?.count, 0)
    }

    func testSymlinkNeverFollowedAndUserFilesSurvive() throws {
        let user = FileManager.default.temporaryDirectory.appendingPathComponent("user-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        let precious = user.appendingPathComponent("library.ipa"); try Data(count: 50).write(to: precious)
        defer { try? FileManager.default.removeItem(at: user) }
        let link = root.appendingPathComponent("evil-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: user)
        age(link, hours: 3)
        XCTAssertFalse(MirsaManagedTmp.isOwned(link, root: root))
        MirsaManagedTmp.sweep(root: root)
        MirsaManagedTmp.end(link, root: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: precious.path))
        // path outside root is never owned
        XCTAssertFalse(MirsaManagedTmp.isOwned(user, root: root))
        MirsaManagedTmp.end(user, root: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: precious.path))
    }

    func testSizeAndPersistenceAcrossLaunchSweep() {
        let d = MirsaManagedTmp.begin("sz", root: root)
        try? Data(count: 20_000).write(to: d.appendingPathComponent("a"))
        XCTAssertGreaterThanOrEqual(MirsaManagedTmp.size(root: root), 20_000)
        let leftover = root.appendingPathComponent("old-run"); try? FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try? Data(count: 5).write(to: leftover.appendingPathComponent("b")); age(leftover, hours: 2)
        XCTAssertEqual(MirsaManagedTmp.sweep(root: root), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: d.path))
        MirsaManagedTmp.end(d, root: root)
        XCTAssertEqual(MirsaManagedTmp.size(root: root), 0)
    }
}
