import XCTest

/// Real SwiftUI bubble geometry in the no-network harness, not a production chat.
final class MirsaReactionBadgeUITests: XCTestCase {
    func testReactionBadgeLanguagesAndThemes() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let shortText = ["ar": "هيك", "en": "Like this", "de": "So", "kmr": "Wisa", "ckb": "بەم شێوەیە"]
        for (language, theme) in [("ar", "dark"), ("en", "dark"), ("de", "dark"),
                                  ("kmr", "dark"), ("ckb", "dark"),
                                  ("ar", "light"), ("en", "classic")] {
            let app = XCUIApplication()
            app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "mirsa-ai-chat",
                "-MirsaChatFixture", "-MirsaReactionBadgeFixture",
                "-mirsa.chat.reactionsTipDismissed", "YES", "-mirsa.chat.appearance", theme,
                "-mirsa.appLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            XCTAssertTrue(app.buttons["chat-back"].waitForExistence(timeout: 25))
            let badges = app.descendants(matching: .any).matching(identifier: "chat-mirsa-reaction")
            XCTAssertTrue(badges.firstMatch.waitForExistence(timeout: 10))
            XCTAssertEqual(badges.count, 2)
            XCTAssertFalse(app.descendants(matching: .any)["chat-waiting"].exists,
                           "A bot reaction answers the last user message without a text reply")
            let text = app.staticTexts[shortText[language]!]
            XCTAssertTrue(text.exists)
            let badge = badges.element(boundBy: 0)
            XCTAssertEqual(badge.label, "❤️")
            XCTAssertEqual(badge.frame.width, badge.frame.height, accuracy: 1)
            XCTAssertEqual(badge.frame.width, 32, accuracy: 2)
            // It must overlap the top-left of the actual short bubble, not its
            // invisible 300-point wrapper, in RTL and LTR alike.
            XCTAssertLessThan(badge.frame.midY, text.frame.midY)
            XCTAssertLessThan(abs(badge.frame.midX - text.frame.minX), 28)
            XCTAssertGreaterThan(badge.frame.maxY, text.frame.minY - 20)
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.name = "reaction_badge_\(language)_\(theme)"
            image.lifetime = .keepAlways
            add(image)
            app.terminate()
        }
    }
}
