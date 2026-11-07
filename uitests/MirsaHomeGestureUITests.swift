import XCTest

/// Real XCUITest gestures on the real home screens (simulator). Not model tests.
final class MirsaHomeGestureUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-AppleLanguages", "(en)"]
        app.launch()
    }
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func layout() -> String { app.staticTexts["uit.layout"].label }
    private func tile(_ n: String) -> XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", n)).firstMatch }

    private func exercise(tab: String, prefix: String) throws {
        app.buttons[tab == "Main" ? "uit.main" : "uit.personal"].tap()
        let first = tile("\(prefix) 1")
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        // long press enters edit mode
        first.press(forDuration: 1.0)
        // Native context menus own long-press on non-editing tiles.
        // Exercise the actual Arrange action rather than assuming the competing gesture won.
        let arrange = app.buttons.matching(NSPredicate(format: "label IN %@", ["Arrange apps", "ترتيب التطبيقات"])).firstMatch
        if arrange.waitForExistence(timeout: 3) { arrange.tap() }
        let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "تم"])).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "edit mode not entered")
        Thread.sleep(forTimeInterval: 2.0)
        shot("\(tab)-jiggle-long-edit-mode")
        app.buttons["uit.refresh"].tap()
        let before = layout()
        XCTAssertNotEqual(before, "none", "initial layout must be persisted")
        // Refresh reconstructs the real home. Re-enter editing before dragging.
        first.press(forDuration: 1.0)
        if arrange.waitForExistence(timeout: 3) { arrange.tap() }
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        // reorder: drag tile 3 onto the left 12% strip of tile 1
        let t3 = tile("\(prefix) 3"), t1 = tile("\(prefix) 1")
        t3.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0, thenDragTo: t1.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)))
        app.buttons["refresh"].tap()
        let afterReorder = layout()
        shot("\(tab)-after-reorder")
        XCTAssertNotEqual(before, afterReorder, "reorder drag did not change layout")
        // folder: drag tile 5 onto centre of tile 4
        tile("\(prefix) 4").press(forDuration: 1.0)
        if arrange.waitForExistence(timeout: 3) { arrange.tap() }
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let t5 = tile("\(prefix) 5"), t4 = tile("\(prefix) 4")
        t5.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0, thenDragTo: t4.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        app.buttons["refresh"].tap()
        let afterFolder = layout()
        shot("\(tab)-after-folder")
        XCTAssertTrue(afterFolder.contains("["), "folder was not created: \(afterFolder)")
        XCTAssertNotEqual(afterReorder, afterFolder)
        // persistence: relaunch and the layout must be identical
        app.terminate(); app.launch()
        app.buttons[tab == "Main" ? "uit.main" : "uit.personal"].tap()
        XCTAssertTrue(app.staticTexts["uit.layout"].waitForExistence(timeout: 10))
        app.buttons["uit.refresh"].tap()
        XCTAssertEqual(layout(), afterFolder, "layout not persisted across relaunch")
        shot("\(tab)-after-relaunch")
    }
    func testMainHomeDragReorderFolderPersistAndJiggle() throws { try exercise(tab: "Main", prefix: "UIT Main") }
    func testPersonalHomeDragReorderFolderPersistAndJiggle() throws { try exercise(tab: "Personal", prefix: "UIT Personal") }
}
