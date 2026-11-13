import XCTest
@testable import Mirsa

final class ForgePortStatusTests: XCTestCase {
    let a = String(repeating: "a", count: 64), b = String(repeating: "b", count: 64)
    func obj(_ s: String, ready: Bool, fix: String?, new: String?, orig: String? = nil, manual: Bool = true) -> [String: Any] {
        var o: [String: Any] = ["status": s, "reviewedFixReady": ready, "originalSourceSHA256": orig ?? a, "manualEnableRequired": manual, "autoEnable": false]
        if let fix { o["fixID"] = fix }; if let new { o["newSourceSHA256"] = new }; return o
    }
    func testReadyNeedsReceiptAndHashes() {
        let id = UUID().uuidString
        XCTAssertEqual(ForgePortStatus.parse(obj("delivered", ready: true, fix: id, new: b), localSourceSHA256: a)?.reviewedFixReady, true)
        XCTAssertEqual(ForgePortStatus.parse(obj("delivered", ready: true, fix: nil, new: b), localSourceSHA256: a)?.reviewedFixReady, false)
        XCTAssertEqual(ForgePortStatus.parse(obj("awaiting_review", ready: true, fix: id, new: b), localSourceSHA256: a)?.reviewedFixReady, false)
        XCTAssertEqual(ForgePortStatus.parse(obj("delivered", ready: true, fix: id, new: a), localSourceSHA256: a)?.reviewedFixReady, false)
    }
    func testRejectsOtherSourceOrAutoEnable() {
        XCTAssertNil(ForgePortStatus.parse(obj("queued", ready: false, fix: nil, new: nil, orig: b), localSourceSHA256: a))
        XCTAssertNil(ForgePortStatus.parse(obj("queued", ready: false, fix: nil, new: nil, manual: false), localSourceSHA256: a))
        XCTAssertNil(ForgePortStatus.parse(obj("bogus", ready: false, fix: nil, new: nil), localSourceSHA256: a))
    }
}
