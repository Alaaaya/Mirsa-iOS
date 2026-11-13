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

    /// Each page of the App Store section's own tab bar, with a harmless fixture account
    /// (DEBUG harness only, no Apple request). Arabic and English.
    private func captureStorePages(lang: String) {
        let pages: [(tab: String, route: String?, name: String)] = [
            ("search", nil, "search"), ("downloads", nil, "downloads"), ("purchases", nil, "purchases"),
            ("account", nil, "account"), ("account", "settings", "settings"),
        ]
        for page in pages {
            let app = XCUIApplication()
            var args = ["-MirsaUITestHarness", "-MirsaStylePage", "encrypted", "-MirsaStoreFixtureAccount",
                        "-MirsaStoreTab", page.tab,
                        "-mirsa.appLanguage", lang,
                        "-AppleLanguages", lang == "en" ? "(en)" : "(ar)",
                        "-AppleLocale", lang == "en" ? "en_US" : "ar"]
            if let route = page.route { args += ["-MirsaStoreRoute", route] }
            app.launchArguments = args
            app.launch()
            Thread.sleep(forTimeInterval: 2.0)
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let alert = springboard.alerts.firstMatch
            if alert.waitForExistence(timeout: 1) {
                let deny = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow", "عدم السماح"])).firstMatch
                if deny.exists { deny.tap() } else { alert.buttons.firstMatch.tap() }
            }
            Thread.sleep(forTimeInterval: 2.0)
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            a.name = "store_\(page.name)_\(lang)"
            a.lifetime = .keepAlways
            add(a)
            if page.name == "settings" && app.state == .runningForeground {
                for _ in 0..<3 { app.swipeUp() }
                Thread.sleep(forTimeInterval: 1.0)
                let b = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                b.name = "store_\(page.name)_\(lang)-bottom"
                b.lifetime = .keepAlways
                add(b)
            }
            XCTAssertEqual(app.state, .runningForeground, "app crashed on App Store \(page.name) (\(lang))")
            app.terminate()
        }
    }

    func testAppStoreSectionPages() {
        for lang in ["ar", "en"] { captureStorePages(lang: lang) }
    }
}
