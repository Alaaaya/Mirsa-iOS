import XCTest

final class ArabicTranslate31UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testGlobeRowUnderInstallAllFiveLanguages() {
        let titles = ["en": "Translate to Arabic", "ar": "ترجم للعربي", "de": "Ins Arabische übersetzen", "kmr": "Bi Erebî wergerîne", "ckb": "وەریبگێڕە بۆ عەرەبی"]
        for lang in ["en", "ar", "de", "kmr", "ckb"] {
            let app = XCUIApplication()
            app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "sources-ts-small", "-MirsaSourceVersionsFixture24", "-mirsa.appLanguage", lang,
                                   "-mirsa.sourceTheme", "aurora", "-AppleLanguages", "(\(lang))", "-AppleLocale", lang]
            app.launch()
            XCTAssertTrue(app.staticTexts["History App"].waitForExistence(timeout: 12))
            app.staticTexts["History App"].firstMatch.tap()
            let install = app.buttons["source-detail-install"]
            XCTAssertTrue(install.waitForExistence(timeout: 5))
            let toggle = app.switches["source-detail-translate-ar"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[titles[lang]!].exists)
            XCTAssertGreaterThan(toggle.frame.minY, install.frame.maxY - 1, "row sits under install")
            XCTAssertEqual(toggle.value as? String, "0")
            toggle.tap()
            XCTAssertEqual(toggle.value as? String, "1")
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = "ar31-" + lang; image.lifetime = .keepAlways; add(image)
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "ar31-" + lang + "-AX"; tree.lifetime = .keepAlways; add(tree)
            toggle.tap()
            XCTAssertEqual(toggle.value as? String, "0")
            app.terminate()
        }
    }
    func testProjectSigningGlobeAllFiveLanguages() {
        let titles = ["en": "Translate to Arabic", "ar": "ترجم للعربي", "de": "Ins Arabische übersetzen", "kmr": "Bi Erebî wergerîne", "ckb": "وەریبگێڕە بۆ عەرەبی"]
        for lang in ["en", "ar", "de", "kmr", "ckb"] {
            let app = XCUIApplication()
            app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "certificate-parity-29", "-mirsa.appLanguage", lang,
                                   "-AppleLanguages", "(\(lang))", "-AppleLocale", lang]
            app.launch()
            let editor = app.scrollViews["mirsa.project.editor-scroll"]
            XCTAssertTrue(editor.waitForExistence(timeout: 15))
            let toggle = app.switches["project-sign-translate-ar"]
            let sign = app.buttons["mirsa.project.sign"]
            func clear() -> Bool {
                guard toggle.exists, toggle.isHittable else { return false }
                let point = toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).screenPoint
                return point.y > editor.frame.minY + 20 && point.y < min(editor.frame.maxY, sign.frame.minY) - 20
            }
            for _ in 0..<20 { if clear() { break }; editor.swipeUp() }
            XCTAssertTrue(clear(), "Signing translation thumb must be visible above export bar")
            XCTAssertTrue(toggle.label.contains(titles[lang]!))
            XCTAssertEqual(toggle.value as? String, "0")
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "1")
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = "ar32-project-" + lang; image.lifetime = .keepAlways; add(image)
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "ar32-project-" + lang + "-AX"; tree.lifetime = .keepAlways; add(tree)
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "0")
            XCTAssertEqual(app.state, .runningForeground)
            app.terminate()
        }
    }

}
