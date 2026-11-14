import XCTest
@testable import Mirsa

final class TendiesSectionNameTests: XCTestCase {
    func testSectionNameIsTendiesInEveryLanguage() {
        XCTAssertEqual(TendiesSection.name, "Tendies")
    }

    func testToolsTabAndTendiesScreenUseSharedName() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for rel in ["ios-app/Apps/ToolsTab.swift", "ios-app/TendiesView.swift"] {
            let src = try String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
            XCTAssertTrue(src.contains("TendiesSection.name"), rel)
            XCTAssertFalse(src.contains("خلفية فيديو"), rel)
            XCTAssertFalse(src.contains("خلفية الفيديو"), rel)
            XCTAssertFalse(src.contains("Video wallpaper"), rel)
        }
    }
}
