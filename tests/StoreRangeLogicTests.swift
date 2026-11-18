import Foundation
import XCTest
#if canImport(MirsaStoreKit)
@testable import MirsaStoreKit
#else
@testable import Mirsa
#endif

final class StoreRangeLogicTests: XCTestCase {
    private let lm = "Wed, 21 Oct 2015 07:28:00 GMT"
    private func state(etag: String? = "\"a\"", lm: String? = nil, total: Int64? = 100, bytes: Int64 = 40) -> StoreResumeState {
        StoreResumeState(etag: etag, lastModified: lm, total: total, bytes: bytes)
    }
    private func h(etag: String? = "\"a\"", lm: String? = nil, cr: String? = "bytes 40-99/100", len: String? = "60", enc: String? = nil) -> StoreResponseHeaders {
        StoreResponseHeaders(etag: etag, lastModified: lm, contentRange: cr, contentLength: len, contentEncoding: enc)
    }
    func testValidAppend() {
        XCTAssertEqual(StoreRangeLogic.decide(status: 206, offset: 40, state: state(), headers: h()), .append(length: 60, total: 100))
    }
    func testLastModifiedFallback() {
        let s = state(etag: nil, lm: lm)
        XCTAssertEqual(StoreRangeLogic.decide(status: 206, offset: 40, state: s, headers: h(etag: nil, lm: lm)), .append(length: 60, total: 100))
        XCTAssertEqual(StoreRangeLogic.decide(status: 206, offset: 40, state: s, headers: h(etag: nil, lm: "Thu, 22 Oct 2015 07:28:00 GMT")), .restartFromZero)
    }
    func testNoValidatorNeverResumes() {
        XCTAssertEqual(StoreRangeLogic.decide(status: 206, offset: 40, state: state(etag: nil), headers: h()), .restartFromZero)
    }
    func testWeakETagIsNotAValidator() {
        XCTAssertFalse(StoreRangeLogic.isStrongETag("W/\"a\""))
        XCTAssertNil(StoreRangeLogic.strongETag("W/\"a\""))
        XCTAssertNil(StoreRangeLogic.validLastModified("yesterday"))
    }
    func testChangedValidatorRestarts() {
        XCTAssertEqual(StoreRangeLogic.decide(status: 206, offset: 40, state: state(), headers: h(etag: "\"b\"")), .restartFromZero)
        XCTAssertEqual(StoreRangeLogic.decide(status: 206, offset: 40, state: state(), headers: h(etag: nil)), .restartFromZero)
    }
    func testWrongRangeRestarts() {
        for cr in ["bytes 0-99/100", "bytes 41-99/100", "bytes 40-98/100", "bytes 40-99/*", "garbage", "bytes 40-99/99"] {
            XCTAssertEqual(StoreRangeLogic.decide(status: 206, offset: 40, state: state(), headers: h(cr: cr)), .restartFromZero, cr)
        }
        XCTAssertEqual(StoreRangeLogic.decide(status: 206, offset: 40, state: state(total: 200), headers: h()), .restartFromZero)
    }
    func testLengthMustMatch() {
        XCTAssertEqual(StoreRangeLogic.decide(status: 206, offset: 40, state: state(), headers: h(len: "59")), .restartFromZero)
        XCTAssertEqual(StoreRangeLogic.decide(status: 206, offset: 40, state: state(), headers: h(len: nil)), .restartFromZero)
    }
    func testFullBodyAnd416() {
        XCTAssertEqual(StoreRangeLogic.decide(status: 200, offset: 40, state: state(), headers: h(cr: nil, len: "100")), .fullBody(total: 100))
        XCTAssertEqual(StoreRangeLogic.decide(status: 416, offset: 40, state: state(), headers: h()), .restartFromZero)
        XCTAssertEqual(StoreRangeLogic.decide(status: 416, offset: 0, state: state(bytes: 0), headers: h()), .fail)
        XCTAssertEqual(StoreRangeLogic.decide(status: 206, offset: 0, state: state(bytes: 0), headers: h()), .fail)
        XCTAssertEqual(StoreRangeLogic.decide(status: 404, offset: 0, state: state(bytes: 0), headers: h()), .fail)
    }
    func testEncodingAndBounds() {
        XCTAssertEqual(StoreRangeLogic.decide(status: 200, offset: 0, state: state(bytes: 0), headers: h(cr: nil, len: "100", enc: "gzip")), .fail)
        XCTAssertEqual(StoreRangeLogic.decide(status: 200, offset: 0, state: state(bytes: 0), headers: h(cr: nil, len: "-5")), .fail)
        XCTAssertEqual(StoreRangeLogic.decide(status: 200, offset: 0, state: state(bytes: 0), headers: h(cr: nil, len: "200"), maxBytes: 100), .fail)
    }
}
