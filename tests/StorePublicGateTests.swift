import XCTest
@testable import Mirsa

final class StorePublicGateTests: XCTestCase {
    func testPublicStoreLoginDisabled() {
        XCTAssertFalse(MirsaStoreAvailability.publicLoginEnabled)
    }
}
