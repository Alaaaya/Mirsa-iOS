import XCTest

/// Screenshots for the Sources redesign + Tools > Store, all four themes. Fixtures come from the DEBUG-only
/// SourcesToolsStoreShotHost (local data, no network).
final class SourcesToolsStoreScreenshotsUITests: XCTestCase {
    private static let themes = ["aurora", "sunset", "ocean", "light"]
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ page: String, theme: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", page,
                               "-mirsa.appLanguage", "en", "-mirsa.sourceTheme", theme,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        Thread.sleep(forTimeInterval: 2.5)
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 1) { alert.buttons.firstMatch.tap() }
        Thread.sleep(forTimeInterval: 1.0)
        return app
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testSourcesListAllThemes() {
        for t in Self.themes { let app = launch("sources-ts-list", theme: t); XCTAssertTrue(app.staticTexts["Small Source"].waitForExistence(timeout: 8)); shot("\(t)_sources-list"); app.terminate() }
    }

    func testSmallSourcePageAndAppSheetAllThemes() {
        for t in Self.themes {
            let app = launch("sources-ts-small", theme: t)
            XCTAssertTrue(app.staticTexts["Small 1"].waitForExistence(timeout: 8))
            shot("\(t)_source-small")
            let row = app.staticTexts["Small 1"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            XCTAssertTrue(app.buttons["source-detail-download"].waitForExistence(timeout: 5))
            shot("\(t)_source-app-sheet")
            app.terminate()
        }
    }

    func testLargeSourceGridAllThemes() {
        for t in Self.themes {
            let app = launch("sources-ts-large", theme: t)
            XCTAssertTrue(app.staticTexts["Large 1"].waitForExistence(timeout: 8))
            shot("\(t)_source-large-grid")
            app.swipeUp(); Thread.sleep(forTimeInterval: 0.8)
            shot("\(t)_source-large-grid-scrolled")
            app.terminate()
        }
    }

    func testToolsStoreEmptyEndpointAllThemes() {
        for t in Self.themes {
            let app = launch("tools", theme: t)
            let tab = app.buttons["tools-section-store"]
            XCTAssertTrue(tab.waitForExistence(timeout: 8))
            tab.tap()
            XCTAssertTrue(app.descendants(matching: .any)["tools-store-unavailable"].waitForExistence(timeout: 8), "store must show not-configured state")
            shot("\(t)_tools-store-empty")
            app.terminate()
        }
    }
}
