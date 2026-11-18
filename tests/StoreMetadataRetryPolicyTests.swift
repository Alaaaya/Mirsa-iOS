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

    func testReopenResetsOnlyExhaustedRows() {
        var attempts = ["a|1": 4, "a|2": 2]
        var status = ["1": "unavailable", "2": "pending"]
        StoreMetadataRetryPolicy.resetExhausted(key: "a", ids: ["1", "2"], attempts: &attempts,
            unavailable: { status[$0] == "unavailable" }, clear: { status[$0] = nil })
        XCTAssertNil(status["1"]); XCTAssertNil(attempts["a|1"])
        XCTAssertEqual(status["2"], "pending"); XCTAssertEqual(attempts["a|2"], 2)
        XCTAssertTrue(StoreMetadataRetryPolicy.shouldRetry(attempt: (attempts["a|1"] ?? 0) + 1))
    }
}
