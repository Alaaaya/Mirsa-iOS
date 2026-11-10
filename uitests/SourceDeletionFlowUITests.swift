import XCTest

/// Real system dialog evidence, not a UIHostingController bitmap (which omits presentations).
final class SourceDeletionFlowUITests: XCTestCase {
    func testArabicSwipeCancelAndConfirm() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "sources-delete-validation",
                               "-mirsa.appLanguage", "ar", "-AppleLanguages", "(ar)", "-AppleLocale", "ar"]
        app.launch()
        defer { app.terminate() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permission = springboard.alerts.firstMatch
        if permission.waitForExistence(timeout: 2) { permission.buttons.firstMatch.tap() }
        let fixture = app.staticTexts["Delete Fixture"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 10))
        fixture.swipeLeft()
        let delete = app.buttons["حذف"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let title = app.staticTexts["تحذف هالسورس؟"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        let cancel = app.buttons["إلغاء"]
        XCTAssertTrue(cancel.exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "sources-delete-real-confirm-ar"
        shot.lifetime = .keepAlways
        add(shot)
        cancel.tap()
        XCTAssertTrue(fixture.waitForExistence(timeout: 5))
        fixture.swipeLeft()
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.buttons["حذف"].firstMatch.tap()
        XCTAssertTrue(fixture.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mirsa"].exists)
    }
}
