import XCTest

/// Captures the real chat view with deterministic debug data. Recording screenshots
/// exercise UI state, not a claim of a real device microphone/production roundtrip.
final class MirsaVoiceUITests: XCTestCase {
    private func launch(_ state: String?, language: String = "ar", theme: String = "dark") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "mirsa-ai-chat",
            "-MirsaChatFixture", "-MirsaChatAttachmentsFixture", "-mirsa.chat.reactionsTipDismissed", "YES",
            "-mirsa.chat.appearance", theme, "-mirsa.appLanguage", language,
            "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        if let state { app.launchArguments.append(state) }
        app.launch()
        XCTAssertTrue(app.buttons["chat-back"].waitForExistence(timeout: 25))
        return app
    }
    private func shot(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testVoiceComposerScreenshots() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        for language in ["ar", "en", "de", "kmr", "ckb"] {
            let idle = launch(nil, language: language)
            XCTAssertTrue(idle.buttons["chat-voice-record"].exists)
            XCTAssertTrue(idle.buttons["chat-attach"].exists)
            shot("voice_idle_\(language)")
            idle.terminate()
            let recording = launch("-MirsaVoiceRecordingFixture", language: language)
            XCTAssertTrue(recording.buttons["chat-voice-discard"].exists)
            XCTAssertTrue(recording.buttons["chat-voice-send"].exists)
            shot("voice_recording_\(language)")
            recording.buttons["chat-voice-discard"].tap()
            XCTAssertTrue(recording.buttons["chat-voice-record"].exists)
            recording.terminate()
            let bubble = launch("-MirsaVoiceBubbleFixture", language: language)
            let play = bubble.buttons["chat-voice-play"]
            XCTAssertTrue(play.waitForExistence(timeout: 10))
            XCTAssertTrue(bubble.descendants(matching: .any)["chat-mirsa-reaction"].exists)
            shot("voice_audio_reaction_\(language)")
            let idleLabel = play.label
            play.tap()
            let pauseLabels = ["ar": "وقّف الصوت", "en": "Pause voice message", "de": "Wiedergabe pausieren", "kmr": "Deng rawestîne", "ckb": "دەنگ بوەستێنە"]
            let started = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", pauseLabels[language]!), object: play)
            XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 5), .completed)
            shot("voice_audio_playing_\(language)")
            play.tap()
            let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", idleLabel), object: play)
            XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 5), .completed)
            shot("voice_audio_paused_\(language)")
            play.tap()
            let resumed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", pauseLabels[language]!), object: play)
            XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 5), .completed)
            if language == "en" {
                let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", idleLabel), object: play)
                XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 20), .completed)
                shot("voice_audio_completed_en")
            }
            bubble.terminate()
        }
        for theme in ["light", "classic"] {
            let app = launch(nil, language: "en", theme: theme)
            XCTAssertTrue(app.buttons["chat-voice-record"].exists)
            shot("voice_idle_\(theme)"); app.terminate()
        }
    }
    func testBotVoiceRepliesReusePlaybackInAllFiveLanguages() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let playLabels = ["ar": "شغّل رد مرسى الصوتي", "en": "Play Mirsa voice reply",
            "de": "Mirsa-Sprachantwort abspielen", "kmr": "Bersiva dengî ya Mirsa bilîze",
            "ckb": "وەڵامی دەنگیی میرسا لێبدە"]
        let pauseLabels = ["ar": "وقّف رد مرسى الصوتي", "en": "Pause Mirsa voice reply",
            "de": "Mirsa-Sprachantwort pausieren", "kmr": "Bersiva dengî ya Mirsa rawestîne",
            "ckb": "وەڵامی دەنگیی میرسا بوەستێنە"]
        for language in ["ar", "en", "de", "kmr", "ckb"] {
            let app = launch("-MirsaBotVoiceBubbleFixture", language: language)
            let play = app.buttons["chat-voice-play"]
            XCTAssertTrue(play.waitForExistence(timeout: 10))
            XCTAssertEqual(play.label, playLabels[language]!)
            XCTAssertEqual(play.value as? String, "0:12")
            XCTAssertTrue(app.buttons["chat-report"].exists, "Voice-only bot replies retain the assistant controls.")
            XCTAssertFalse(app.staticTexts["chat-waiting"].exists)
            shot("bot_voice_idle_\(language)")
            play.tap()
            let started = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", pauseLabels[language]!), object: play)
            XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 5), .completed)
            shot("bot_voice_playing_\(language)")
            play.tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", playLabels[language]!), object: play)], timeout: 5), .completed)
            play.tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", pauseLabels[language]!), object: play)], timeout: 5), .completed)
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", playLabels[language]!), object: play)], timeout: 10), .completed,
                "Backgrounding must stop bot audio too.")
            shot("bot_voice_returned_\(language)")
            app.terminate()
        }
    }

    func testUnavailableBotVoiceDoesNotOfferPlayback() {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "mirsa-ai-chat",
            "-MirsaChatFixture", "-MirsaChatAttachmentsFixture", "-MirsaBotVoiceBubbleFixture",
            "-MirsaBotVoiceExpiredFixture", "-mirsa.chat.reactionsTipDismissed", "YES",
            "-mirsa.appLanguage", "en"]
        app.launch()
        let play = app.buttons["chat-voice-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 25))
        XCTAssertFalse(play.isEnabled)
        shot("bot_voice_unavailable_en")
        app.terminate()
    }

}
