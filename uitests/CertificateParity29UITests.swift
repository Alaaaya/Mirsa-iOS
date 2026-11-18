import XCTest

/// Exercises the real editor and its bindings with a DEBUG-only, non-account fixture.
/// Does not sign, install, import a certificate, or claim on-device App Group success.
final class CertificateParity29UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func verify(_ lang: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "certificate-parity-29",
                               "-mirsa.appLanguage", lang, "-AppleLanguages", "(\(lang))",
                               "-AppleLocale", lang]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 2) {
            let deny = alert.buttons.matching(NSPredicate(format: "label IN %@",
                ["Don’t Allow", "Don't Allow", "عدم السماح"])).firstMatch
            if deny.exists { deny.tap() }
        }

        let iconLabel = lang == "ar" ? "تغيير أيقونة التطبيق" : "Change app icon"
        let icon = app.buttons[iconLabel]
        XCTAssertTrue(icon.waitForExistence(timeout: 15))
        icon.tap()
        XCTAssertTrue(app.buttons[lang == "ar" ? "الصور" : "Photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[lang == "ar" ? "الملفات" : "Files"].exists)
        screenshot("certificate-29-\(lang)-real-icon-menu")
        // Dismiss the menu without opening Photos or the filesystem.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()

        let rows: [(String, String, String)] = [
            ("Enable Files access", "تمكين الوصول إلى الملفات", "1"),
            ("Omit embedded profile", "عدم تضمين البروفايل", "0"),
            ("Fix dark icon (iOS 18)", "إصلاح الأيقونة الداكنة (iOS 18)", "0"),
            ("Direct injection (main executable)", "حقن مباشر بالملف الرئيسي", "0"),
            ("New tweaks first", "الإضافات الجديدة أولاً", "0")
        ]
        for (en, ar, expected) in rows {
            let title = lang == "ar" ? ar : en
            let control = app.switches.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
            for _ in 0..<20 {
                if control.exists && control.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(control.exists, "Missing real editor toggle \(title)")
            XCTAssertTrue(control.isHittable, "Unreachable editor toggle \(title)")
            XCTAssertEqual(control.value as? String, expected, "Unexpected initial value \(title)")
            control.tap()
            XCTAssertEqual(control.value as? String, expected == "1" ? "0" : "1")
            control.tap()
            XCTAssertEqual(control.value as? String, expected, "Binding did not round-trip \(title)")
            screenshot("certificate-29-\(lang)-\(en)")
        }
        XCTAssertEqual(app.state, .runningForeground)
        app.terminate()
    }

    func testEnglishRealEditorSettingsAndIconMenu() { verify("en") }
    func testArabicRealEditorSettingsAndIconMenu() { verify("ar") }
}
