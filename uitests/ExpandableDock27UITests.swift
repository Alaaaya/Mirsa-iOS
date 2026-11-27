import XCTest

/// Arabic real retained ContentView. Tests actual dock hit areas, context pill,
/// workspace card, navigation menu, outside dismissal and unchanged tab order.
final class ExpandableDock27UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "dock27-" + name + "-ar"; a.lifetime = .keepAlways; add(a)
    }
    func testExpandCardSelectCollapseInArabic() {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "dock-clearance-29",
                               "-mirsa.appLanguage", "ar", "-AppleLanguages", "(ar)", "-AppleLocale", "ar"]
        app.launch()
        let dock = app.otherElements["mirsa-tab-dock"]
        XCTAssertTrue(dock.waitForExistence(timeout: 15))
        let pill = app.otherElements["dock-context-pill"]
        XCTAssertFalse(pill.exists)
        let tabs = ["Apps", "Sources", "Pairing", "Encrypted", "Personal Apps Hub", "Mirsa AI"]
        for (left, right) in zip(tabs, tabs.dropFirst()) {
            XCTAssertLessThan(app.buttons["main-tab-" + left].frame.midX,
                              app.buttons["main-tab-" + right].frame.midX)
        }
        shot("compact")
        // A real hit in the Sources page remains available while collapsed.
        XCTAssertTrue(app.staticTexts["Dock Source 1"].exists)
        let handle = app.buttons["dock-expand-handle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        XCTAssertTrue(handle.isHittable)
        XCTAssertGreaterThanOrEqual(handle.frame.width, 44)
        XCTAssertGreaterThanOrEqual(handle.frame.height, 44)
        XCTAssertLessThanOrEqual(handle.frame.maxY, dock.frame.minY)
        handle.tap()
        XCTAssertTrue(app.buttons["main-tab-Sources"].isSelected)
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(pill.frame.maxY, dock.frame.minY)
        shot("context-pill")
        app.buttons["dock-status-menu"].tap()
        let menu = app.otherElements["dock-navigation-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(menu.frame.maxY, pill.frame.minY)
        XCTAssertGreaterThanOrEqual(menu.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(menu.frame.maxX, app.frame.maxX)
        XCTAssertTrue(app.buttons["dock-menu-tab-Sources"].isSelected)
        shot("navigation-menu")
        app.buttons["dock-menu-tab-Apps"].tap()
        XCTAssertTrue(pill.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["main-tab-Apps"].isSelected)
        handle.tap(); XCTAssertTrue(pill.waitForExistence(timeout: 5))
        app.buttons["dock-workspace-toggle"].tap()
        let card = app.otherElements["dock-expanded-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(card.frame.maxY, pill.frame.minY)
        XCTAssertLessThan(app.buttons["dock-card-tab-Apps"].frame.midX,
                          app.buttons["dock-card-tab-Sources"].frame.midX)
        shot("workspace-dark")
        app.buttons["dock-card-tab-Sources"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(pill.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["main-tab-Sources"].isSelected)
        // Outside dismissal must not select an underlying item.
        handle.tap(); XCTAssertTrue(pill.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(pill.waitForNonExistence(timeout: 5))
        // Swipe from inside the dock into the page.
        let start = dock.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -90)))
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        app.buttons["dock-workspace-toggle"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.buttons["dock-card-close"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
    }
}
