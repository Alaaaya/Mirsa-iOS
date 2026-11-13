import XCTest
#if canImport(MirsaStoreKit)
@testable import MirsaStoreKit
#else
@testable import Mirsa
#endif

final class StoreMetadataRetryPolicyTests: XCTestCase {
    func testTimeoutIsRetriedThenBoundedTerminal() {
        XCTAssertTrue(StoreMetadataRetryPolicy.shouldRetry(attempt: 1))
        XCTAssertTrue(StoreMetadataRetryPolicy.shouldRetry(attempt: 3))
        XCTAssertFalse(StoreMetadataRetryPolicy.shouldRetry(attempt: 4))
    }
    func testBackoffIsBounded() {
        XCTAssertEqual(StoreMetadataRetryPolicy.delay(attempt: 1), 2)
        XCTAssertEqual(StoreMetadataRetryPolicy.delay(attempt: 10), 8)
    }
}
