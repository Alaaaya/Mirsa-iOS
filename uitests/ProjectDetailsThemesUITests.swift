import XCTest

final class ProjectDetailsThemesUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func verify(_ language: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "certificate-parity-29",
            "-MirsaProjectThemesFixture", "-mirsa.projectDetailsTheme", "obsidianGold",
            "-mirsa.appLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        XCTAssertTrue(app.buttons["mirsa.project.sign"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["mirsa.project.more"].exists)
        XCTAssertFalse(app.buttons["mirsa.project.theme-menu"].exists)
        capture("project-\(language)-top")
        let scroll = app.scrollViews["mirsa.project.editor-scroll"]
        for index in 1...2 { scroll.swipeUp(); capture("project-\(language)-scroll-\(index)") }
        app.terminate()
    }
    func testArabicPage() { verify("ar") }
    func testEnglishPage() { verify("en") }
}
