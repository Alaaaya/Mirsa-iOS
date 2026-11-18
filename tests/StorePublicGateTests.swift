import XCTest
@testable import Mirsa

final class StorePublicGateTests: XCTestCase {
    func testPublicStoreLoginEnabled() {
        XCTAssertTrue(MirsaStoreAvailability.publicLoginEnabled)
    }
}
