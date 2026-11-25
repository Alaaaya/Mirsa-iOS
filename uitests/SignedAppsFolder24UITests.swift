import XCTest

final class SignedAppsFolder24UITests: XCTestCase {
    func testArabicProjectsFolderOpensAndSharesRetainedSignedIPA() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "signed-folder24",
                               "-mirsa.appLanguage", "ar", "-AppleLanguages", "(ar)", "-AppleLocale", "ar"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 2) { alert.buttons.firstMatch.tap() }
        let folder = app.buttons["projects-signed-folder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 25))
        let toggle = app.buttons["تبديل القائمة والشبكة"]
        XCTAssertTrue(toggle.exists)
        XCTAssertLessThan(folder.frame.midX, toggle.frame.midX, "Arabic must keep the LTR header controls")
        capture("Arabic-projects-folder-beside-plus")
        folder.tap()
        let share = app.buttons["signed-file-share"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 15), "Real retained signing fixture must be listed")
        XCTAssertTrue(app.staticTexts["CI Signing Fixture"].exists)
        let real = app.images.matching(identifier: "signed-file-icon-real")
            .matching(NSPredicate(format: "label == %@", "CI Signing Fixture")).element
        let car = app.images.matching(identifier: "signed-file-icon-real")
            .matching(NSPredicate(format: "label == %@", "CI Car Icon Fixture")).element
        let generic = app.images.matching(identifier: "signed-file-icon-generic")
            .matching(NSPredicate(format: "label == %@", "أيقونة تطبيق افتراضية لـ CI No Icon Fixture")).element
        XCTAssertTrue(real.waitForExistence(timeout: 10), "Row with an icon in its signed IPA must render the extracted real icon")
        XCTAssertTrue(app.staticTexts["CI Car Icon Fixture"].exists)
        XCTAssertEqual(app.images.matching(identifier: "signed-file-icon-real").count, 2, "loose-PNG row and Assets.car-only row both show real icons")
        XCTAssertEqual(app.images.matching(identifier: "signed-file-icon-generic").count, 1, "Icon-less signed IPA must use the generic fallback")
        XCTAssertTrue(app.staticTexts["CI No Icon Fixture"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "signed-file-share").count, 3, "Every retained signed IPA has its own share action")
        XCTAssertTrue(car.exists, "Assets.car artwork must belong to its own retained app")
        XCTAssertTrue(generic.exists, "Fallback must have the icon-less app's meaningful accessibility label")
        for icon in [real, car, generic] {
            XCTAssertEqual(icon.frame.width, 44, accuracy: 1)
            XCTAssertEqual(icon.frame.height, 44, accuracy: 1)
        }
        capture("Arabic-signed-outputs-real-IPA")
        share.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5)
                      || app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Copy' OR label CONTAINS 'نسخ'")).firstMatch.waitForExistence(timeout: 5)
                      || app.collectionViews.firstMatch.waitForExistence(timeout: 5),
                      "Sharing must open the actual system activity sheet")
        capture("Arabic-signed-IPA-system-share")
        let evidence = XCTAttachment(string: app.debugDescription)
        evidence.name = "system-share-accessibility"; evidence.lifetime = .keepAlways; add(evidence)
    }

    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
