import XCTest
@testable import Mirsa

final class TendiesSectionNameTests: XCTestCase {
    func testSectionNameIsTendiesInEveryLanguage() {
        XCTAssertEqual(AppLanguage.allCases.count, 5)
        for language in AppLanguage.allCases {
            XCTAssertEqual(TendiesSection.title(language: language), "Tendies")
        }
    }

    func testLocalizedSectionLookupHasNoOldLabels() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for rel in ["ios-app/Apps/AppsStrings.swift", "ios-app/Apps/MirsaTr.swift"] {
            let src = try String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
            let lines = src.components(separatedBy: "\n").filter { $0.contains("\"tools.wallpapers\":") }
            XCTAssertEqual(lines.count, 2, rel)
            for line in lines { XCTAssertTrue(line.contains("\"Tendies\""), line) }
        }
    }

    func testToolsTabAndTendiesScreenUseSharedName() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for rel in ["ios-app/Apps/ToolsTab.swift", "ios-app/TendiesView.swift", "ios-app/WallpaperMakerView.swift"] {
            let src = try String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
            if !rel.hasSuffix("WallpaperMakerView.swift") {
                XCTAssertTrue(src.contains("TendiesSection.name"), rel)
            }
            XCTAssertFalse(src.contains("خلفية فيديو"), rel)
            XCTAssertFalse(src.contains("خلفية الفيديو"), rel)
            XCTAssertFalse(src.contains("Video wallpaper"), rel)
        }
    }
}
