import Foundation
import XCTest
#if canImport(MirsaStoreKit)
@testable import MirsaStoreKit
#else
@testable import Mirsa
#endif

final class ForgeChatLengthTests: XCTestCase {
    func testArabic4000And4001MatchServerScalarLimit() {
        XCTAssertEqual(ForgeChatText.messageMax, 4000)
        XCTAssertEqual(ForgeChatText.messageCount(String(repeating: "ع", count: 4000)), 4000)
        XCTAssertEqual(ForgeChatText.messageCount(String(repeating: "ع", count: 4001)), 4001)
    }
    func testAstralCharactersCountAsOneScalarNotTwoUTF16Units() {
        let text = String(repeating: "😀", count: 4000)
        XCTAssertEqual(text.utf16.count, 8000)
        XCTAssertEqual(ForgeChatText.messageCount(text), 4000)
    }
    func testCombiningCharactersCountScalarsNotGraphemes() {
        let text = String(repeating: "e\u{301}", count: 2000)
        XCTAssertEqual(text.count, 2000)
        XCTAssertEqual(ForgeChatText.messageCount(text), 4000)
        XCTAssertEqual(ForgeChatText.messageCount(text + "\u{301}"), 4001)
    }
    func testOnlyOuterWhitespaceIsTrimmedAndCounterUsesSameLimit() {
        XCTAssertEqual(ForgeChatText.messageCount(" \nع ع\n "), 3)
        XCTAssertEqual(ForgeChatText.messageCount(" \n "), 0)
        XCTAssertTrue(ForgeChatText.counter(4001).hasPrefix("4001 / 4000 "))
        XCTAssertFalse(ForgeChatText.tooLong.isEmpty)
    }
}
