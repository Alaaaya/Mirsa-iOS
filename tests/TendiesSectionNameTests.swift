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
    func testWallpaperHelpRetainsLimitsWithoutUntestedStatus() {
        for language in AppLanguage.allCases {
            let help = WallpaperMakerStrings.text(.effectsHelp, language: language)
            for wording in ["has not been verified", "مو مجرّب", "nicht geprüft", "nehatiye ceribandin", "تاقی نەکراوەتەوە"] {
                XCTAssertFalse(help.contains(wording), language.rawValue)
            }
            XCTAssertFalse(help.isEmpty)
            XCTAssertTrue(WallpaperMakerStrings.text(.compatibility, language: language).contains("18.0"))
            XCTAssertTrue(WallpaperMakerStrings.text(.compatibility, language: language).contains("27.2"))
        }
        XCTAssertTrue(WallpaperMakerStrings.text(.effectsHelp, language: .english).contains("Preview shows layout only, not system effects"))
    }

}

final class VideoWallpaperSameSectionTests: XCTestCase {
    func testStringsInEveryLanguage() {
        XCTAssertEqual(AppLanguage.allCases.count, 5)
        for language in AppLanguage.allCases {
            for key in [VideoWallpaperSection.Key.tab, .fromPhotos, .preparing, .info, .experimental] {
                XCTAssertFalse(VideoWallpaperSection.text(key, language: language).isEmpty)
            }
        }
    }

    func testVideoBlockIsFirstInTendiesTab() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let src = try String(contentsOf: root.appendingPathComponent("ios-app/TendiesView.swift"), encoding: .utf8)
        let video = try XCTUnwrap(src.range(of: "OriginalVideoWallpaperBlock("))
        let maker = try XCTUnwrap(src.range(of: "WallpaperMakerSection("))
        XCTAssertLessThan(video.lowerBound, maker.lowerBound)
        let tools = try String(contentsOf: root.appendingPathComponent("ios-app/Apps/ToolsTab.swift"), encoding: .utf8)
        XCTAssertFalse(tools.contains("videoWallpaper"))
    }
}
