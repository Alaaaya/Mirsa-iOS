import XCTest

/// Navigate the real Tools Store wallpaper category. Only catalog
/// data/art is local. Store actions use the real importer with an original test archive; no system apply or respring.
final class WallpaperSourceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(_ language: String, downloadError: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "tools",
            "-MirsaWallpaperSourceFixture", "-mirsa.appLanguage", language]
        if downloadError { app.launchEnvironment["mirsa_wallpaper_source_download_error"] = "1" }
        app.launch()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 2) { alert.buttons.firstMatch.tap() }
        XCTAssertTrue(app.buttons["tools-section-store"].waitForExistence(timeout: 15))
        app.buttons["tools-section-store"].tap()
        app.buttons["tools-store-cat-wallpapers"].tap()
        return app
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let scroll = app.scrollViews.containing(.textField, identifier: "wallpaper-source-url").firstMatch
        for _ in 0..<8 { if element.isHittable { break }; scroll.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    func testGridInstallImportsSelectsAndOpensTendies() {
        let app = launch("ar")
        let install = app.buttons.matching(identifier: "wallpaper-source-install").firstMatch
        reveal(install, app: app)
        install.tap()
        let selected = app.buttons["wallpaper-install-selected"]
        XCTAssertTrue(selected.waitForExistence(timeout: 15), "Store CTA must navigate to ready selected wallpaper")
        XCTAssertTrue(app.staticTexts["Solar arc"].exists)
        shot("Wallpaper-Store-Imported-Selected-AR")
    }

    func testPreviewInstallDismissesThenOpensImportedWallpaper() {
        let app = launch("en")
        let card = app.buttons["wallpaper-preview-original-1"]
        reveal(card, app: app)
        card.tap()
        let install = app.buttons["wallpaper-preview-install"]
        XCTAssertTrue(install.waitForExistence(timeout: 5))
        install.tap()
        XCTAssertTrue(app.buttons["wallpaper-install-selected"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["wallpaper-preview-close"].exists)
        XCTAssertTrue(app.staticTexts["Night tide"].exists)
        shot("Wallpaper-Preview-Imported-Selected-EN")
    }

    func testPreviewDownloadFailureIsVisibleInsidePreview() {
        let app = launch("ar", downloadError: true)
        let card = app.buttons["wallpaper-preview-original-1"]
        reveal(card, app: app); card.tap()
        let install = app.buttons["wallpaper-preview-install"]
        XCTAssertTrue(install.waitForExistence(timeout: 5)); install.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        shot("Wallpaper-Preview-Download-Error-AR")
    }

    func testToolsStoreWallpaperSourcesOnlyInFiveLanguages() {
        for language in ["ar", "en", "de", "kmr", "ckb"] {
            continueAfterFailure = false
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
            XCTAssertFalse(app.buttons["wallpaper-source-add-caplayground"].exists, "Community source is already enabled by default")

            // This is Tools Store's real vertical ScrollView, not the horizontal
            // category bar or a screen-wide gesture that could start on the dock.
            let scroll = app.scrollViews.containing(.textField, identifier: "wallpaper-source-url").firstMatch
            XCTAssertTrue(scroll.exists)
            let dock = app.descendants(matching: .any).matching(identifier: "mirsa-tab-dock").firstMatch
            XCTAssertTrue(dock.exists, "Measure the actual floating dock, never a hardcoded screen inset")
            // Regression for the dead band above the dock: the scroll surface
            // must cover the dock AND extend to the screen bottom. Final item
            // clearance is separately verified below, not by shrinking this frame.
            shot(language + "_wallpaper_scroll_viewport")
            XCTAssertGreaterThan(scroll.frame.maxY, dock.frame.maxY,
                                 "Scroll content must continue behind the whole floating dock")
            XCTAssertEqual(scroll.frame.maxY, app.windows.firstMatch.frame.maxY, accuracy: 2,
                           "No dead band may remain between the scroll viewport and screen bottom")
            let finalName = app.staticTexts["Halo"] // sixth and final fixture entry
            // The source grid is followed by Most Downloaded / Latest content.
            // Scrolling to the PAGE bottom moves Halo off the TOP, so target the
            // end of the fixture grid, not the end of the unrelated feed.
            var reachedEnd = false
            var endSwipes = 0
            let endActions = app.buttons.matching(identifier: "wallpaper-source-install")
            for _ in 0..<24 {
                if finalName.exists, endActions.count >= 2 {
                    let name = finalName.frame
                    let action = endActions.element(boundBy: endActions.count - 1).frame
                    if scroll.frame.contains(name), scroll.frame.contains(action),
                       name.maxY < dock.frame.minY, action.maxY < dock.frame.minY,
                       finalName.isHittable,
                       endActions.element(boundBy: endActions.count - 1).isHittable {
                        reachedEnd = true
                        break
                    }
                }
                // Small, bounded drags cannot skip the final row in a single
                // page-sized fling. Reverse if the row has moved above viewport.
                let passedRow = finalName.exists && finalName.frame.minY < scroll.frame.minY
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: passedRow ? 0.40 : 0.70))
                let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: passedRow ? 0.65 : 0.45))
                start.press(forDuration: 0.05, thenDragTo: end)
                endSwipes += 1
            }

            // Keep all end assertions, but attach actual pixels/geometry BEFORE
            // them so failures remain diagnosable. Continue through all languages.
            continueAfterFailure = true
            let finalAction = endActions.element(boundBy: max(0, endActions.count - 1))
            let nameFrame = finalName.exists ? finalName.frame : .zero
            let actionFrame = finalAction.exists ? finalAction.frame : .zero
            let scrollFrame = scroll.frame
            let dockFrame = dock.frame
            let windowFrame = app.windows.firstMatch.frame
            func geometry(_ frame: CGRect) -> [String: Double] {
                ["x": Double(frame.minX), "y": Double(frame.minY),
                 "width": Double(frame.width), "height": Double(frame.height),
                 "maxY": Double(frame.maxY)]
            }
            let proof: [String: Any] = [
                "language": language, "finalFixture": "Halo", "endSwipes": endSwipes,
                "reachedFixtureEnd": reachedEnd, "installMatchCount": endActions.count,
                "nameHittable": finalName.exists && finalName.isHittable,
                "actionHittable": finalAction.exists && finalAction.isHittable,
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
            XCTAssertTrue(reachedEnd, "Final fixture row must be fully visible within 24 bounded drags")
            XCTAssertTrue(finalName.exists)
            XCTAssertTrue(finalName.isHittable)
            XCTAssertTrue(app.staticTexts["Lagoon"].exists, "Both final-row names must remain in the native grid")
            XCTAssertGreaterThanOrEqual(endActions.count, 2)
            XCTAssertTrue(finalAction.exists)
            XCTAssertTrue(finalAction.isEnabled)
            XCTAssertTrue(finalAction.isHittable)
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
            app.buttons["tools-section-wallpapers"].tap()
            XCTAssertFalse(app.textFields["wallpaper-source-url"].exists)
        }
    }
    func testFullscreenImageVideoAndWideThumbnail() {
        for language in ["ar", "en", "de", "kmr", "ckb"] {
            let app = XCUIApplication()
            app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "tools",
                "-MirsaWallpaperSourceFixture", "-mirsa.appLanguage", language]
            app.launch()
            let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
            if alert.waitForExistence(timeout: 2) { alert.buttons.firstMatch.tap() }
            XCTAssertTrue(app.buttons["tools-section-store"].waitForExistence(timeout: 15))
            app.buttons["tools-section-store"].tap()
            app.buttons["tools-store-cat-wallpapers"].tap()
            let wide = app.buttons["wallpaper-preview-original-1"]
            XCTAssertTrue(wide.waitForExistence(timeout: 10))
            let scroll = app.scrollViews.containing(.textField, identifier: "wallpaper-source-url").firstMatch
            // Hittable includes partially visible cards. Reveal the entire card
            // before checking its bounds, including single-column localized layouts.
            for _ in 0..<8 {
                let frame = wide.frame
                let viewport = scroll.frame.intersection(app.windows.firstMatch.frame)
                if viewport.contains(frame) { break }
                let startY: CGFloat = frame.maxY > viewport.maxY ? 0.75 : 0.35
                let endY: CGFloat = frame.maxY > viewport.maxY ? 0.35 : 0.75
                scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                    .press(forDuration: 0.05, thenDragTo:
                        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY)))
            }
            let normal = app.buttons["wallpaper-preview-original-0"]
            XCTAssertEqual(wide.frame.width, normal.frame.width, accuracy: 1)
            XCTAssertTrue(app.windows.firstMatch.frame.contains(wide.frame))
            XCTAssertGreaterThanOrEqual(normal.frame.minX, 0)
            shot(language + "_wide_thumbnail_bounded")
            let multi = app.buttons["wallpaper-preview-original-2"]
            // Oversized multi-frame UIImage must never enlarge a neighbouring column.
            if multi.exists {
                XCTAssertEqual(multi.frame.width, wide.frame.width, accuracy: 1)
                XCTAssertGreaterThanOrEqual(multi.frame.minX, 0)
                XCTAssertLessThanOrEqual(multi.frame.maxX, app.windows.firstMatch.frame.maxX)
            }
            wide.tap()
            let close = app.buttons["wallpaper-preview-close"]
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            let install = app.buttons["wallpaper-preview-install"]
            XCTAssertTrue(install.exists && install.isEnabled)
            XCTAssertLessThan(close.frame.midX, app.windows.firstMatch.frame.midX)
            XCTAssertTrue(app.staticTexts["Night tide"].exists)
            shot(language + "_fullscreen_static_image")
            close.tap()
            normal.tap()
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["wallpaper-preview-video"].waitForExistence(timeout: 10))
            shot(language + "_fullscreen_video_frame_a")
            // Wait for actual playback frames, not a replacement still-image fixture.
            let moving = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                (app.descendants(matching: .any)["wallpaper-preview-video"].value as? String) == "playing-muted"
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [moving], timeout: 15), .completed)
            shot(language + "_fullscreen_video_frame_b")
            close.tap()
            XCTAssertFalse(app.buttons["wallpaper-preview-install"].exists)
            app.terminate()
        }
    }

    func testLiveDefaultCAPlaygroundCatalog() {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "tools",
            "-mirsa.appLanguage", "ar", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 2) { alert.buttons.firstMatch.tap() }
        XCTAssertTrue(app.buttons["tools-section-store"].waitForExistence(timeout: 15))
        app.buttons["tools-section-store"].tap()
        XCTAssertTrue(app.buttons["tools-store-cat-wallpapers"].waitForExistence(timeout: 10))
        app.buttons["tools-store-cat-wallpapers"].tap()
        XCTAssertTrue(app.textFields["wallpaper-source-url"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["wallpaper-source-add-caplayground"].exists)
        XCTAssertFalse(app.buttons["tools-store-cat-tweaks"].exists, "Hide placeholder deb/dylib category, retain underlying data")
        XCTAssertFalse(app.buttons["tools-store-cat-sounds"].exists, "Sounds always hidden regardless of inventory")
        shot("ar_tools_store_categories_placeholder_hidden")
        // Real HTTPS feeds and production adapter, deliberately NO fixture flag.
        let first = app.staticTexts["11037 Case 1"]
        XCTAssertTrue(first.waitForExistence(timeout: 100), "Live CA catalog must load without adding a source")
        let scroll = app.scrollViews.containing(.textField, identifier: "wallpaper-source-url").firstMatch
        for _ in 0..<8 {
            if first.isHittable { break }
            scroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(first.isHittable)
        XCTAssertTrue(app.staticTexts["MakotoNaeg"].exists, "Original creator attribution must remain")
        shot("ar_wallpaper_caplayground_live_default")
        let storeScroll = app.scrollViews["tools-store-root"]
        XCTAssertTrue(storeScroll.exists)
        for category in ["wallpapers", "tweaks", "app_tweaks", "sounds", "fonts"] {
            let chip = app.buttons["tools-store-cat-" + category]
            if !chip.exists { continue }
            // Return to the category strip without changing the app's tab order.
            for _ in 0..<12 {
                if chip.isHittable { break }
                storeScroll.swipeDown(velocity: .fast)
            }
            XCTAssertTrue(chip.isHittable)
            chip.tap()
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "reviewed-tools-sources").firstMatch.exists)
            XCTAssertFalse(app.staticTexts["Cylinder Reborn"].exists)
            XCTAssertFalse(app.staticTexts["Return YouTube Dislike"].exists)
            XCTAssertFalse(app.staticTexts["Google Fonts · Noto"].exists)
            XCTAssertFalse(app.staticTexts["Kenney"].exists)
            shot("ar_tools_store_remaining_category_" + category)
        }
    }

}
