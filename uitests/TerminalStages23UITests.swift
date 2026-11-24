import XCTest
final class TerminalStages23UITests: XCTestCase {
    func testRealCardRendersSuccessiveStructuredPackets() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let lang = MirsaUILanguages.primary
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "terminal-stages23",
                               "-mirsa.appLanguage", lang, "-AppleLanguages", "(\(lang))", "-AppleLocale", lang]
        app.launch()
        let systemAlert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if systemAlert.waitForExistence(timeout: 2) {
            let deny = systemAlert.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow", "عدم السماح"])).firstMatch
            if deny.exists { deny.tap() } else { systemAlert.buttons.firstMatch.tap() }
        }
        let next = app.buttons["terminal-fixture-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", (lang == "ar" ? "> بالدور" : "> Queued"))).firstMatch.waitForExistence(timeout: 5))
        capture("terminal-queued-synthetic")
        next.tap(); next.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", (lang == "ar" ? "> عم يترجم الكود" : "> Compiling"))).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", (lang == "ar" ? "> استلمها عامل البناء" : "> Picked up by builder"))).firstMatch.exists)
        capture("terminal-compiling-synthetic")
        next.tap(); next.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", (lang == "ar" ? "> عم يرفع المرفق" : "> Uploading the attachment"))).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", (lang == "ar" ? "> عم يجهّز الملف" : "> Packaging the file"))).firstMatch.exists)
        capture("terminal-uploading-synthetic")
    }
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
