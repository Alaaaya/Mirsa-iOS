import XCTest

/// Arabic feed content, not just Arabic app chrome, on the real animated ContentView.
final class MirsaArabicFeed22UITests: XCTestCase {
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func verify(_ language: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaLiveStyle", "-MirsaStylePage", "sources-real",
            "-MirsaArabicFeedFixture22", "-mirsa.sourceTheme", "sunset",
            "-mirsa.appLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        let source = app.staticTexts["مكتبة مرسى العربية"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 20))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow", "عدم السماح"])).firstMatch
        if deny.waitForExistence(timeout: 2) { deny.tap() }
        XCTAssertTrue(source.isHittable)
        capture("feed22-\(language)-arabic-source-list")
        source.tap()
        let title = app.staticTexts["يوتيوب بلس"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["فيديو وموسيقى بلا حدود"].firstMatch.exists)
        capture("feed22-\(language)-arabic-app-row")
        title.tap()
        XCTAssertTrue(app.buttons["source-detail-install"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["يوتيوب بلس"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["مطور عربي"].firstMatch.exists)
        capture("feed22-\(language)-arabic-app-detail")
        app.swipeUp()
        let description = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "هذا وصف عربي")).firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 10))
        XCTAssertTrue(description.isHittable)
        capture("feed22-\(language)-arabic-paragraph")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(description.waitForExistence(timeout: 10))
        capture("feed22-\(language)-arabic-paragraph-return")
        app.terminate()
    }
    func testArabicFeedInEnglishChrome() throws { try verify("en") }
    func testArabicFeedInArabicChrome() throws { try verify("ar") }
}
