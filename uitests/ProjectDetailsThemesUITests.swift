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
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let interruption = addUIInterruptionMonitor(withDescription: "First-launch notification permission") { alert in
            // Dismiss only the OS permission alert, never app validation/errors.
            for label in ["Don’t Allow", "Don't Allow", "عدم السماح"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); return true }
            }
            return false
        }
        defer { removeUIInterruptionMonitor(interruption) }
        app.launch()
        if springboard.alerts.firstMatch.waitForExistence(timeout: 5) {
            let alert = springboard.alerts.firstMatch
            for label in ["Don’t Allow", "Don't Allow", "عدم السماح"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                break
            }
        }
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "System permission dialog obscures screenshot")
        XCTAssertTrue(app.buttons["mirsa.project.sign"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["mirsa.project.more"].exists)
        XCTAssertFalse(app.buttons["mirsa.project.theme-menu"].exists)
        capture("project-\(language)-top")
        let scroll = app.scrollViews["mirsa.project.editor-scroll"]
        for index in 1...2 { scroll.swipeUp(); capture("project-\(language)-scroll-\(index)") }
        // Two swipes are mid-scroll, not bottom reachability evidence.
        for _ in 0..<6 { scroll.swipeUp() }
        capture("project-\(language)-bottom-after-eight-swipes")
        app.terminate()
    }
    func testArabicPage() { verify("ar") }
    func testEnglishPage() { verify("en") }
}
