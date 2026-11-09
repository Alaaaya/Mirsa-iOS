import XCTest

/// Screenshots of the Encrypted tab (fixture library, DEBUG harness only) in all four languages.
final class EncryptedTabScreenshotsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private func capture(lang: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "encrypted",
                               "-mirsa.appLanguage", lang,
                               "-AppleLanguages", lang == "en" ? "(en)" : "(ar)",
                               "-AppleLocale", lang == "en" ? "en_US" : "ar"]
        app.launch()
        Thread.sleep(forTimeInterval: 2.0)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 1) {
            let deny = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow", "عدم السماح"])).firstMatch
            if deny.exists { deny.tap() } else { alert.buttons.firstMatch.tap() }
        }
        Thread.sleep(forTimeInterval: 1.5)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "encrypted_\(lang)"
        a.lifetime = .keepAlways
        add(a)
        if app.state == .runningForeground {
            for _ in 0..<3 { app.swipeUp() }
            Thread.sleep(forTimeInterval: 1.0)
            let b = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            b.name = "encrypted_\(lang)-bottom"
            b.lifetime = .keepAlways
            add(b)
        }
        XCTAssertEqual(app.state, .runningForeground, "app crashed on the Encrypted tab (\(lang))")
        app.terminate()
    }

    func testEncryptedTabAllLanguages() {
        for lang in ["ar", "ckb", "kmr", "en"] { capture(lang: lang) }
    }
}
