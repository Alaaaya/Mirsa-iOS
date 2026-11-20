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
            play.tap()
            let pauseLabels = ["ar": "وقّف الصوت", "en": "Pause voice message", "de": "Wiedergabe pausieren", "kmr": "Deng rawestîne", "ckb": "دەنگ بوەستێنە"]
            let started = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", pauseLabels[language]!), object: play)
            XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 5), .completed)
            shot("voice_audio_playing_\(language)")
            bubble.terminate()
        }
        for theme in ["light", "classic"] {
            let app = launch(nil, language: "en", theme: theme)
            XCTAssertTrue(app.buttons["chat-voice-record"].exists)
            shot("voice_idle_\(theme)"); app.terminate()
        }
    }
}
