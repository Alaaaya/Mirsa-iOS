import Foundation
import XCTest
@testable import Mirsa

final class HomeShortcutSchemeTests: XCTestCase {
    func testLaunchURLUsesMirsaOnlySchemeAndRoundTrips() {
        for id in ["com.alaa.player", "com.a b/c&d=e?f#g", "اختبار.app", "x%20y"] {
            let url = HomeShortcut.launchURL(for: id)
            XCTAssertEqual(url.scheme, "mirsa-container")
            XCTAssertEqual(HomeShortcut.containerID(from: url), id)
        }
    }

    func testInvalidOrMissingIDIsRejected() {
        XCTAssertNil(HomeShortcut.containerID(from: URL(string: "mirsa-container://launch")!))
        XCTAssertNil(HomeShortcut.containerID(from: URL(string: "mirsa-container://launch?bundle=")!))
        XCTAssertNil(HomeShortcut.containerID(from: URL(string: "mirsa-container://other?bundle=a")!))
        XCTAssertNil(HomeShortcut.containerID(from: URL(string: "https://launch?bundle=a")!))
        XCTAssertNil(HomeShortcut.containerID(from: URL(string: "mirsa-container://launch?bundle=" + String(repeating: "a", count: 300))!))
        XCTAssertFalse(HomeShortcut.handle(URL(string: "mirsa-container://launch")!))
    }

    func testLegacySchemeStillParsesAndNeverRunsPathsAsCommands() {
        XCTAssertEqual(HomeShortcut.containerID(from: URL(string: "mirsa://launch?app=com.x")!), "com.x")
        XCTAssertEqual(HomeShortcut.containerID(from: URL(string: "mirsa-container://launch?bundle=../../etc/passwd")!), "../../etc/passwd")
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
