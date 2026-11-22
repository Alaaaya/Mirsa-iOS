import XCTest

/// Runtime checks for the store single-action fix and the Settings > Certificates sheet.
/// Uses only the DEBUG fixtures (no Apple account, no signing).
final class StoreSingleActionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func launchDetail(style: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "encrypted",
            "-mirsa.appLanguage", "en", "-mirsa.theme", "classic", "-mirsa.store.style", style,
            "-AppleLanguages", "(en)", "-AppleLocale", "en",
            "-MirsaStoreFixtureAccount", "-MirsaStoreTab", "search", "-MirsaStoreFixtureDetail"]
        app.launch()
        return app
    }

    func testDetailShowsExactlyOneAction() {
        for style in ["new", "classic"] {
            let app = launchDetail(style: style)
            let get = app.buttons["store-detail-get"]
            XCTAssertTrue(get.waitForExistence(timeout: 20), "\(style): free unowned app must show Get")
            XCTAssertFalse(app.buttons["store-detail-download"].exists, "\(style): Download must not show beside Get")
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'store-detail-'")).count
                - app.buttons.matching(identifier: "store-detail-back").count, 1, "\(style): exactly one main action")
            shot("store-detail-single-\(style)")
            app.terminate()
        }
    }

    func testSettingsCertificatesSheetOpensAndCloses() {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "settings",
            "-mirsa.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        let cert = app.buttons["Certificates"]
        XCTAssertTrue(cert.waitForExistence(timeout: 20))
        shot("settings-before")
        for i in 1...2 {
            cert.tap()
            let back = app.buttons["Back"]
            XCTAssertTrue(back.waitForExistence(timeout: 10), "certificate manager sheet \(i) did not open")
            shot("cert-sheet-open-\(i)")
            back.tap()
            XCTAssertTrue(cert.waitForExistence(timeout: 10), "settings not restored after close \(i)")
        }
        shot("settings-after")
    }
}
