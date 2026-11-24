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
        assertDockAtWindowBottom(app, name)
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
        for lang in MirsaUILanguages.selected(["en", "ar"]) {
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
    private func assertDockAtWindowBottom(_ app: XCUIApplication, _ name: String) {
        let probe = app.otherElements["mirsa-dock-window-geometry"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        let values = (probe.value as? String ?? "").split(separator: ";").reduce(into: [String: Double]()) { result, item in
            let pair = item.split(separator: "=")
            if pair.count == 2 { result[String(pair[0])] = Double(pair[1]) }
        }
        guard let heightValue = values["height"], let safeValue = values["safeBottom"] else {
            XCTFail("Missing actual UIWindow safe-area geometry"); return
        }
        let height = CGFloat(heightValue), safe = CGFloat(safeValue)
        XCTAssertGreaterThan(height, 100)
        let dock = app.otherElements["mirsa-tab-dock"]
        let expectedBottom = height - max(8, safe / 2)
        XCTAssertEqual(dock.frame.maxY, expectedBottom, accuracy: 1, name + " dock must sit near the actual home indicator")
        if safe > 20 {
            XCTAssertGreaterThan(dock.frame.maxY, height - safe - 8 + 10,
                                 name + " must lower the old safe-area-anchored dock, not only raise the store bar")
        }
        let pill = app.otherElements["mirsa-main-tab-pill"]
        let ai = app.buttons["main-tab-Mirsa AI"]
        XCTAssertEqual(pill.frame.minY, dock.frame.minY, accuracy: 1)
        XCTAssertEqual(ai.frame.midY, pill.frame.midY, accuracy: 1)
        XCTAssertLessThanOrEqual(dock.frame.maxY, app.frame.maxY - 8)
        print("DOCK24 \(name) windowHeight=\(height) safeBottom=\(safe) dock=\(dock.frame)")
    }

    func testBothStoreStylesKeepEveryInnerPageAboveLoweredMainDock() {
        for lang in MirsaUILanguages.selected(["en", "ar"]) {
            for style in ["new", "classic"] {
                let app = XCUIApplication()
                app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "dock-clearance-29",
                                       "-mirsa.store.style", style, "-mirsa.appLanguage", lang,
                                       "-AppleLanguages", "(\(lang))", "-AppleLocale", lang]
                app.launch()
                let tab = app.buttons["main-tab-Encrypted"]
                XCTAssertTrue(tab.waitForExistence(timeout: 15)); tab.tap()
                let pages = style == "new" ? ["discover", "search", "downloads", "account"] : ["search", "downloads", "account"]
                for page in pages {
                    let button = app.buttons["store-tab-" + page]
                    XCTAssertTrue(button.waitForExistence(timeout: 10)); XCTAssertTrue(button.isHittable); button.tap()
                    let bar = app.otherElements[style == "new" ? "store-gallery-capsule" : "store-classic-capsule"]
                    XCTAssertTrue(bar.waitForExistence(timeout: 10))
                    let dock = app.otherElements["mirsa-tab-dock"]
                    let name = lang + "-" + style + "-" + page
                    assertDockAtWindowBottom(app, name)
                    XCTAssertLessThanOrEqual(bar.frame.maxY, dock.frame.minY - 8,
                                             name + " inner bar must be fully above the main dock")
                    XCTAssertGreaterThanOrEqual(bar.frame.minX, app.frame.minX)
                    XCTAssertLessThanOrEqual(bar.frame.maxX, app.frame.maxX)
                    for item in pages {
                        let control = app.buttons["store-tab-" + item]
                        XCTAssertTrue(control.isHittable, name + " inner control must not be covered")
                        XCTAssertLessThanOrEqual(control.frame.maxY, dock.frame.minY - 8)
                    }
                    shot("dock24-" + name)
                    let ax = XCTAttachment(string: app.debugDescription)
                    ax.name = "dock24-" + name + "-geometry"; ax.lifetime = .keepAlways; add(ax)
                }
                app.terminate()
            }
        }
    }

    func testMainDockNearHomeIndicatorOnAllSixTabs() {
        for lang in MirsaUILanguages.selected(["en", "ar"]) {
            let app = XCUIApplication()
            app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "dock-clearance-29",
                                   "-mirsa.appLanguage", lang, "-AppleLanguages", "(\(lang))", "-AppleLocale", lang]
            app.launch()
            for tab in ["Apps", "Sources", "Mirsa AI", "Pairing", "Encrypted", "Personal Apps Hub"] {
                let button = app.buttons["main-tab-" + tab]
                XCTAssertTrue(button.waitForExistence(timeout: 10)); XCTAssertTrue(button.isHittable); button.tap()
                assertDockAtWindowBottom(app, lang + "-" + tab)
                shot("dock24-main-" + lang + "-" + tab)
            }
            app.terminate()
        }
    }

}
