import XCTest

/// Navigate the real retained Tools tab and Tendies NavigationLink. Only catalog
/// data/art is local; no substitute screen and no import action, video network or respring is triggered.
final class WallpaperSourceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTendiesSourceNavigationAndActualGridInFiveLanguages() {
        let titles = [
            "ar": "مصادر الخلفيات", "en": "Wallpaper sources", "de": "Hintergrundquellen",
            "kmr": "Çavkaniyên wêneyan", "ckb": "سەرچاوەی وێنەکان"
        ]
        for language in ["ar", "en", "de", "kmr", "ckb"] {
            let app = XCUIApplication()
            app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "tools",
                "-MirsaWallpaperSourceFixture", "-mirsa.appLanguage", language,
                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            defer { app.terminate() }
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let alert = springboard.alerts.firstMatch
            if alert.waitForExistence(timeout: 2) {
                let deny = alert.buttons.matching(NSPredicate(format: "label IN %@",
                    ["Don’t Allow", "Don't Allow", "عدم السماح"])).firstMatch
                if deny.exists { deny.tap() } else { alert.buttons.firstMatch.tap() }
            }
            let tendies = app.buttons["tools-section-wallpapers"]
            XCTAssertTrue(tendies.waitForExistence(timeout: 15))
            tendies.tap()
            let source = app.descendants(matching: .any).matching(identifier: "wallpaper-sources").firstMatch
            for _ in 0..<12 {
                if source.exists && source.isHittable { break }
                app.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(source.exists && source.isHittable, "Tendies source link must be reachable")
            shot(language + "_tendies_source_entry")
            source.tap()
            let field = app.textFields["wallpaper-source-url"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            XCTAssertTrue(app.navigationBars[titles[language]!].exists)
            XCTAssertTrue(app.staticTexts["Mirsa Originals"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Solar arc"].exists, "Screenshot must contain actual catalog entries")
            let imports = app.buttons.matching(identifier: "wallpaper-source-install")
            XCTAssertGreaterThanOrEqual(imports.count, 2, "Actual adaptive grid, not an empty feed")
            XCTAssertTrue(imports.firstMatch.isEnabled)
            XCTAssertFalse(app.buttons["wallpaper-source-add"].isEnabled)
            XCTAssertFalse(app.alerts.firstMatch.exists)
            shot(language + "_wallpaper_source_grid_top")
            app.swipeUp(velocity: .slow)
            shot(language + "_wallpaper_source_grid_scrolled")
            // The back action returns to the actual Tendies page, not the IPA Sources tab.
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.isHittable)
            back.tap()
            XCTAssertTrue(source.waitForExistence(timeout: 5))
            shot(language + "_wallpaper_source_return")
        }
    }
}
