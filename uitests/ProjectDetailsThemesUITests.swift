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
    func testArabicThemes() { verify("ar") }
    func testEnglishThemes() { verify("en") }
}
