import XCTest
@testable import Mirsa

final class ForgeInspectorTests: XCTestCase {
    private let id = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!

    /// The server injects the trusted inspector into every tweak and rejects a second copy, so the client scaffold must stay inert.
    func testScaffoldIsInertValidAndDoesNotEmbedReservedInspector() {
        let code = ForgeInspector.code(tweakID: id)
        XCTAssertEqual(code, "%hook UIWindow\n- (void)becomeKeyWindow { %orig; }\n%end")
        for banned in ["mirsa.inspector.v1", "MirsaLocalInspector", "%ctor", "NSURLSession", "UILongPress", "writeToFile"] {
            XCTAssertFalse(code.contains(banned), banned)
        }
        XCTAssertLessThan(code.utf8.count, 200)
    }

    func testGuideDescribesTwoFingerDoubleTapNotLongPress() throws {
        for f in ["MirsaTrForge.swift", "ForgeFeaturesView.swift"] {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ios-app/Apps/" + f)
            let s = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(s.contains("then long-press inside it"), f)
        }
    }
}
