import XCTest

/// Real source parser and the production selected-URL routing, with only the final network/install side effect intercepted in DEBUG.
final class SourceVersions24UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "sources-ts-small",
                               "-MirsaSourceVersionsFixture24", "-mirsa.appLanguage", language,
                               "-mirsa.sourceTheme", "aurora", "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        XCTAssertTrue(app.staticTexts["History App"].waitForExistence(timeout: 12))
        return app
    }
    private func shot(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "versions24-" + name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "versions24-" + name + "-AX"; tree.lifetime = .keepAlways; add(tree)
    }
    private func proof(_ expected: String, _ app: XCUIApplication) {
        let text = app.staticTexts["source-versions-route-proof"].firstMatch
        expectation(for: NSPredicate(format: "label == %@", expected), evaluatedWith: text)
        waitForExpectations(timeout: 5)
    }

    func testActualHistoryAllFiveLanguagesAndExactSelectedVersionInstall() {
        let titles = ["en": "Versions", "ar": "الإصدارات", "de": "Versionen", "kmr": "Guherto", "ckb": "وەشانەکان"]
        for lang in ["en", "ar", "de", "kmr", "ckb"] {
            let app = launch(lang)
            app.staticTexts["History App"].firstMatch.tap()
            let history = app.buttons["source-detail-versions"]
            let latest = app.buttons["source-detail-install"]
            XCTAssertTrue(history.waitForExistence(timeout: 5))
            XCTAssertTrue(history.isEnabled)
            XCTAssertEqual(history.label, titles[lang])
            XCTAssertFalse(app.buttons["source-detail-download"].exists)
            XCTAssertGreaterThan(history.frame.minX, latest.frame.minX, "Layout remains LTR even for Arabic/Sorani")
            shot(lang + "-detail", app)
            latest.tap()
            proof("https://example.org/latest.ipa", app)
            history.tap()
            let old = app.buttons["source-version-2.0"]
            XCTAssertTrue(old.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["source-version-3.0"].exists)
            XCTAssertTrue(app.buttons["source-version-1.0"].exists)
            XCTAssertFalse(app.buttons["source-version-bad"].exists)
            shot(lang + "-history", app)
            old.tap()
            proof("https://example.org/older.ipa", app)
            app.buttons["source-version-1.0"].tap()
            proof("https://example.org/oldest.ipa", app)
            shot(lang + "-selected", app)
            app.buttons["source-versions-close"].tap()
            XCTAssertTrue(latest.waitForExistence(timeout: 5))
            latest.tap()
            proof("https://example.org/latest.ipa", app)
            app.terminate()
        }
    }

    func testZeroOneLegacyDisabledHistoryKeepsLatestInstallation() {
        for (name, path) in [("Single App", "single.ipa"), ("Legacy App", "legacy.ipa"), ("Broken History App", "fallback.ipa")] {
            let app = launch()
            app.staticTexts[name].firstMatch.tap()
            let history = app.buttons["source-detail-versions"]
            XCTAssertTrue(history.waitForExistence(timeout: 5))
            XCTAssertFalse(history.isEnabled, "Never open an empty or single-version list")
            let latest = app.buttons["source-detail-install"]
            XCTAssertTrue(latest.isEnabled)
            latest.tap()
            proof("https://example.org/" + path, app)
            shot(name, app)
            app.terminate()
        }
    }

    func testGroupedLegacyEntriesShowOneCardAndOwnVersionRoutes() {
        let app = launch()
        XCTAssertEqual(app.staticTexts.matching(identifier: "Grouped Legacy App").count, 1, "one card per bundle")
        app.staticTexts["Grouped Legacy App"].firstMatch.tap()
        let history = app.buttons["source-detail-versions"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertTrue(history.isEnabled)
        app.buttons["source-detail-install"].tap()
        proof("https://example.org/g3.ipa", app)
        history.tap()
        for v in ["3.0", "2.0", "1.0"] { XCTAssertTrue(app.buttons["source-version-" + v].waitForExistence(timeout: 5)) }
        shot("grouped-history", app)
        app.buttons["source-version-1.0"].tap()
        proof("https://example.org/g1.ipa", app)
        app.buttons["source-version-2.0"].tap()
        proof("https://example.org/g2.ipa", app)
        shot("grouped-selected", app)
        app.terminate()
    }
}
