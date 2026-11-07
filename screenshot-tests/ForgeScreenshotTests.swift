import XCTest

/// Captures the real, unseeded app after navigating its visible controls.
final class ForgeScreenshotTests: XCTestCase {
    func testToolsTweaksScreenshot() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-mirsa.appLanguage", "ar",
            "-aircard.dont_show_support_on_launch", "YES",
            "-AppleLanguages", "(ar, en)",
            "-AppleLocale", "ar"
        ]
        app.launch()
        defer {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Forge-actual-final-state"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let tools = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@", "الأدوات", "Tools"
        )).firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 30), app.debugDescription)
        tools.tap()

        let tweaks = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@", "التويكس", "Tweaks"
        )).firstMatch
        XCTAssertTrue(tweaks.waitForExistence(timeout: 15), app.debugDescription)
        tweaks.tap()

        XCTAssertTrue(app.staticTexts["ترجم تطبيق"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "اختر IPA")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "تويكس المجتمع")).firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Forge-Tools-Tweaks-Arabic"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
