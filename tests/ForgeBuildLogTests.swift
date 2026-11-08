import XCTest
@testable import Mirsa

final class ForgeBuildLogTests: XCTestCase {
    private let raw = "\u{1B}[1mTweak.xm:28:16: \u{1B}[0;1;31merror: \u{1B}[0m\u{1B}[1mno known instance method for selector 'show'\u{1B}[0m\n[0m2 errors generated.\r\nmake: *** Error 2\u{07}"
    func testStripsAnsiAndControlCodes() {
        let c = ForgeBuildLog.sanitize(raw)
        XCTAssertFalse(c.contains("\u{1B}"))
        XCTAssertFalse(c.contains("[0m"))
        XCTAssertFalse(c.contains("\u{07}"))
        XCTAssertTrue(c.contains("error: no known instance method for selector 'show'"))
    }
    func testSummaryUsesFirstErrorLineAndKeepsFullLog() {
        let f = ForgeBuildFailure(rawLog: raw)
        XCTAssertFalse(f.summary.contains("make:"))
        XCTAssertFalse(f.summary.contains("Tweak.xm"))
        XCTAssertTrue(f.summary.contains("UIAlertView"))
        XCTAssertTrue(f.log.contains("make: *** Error 2"))
        XCTAssertEqual(f.errorDescription, f.summary)
    }
    func testStripsOSC() {
        XCTAssertEqual(ForgeBuildLog.sanitize("\u{1B}]0;title\u{07}ok"), "ok")
        XCTAssertEqual(ForgeBuildLog.sanitize("\u{1B}]8;;http://x\u{1B}\\link"), "link")
    }
    func testGenericSummaryWithoutErrorLine() {
        XCTAssertFalse(ForgeBuildLog.summary("something odd").isEmpty)
    }
}
