import XCTest

/// Sources use explicit DEBUG fixtures; Tools > Store uses the bundled live endpoint, without catalogue fixtures.
final class SourcesToolsStoreScreenshotsUITests: XCTestCase {
    private static let themes = ["aurora", "sunset", "ocean", "light"]
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ page: String, theme: String, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", page,
                               "-mirsa.appLanguage", language, "-mirsa.sourceTheme", theme,
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language]
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

    func testToolsStoreLiveAllLanguagesAndThemes() {
        for language in ["ar", "en", "de", "kmr", "ckb"] {
            for t in Self.themes {
                let app = launch("tools", theme: t, language: language)
                let tab = app.buttons["tools-section-store"]
                XCTAssertTrue(tab.waitForExistence(timeout: 8))
                tab.tap()
                // This ID exists only after a successful list response with no published items.
                XCTAssertTrue(app.descendants(matching: .any)["tools-store-empty"].waitForExistence(timeout: 30),
                              "Live catalogue must load, not the unavailable/configuration state")
                XCTAssertFalse(app.descendants(matching: .any)["tools-store-unavailable"].exists)
                let dock = app.descendants(matching: .any)["mirsa-tab-dock"].firstMatch
                XCTAssertTrue(dock.waitForExistence(timeout: 5))
                XCTAssertEqual(dock.value as? String, t == "light" ? "light" : "dark")
                shot("\(language)_\(t)_tools-store-live")
                if t == "light" {
                    let categories = app.scrollViews.containing(.button, identifier: "tools-store-cat-fonts").firstMatch
                    categories.swipeLeft()
                    shot("\(language)_light_tools-store-categories")
                    app.buttons["tools-store-upload"].tap()
                    XCTAssertTrue(app.descendants(matching: .any)["tools-store-upload-review-notice"].waitForExistence(timeout: 8))
                    shot("\(language)_light_tools-store-upload")
                }
                app.terminate()
            }
        }
    }

    func testLightDockDoesNotLeakToOtherToolsSections() {
        let app = launch("tools", theme: "light")
        app.buttons["tools-section-store"].tap()
        let dock = app.descendants(matching: .any)["mirsa-tab-dock"].firstMatch
        let light = NSPredicate(format: "value == %@", "light")
        expectation(for: light, evaluatedWith: dock)
        waitForExpectations(timeout: 8)
        app.buttons["tools-section-pairing"].tap()
        let dark = NSPredicate(format: "value == %@", "dark")
        expectation(for: dark, evaluatedWith: dock)
        waitForExpectations(timeout: 8)
        app.terminate()
    }
}
