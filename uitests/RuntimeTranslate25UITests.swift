import XCTest

final class RuntimeTranslate25UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testArabicTranslateToggleHintBelowToggleAndPersists() {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "certificate-parity-29", "-MirsaProjectThemesFixture",
            "-mirsa.appLanguage", "ar", "-AppleLanguages", "(ar)", "-AppleLocale", "ar"]
        app.launch()
        let editor = app.scrollViews["mirsa.project.editor-scroll"]
        XCTAssertTrue(editor.waitForExistence(timeout: 20))
        let toggle = app.switches["project-sign-translate-ar"]
        let hint = app.staticTexts["project-sign-translate-ar-hint"]
        for _ in 0..<20 { if toggle.exists && toggle.isHittable && hint.exists { break }; editor.swipeUp() }
        XCTAssertTrue(toggle.exists && hint.exists)
        XCTAssertTrue(hint.label.contains("بعض النصوص بتحتاج إنترنت لتترجم"))
        let hint2 = app.staticTexts["project-sign-translate-ar-hint2"]
        XCTAssertTrue(hint2.exists)
        XCTAssertTrue(hint2.label.contains("التطبيقات المشفّرة والألعاب والنصوص اللي بالصور ما بتتعرّب"))
        XCTAssertGreaterThanOrEqual(hint.frame.minY, toggle.frame.maxY - 1)
        XCTAssertGreaterThanOrEqual(hint2.frame.minY, hint.frame.maxY - 1)
        capture("runtime-translate-hint-initial")
        let start = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertNotEqual(toggle.value as? String, start)
        capture("runtime-translate-hint-toggled")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, start)
        capture("runtime-translate-hint-restored")
        XCTAttachment(string: app.debugDescription).lifetime = .keepAlways
        let ax = XCTAttachment(string: app.debugDescription); ax.name = "AX"; ax.lifetime = .keepAlways; add(ax)
    }

    func testArabicEncryptedFixtureShowsProductionNotice() {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "certificate-parity-29", "-MirsaProjectThemesFixture",
            "-MirsaRuntimeEncryptedFixture", "-mirsa.appLanguage", "ar", "-AppleLanguages", "(ar)", "-AppleLocale", "ar"]
        app.launch()
        let editor = app.scrollViews["mirsa.project.editor-scroll"]
        XCTAssertTrue(editor.waitForExistence(timeout: 20))
        let notice = app.staticTexts["project-sign-result-notice"]
        let hint = app.staticTexts["project-sign-translate-ar-hint"]
        let hint2 = app.staticTexts["project-sign-translate-ar-hint2"]
        for _ in 0..<30 { if notice.exists && notice.isHittable { break }; editor.swipeUp() }
        XCTAssertTrue(notice.exists)
        XCTAssertEqual(notice.label, "هالتطبيق مشفّر، وما فينا نعرّبه.")
        capture("runtime-encrypted-notice")
        for _ in 0..<30 { if hint.exists && hint2.exists { break }; editor.swipeDown() }
        XCTAssertTrue(hint.label.contains("بعض النصوص بتحتاج إنترنت لتترجم"))
        XCTAssertTrue(hint2.label.contains("التطبيقات المشفّرة والألعاب والنصوص اللي بالصور ما بتتعرّب"))
        let ax = XCTAttachment(string: app.debugDescription); ax.name = "AX-encrypted"; ax.lifetime = .keepAlways; add(ax)
    }
}
