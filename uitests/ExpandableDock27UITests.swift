import XCTest

/// Arabic, real ContentView with the real Apps + button. One continuous glass bar:
/// tap/hold the ACTIVE tab to grow a contextual card out of it, no overlap with the
/// + button, crisp hittable tabs in both states, physical tab order unchanged.
final class ExpandableDock27UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "dock30-" + name + "-ar"; a.lifetime = .keepAlways; add(a)
    }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "dock-apps-30",
                               "-mirsa.appLanguage", "ar", "-AppleLanguages", "(ar)", "-AppleLocale", "ar"]
        app.launch()
        return app
    }
    private let tabs = ["Apps", "Sources", "Pairing", "Encrypted", "Personal Apps Hub", "Mirsa AI"]
    private func assertTabsCrisp(_ app: XCUIApplication) {
        for t in tabs {
            let b = app.buttons["main-tab-" + t]
            XCTAssertTrue(b.exists, t)
            XCTAssertTrue(b.isHittable, t + " must stay hittable")
            XCTAssertGreaterThanOrEqual(b.frame.width, 40, t)
        }
        for (l, r) in zip(tabs, tabs.dropFirst()) {
            XCTAssertLessThan(app.buttons["main-tab-" + l].frame.midX, app.buttons["main-tab-" + r].frame.midX)
        }
    }

    func testTapActiveTabGrowsCardFromBarWithoutFabCollision() {
        let app = launch()
        let dock = app.otherElements["mirsa-tab-dock"]
        XCTAssertTrue(dock.waitForExistence(timeout: 20))
        let fab = app.descendants(matching: .any)["apps-fab"].firstMatch
        XCTAssertTrue(fab.waitForExistence(timeout: 10), "real Apps + button must be on screen")
        XCTAssertLessThanOrEqual(fab.frame.maxY, dock.frame.minY, "FAB clear of compact bar")
        // No handle, no separate capsule, no card yet.
        XCTAssertFalse(app.buttons["dock-expand-handle"].exists)
        XCTAssertFalse(app.otherElements["dock-context-pill"].exists)
        let card = app.otherElements["dock-expanded-card"]
        XCTAssertFalse(card.exists)
        assertTabsCrisp(app)
        shot("compact")

        app.buttons["main-tab-Apps"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["main-tab-Apps"].isSelected)
        XCTAssertLessThanOrEqual(card.frame.maxY, dock.frame.minY + 1, "card sits directly on the same bar")
        XCTAssertGreaterThanOrEqual(card.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(card.frame.maxX, app.frame.maxX)
        XCTAssertTrue(app.buttons["dock-action-apps-files"].isHittable)
        XCTAssertLessThan(app.buttons["dock-action-apps-files"].frame.midX, app.buttons["dock-action-apps-link"].frame.midX)
        // FAB rides above the card with real geometry.
        let moved = NSPredicate { _, _ in fab.frame.maxY <= card.frame.minY }
        wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 5)
        XCTAssertLessThanOrEqual(fab.frame.maxY, card.frame.minY, "FAB must not overlap the expanded card")
        assertTabsCrisp(app)
        shot("expanded")

        // Tapping the active tab again closes it; the FAB returns.
        app.buttons["main-tab-Apps"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        // Hold on the active tab opens it again.
        app.buttons["main-tab-Apps"].press(forDuration: 0.8)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["main-tab-Apps"].isSelected)
        // Outside tap closes without selecting anything underneath.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["main-tab-Apps"].isSelected)
        // Swipe up on the bar expands without activating a different tab.
        let start = dock.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -90)))
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["main-tab-Apps"].isSelected)
        // Another tab closes the card and navigates.
        app.buttons["main-tab-Sources"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["main-tab-Sources"].isSelected)
        // Sources owns real actions of its own.
        app.buttons["main-tab-Sources"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dock-action-sources-add"].isHittable)
        shot("sources-expanded")
        app.buttons["main-tab-Sources"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        // A tab without real quick actions simply does not expand.
        app.buttons["main-tab-Pairing"].tap()
        app.buttons["main-tab-Pairing"].tap()
        XCTAssertFalse(card.waitForExistence(timeout: 1.5))
    }
}
