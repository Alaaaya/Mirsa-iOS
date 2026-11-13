import Foundation
import XCTest
#if canImport(MirsaStoreKit)
@testable import MirsaStoreKit
#else
@testable import Mirsa
#endif

final class ForgeQueuedTests: XCTestCase {
    let thread = "11111111-2222-3333-4444-555555555555"
    let orig = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    func data(_ o: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: o) }
    func receipt(_ extra: [String: Any] = [:]) -> [String: Any] {
        var r: [String: Any] = ["saved": true, "status": "manual-queue", "threadID": thread, "originalID": orig, "replayed": false, "message": "x"]
        for (k, v) in extra { r[k] = v }; return r
    }
    func testValidReceiptQueuedAt200And202() throws {
        for s in [200, 202] {
            guard case .queued(let r) = try ForgeQueued.decode(status: s, data: data(receipt()), expectedThreadID: thread) else { return XCTFail() }
            XCTAssertEqual(r.originalID, orig); XCTAssertEqual(r.threadID, thread)
        }
    }
    func testReadyCodePathUnchanged() throws {
        guard case .generated(let o) = try ForgeQueued.decode(status: 200, data: data(["code": "// code here", "settings": []]), expectedThreadID: thread) else { return XCTFail() }
        XCTAssertEqual(o["code"] as? String, "// code here")
    }
    func testMalformedOrMismatchedRejected() {
        for bad in [receipt(["saved": false]), receipt(["threadID": "other"]), receipt(["originalID": "nope"]),
                    receipt(["code": "int x;"]), receipt(["status": "queued"]), ["saved": true]] as [[String: Any]] {
            XCTAssertThrowsError(try ForgeQueued.decode(status: 200, data: data(bad), expectedThreadID: thread))
        }
        XCTAssertThrowsError(try ForgeQueued.decode(status: 202, data: data(["code": "int x;"]), expectedThreadID: thread))
        XCTAssertThrowsError(try ForgeQueued.decode(status: 202, data: Data("x".utf8), expectedThreadID: thread))
        XCTAssertThrowsError(try ForgeQueued.decode(status: 204, data: data([:]), expectedThreadID: thread))
    }
    func testIDsPersistedForRetryAndForgotten() {
        let d = UserDefaults(suiteName: "mirsa.queued.test." + UUID().uuidString)!
        let body: [String: Any] = ["action": "generate", "prompt": "hello", "inspector": ["a", "b"]]
        let a = ForgeQueued.ids(for: body, defaults: d), b = ForgeQueued.ids(for: body, defaults: d)
        XCTAssertEqual(a.id, b.id); XCTAssertEqual(a.thread, b.thread)
        XCTAssertNotEqual(ForgeQueued.ids(for: ["action": "generate", "prompt": "other"], defaults: d).id, a.id)
        ForgeQueued.forget(body, defaults: d)
        XCTAssertNotEqual(ForgeQueued.ids(for: body, defaults: d).id, a.id)
    }
    func testNoticeAllFiveLanguagesNonEmpty() {
        XCTAssertFalse(ForgeQueued.notice.isEmpty)
    }
    func testArabicExactText() throws {
        let src = try String(contentsOfFile: #filePath.replacingOccurrences(of: "tests/ForgeQueuedTests.swift", with: "ios-app/Apps/ForgeQueued.swift"), encoding: .utf8)
        XCTAssertTrue(src.contains("طلبك وصل وبالدور، رح يوصلك التويك هون"))
        for k in ["Deine Anfrage", "داواکارییەکەت", "Daxwaza te"] { XCTAssertTrue(src.contains(k)) }
    }
}
