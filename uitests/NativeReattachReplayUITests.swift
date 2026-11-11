import XCTest

/// Native rendering of exact extracted API messages. No live HTTP or download claim.
final class NativeReattachReplayUITests: XCTestCase {
    func testEveryDistinctCapturedResendRenders() throws {
        let cases: [(String, String)] = [
            ("النسخة (1) · MirsaFixture-v1.zip", "ffbcb6997b6edd2e5002f87ec27882f6637debbeb09a7fda531c49e709927dab"),
            ("النسخة المصحّحة (2) · MirsaFixture-v2.zip", "e74644d2663d70d6d4f5258bf54aedf4bc0006ad8f753af9f2aa92ccfc5ab8ce"),
            ("النسخة المصحّحة (2) · MirsaFixture-v2.zip", "3af5af9bb1d53c769ad41b0ac88e8c85947dbfebb8ae17c2ffefef5a52b548ac"),
            ("النسخة المصحّحة (2) · MirsaFixture-v2.zip", "e388d9fa49d699cc4a73a933d038d74d81ecbd10ffab48ac4797aa9c9cc80ab8"),
            ("النسخة المصحّحة (2) · MirsaFixture-v2.zip", "9a9b0c59a554be468cd0974809d21fa50035e54c2951712a4171c3ce2243027d")
        ]
        for (index, item) in cases.enumerated() {
            let app = XCUIApplication()
            app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "mirsa-ai-chat",
                                   "-MirsaChatFixture", "-mirsa.appLanguage", "ar",
                                   "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
            app.launchEnvironment["MIRSA_NATIVE_REPLAY_INDEX"] = String(index)
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            let filename = app.staticTexts[item.0].firstMatch
            XCTAssertTrue(filename.waitForExistence(timeout: 20), "Captured filename missing")
            XCTAssertTrue(filename.isHittable, "Newest captured card offscreen")
            let share = app.buttons["شارك"].firstMatch
            XCTAssertTrue(share.waitForExistence(timeout: 5))
            XCTAssertTrue(share.isHittable, "ZIP share route unavailable")
            XCTAssertFalse(app.buttons["ثبّت"].exists, "ZIP incorrectly routed as IPA")
            // Do not tap. The approved replay has no credential or download authority.
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "resend_\(index)_fragment_\(item.1)"
            shot.lifetime = .keepAlways
            add(shot)
            let tree = XCTAttachment(string: "Fragment canonical SHA256=\(item.1)\nExpected route=ZIP share, not exercised\n" + app.debugDescription)
            tree.name = "resend_\(index)_accessibility"
            tree.lifetime = .keepAlways
            add(tree)
            XCTAssertEqual(app.state, .runningForeground)
            app.terminate()
        }
    }
}
