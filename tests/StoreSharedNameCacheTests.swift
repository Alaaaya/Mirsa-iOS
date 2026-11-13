import XCTest
#if canImport(MirsaStoreKit)
@testable import MirsaStoreKit
#else
@testable import Mirsa
#endif

final class StoreSharedNameCacheTests: XCTestCase {
    func testDisabledByDefaultMakesNoCall() async {
        var called = false
        let r = await StoreSharedNameCache.fetch(appID: "1", ids: ["2"]) { _, _ in called = true; return Data() }
        XCTAssertTrue(r.isEmpty); XCTAssertFalse(called)
    }
    func testBodiesCarryOnlyPublicFields() {
        let b = StoreSharedNameCache.contributeBody(appID: "1", names: ["2": "4.0", "3": ""])
        XCTAssertEqual(Set(b.keys), ["version", "appId", "names"])
        XCTAssertEqual((b["names"] as? [String: String])?.count, 1)
    }
    func testLookupBodyCapped() {
        let ids = (0..<900).map(String.init)
        XCTAssertEqual((StoreSharedNameCache.lookupBody(appID: "1", ids: ids)["externalVersionIds"] as? [String])?.count, 500)
    }
}
