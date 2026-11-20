import XCTest

final class ProjectDetailsThemesUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
    private func verify(_ language: String) {
        for theme in ["classic", "obsidianGold", "aurora", "bento", "buildPipeline", "lightPearl"] {
            let app = XCUIApplication()
            app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "certificate-parity-29",
                "-MirsaProjectThemesFixture", "-mirsa.projectDetailsTheme", theme,
                "-mirsa.appLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            let menu = app.buttons["mirsa.project.theme-menu"]
            XCTAssertTrue(menu.waitForExistence(timeout: 20), "\(theme) header")
            XCTAssertTrue(app.buttons["mirsa.project.sign"].exists)
            capture("project-\(language)-\(theme)-top")
            let scroll = app.scrollViews["mirsa.project.editor-scroll"]
            for index in 1...2 {
                scroll.swipeUp()
                capture("project-\(language)-\(theme)-scroll-\(index)")
            }
            app.terminate()
        }
    }

    /// Select through the real palette, never launch-override the persisted key.
    private func liveSwitches(_ language: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "certificate-parity-29",
            "-MirsaProjectThemesFixture", "-mirsa.appLanguage", language,
            "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        let names = language == "ar"
            ? ["الأساسي", "الذهبي الأسود", "الشفق", "بينتو", "خط البناء", "اللؤلؤي الفاتح"]
            : ["Classic", "Obsidian Gold", "Aurora", "Bento", "Build Pipeline", "Light Pearl"]
        let themes = ["classic", "obsidianGold", "aurora", "bento", "buildPipeline", "lightPearl"]
        func select(_ index: Int) {
            let menu = app.buttons["mirsa.project.theme-menu"]
            XCTAssertTrue(menu.waitForExistence(timeout: 20))
            menu.tap()
            let identified = app.buttons["mirsa.project.theme." + themes[index]]
            let choice = identified.exists ? identified : app.buttons[names[index]]
            XCTAssertTrue(choice.waitForExistence(timeout: 5), app.debugDescription)
            choice.tap()
            XCTAssertTrue(menu.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["mirsa.project.sign"].exists)
            XCTAssertEqual(app.state, .runningForeground)
        }
        for index in themes.indices {
            select(index)
            capture("live-project-\(language)-\(themes[index])-top")
        }
        select(1)
        app.terminate()
        app.launch() // Must read the real saved obsidianGold, no launch argument override.
        XCTAssertTrue(app.buttons["mirsa.project.theme-menu"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["mirsa.project.sign"].exists)
        capture("live-project-\(language)-persisted-obsidianGold")
        select(0)
        app.terminate()
    }
    func testLiveArabicPaletteAndPersistedGold() { liveSwitches("ar") }
    func testLiveEnglishPaletteAndPersistedGold() { liveSwitches("en") }
    func testArabicThemes() { verify("ar") }
    func testEnglishThemes() { verify("en") }
}
