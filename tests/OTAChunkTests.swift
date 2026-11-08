import XCTest
@testable import Mirsa

final class OTAChunkTests: XCTestCase {
    func testPlanCoversFileExactly() throws {
        let p = try OTAChunkPlan(total: 20, chunkSize: 8)
        XCTAssertEqual(p.count, 3)
        XCTAssertEqual(p.range(0), 0..<8); XCTAssertEqual(p.range(2), 16..<20)
    }
    func testPlanLimits() {
        XCTAssertThrowsError(try OTAChunkPlan(total: 0))
        XCTAssertThrowsError(try OTAChunkPlan(total: OTAChunkPlan.maxBytes + 1))
        XCTAssertNoThrow(try OTAChunkPlan(total: OTAChunkPlan.maxBytes))
    }
    func testHostAllowlist() {
        XCTAssertTrue(OTAHostPolicy.accepts(URL(string: "https://mirsa-app.mooo.com/x")!))
        XCTAssertFalse(OTAHostPolicy.accepts(URL(string: "http://mirsa-app.mooo.com/x")!))
        XCTAssertFalse(OTAHostPolicy.accepts(URL(string: "https://evil.com/x")!))
        XCTAssertFalse(OTAHostPolicy.accepts(URL(string: "https://mirsa-app.mooo.com@evil.com/x")!))
        XCTAssertFalse(OTAHostPolicy.accepts(URL(string: "https://mirsa-app.mooo.com.evil.com/")!))
    }
    func testErrorsLocalized() {
        XCTAssertNotNil(OTAChunkError.tooLarge.errorDescription)
        XCTAssertNotNil(OTAChunkError.server(500).errorDescription)
    }
}
