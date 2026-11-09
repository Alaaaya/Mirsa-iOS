import XCTest
#if canImport(MirsaStoreKit)
@testable import MirsaStoreKit
#else
@testable import Mirsa
#endif

final class UpdateNetworkPathTests: XCTestCase {
    func testConfirmedWiFiAllowsUpdate() {
        XCTAssertEqual(UpdateNetworkPath.classify(satisfied: true, usesWiFi: true, usesCellular: false), .wifi)
    }
    func testCellularActiveWithWiFiAvailableBlocks() {
        XCTAssertEqual(UpdateNetworkPath.classify(satisfied: true, usesWiFi: false, usesCellular: true), .cellular)
    }
    func testMixedCellularAndWiFiFailsClosed() {
        XCTAssertEqual(UpdateNetworkPath.classify(satisfied: true, usesWiFi: true, usesCellular: true), .cellular)
    }
    func testUnknownPathNeverCountsAsWiFi() {
        XCTAssertEqual(UpdateNetworkPath.classify(satisfied: true, usesWiFi: false, usesCellular: false), .unknown)
    }
    func testUnsatisfiedWiFiDoesNotAllowUpdate() {
        XCTAssertEqual(UpdateNetworkPath.classify(satisfied: false, usesWiFi: true, usesCellular: false), .unavailable)
    }
}
