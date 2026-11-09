import XCTest

/// Screenshot of the REAL ForgeChatThreadView with a seeded no-network store (DEBUG harness only).
final class MirsaAIChatFixtureUITests: XCTestCase {
    func testChatFixtureScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "mirsa-ai-chat", "-MirsaChatFixture",
                               "-mirsa.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["chat-welcome"].waitForExistence(timeout: 15), "welcome text missing")
        XCTAssertTrue(app.staticTexts["chat-waiting"].waitForExistence(timeout: 5), "working indicator missing")
        XCTAssertTrue(app.staticTexts["Make me a tweak that hides the dock labels."].exists, "user bubble missing")
        XCTAssertTrue(app.staticTexts["Got it. I'll build it and send it here when it's ready."].exists, "assistant reply missing")
        Thread.sleep(forTimeInterval: 1.5)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "mirsa_ai_chat"; a.lifetime = .keepAlways; add(a)
        XCTAssertEqual(app.state, .runningForeground)
        app.terminate()
    }

    func testChatFixtureScreenshotArabic() {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "mirsa-ai-chat", "-MirsaChatFixture",
                               "-mirsa.appLanguage", "ar", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
        XCTAssertTrue(app.staticTexts["chat-welcome"].waitForExistence(timeout: 15), "welcome text missing")
        XCTAssertTrue(app.staticTexts["chat-waiting"].waitForExistence(timeout: 5), "working indicator missing")
        Thread.sleep(forTimeInterval: 1.5)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "mirsa_ai_chat_ar"; a.lifetime = .keepAlways; add(a)
        XCTAssertEqual(app.state, .runningForeground)
        app.terminate()
    }
}
