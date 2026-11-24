import XCTest

final class MirsaLicense24UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "license24-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "license24-" + name + "-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }

    func testMirsaFirstAndUpstreamAttributionInAllFiveLanguages() {
        let notes = [
            "en": "Credit \"Based on Mirsa\" and share the full corresponding source under the same license.",
            "ar": "اذكر \"Based on Mirsa\" وانشر الكود المصدري الكامل بنفس الترخيص.",
            "de": "Nenne \"Based on Mirsa\" und veröffentliche den vollständigen zugehörigen Quellcode unter derselben Lizenz.",
            "ckb": "\"Based on Mirsa\" بنووسە و تەواوی کۆدی سەرچاوەی پەیوەندیدار بە هەمان مۆڵەتنامە بڵاو بکەرەوە.",
            "kmr": "Navê \"Based on Mirsa\" bi bîr bîne û hemû koda çavkaniyê ya têkildar bi heman lîsansê belav bike."
        ]
        let fullTitles = ["en": "Full license", "ar": "نص الترخيص الكامل", "de": "Vollständige Lizenz",
                          "ckb": "دەقی تەواوی مۆڵەتنامە", "kmr": "Nivîsa tevahî ya lîsansê"]
        for lang in ["en", "ar", "de", "kmr", "ckb"] {
            let app = XCUIApplication()
            app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "licenses",
                                   "-mirsa.appLanguage", lang, "-AppleLanguages", "(\(lang))", "-AppleLocale", lang]
            app.launch()
            let open = app.buttons["licenses-open"]
            XCTAssertTrue(open.waitForExistence(timeout: 15)); open.tap()
            let mirsa = app.staticTexts["license-name-Mirsa"]
            XCTAssertTrue(mirsa.waitForExistence(timeout: 10))
            XCTAssertEqual(mirsa.label, "Mirsa")
            XCTAssertTrue(mirsa.isHittable)
            XCTAssertEqual(app.staticTexts["license-badge-Mirsa"].label, "Mirsa License")
            XCTAssertEqual(app.staticTexts["license-note-Mirsa"].label, notes[lang]!)
            let link = app.descendants(matching: .any)["license-link-Mirsa"].firstMatch
            XCTAssertTrue(link.exists)
            XCTAssertEqual(link.label, "https://github.com/Alaaaya/Mirsa-iOS/blob/main/LICENSE")
            let next = app.staticTexts["license-name-isideload"]
            if next.exists { XCTAssertLessThan(mirsa.frame.minY, next.frame.minY) }
            XCTAssertFalse(app.staticTexts["Mirsa base code"].exists)
            shot(app, lang + "-mirsa-first")
            let upstream = app.staticTexts["license-name-AirCard-iOS"]
            for _ in 0..<10 {
                if upstream.exists && upstream.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(upstream.exists && upstream.isHittable)
            XCTAssertEqual(app.staticTexts["license-badge-AirCard-iOS"].label, "MIT")
            XCTAssertEqual(app.staticTexts["license-note-AirCard-iOS"].label,
                           "Copyright (c) 2026 Johnny Franks. MIT License.")
            XCTAssertEqual(app.descendants(matching: .any)["license-link-AirCard-iOS"].firstMatch.label, "https://github.com/Mak5er/AirCard-iOS")
            shot(app, lang + "-upstream")
            let disclosure = app.buttons[fullTitles[lang]!]
            for _ in 0..<4 { if disclosure.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(disclosure.isHittable); disclosure.tap()
            let notice = app.staticTexts["license-full-notice-AirCard-iOS"]
            XCTAssertTrue(notice.waitForExistence(timeout: 5))
            XCTAssertTrue(notice.label.contains("Copyright (c) 2026 Johnny Franks"))
            XCTAssertTrue(notice.label.contains("Permission is hereby granted, free of charge"))
            XCTAssertTrue(notice.label.contains("OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE"))
            XCTAssertTrue(notice.label.contains("SOFTWARE."))
            shot(app, lang + "-full-mit")
            app.terminate()
        }
    }
}
