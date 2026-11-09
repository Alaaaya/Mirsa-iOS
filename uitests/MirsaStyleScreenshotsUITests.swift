import XCTest

/// Captures every reachable page for the style review. Each page is hosted by the
/// DEBUG-only MirsaStyleShotHost (launch argument -MirsaStylePage). No assertions on
/// content: a page that fails to render still yields a screenshot of what is shown.
final class MirsaStyleScreenshotsUITests: XCTestCase {
    private static let pages: [String] = [
        "apps", "sources", "tools", "encrypted", "more", "home-main", "home-personal", "setup",
        "settings", "login", "url-import", "discovery", "certificates", "personal-certificate",
        "signing-queue", "telemetry", "credits", "pairing-guide", "support-popup", "licenses",
        "github-sources", "expiry", "web-upload", "browser", "update", "hidden", "prompt",
        "app-info", "backups", "tweak-library", "no-profile-guide",
    ]
    /// Long pages also get a second screenshot scrolled to the bottom.
    private static let scrolled: Set<String> = ["apps", "sources", "tools", "more", "setup", "settings",
                                                 "pairing-guide", "support-popup", "certificates", "discovery", "credits"]

    override func setUpWithError() throws { continueAfterFailure = true }

    private func launch(_ page: String, lang: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", page,
                               "-mirsa.appLanguage", lang,
                               "-AppleLanguages", lang == "en" ? "(en)" : "(ar)",
                               "-AppleLocale", lang == "en" ? "en_US" : "ar"]
        app.launch()
        Thread.sleep(forTimeInterval: 2.0)
        // First launch asks for notification permission; the system alert would hide the page.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 1) {
            let deny = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow", "عدم السماح"])).firstMatch
            if deny.exists { deny.tap() } else { alert.buttons.firstMatch.tap() }
        }
        Thread.sleep(forTimeInterval: 1.5)
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        guard alive(app) else { print("STYLE-SHOT-SKIPPED \(name): app not running"); return }
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func alive(_ app: XCUIApplication) -> Bool { app.state == .runningForeground }

    private func tap(_ app: XCUIApplication, _ labels: [String]) -> Bool {
        guard alive(app) else { return false }
        for l in labels {
            let b = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", l)).firstMatch
            if b.waitForExistence(timeout: 3), b.isHittable { b.tap(); Thread.sleep(forTimeInterval: 1.5); return true }
        }
        return false
    }

    private func scrollToBottom(_ app: XCUIApplication) {
        guard alive(app) else { return }
        for _ in 0..<4 where alive(app) { app.swipeUp(velocity: .fast) }
        Thread.sleep(forTimeInterval: 1.2)
    }

    private func run(lang: String) {
        for page in Self.pages {
            let app = launch(page, lang: lang)
            shot(app, "\(lang)_\(page)")
            if Self.scrolled.contains(page) && alive(app) {
                scrollToBottom(app)
                shot(app, "\(lang)_\(page)-bottom")
            }
            switch page {
            case "apps":
                app.terminate()
                let a = launch(page, lang: lang)
                if tap(a, ["Real Apps", "تطبيقات حقيقية"]) { shot(a, "\(lang)_apps-real") }
                if tap(a, ["Downloads", "التنزيلات"]) { shot(a, "\(lang)_apps-downloads") }
                a.terminate()
            case "tools":
                app.terminate()
                let a = launch(page, lang: lang)
                if tap(a, ["Device", "الجهاز"]) { shot(a, "\(lang)_tools-device") }
                if tap(a, ["Tweaks", "التويكس"]) { shot(a, "\(lang)_tools-tweaks"); if alive(a) { scrollToBottom(a); shot(a, "\(lang)_tools-tweaks-bottom") } }
                if tap(a, ["Translation", "الترجمة"]) { shot(a, "\(lang)_tools-translate") }
                a.terminate()
            default:
                app.terminate()
            }
        }
    }

    func testArabicPages() { run(lang: "ar") }
    func testEnglishPages() { run(lang: "en") }
}
