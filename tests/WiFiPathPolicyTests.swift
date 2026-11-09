import XCTest
@testable import Mirsa

final class WiFiPathPolicyTests: XCTestCase {
    func testStateMapping() {
        XCTAssertEqual(WiFiPathPolicy.state(satisfied: true, usesWiFi: true, wifiAvailable: true), .wifi)
        XCTAssertEqual(WiFiPathPolicy.state(satisfied: true, usesWiFi: false, wifiAvailable: true), .wifi)
        XCTAssertEqual(WiFiPathPolicy.state(satisfied: true, usesWiFi: false, wifiAvailable: false), .notWifi)
        XCTAssertEqual(WiFiPathPolicy.state(satisfied: false, usesWiFi: true, wifiAvailable: true), .notWifi)
    }
    func testVerdictIsAuthoritative() {
        XCTAssertEqual(WiFiPathPolicy.verdict(path: .wifi), .allow)
        XCTAssertEqual(WiFiPathPolicy.verdict(path: .notWifi), .needWiFi)
        XCTAssertEqual(WiFiPathPolicy.verdict(path: .unknown), .undetermined)
    }
    func testEveryLanguageHasEveryNewMessage() {
        let keys = Array(MirsaTr.extraCkb.keys.filter { $0.contains("Wi-Fi, not mobile data") || $0.hasPrefix("Next step:") || $0 == "Open Settings" || $0.hasPrefix("Another install") || $0.hasPrefix("Could not confirm") })
        XCTAssertGreaterThanOrEqual(keys.count, 5)
        for k in keys {
            XCTAssertNotNil(MirsaTr.extraCkb[k], k)
            XCTAssertNotNil(MirsaTr.extraKmr[k], k)
            XCTAssertFalse(MirsaTr.extraCkb[k]!.isEmpty)
            XCTAssertFalse(MirsaTr.extraKmr[k]!.isEmpty)
        }
    }
    @MainActor func testNextStepAddedOnceForAnyFailure() {
        let once = AppsStore.withNextStep("Install failed: boom")
        XCTAssertTrue(once.hasPrefix("Install failed: boom"))
        XCTAssertEqual(AppsStore.withNextStep(once), once)
    }
}
