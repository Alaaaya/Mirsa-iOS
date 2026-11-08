import XCTest
@testable import Mirsa

final class ForgeInspectorTests: XCTestCase {
    private let id = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!

    func testCaptureRequiresExplicitForegroundMainThreadAction() {
        let code = ForgeInspector.code(tweakID: id)
        for marker in ["UIGestureRecognizerStateBegan", "[NSThread isMainThread]", "UIApplicationStateActive", "UISceneActivationStateForegroundActive"] {
            XCTAssertTrue(code.contains(marker), marker)
        }
        XCTAssertFalse(code.contains("%ctor"))
        XCTAssertFalse(code.contains("NSURLSession"))
    }

    func testTraversalAndTransportAreBounded() {
        let code = ForgeInspector.code(tweakID: id)
        for marker in ["nodes.count < 400", "queue.count >= 400", "depth >= 32", "data.length > 24000", "events.count > 20", "className.length > 128", "UIPasteboardOptionLocalOnly:@YES", "dateWithTimeIntervalSinceNow:120", "SwiftUI/WebView", "@\"truncated\""] {
            XCTAssertTrue(code.contains(marker), marker)
        }
        XCTAssertLessThan(code.utf8.count, 24000)
    }

    func testGuardIsReadOnlyAndBoundToSuppliedProject() {
        let code = ForgeInspector.code(tweakID: id)
        XCTAssertTrue(code.contains("mirsa_guard_\(id.uuidString.lowercased()).plist"))
        XCTAssertTrue(code.contains("NSHomeDirectory()"))
        XCTAssertTrue(code.contains("guardDisabled"))
        XCTAssertFalse(code.contains("writeToFile"))
        XCTAssertFalse(code.contains("/var/"))
    }

    func testFreeformContentIsNotExportedAndCopyNeedsPreviewAction() {
        let code = ForgeInspector.code(tweakID: id)
        XCTAssertTrue(code.contains("secureTextEntry"))
        XCTAssertTrue(code.contains("[safeWords containsObject:"))
        XCTAssertTrue(code.contains("@\"identifier\":@\"[redacted]\""))
        XCTAssertFalse(code.contains("accessibilityLabel"))
        XCTAssertFalse(code.contains("accessibilityIdentifier"))
        XCTAssertFalse(code.contains("UITextView *)view).text"))
        let action = code.range(of: "actionWithTitle:@\"Copy / نسخ\"")!
        let copy = code.range(of: "setItems:")!
        XCTAssertLessThan(action.lowerBound, copy.lowerBound)
        XCTAssertTrue(code.contains("mirsa.inspector.v1"))
    }
}
