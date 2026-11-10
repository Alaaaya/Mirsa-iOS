import XCTest

/// Screenshot of the REAL ForgeChatThreadView with a seeded no-network store (DEBUG harness only).
final class MirsaAIChatFixtureUITests: XCTestCase {
    private func openEmptyChat(_ state: String = "", theme: String = "liquid", largeText: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "mirsa-ai-embedded", "-MirsaChatFixture",
                               "-MirsaChatEmbeddedFixture", "-MirsaChatEmptyFixture", "-mirsa.theme", theme,
                               "-mirsa.appLanguage", "ar", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        if !state.isEmpty { app.launchArguments.append(state) }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let newChat = app.buttons["chat-new"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 20))
        newChat.tap()
        XCTAssertTrue(app.staticTexts["chat-welcome"].waitForExistence(timeout: 10))
        return app
    }

    private func waitForLandscape(_ app: XCUIApplication) -> Bool {
        let predicate = NSPredicate { _, _ in app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app)], timeout: 10) == .completed
    }

    private func assertComposer(_ app: XCUIApplication, keyboard: Bool = false, liquid: Bool = true, name: String) {
        // SwiftUI.VerticalTextView reports conflicting legacy/modern element types
        // on iOS 26. Query its stable identifier without a TextField/TextView filter.
        let input = app.descendants(matching: .any).matching(identifier: "chat-input").firstMatch
        guard input.waitForExistence(timeout: 10) else {
            print("COMPOSER_ACCESSIBILITY_TREE \(app.debugDescription)")
            let failure = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            failure.name = "missing_" + name; failure.lifetime = .keepAlways; add(failure)
            XCTFail("composer missing")
            return
        }
        XCTAssertTrue(input.isHittable, "composer not reachable")
        let bounds = app.windows.firstMatch.frame
        XCTAssertGreaterThan(input.frame.width, 30)
        XCTAssertGreaterThanOrEqual(input.frame.minY, bounds.minY)
        XCTAssertLessThanOrEqual(input.frame.maxY, bounds.maxY)
        let send = app.buttons["chat-send"]
        XCTAssertTrue(send.exists)
        XCTAssertLessThanOrEqual(send.frame.maxY, bounds.maxY)
        if keyboard {
            let keys = app.keyboards.firstMatch
            XCTAssertTrue(keys.waitForExistence(timeout: 5))
            XCTAssertLessThanOrEqual(input.frame.maxY, keys.frame.minY + 1, "composer obscured by keyboard")
        } else if liquid {
            // SwiftUI exposes this HStack's identifier on its tab buttons.
            // Require the real dock, rather than silently skipping its geometry.
            let dock = app.buttons.matching(identifier: "mirsa-tab-dock").firstMatch
            XCTAssertTrue(dock.exists, "floating dock missing in liquid theme")
            if dock.exists {
                XCTAssertLessThanOrEqual(input.frame.maxY, dock.frame.minY + 1, "composer obscured by dock")
                XCTAssertLessThanOrEqual(send.frame.maxY, dock.frame.minY + 1, "send button obscured by dock")
                let status = app.staticTexts["chat-composer-status"]
                if status.exists {
                    XCTAssertLessThanOrEqual(status.frame.maxY, dock.frame.minY + 1, "inline status obscured by dock")
                }
            }
        }
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testEmptyNewChatComposerKeyboardAndRotation() {
        let app = openEmptyChat()
        assertComposer(app, name: "empty_portrait")
        XCTAssertFalse(app.buttons["chat-send"].isEnabled)
        let input = app.descendants(matching: .any).matching(identifier: "chat-input").firstMatch
        input.tap(); input.typeText("hello")
        XCTAssertTrue(app.buttons["chat-send"].isEnabled)
        assertComposer(app, keyboard: true, name: "empty_portrait_keyboard")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitForLandscape(app))
        assertComposer(app, keyboard: true, name: "empty_landscape_keyboard")
        app.swipeDown()
        // Interactive keyboard dismissal can depend on scroll position. Relaunch to
        // assert the keyboard-off landscape independently of that gesture.
        app.terminate()
        let landscape = openEmptyChat()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitForLandscape(landscape))
        assertComposer(landscape, name: "empty_landscape")
        landscape.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testQuotaZeroKeepsComposerAndInlineStatus() {
        let app = openEmptyChat("-MirsaChatQuotaFixture")
        assertComposer(app, name: "quota_zero")
        XCTAssertTrue(app.staticTexts["chat-composer-status"].exists)
        app.terminate()
    }

    func testRegistrationFailureKeepsComposerAndInlineStatus() {
        let app = openEmptyChat("-MirsaChatRegistrationFailureFixture")
        assertComposer(app, name: "registration_failed")
        XCTAssertTrue(app.staticTexts["chat-composer-status"].exists)
        app.terminate()
    }

    func testRegistrationPendingClassicLargeTextKeepsComposer() {
        let app = openEmptyChat("-MirsaChatRegistrationPendingFixture", theme: "classic", largeText: true)
        assertComposer(app, liquid: false, name: "registration_pending_classic_large_text")
        app.terminate()
    }

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
