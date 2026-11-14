import Foundation
import XCTest
@testable import Mirsa

final class HomeShortcutSchemeTests: XCTestCase {
    @MainActor
    func testLaunchURLUsesMirsaOnlySchemeAndRoundTrips() {
        for id in ["com.alaa.player", "اختبار.app", "x%20y"] {
            let url = HomeShortcut.launchURL(for: id)
            XCTAssertEqual(url.scheme, "mirsa-container")
            XCTAssertEqual(HomeShortcut.containerID(from: url), id)
        }
    }

    @MainActor
    func testInvalidOrMissingIDIsRejected() {
        XCTAssertNil(HomeShortcut.containerID(from: URL(string: "mirsa-container://launch")!))
        XCTAssertNil(HomeShortcut.containerID(from: URL(string: "mirsa-container://launch?bundle=")!))
        XCTAssertNil(HomeShortcut.containerID(from: URL(string: "mirsa-container://other?bundle=a")!))
        XCTAssertNil(HomeShortcut.containerID(from: URL(string: "https://launch?bundle=a")!))
        XCTAssertNil(HomeShortcut.containerID(from: URL(string: "mirsa-container://launch?bundle=" + String(repeating: "a", count: 300))!))
        XCTAssertFalse(HomeShortcut.handle(URL(string: "mirsa-container://launch")!))
    }

    @MainActor
    func testLegacySchemeStillParsesAndNeverRunsPathsAsCommands() {
        XCTAssertEqual(HomeShortcut.containerID(from: URL(string: "mirsa://launch?app=com.x")!), "com.x")
        for raw in [
            "mirsa-container://launch?bundle=../../etc/passwd",
            "mirsa-container://user@launch?bundle=com.x",
            "mirsa-container://launch:123?bundle=com.x",
            "mirsa-container://launch/path?bundle=com.x",
            "mirsa-container://launch?bundle=com.x#fragment",
            "mirsa-container://launch?app=com.x&bundle=com.y",
            "mirsa-container://launch?bundle=com.x&bundle=com.x",
            "mirsa-container://launch?bundle=com%2Fx",
            "mirsa-container://launch?bundle=%00",
            "mirsa-container://launch?bundle=..",
            "mirsa-container://launch?bundle=com%5Cx",
            "mirsa-container://launch?bundle=com.x&unknown=1"
        ] { XCTAssertNil(HomeShortcut.containerID(from: URL(string: raw)!), raw) }
        // handle() only looks the id up among installed containers; unknown ids just show an error.
    }

    @MainActor
    func testColdShortcutWaitsForInitializationAndLaunchesExactIDOnce() throws {
        var launched: [String] = []
        let route = HomeShortcutLaunchRoute { launched.append($0) }
        let id = "com.alaa.player.cold"
        route.receive(try XCTUnwrap(HomeShortcut.containerID(from: HomeShortcut.launchURL(for: id))))
        XCTAssertTrue(launched.isEmpty)
        route.markReady()
        XCTAssertEqual(launched, [id])
        route.markReady()
        XCTAssertEqual(launched, [id])
    }

    @MainActor
    func testWarmShortcutAutoLaunchesExactIDOnce() throws {
        var launched: [String] = []
        let route = HomeShortcutLaunchRoute { launched.append($0) }
        route.markReady()
        let id = "com.alaa.player.warm"
        route.receive(try XCTUnwrap(HomeShortcut.containerID(from: HomeShortcut.launchURL(for: id))))
        XCTAssertEqual(launched, [id])
        route.markReady()
        XCTAssertEqual(launched, [id])
    }

    func testNormalPlistRegistersContainerSchemeSeparately() throws {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.contains("mirsa-container"))
    }
}
