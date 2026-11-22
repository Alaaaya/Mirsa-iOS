import XCTest

/// Navigate the real Tools Store wallpaper category. Only catalog
/// data/art is local; no substitute screen and no import action, video network or respring is triggered.
final class WallpaperSourceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testToolsStoreWallpaperSourcesOnlyInFiveLanguages() {
        for language in ["ar", "en", "de", "kmr", "ckb"] {
            let app = XCUIApplication()
            app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "tools",
                "-MirsaWallpaperSourceFixture", "-mirsa.appLanguage", language,
                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            defer { app.terminate() }
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let alert = springboard.alerts.firstMatch
            if alert.waitForExistence(timeout: 2) {
                let deny = alert.buttons.matching(NSPredicate(format: "label IN %@",
                    ["Don’t Allow", "Don't Allow", "عدم السماح"])).firstMatch
                if deny.exists { deny.tap() } else { alert.buttons.firstMatch.tap() }
            }
            let tendies = app.buttons["tools-section-wallpapers"]
            XCTAssertTrue(tendies.waitForExistence(timeout: 15))
            tendies.tap()
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "wallpaper-sources").firstMatch.exists)
            app.buttons["tools-section-store"].tap()
            let filter = app.buttons["tools-store-cat-wallpapers"]
            XCTAssertTrue(filter.waitForExistence(timeout: 10))
            filter.tap()
            let field = app.textFields["wallpaper-source-url"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Mirsa Originals"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Solar arc"].exists, "Screenshot must contain actual catalog entries")
            let imports = app.buttons.matching(identifier: "wallpaper-source-install")
            XCTAssertGreaterThanOrEqual(imports.count, 2, "Actual adaptive grid, not an empty feed")
            XCTAssertTrue(imports.firstMatch.isEnabled)
            XCTAssertFalse(app.buttons["wallpaper-source-add"].isEnabled)
            XCTAssertFalse(app.alerts.firstMatch.exists)
            shot(language + "_wallpaper_source_grid_top")
            app.swipeUp(velocity: .slow)
            shot(language + "_wallpaper_source_grid_scrolled")
            XCTAssertTrue(app.buttons["wallpaper-source-add-caplayground"].exists)

            // This is Tools Store's real vertical ScrollView, not the horizontal
            // category bar or a screen-wide gesture that could start on the dock.
            let scroll = app.scrollViews.containing(.textField, identifier: "wallpaper-source-url").firstMatch
            XCTAssertTrue(scroll.exists)
            let dock = app.descendants(matching: .any).matching(identifier: "mirsa-tab-dock").firstMatch
            XCTAssertTrue(dock.exists, "Measure the actual floating dock, never a hardcoded screen inset")
            let finalName = app.staticTexts["Halo"] // sixth and final fixture entry
            var previousFrame: CGRect?
            var reachedEnd = false
            var endSwipes = 0
            for _ in 0..<12 {
                scroll.swipeUp(velocity: .slow)
                endSwipes += 1
                // Swipe completion waits for XCTest idleness, including scroll deceleration.
                guard finalName.exists else { continue }
                let current = finalName.frame
                if let previous = previousFrame,
                   abs(current.minY - previous.minY) < 1,
                   abs(current.minX - previous.minX) < 1 {
                    reachedEnd = true
                    break
                }
                previousFrame = current
            }
            XCTAssertTrue(reachedEnd, "Final fixture must stop moving at the real scroll end within 12 swipes")
            XCTAssertTrue(finalName.exists)
            XCTAssertTrue(finalName.isHittable)
            XCTAssertTrue(app.staticTexts["Lagoon"].exists, "Both final-row names must remain in the native grid")

            // Fixture order is Solar arc, Night tide, Cinder, Dune, Lagoon, Halo.
            // LazyVGrid may evict earlier rows; the last ordered install match is
            // Halo's action. Prove its association geometrically as well, rather
            // than treating an arbitrary visible install button as the final one.
            let endActions = app.buttons.matching(identifier: "wallpaper-source-install")
            XCTAssertGreaterThanOrEqual(endActions.count, 2)
            let finalAction = endActions.element(boundBy: endActions.count - 1)
            XCTAssertTrue(finalAction.exists)
            XCTAssertTrue(finalAction.isEnabled)
            XCTAssertTrue(finalAction.isHittable)
            let nameFrame = finalName.frame
            let actionFrame = finalAction.frame
            let scrollFrame = scroll.frame
            let dockFrame = dock.frame
            let windowFrame = app.windows.firstMatch.frame
            XCTAssertGreaterThan(nameFrame.width, 0)
            XCTAssertGreaterThan(nameFrame.height, 0)
            XCTAssertGreaterThan(actionFrame.width, 0)
            XCTAssertGreaterThan(actionFrame.height, 0)
            XCTAssertGreaterThan(dockFrame.height, 0)
            XCTAssertLessThan(dockFrame.minY, windowFrame.maxY)
            XCTAssertLessThanOrEqual(abs(nameFrame.midX - actionFrame.midX), actionFrame.width / 2,
                                     "Last action must occupy Halo's column")
            XCTAssertGreaterThanOrEqual(actionFrame.minY, nameFrame.maxY,
                                        "Last action must be below Halo's name")
            XCTAssertLessThan(actionFrame.minY - nameFrame.maxY, 120,
                              "Do not associate Halo with another row's action")
            for frame in [nameFrame, actionFrame] {
                XCTAssertTrue(windowFrame.contains(frame), "Final name/action must be entirely on screen")
                XCTAssertTrue(scrollFrame.contains(frame), "Final name/action must be fully inside the clipped scroll viewport")
                XCTAssertLessThan(frame.maxY, dockFrame.minY,
                                  "Final name/action must be fully ABOVE the actual dock, not merely hittable")
            }
            func geometry(_ frame: CGRect) -> [String: Double] {
                ["x": Double(frame.minX), "y": Double(frame.minY),
                 "width": Double(frame.width), "height": Double(frame.height),
                 "maxY": Double(frame.maxY)]
            }
            let proof: [String: Any] = [
                "language": language, "finalFixture": "Halo", "endSwipes": endSwipes,
                "reachedStableEnd": reachedEnd, "installMatchCount": endActions.count,
                "nameHittable": finalName.isHittable, "actionHittable": finalAction.isHittable,
                "name": geometry(nameFrame), "action": geometry(actionFrame),
                "scroll": geometry(scrollFrame), "dock": geometry(dockFrame),
                "window": geometry(windowFrame),
                "actionDockGap": Double(dockFrame.minY - actionFrame.maxY)
            ]
            let proofData = try! JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
            let geometryAttachment = XCTAttachment(data: proofData, uniformTypeIdentifier: "public.json")
            geometryAttachment.name = language + "_wallpaper_source_grid_end_geometry"
            geometryAttachment.lifetime = .keepAlways
            add(geometryAttachment)
            let hierarchyAttachment = XCTAttachment(string: app.debugDescription)
            hierarchyAttachment.name = language + "_wallpaper_source_grid_end_hierarchy"
            hierarchyAttachment.lifetime = .keepAlways
            add(hierarchyAttachment)
            shot(language + "_wallpaper_source_grid_end")
            app.buttons["tools-section-wallpapers"].tap()
            XCTAssertFalse(app.textFields["wallpaper-source-url"].exists)
        }
    }
}
