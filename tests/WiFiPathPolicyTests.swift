import XCTest
@testable import Mirsa

final class WiFiPathPolicyTests: XCTestCase {
    func testStateMapping() {
        XCTAssertEqual(WiFiPathPolicy.state(satisfied: true, usesWiFi: true), .wifi)
        XCTAssertEqual(WiFiPathPolicy.state(satisfied: true, usesWiFi: false), .notWifi)
        XCTAssertEqual(WiFiPathPolicy.state(satisfied: false, usesWiFi: true), .notWifi)
    }
    func testUnknownIsNeverReportedAsCellular() {
        XCTAssertEqual(WiFiPathPolicy.verdict(path: .unknown, en0HasAddress: false), .undetermined)
    }
    func testCellularBlocks() {
        XCTAssertEqual(WiFiPathPolicy.verdict(path: .notWifi, en0HasAddress: false), .needWiFi)
    }
    func testEitherWiFiSignalAllows() {
        XCTAssertEqual(WiFiPathPolicy.verdict(path: .wifi, en0HasAddress: false), .allow)
        XCTAssertEqual(WiFiPathPolicy.verdict(path: .notWifi, en0HasAddress: true), .allow)
        XCTAssertEqual(WiFiPathPolicy.verdict(path: .unknown, en0HasAddress: true), .allow)
    }
}
