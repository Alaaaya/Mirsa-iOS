import XCTest

/// Screenshot of the REAL ForgeChatThreadView with a seeded no-network store (DEBUG harness only).
final class MirsaAIChatFixtureUITests: XCTestCase {
    private func openEmptyChat(_ state: String = "", theme: String = "liquid", largeText: Bool = false, language: String = "ar") -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "mirsa-ai-embedded", "-MirsaChatFixture",
                               "-MirsaChatEmbeddedFixture", "-MirsaChatEmptyFixture", "-mirsa.theme", theme,
                               "-mirsa.appLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        if !state.isEmpty { app.launchArguments.append(state) }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        // A relaunch after landscape must finish restoring the full portrait
        // window before a toolbar tap. A transient transformed window can expose
        // an element whose hit point is outside the actual screen.
        let portrait = NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return frame.width >= 300 && frame.height > frame.width
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: portrait, object: app)], timeout: 15), .completed)
        let newChat = app.buttons["chat-new"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 20))
        let reachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: newChat)
        XCTAssertEqual(XCTWaiter.wait(for: [reachable], timeout: 10), .completed)
        newChat.tap()
        XCTAssertTrue(app.staticTexts["chat-welcome"].waitForExistence(timeout: 10))
        return app
    }


    func testPlayfulCatRoofTapAndPassThrough() {
        for language in ["ar", "en"] {
            let app = openEmptyChat(language: language)
            app.buttons["chat-settings"].tap()
            let initialToggle = app.switches["chat-cat-toggle"]
            if initialToggle.value as? String == "0" { initialToggle.tap() }
            app.buttons["chat-settings-close"].tap()
            let cat = app.buttons["chat-playful-cat"]
            XCTAssertTrue(cat.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["chat-send"].exists)
            let input = app.descendants(matching: .any).matching(identifier: "chat-input").firstMatch
            XCTAssertTrue(input.isHittable, "Cat overlay must not swallow composer taps")
            let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            before.name = "playful_roof_\(language)"; before.lifetime = .keepAlways; add(before)
            if cat.isHittable { cat.tap() }
            let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            after.name = "playful_heart_\(language)"; after.lifetime = .keepAlways; add(after)
            input.tap()
            input.typeText("Hello")
            XCTAssertTrue(app.buttons["chat-send"].isEnabled)
            app.buttons["chat-settings"].tap()
            let toggle = app.switches["chat-cat-toggle"]
            if toggle.value as? String != "0" { toggle.tap() }
            assertCatSetting(toggle, enabled: false)
            app.buttons["chat-settings-close"].tap()
            XCTAssertFalse(app.buttons["chat-playful-cat"].exists)
            app.terminate()
        }
    }

    func testCatCompanionStatesAndSettings() {
        for language in ["ar", "en"] {
            for (state, name) in [("", "idle"), ("-MirsaCatThinkingFixture", "thinking"),
                                   ("-MirsaCatSleepingFixture", "sleeping"), ("-MirsaCatHappyFixture", "happy")] {
                let app = openEmptyChat(state, language: language)
                assertComposer(app, name: "cat_\(language)_\(name)")
                // Scroll still belongs to the conversation, never to the decoration.
                app.swipeUp()
                assertComposer(app, name: "cat_\(language)_\(name)_scroll")
                app.terminate()
            }
        }
        for language in ["ar", "en", "de", "kmr", "ckb"] {
            let app = openEmptyChat(language: language)
            app.buttons["chat-settings"].tap()
            let toggle = app.switches["chat-cat-toggle"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            XCTAssertTrue(toggle.isHittable)
            if toggle.value as? String == "0" { toggle.tap() }
            assertCatSetting(toggle, enabled: true)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "cat_settings_\(language)"; shot.lifetime = .keepAlways; add(shot)
            toggle.tap()
            assertCatSetting(toggle, enabled: false)
            app.buttons["chat-settings-close"].tap()
            assertComposer(app, name: "cat_\(language)_disabled")
            // Setting persists while the chat and app are reopened.
            app.terminate()
            let reopened = openEmptyChat(language: language)
            reopened.buttons["chat-settings"].tap()
            let persisted = reopened.switches["chat-cat-toggle"]
            XCTAssertTrue(persisted.waitForExistence(timeout: 5))
            assertCatSetting(persisted, enabled: false)
            persisted.tap()
            reopened.terminate()
        }
    }

    private func assertCatSetting(_ toggle: XCUIElement, enabled: Bool,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed,
                       "Cat setting did not settle to the requested value", file: file, line: line)
    }

    /// Real thread, real composer and existing result attachments, in both material environments.
    func testIsletChatMaterialsAndLanguages() {
        XCUIDevice.shared.orientation = .portrait
        for language in ["ar", "en", "de", "kmr", "ckb"] {
            for light in [false, true] {
                let app = XCUIApplication()
                app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "mirsa-ai-chat", "-MirsaChatFixture",
                                       "-mirsa.chat.catEnabled", "YES", "-mirsa.chat.reactionsTipDismissed", "YES",
                                       "-mirsa.appLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
                app.launchArguments += ["-mirsa.chat.appearance", light ? "light" : "dark"]
                app.launch()
                XCTAssertTrue(app.staticTexts["chat-waiting"].waitForExistence(timeout: 20))
                XCTAssertTrue(app.staticTexts["Thanks, no rush."].exists)
                let appearance = app.buttons["chat-black-background"]
                XCTAssertEqual(appearance.value as? String, light ? "light" : "dark")
                selectTheme(app, light ? "dark" : "light")
                XCTAssertEqual(appearance.value as? String, light ? "dark" : "light")
                assertComposer(app, liquid: false, name: "islet_toggled_\(language)_\(light ? "dark" : "light")")
                selectTheme(app, light ? "light" : "dark")
                XCTAssertEqual(appearance.value as? String, light ? "light" : "dark")
                assertComposer(app, liquid: false, name: "islet_\(language)_\(light ? "light" : "dark")")
                app.buttons["chat-settings"].tap()
                XCTAssertTrue(app.switches["chat-cat-toggle"].waitForExistence(timeout: 5))
                app.buttons["chat-settings-close"].tap()
                let input = app.descendants(matching: .any).matching(identifier: "chat-input").firstMatch
                input.tap()
                input.typeText("Hello")
                XCTAssertTrue(app.buttons["chat-send"].isEnabled)
                assertComposer(app, keyboard: true, liquid: false, name: "islet_\(language)_\(light ? "light" : "dark")_keyboard")
                app.terminate()
            }
        }
        // No appearance override: menu selection must persist across real relaunches.
        for language in ["ar", "en"] {
            let app = XCUIApplication()
            app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "mirsa-ai-chat", "-MirsaChatFixture",
                                   "-mirsa.appLanguage", language]
            app.launch()
            let appearance = app.buttons["chat-black-background"]
            XCTAssertTrue(appearance.waitForExistence(timeout: 20))
            for theme in ["classic", "light", "dark"] {
                selectTheme(app, theme)
                XCTAssertEqual(appearance.value as? String, theme)
                app.terminate()
                app.launch()
                XCTAssertTrue(appearance.waitForExistence(timeout: 20))
                XCTAssertEqual(appearance.value as? String, theme)
                assertComposer(app, liquid: false, name: "three_themes_\(language)_\(theme)")
            }
            app.terminate()
        }
    }

    private func selectTheme(_ app: XCUIApplication, _ theme: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["chat-black-background"].tap()
        let choice = app.buttons["chat-theme-" + theme]
        XCTAssertTrue(choice.waitForExistence(timeout: 5), file: file, line: line)
        choice.tap()
    }

    func testIsletDeliveredAttachmentRemainsReachable() {
        for language in ["ar", "en"] {
            for light in [false, true] {
                let app = XCUIApplication()
                app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "mirsa-ai-chat", "-MirsaChatFixture",
                                       "-MirsaTweakDeliveryFixture", "-mirsa.chat.catEnabled", "YES", "-mirsa.chat.reactionsTipDismissed", "YES",
                                       "-mirsa.appLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
                app.launchArguments += ["-mirsa.chat.appearance", light ? "light" : "dark"]
                app.launch()
                let delivery = app.buttons["mirsa.chat.artifact.inject"]
                XCTAssertTrue(delivery.waitForExistence(timeout: 20))
                let input = app.descendants(matching: .any).matching(identifier: "chat-input").firstMatch
                XCTAssertTrue(input.waitForExistence(timeout: 10))
                // Scroll only the conversation, leaving the composer untouched.
                app.scrollViews.firstMatch.swipeUp()
                let clearOfLane = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    delivery.isHittable && delivery.frame.maxY <= input.frame.minY - 80
                }, object: delivery)
                XCTAssertEqual(XCTWaiter.wait(for: [clearOfLane], timeout: 10), .completed,
                               "Last delivery row overlaps the reserved cat/composer lane")
                let share = app.buttons["mirsa.chat.artifact.download"]
                XCTAssertTrue(share.isHittable)
                XCTAssertLessThanOrEqual(share.frame.maxY, input.frame.minY - 80)
                XCTAssertFalse(app.staticTexts["chat-waiting"].exists, "A completed delivery must not pretend to think")
                assertComposer(app, liquid: false, name: "islet_delivery_\(language)_\(light ? "light" : "dark")")
                app.terminate()
            }
        }
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
            // Since 2.1 a conversation opens full screen (fullScreenCover) over the
            // tab bar. Then the dock is covered and cannot obscure the composer;
            // the composer/send bounds checks above still apply.
            let fullScreen = app.buttons["chat-back"].exists && !(dock.exists && dock.isHittable)
            if fullScreen {
                let status = app.staticTexts["chat-composer-status"]
                if status.exists { XCTAssertLessThanOrEqual(status.frame.maxY, bounds.maxY, "inline status off screen") }
            } else {
            XCTAssertTrue(dock.exists, "floating dock missing in liquid theme")
            }
            if dock.exists && !fullScreen {
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
        // Attachments 2.1 flag OFF: the 2.0 photo button stays, no attachments menu.
        XCTAssertFalse(app.buttons["chat-attach"].exists, "attachments menu must be hidden while the feature flag is off")
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

    func testDraft4000And4001ScalarLimitInAllLanguages() {
        let errors = [
            "en": "Maximum 4,000 characters. Shorten your message or split it into two.",
            "ar": "الحد ٤٠٠٠ حرف. اختصر رسالتك أو قسّمها لرسالتين.",
            "ckb": "زۆرترین ٤٠٠٠ پیت. نامەکەت کورت بکەوە یان بیکە بە دوو نامە.",
            "kmr": "Herî zêde 4.000 tîp. Peyamê kurt bike an bike du peyam."
        ]
        for language in ["en", "ar", "ckb", "kmr"] {
            for count in [4000, 4001] {
                let app = openEmptyChat("-MirsaChatDraft\(count)Fixture", language: language)
                assertComposer(app, name: "draft_\(count)_\(language)")
                let counter = app.staticTexts["chat-character-limit"]
                XCTAssertTrue(counter.waitForExistence(timeout: 5))
                XCTAssertTrue(counter.label.hasPrefix("\(count) / 4000 "))
                XCTAssertEqual(app.buttons["chat-send"].isEnabled, count == 4000)
                let input = app.descendants(matching: .any).matching(identifier: "chat-input").firstMatch
                XCTAssertEqual((input.value as? String)?.unicodeScalars.count, count, "Draft was truncated")
                // Accessibility exposes the counter, while the full localized error remains visible.
                if count == 4001 {
                    XCTAssertEqual(counter.value as? String, errors[language])
                }
                app.terminate()
            }
        }
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

    /// Mirsa 2.1 attachment rules (URL validation, text files, JPEG normalisation) run in-app.
    func testAttachmentRulesSelfTest() {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "mirsa-ai-chat", "-MirsaChatFixture",
                               "-MirsaAttachmentRulesSelfTest", "-mirsa.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let badge = app.staticTexts["attachment-rules-selftest"]
        XCTAssertTrue(badge.waitForExistence(timeout: 20), "self-test badge missing")
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != 'RUNNING'"), object: badge)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 30), .completed)
        XCTAssertEqual(badge.label, "PASS")
        app.terminate()
    }

    /// Attachments menu (DEBUG fixture only, the release flag stays OFF): From link refuses an IPA link.
    func testAttachmentMenuFixtureRejectsIPALink() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "mirsa-ai-chat", "-MirsaChatFixture",
                               "-MirsaChatAttachmentsFixture", "-mirsa.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["chat-welcome"].waitForExistence(timeout: 15))
        let attach = app.buttons["chat-attach"]
        XCTAssertTrue(attach.waitForExistence(timeout: 10), "attachments menu missing in fixture")
        attach.tap()
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Files"].exists)
        let link = app.buttons["From link"]
        XCTAssertTrue(link.exists)
        let menu = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        menu.name = "attachments_menu"; menu.lifetime = .keepAlways; add(menu)
        link.tap()
        let field = app.textFields["chat-link-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("https://example.com/Mirsa.ipa")
        app.buttons["chat-link-add"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "chat-link-error").firstMatch.waitForExistence(timeout: 5), "IPA link was not refused")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "attachments_link_ipa_refused"; shot.lifetime = .keepAlways; add(shot)
        app.terminate()
    }
}
