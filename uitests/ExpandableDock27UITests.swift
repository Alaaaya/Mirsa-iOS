import XCTest

/// Real app, Arabic. Expandable glass dock: swipe up or grabber expands a card with all six tabs.
final class ExpandableDock27UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testExpandCardSelectCollapseInArabic() {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "dock-clearance-29",
                               "-mirsa.appLanguage", "ar", "-AppleLanguages", "(ar)", "-AppleLocale", "ar"]
        app.launch()
        let dock = app.otherElements["mirsa-tab-dock"]
        XCTAssertTrue(dock.waitForExistence(timeout: 15))
        let card = app.otherElements["dock-expanded-card"]
        XCTAssertFalse(card.exists)
        // Physical order stays left to right.
        let apps = app.buttons["main-tab-Apps"], sources = app.buttons["main-tab-Sources"]
        XCTAssertLessThan(apps.frame.minX, sources.frame.minX)
        let handle = app.buttons["dock-expand-handle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5)); handle.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(card.frame.maxY, dock.frame.minY)
        XCTAssertGreaterThanOrEqual(card.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(card.frame.maxX, app.frame.maxX)
        let first = app.buttons["dock-card-tab-Apps"], second = app.buttons["dock-card-tab-Sources"]
        XCTAssertTrue(first.exists && second.exists)
        XCTAssertLessThan(first.frame.minX, second.frame.minX)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = "dock27-expanded-ar"; a.lifetime = .keepAlways; add(a)
        second.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["main-tab-Sources"].isSelected)
        // Tap outside collapses.
        handle.tap(); XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        // Swipe up on the bar expands.
        dock.swipeUp()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }
}
