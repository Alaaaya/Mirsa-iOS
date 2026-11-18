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
            ("Fix dark icon (iOS 18)", "إصلاح الأيقونة الداكنة (iOS 18)", "1"),
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
            // The AX switch includes its multiline label. Target the actual
            // trailing switch thumb, not the Arabic label's bounding-box center.
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            XCTAssertEqual(control.value as? String, expected == "1" ? "0" : "1")
            // The AX switch includes its multiline label. Target the actual
            // trailing switch thumb, not the Arabic label's bounding-box center.
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            XCTAssertEqual(control.value as? String, expected, "Binding did not round-trip \(title)")
            screenshot("certificate-29-\(lang)-\(en)")
        }
        XCTAssertEqual(app.state, .runningForeground)
        app.terminate()
    }

    func testEnglishRealEditorSettingsAndIconMenu() { verify("en") }
    func testArabicRealEditorSettingsAndIconMenu() { verify("ar") }
    private func launchDock(_ lang: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "dock-clearance-29",
                               "-mirsa.appLanguage", lang, "-AppleLanguages", "(\(lang))", "-AppleLocale", lang]
        app.launch()
        XCTAssertTrue(app.otherElements["mirsa-tab-dock"].waitForExistence(timeout: 20))
        return app
    }

    private func verifySourcesDock(_ lang: String) {
        let app = launchDock(lang)
        let dock = app.otherElements["mirsa-tab-dock"]
        let source = app.staticTexts["Dock Source Last"]
        for _ in 0..<35 {
            if source.exists && source.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(source.exists && source.isHittable)
        let sourceRow = app.cells.containing(.staticText, identifier: "Dock Source Last").firstMatch
        XCTAssertTrue(sourceRow.exists)
        XCTAssertLessThanOrEqual(sourceRow.frame.maxY, dock.frame.minY, "Last source must clear dock")
        screenshot("dock29-\(lang)-last-source")
        source.tap()
        let last = app.staticTexts["Alaa Player"]
        for _ in 0..<45 {
            if last.exists && last.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(last.exists && last.isHittable)
        let row = app.cells.containing(.staticText, identifier: "Alaa Player").firstMatch
        XCTAssertTrue(row.exists)
        XCTAssertLessThanOrEqual(row.frame.maxY, dock.frame.minY,
                                 "The entire pushed destination row, including GET, must clear the dock")
        screenshot("dock29-\(lang)-pushed-source-last-Alaa-Player")
        app.terminate()
    }

    func testEnglishPushedSourceLastRowClearsDock() { verifySourcesDock("en") }
    func testArabicPushedSourceLastRowClearsDock() { verifySourcesDock("ar") }

    func testAllSixRealTabsScrollBoundsClearDock() {
        let app = launchDock("en")
        let dock = app.otherElements["mirsa-tab-dock"]
        for tab in ["Apps", "Sources", "Mirsa AI", "Pairing", "Encrypted", "Personal Apps Hub"] {
            let button = app.buttons["main-tab-" + tab]
            XCTAssertTrue(button.exists && button.isHittable)
            button.tap()
            let containers = app.descendants(matching: .any).matching(NSPredicate(
                format: "elementType IN %@", [XCUIElement.ElementType.scrollView.rawValue,
                    XCUIElement.ElementType.table.rawValue, XCUIElement.ElementType.collectionView.rawValue]))
            let deadline = Date().addingTimeInterval(8)
            var visible: [XCUIElement] = []
            repeat {
                visible = containers.allElementsBoundByIndex.filter {
                    $0.exists && $0.frame.width > app.frame.width * 0.7 && $0.frame.height > 100
                }
                if !visible.isEmpty { break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            } while Date() < deadline
            XCTAssertFalse(visible.isEmpty, "Must inspect a real scroll container for \(tab)")
            for container in visible {
                XCTAssertLessThanOrEqual(container.frame.maxY, dock.frame.minY + 1,
                                         "Real \(tab) scroll viewport must end above dock")
            }
            app.swipeUp()
            screenshot("dock29-real-tab-" + tab)
        }
        app.terminate()
    }

    func testRealSoftwareKeyboardHidesAndRestoresProjectCTA() {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "certificate-parity-29",
                               "-mirsa.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        let sign = app.buttons["mirsa.project.sign"]
        XCTAssertTrue(sign.waitForExistence(timeout: 20) && sign.isHittable)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.exists && field.isHittable)
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8), "Requires real OS software keyboard")
        XCTAssertFalse(sign.exists && sign.isHittable, "CTA must not cover editor while typing")
        XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.firstMatch.frame.minY)
        screenshot("certificate29-real-OS-keyboard-visible")
        // Start on static card content inside the real scroll view, not the
        // outer margin or a text field. Dismissal must come from real scrolling.
        let keyboard = app.keyboards.firstMatch
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: app.frame.width * 0.5, dy: keyboard.frame.minY * 0.65))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: app.frame.width * 0.5, dy: keyboard.frame.minY - 20))
        start.press(forDuration: 0.05, thenDragTo: end)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 8), .completed)
        XCTAssertTrue(sign.waitForExistence(timeout: 8) && sign.isHittable)
        screenshot("certificate29-real-OS-keyboard-dismissed-CTA-restored")
        app.terminate()
    }

}
