import Foundation
import XCTest
#if canImport(MirsaStoreKit)
@testable import MirsaStoreKit
#else
@testable import Mirsa
#endif

final class ForgeMarkdownTests: XCTestCase {
    func testBoldRendersWithoutMarkers() {
        XCTAssertEqual(ForgeChatMarkdown.visibleText("hi **there** you"), "hi there you")
        XCTAssertTrue(ForgeChatMarkdown.hasBold("hi **there** you"))
    }
    func testShortLabelHttpsLinkIsTappable() {
        let t = "شوف [الموقع](https://example.com/a?b=1) هون"
        XCTAssertEqual(ForgeChatMarkdown.visibleText(t), "شوف الموقع هون")
        XCTAssertEqual(ForgeChatMarkdown.links(t).map(\.absoluteString), ["https://example.com/a?b=1"])
    }
    func testUnsafeSchemesAreNotTappableButLabelStays() {
        for u in ["javascript:alert(1)", "data:text/html;base64,AAAA", "file:///etc/passwd", "myapp://x", "tel:123", "https://user:pw@example.com", "https://localhost/x", "https:///nohost"] {
            let t = "[click](\(u))"
            XCTAssertTrue(ForgeChatMarkdown.links(t).isEmpty, u)
            XCTAssertEqual(ForgeChatMarkdown.visibleText(t), "click", u)
        }
    }
    func testMalformedAndPlainTextSurvive() {
        for t in ["plain text", "**unclosed bold", "[a](", "[a]((b", "", "1 * 2 * 3"] {
            XCTAssertFalse(ForgeChatMarkdown.visibleText(t).isEmpty && !t.isEmpty, t)
        }
        XCTAssertEqual(ForgeChatMarkdown.visibleText("plain text"), "plain text")
    }
    func testLiteralHTMLStaysNonExecutingText() {
        let t = "<b>x</b> <a href=\"https://evil.com\">y</a> <img src=\"https://evil.com/p.png\">"
        XCTAssertTrue(ForgeChatMarkdown.links(t).isEmpty)
        XCTAssertTrue(ForgeChatMarkdown.visibleText(t).contains("<img"))
    }
    func testImagesAreNotRendered() {
        let a = ForgeChatMarkdown.attributed("![alt](https://example.com/p.png)")
        XCTAssertTrue(a.runs.allSatisfy { $0.link == nil })
    }
    func testMultilineAllLocalesKeepLineBreaks() {
        let samples = ["سطر أول\nسطر **ثاني**", "line one\nline **two**", "Zeile eins\nZeile **zwei**", "rêz yek\nrêz **du**", "دێڕی یەک\nدێڕی **دوو**"]
        for s in samples {
            let v = ForgeChatMarkdown.visibleText(s)
            XCTAssertTrue(v.contains("\n"), s)
            XCTAssertFalse(v.contains("**"), s)
        }
    }
}
