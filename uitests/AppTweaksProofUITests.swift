import XCTest

/// Proof only: unchanged app, endpoint override pointing at an isolated local catalogue source.
final class AppTweaksProofUITests: XCTestCase {
    func testServerFedAppTweaksArabic() throws {
        continueAfterFailure = false
        let language = MirsaUILanguages.primary
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "tools",
                               "-mirsa.toolsStore.endpoint", "https://localhost:8443/",
                               "-mirsa.appLanguage", language, "-mirsa.sourceTheme", "aurora",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 3) { alert.buttons.firstMatch.tap() }
        let tab = app.buttons["tools-section-store"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10)); tab.tap()
        let cat = app.buttons["tools-store-cat-app_tweaks"]
        XCTAssertTrue(cat.waitForExistence(timeout: 30), "app_tweaks tab must appear from the server feed")
        cat.tap()
        XCTAssertTrue(app.staticTexts["SCInsta"].firstMatch.waitForExistence(timeout: 20))
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "\(language)_app_tweaks_scinsta_server_fed"; a.lifetime = .keepAlways; add(a)
    }
}
