import XCTest
import SwiftUI
import UIKit
@testable import Mirsa

/// Source-feed text keeps its own direction inside the always-LTR UI, and the
/// window backdrop paint never touches system overlay windows (blank-screen fix).
@MainActor
final class MirsaTextDirectionTests: XCTestCase {
    func testArabicNamesResolveRightToLeft() {
        XCTAssertEqual(MirsaTextDirection.of("يوتيوب بلس"), .rightToLeft)
        // Leading digits/punctuation are weak: the first letter decides.
        XCTAssertEqual(MirsaTextDirection.of("2.0 - تطبيق"), .rightToLeft)
        XCTAssertEqual(MirsaTextDirection.of("«مرسى» 1.2"), .rightToLeft)
        XCTAssertEqual(MirsaTextDirection.of("٣ تطبيقات"), .rightToLeft)
    }

    func testSoraniAndKurmanjiFollowTheirScript() {
        XCTAssertEqual(MirsaTextDirection.of("ئەپەکان"), .rightToLeft)   // Sorani, Arabic script
        XCTAssertEqual(MirsaTextDirection.of("Sepan"), .leftToRight)     // Kurmanji, Latin script
    }

    func testLatinAndMixedStartingWithLatinStayLeftToRight() {
        XCTAssertEqual(MirsaTextDirection.of("YouTube++"), .leftToRight)
        XCTAssertEqual(MirsaTextDirection.of("Mirsa مرسى"), .leftToRight)
        XCTAssertEqual(MirsaTextDirection.of("Über App"), .leftToRight)
    }

    func testNoStrongCharacterKeepsUIDirection() {
        XCTAssertEqual(MirsaTextDirection.of(""), .leftToRight)
        XCTAssertEqual(MirsaTextDirection.of("1.2.3 🚀"), .leftToRight)
        XCTAssertEqual(MirsaTextDirection.of("١٢٣"), .leftToRight)   // Arabic-Indic digits are weak
    }

    func testExplicitMarksWin() {
        XCTAssertEqual(MirsaTextDirection.of("\u{200F}123 abc"), .rightToLeft)
        XCTAssertEqual(MirsaTextDirection.of("\u{200E}مرسى"), .leftToRight)
    }

    func testBackdropPaintSkipsSystemOverlayWindows() {
        XCTAssertTrue(MirsaChrome.paintsBackdrop(windowLevel: .normal, className: "UIWindow"))
        XCTAssertFalse(MirsaChrome.paintsBackdrop(windowLevel: .normal, className: "UITextEffectsWindow"))
        XCTAssertFalse(MirsaChrome.paintsBackdrop(windowLevel: .normal, className: "UIRemoteKeyboardWindow"))
        XCTAssertFalse(MirsaChrome.paintsBackdrop(windowLevel: UIWindow.Level(rawValue: 10_000_000), className: "UIWindow"))
        XCTAssertFalse(MirsaChrome.paintsBackdrop(windowLevel: .alert, className: "UIWindow"))
    }
}
