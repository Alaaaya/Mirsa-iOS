import XCTest

/// These views use the actual loaded catalogues, not a recreated mock storefront.
final class SourceStoreScreenshotsUITests: XCTestCase {
    func testStoreAndClassicArabicEnglish() {
        continueAfterFailure = false
        for language in ["ar", "en"] {
            for layout in ["store", "classic"] {
                let app = XCUIApplication()
                app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "sources-\(layout)-live",
                                       "-mirsa.appLanguage", language, "-AppleLanguages", "(\(language))",
                                       "-AppleLocale", language, "-mirsa.sources.layout", layout]
                app.launch()
                let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                let permission = springboard.alerts.firstMatch
                if permission.waitForExistence(timeout: 2) { permission.buttons.firstMatch.tap() }
                if layout == "store" {
                    XCTAssertTrue(app.otherElements["sources-store-front"].waitForExistence(timeout: 15), app.debugDescription)
                    XCTAssertTrue(app.otherElements["sources-store-featured"].waitForExistence(timeout: 90), "No real catalogue apps loaded. " + app.debugDescription)
                } else {
                    XCTAssertTrue(app.staticTexts["Mirsa"].firstMatch.waitForExistence(timeout: 20), app.debugDescription)
                }
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = "sources_\(layout)_\(language)"
                shot.lifetime = .keepAlways
                add(shot)
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "sources_\(layout)_\(language)_hierarchy"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
                app.terminate()
            }
        }
    }
}
