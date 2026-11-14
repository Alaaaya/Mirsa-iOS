import XCTest
@testable import Mirsa

final class VideoWallpaperSectionTests: XCTestCase {
    func testEveryLanguageHasEveryString() {
        XCTAssertEqual(AppLanguage.allCases.count, 5)
        for language in AppLanguage.allCases {
            for key in [VideoWallpaperSection.Key.tab, .fromPhotos, .preparing, .info, .experimental] {
                XCTAssertFalse(VideoWallpaperSection.text(key, language: language).isEmpty)
            }
            XCTAssertNotEqual(VideoWallpaperSection.text(.tab, language: language), TendiesSection.name)
        }
        XCTAssertEqual(VideoWallpaperSection.text(.tab, language: .arabic), "خلفية فيديو")
        XCTAssertEqual(VideoWallpaperSection.text(.tab, language: .english), "Video wallpaper")
    }

    func testToolsTabHasSeparateVideoAndTendiesSections() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let tools = try String(contentsOf: root.appendingPathComponent("ios-app/Apps/ToolsTab.swift"), encoding: .utf8)
        XCTAssertTrue(tools.contains("case .videoWallpaper: VideoWallpaperView()"))
        XCTAssertTrue(tools.contains("case .wallpapers: TendiesView()"))
        let video = try String(contentsOf: root.appendingPathComponent("ios-app/VideoWallpaperView.swift"), encoding: .utf8)
        XCTAssertTrue(video.contains("VideoWallpaper.makeArchive"))
        XCTAssertFalse(video.contains("WallpaperMakerSection"))
    }
}
