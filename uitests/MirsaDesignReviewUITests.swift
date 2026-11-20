import XCTest

final class MirsaDesignReviewUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testConceptGallery() {
        for page in ["discover", "details", "search", "downloads", "account"] {
            let app = XCUIApplication()
            app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "encrypted",
                "-mirsa.appLanguage", "ar", "-mirsa.theme", "classic",
                "-mirsa.store.style", "new", "-AppleLanguages", "(ar)", "-AppleLocale", "ar",
                "-MirsaStoreFixtureAccount", "-MirsaStoreTab", page == "details" ? "search" : page]
            if page == "details" { app.launchArguments.append("-MirsaStoreFixtureDetail") }
            app.launch()
            Thread.sleep(forTimeInterval: 5)
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let alert = springboard.alerts.firstMatch
            if alert.exists { alert.buttons.firstMatch.tap() }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "store-gallery-capsule").firstMatch.waitForExistence(timeout: 15))
            if page == "details" { XCTAssertTrue(app.buttons["store-detail-get"].exists) }
            Thread.sleep(forTimeInterval: 2)
            let name = "concept1_ar_dark_" + page
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = name + "_hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }
}
