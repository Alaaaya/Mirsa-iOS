import XCTest

/// Real retained ContentView, real scroll surfaces. Fixture only supplies source data.
final class UnderDock23UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "underdock23-" + name; a.lifetime = .keepAlways; add(a)
    }
    private func inspect(_ app: XCUIApplication, _ name: String) {
        let dock = app.otherElements["mirsa-tab-dock"]
        XCTAssertTrue(dock.waitForExistence(timeout: 10))
        let containers = app.descendants(matching: .any).matching(NSPredicate(
            format: "elementType IN %@", [XCUIElement.ElementType.scrollView.rawValue,
                XCUIElement.ElementType.table.rawValue, XCUIElement.ElementType.collectionView.rawValue]))
        let viewport = containers.allElementsBoundByIndex.filter {
            $0.exists && $0.frame.width > app.frame.width * 0.7 && $0.frame.height > 100
        }.max { $0.frame.height < $1.frame.height }
        guard let viewport else { XCTFail("Missing real scroll surface for " + name); return }
        XCTAssertGreaterThanOrEqual(viewport.frame.maxY, dock.frame.maxY - 1,
                                    name + " must not clip scrolling above the dock")
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: app.frame.midX, dy: dock.frame.minY - 30))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: app.frame.midX, dy: dock.frame.minY - 170))
        start.press(forDuration: 0.05, thenDragTo: end)
        shot(name + "-mid-scroll")
        let ax = XCTAttachment(string: app.debugDescription)
        ax.name = "underdock23-" + name + "-geometry"; ax.lifetime = .keepAlways; add(ax)
    }
    func testRealScreensUnderTranslucentDock() {
        for lang in ["en", "ar"] {
            let app = XCUIApplication()
            app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "dock-clearance-29",
                                   "-mirsa.appLanguage", lang, "-AppleLanguages", "(\(lang))", "-AppleLocale", lang]
            app.launch()
            inspect(app, lang + "-sources-list")
            // Last source is populated. Open it, then capture both real layouts.
            let last = app.staticTexts["Dock Source Last"]
            for _ in 0..<30 { if last.exists && last.isHittable { break }; app.swipeUp() }
            app.swipeUp(); app.swipeUp()
            XCTAssertTrue(last.exists && last.isHittable); last.tap()
            XCTAssertTrue(app.staticTexts["Dock App 1"].waitForExistence(timeout: 10))
            // The 35-app fixture defaults to list; explicitly switch to grid.
            let gridToggle = app.buttons["source-layout-toggle"]
            XCTAssertTrue(gridToggle.waitForExistence(timeout: 5)); gridToggle.tap()
            inspect(app, lang + "-source-detail-grid")
            app.swipeDown(); app.swipeDown()
            let toggle = app.buttons["source-layout-toggle"]
            for _ in 0..<10 { if toggle.isHittable { break }; app.swipeDown() }
            XCTAssertTrue(toggle.isHittable); toggle.tap()
            inspect(app, lang + "-source-detail-list")
            for (tab, name) in [("Apps", "apps"), ("Pairing", "tools"),
                                ("Encrypted", "apple-store"), ("Personal Apps Hub", "certificate")] {
                let button = app.buttons["main-tab-" + tab]
                XCTAssertTrue(button.isHittable); button.tap()
                inspect(app, lang + "-" + name)
                if tab == "Pairing" {
                    let store = app.buttons["tools-section-store"]
                    XCTAssertTrue(store.waitForExistence(timeout: 10)); store.tap()
                    inspect(app, lang + "-tools-store")
                }
            }
            app.terminate()
        }
    }
}
