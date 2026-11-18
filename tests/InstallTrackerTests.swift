import XCTest
@testable import Mirsa

@MainActor
final class InstallTrackerTests: XCTestCase {
    override func setUp() { InstallTracker.shared.end(InstallTracker.shared.current?.id) }

    func testRequestIdentityIsTheTappedURLNotABundleID() {
        let a = URL(string: "https://example.com/a.ipa")!
        let token = InstallTracker.shared.begin(key: InstallTracker.urlKey(a))
        XCTAssertNotNil(token)
        XCTAssertTrue(InstallTracker.shared.isActive(InstallTracker.urlKey(a)))
        XCTAssertFalse(InstallTracker.shared.isActive("url:https://example.com/b.ipa"))
        XCTAssertFalse(InstallTracker.shared.isActive("com.example.app"))
        InstallTracker.shared.end(token)
        XCTAssertNil(InstallTracker.shared.current)
    }

    func testNestedBeginIsIgnoredAndCannotEndOuterRequest() {
        let outer = InstallTracker.shared.begin(key: "mirsa-update")
        XCTAssertNil(InstallTracker.shared.begin(key: "self", phase: .installing))
        InstallTracker.shared.end(nil)
        XCTAssertTrue(InstallTracker.shared.isActive("mirsa-update"))
        InstallTracker.shared.end(outer)
        XCTAssertNil(InstallTracker.shared.current)
    }

    func testFractionIsClampedAndUnknownStaysNil() {
        let token = InstallTracker.shared.begin(key: "k", cancel: {})
        XCTAssertNil(InstallTracker.shared.current?.fraction)
        InstallTracker.shared.set(token, phase: .downloading, fraction: 1.7)
        XCTAssertEqual(InstallTracker.shared.current?.fraction, 1)
        InstallTracker.shared.set(token, phase: .downloading, fraction: nil)
        XCTAssertNil(InstallTracker.shared.current?.fraction)
        InstallTracker.shared.end(token)
    }

    func testCancelOnlyWhileDownloading() {
        var cancelled = 0
        let token = InstallTracker.shared.begin(key: "k", cancel: { cancelled += 1 })
        XCTAssertTrue(InstallTracker.shared.current?.cancellable == true)
        InstallTracker.shared.set(token, phase: .preparing)
        XCTAssertFalse(InstallTracker.shared.current?.cancellable == true)
        XCTAssertFalse(InstallTracker.shared.cancelIfSupported("k"))
        InstallTracker.shared.set(token, phase: .installing)
        XCTAssertFalse(InstallTracker.shared.cancelIfSupported("k"))
        XCTAssertEqual(cancelled, 0)
        InstallTracker.shared.end(token)
    }

    func testRequestWithoutCancelHandlerIsNotCancellable() {
        let token = InstallTracker.shared.begin(key: "self", phase: .installing)
        XCTAssertFalse(InstallTracker.shared.cancelIfSupported("self"))
        let t2 = InstallTracker.shared.begin(key: "x")
        XCTAssertNil(t2)
        InstallTracker.shared.end(token)
        let t3 = InstallTracker.shared.begin(key: "entry:1")
        XCTAssertFalse(InstallTracker.shared.current?.cancellable == true)
        InstallTracker.shared.end(t3)
    }

    func testCancelFiresOnceInDownloadPhase() {
        var cancelled = 0
        let token = InstallTracker.shared.begin(key: "k", cancel: { cancelled += 1 })
        XCTAssertTrue(InstallTracker.shared.cancelIfSupported("k"))
        XCTAssertEqual(cancelled, 1)
        InstallTracker.shared.end(token)
    }
}
