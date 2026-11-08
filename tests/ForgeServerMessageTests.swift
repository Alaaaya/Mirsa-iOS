import XCTest
@testable import Mirsa

final class ForgeServerMessageTests: XCTestCase {
    private func d(_ s: String) -> Data { Data(s.utf8) }
    func testLocalizedDictAndSteps() {
        let j = #"{"error":"x","message":{"ar":"ناقص معلومات","en":"Missing info"},"nextSteps":{"ar":["افتح الفاحص","اختر التطبيق"],"en":["Open inspector"]}}"#
        XCTAssertEqual(ForgeServerMessage.text(d(j), lang: "ar"), "ناقص معلومات\n\n1. افتح الفاحص\n2. اختر التطبيق")
        XCTAssertEqual(ForgeServerMessage.text(d(j), lang: "ckb"), "Missing info\n\n1. Open inspector")
    }
    func testSuffixFieldsAndPlain() {
        XCTAssertEqual(ForgeServerMessage.text(d(#"{"reason_kmr":"Sedem","reason_en":"Why"}"#), lang: "kmr"), "Sedem")
        XCTAssertEqual(ForgeServerMessage.text(d(#"{"reason":"Plain"}"#), lang: "ar"), "Plain")
        XCTAssertNil(ForgeServerMessage.text(d(#"{"error":"busy"}"#), lang: "en"))
        XCTAssertNil(ForgeServerMessage.text(Data(), lang: "en"))
    }
    func testNeedsInspectorFlagsAndText() {
        XCTAssertTrue(ForgeServerMessage.needsInspector(d(#"{"error":"unsupported_request","needsInspector":true,"message":"x"}"#)))
        XCTAssertTrue(ForgeServerMessage.needsInspector(d(#"{"error":"inspector_required"}"#)))
        XCTAssertTrue(ForgeServerMessage.needsInspector(d(#"{"message":{"ar":"افتح المفتش أولاً","en":"x"}}"#)))
        XCTAssertFalse(ForgeServerMessage.needsInspector(d(#"{"error":"unsupported_request","message":"Not possible"}"#)))
        XCTAssertFalse(ForgeServerMessage.needsInspector(Data()))
    }
}
