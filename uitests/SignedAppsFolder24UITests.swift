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
        capture("icon-frames-before-assert")
        let axDump = XCTAttachment(string: "real=\(real.frame) car=\(car.frame) generic=\(generic.frame)\n" + app.debugDescription)
        axDump.name = "icon-ax-before-dimension-assert"; axDump.lifetime = .keepAlways; add(axDump)
        for icon in [real, car, generic] {
            XCTAssertEqual(icon.frame.width, 44, accuracy: 1)
            XCTAssertEqual(icon.frame.height, 44, accuracy: 1)
        }
        capture("Arabic-signed-outputs-real-IPA")
        capture("Arabic-signed-folder-background-through-bottom-safe-area")
        share.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5)
                      || app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Copy' OR label CONTAINS 'نسخ'")).firstMatch.waitForExistence(timeout: 5)
                      || app.collectionViews.firstMatch.waitForExistence(timeout: 5),
                      "Sharing must open the actual system activity sheet")
        capture("Arabic-signed-IPA-system-share")
        let evidence = XCTAttachment(string: app.debugDescription)
        evidence.name = "system-share-accessibility"; evidence.lifetime = .keepAlways; add(evidence)
    }

    func testArabicMainSourcesSearchShowsAppsNotSourceNames() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "sources-ts-list",
                               "-mirsa.appLanguage", "ar", "-AppleLanguages", "(ar)", "-AppleLocale", "ar"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["sources-search-toggle"].waitForExistence(timeout: 20))
        app.buttons["sources-more-menu"].tap()
        XCTAssertFalse(app.buttons["اكتشف تطبيقات"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        app.buttons["sources-search-toggle"].tap()
        let field = app.textFields["sources-list-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Large 45")
        XCTAssertTrue(app.staticTexts["Large 45"].waitForExistence(timeout: 5), "Search must include catalogue tail")
        XCTAssertFalse(app.staticTexts["Small Source"].exists)
        capture("Arabic-main-sources-app-search-tail")
        app.buttons["sources-search-toggle"].tap()
        XCTAssertTrue(app.staticTexts["Small Source"].waitForExistence(timeout: 5))
    }

    func testZArabicDeleteAllCancelSwipeAndMultiSelect() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "signed-folder24",
                               "-mirsa.appLanguage", "ar", "-AppleLanguages", "(ar)", "-AppleLocale", "ar"]
        app.launch()
        defer { app.terminate() }
        app.buttons["projects-signed-folder"].waitForExistence(timeout: 20)
        app.buttons["projects-signed-folder"].tap()
        let all = app.buttons["signed-folder-delete-all"]
        XCTAssertTrue(all.waitForExistence(timeout: 15))
        all.tap()
        XCTAssertTrue(app.buttons["إلغاء"].waitForExistence(timeout: 5))
        capture("Arabic-signed-delete-all-confirmation")
        app.buttons["إلغاء"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "signed-file-share").count, 3)
        let name = app.staticTexts["CI Signing Fixture"]
        name.swipeLeft()
        app.buttons["حذف"].firstMatch.tap()
        XCTAssertTrue(app.buttons["إلغاء"].waitForExistence(timeout: 5))
        app.buttons["حذف"].firstMatch.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        app.buttons["signed-folder-select"].tap()
        let choices = app.buttons.matching(identifier: "signed-file-select")
        XCTAssertEqual(choices.count, 2)
        choices.element(boundBy: 0).tap()
        capture("Arabic-signed-multi-selection")
        app.buttons["signed-folder-delete-selected"].tap()
        XCTAssertTrue(app.buttons["إلغاء"].waitForExistence(timeout: 5))
        app.buttons["حذف"].firstMatch.tap()
        XCTAssertTrue(app.buttons["signed-folder-delete-all"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "signed-file-share").count, 1)
        app.buttons["signed-folder-delete-all"].tap()
        XCTAssertTrue(app.buttons["إلغاء"].waitForExistence(timeout: 5))
        app.buttons["حذف"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["signed-folder-empty"].waitForExistence(timeout: 5)
                      || app.staticTexts["ما في تطبيقات موقّعة بعد"].waitForExistence(timeout: 5))
        capture("Arabic-signed-files-deleted-empty")
    }

    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
