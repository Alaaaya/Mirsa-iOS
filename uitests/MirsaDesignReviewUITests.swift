import XCTest

/// Design review screenshots for mirsa/design-floating-dock-glass: the Apps home and
/// Tools › Device, in Arabic and English, for both themes. No assertions on content
/// beyond the dock being present; every run attaches named full-screen screenshots.
final class MirsaDesignReviewUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(lang: String, theme: String, storeDetail: Bool? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "apps-design",
                               "-mirsa.appLanguage", lang, "-mirsa.theme", theme,
                               "-mirsa.apps.homeLayout", "NO",
                               "-AppleLanguages", lang == "en" ? "(en)" : "(ar)",
                               "-AppleLocale", lang == "en" ? "en_US" : "ar"]
        if let detail = storeDetail {
            let i = app.launchArguments.firstIndex(of: "apps-design")!
            app.launchArguments[i] = "encrypted"
            app.launchArguments += ["-MirsaStoreFixtureAccount", "-MirsaStoreTab", "search"]
            if detail { app.launchArguments.append("-MirsaStoreFixtureDetail") }
        }
        app.launch()
        Thread.sleep(forTimeInterval: 2.0)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 1) {
            let deny = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow", "عدم السماح"])).firstMatch
            if deny.exists { deny.tap() } else { alert.buttons.firstMatch.tap() }
        }
        Thread.sleep(forTimeInterval: 1.5)
        return app
    }

    private func shot(_ name: String) {
        let hierarchy = XCTAttachment(string: XCUIApplication().debugDescription)
        hierarchy.name = name + "_hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testDesignReviewHomeAndTools() {
        for theme in ["classic", "liquid"] {
            for lang in ["ar", "en"] {
                let app = launch(lang: lang, theme: theme)
                XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "mirsa-tab-dock").firstMatch.waitForExistence(timeout: 10))
                shot("design_\(lang)_\(theme)_1_home")

                app.swipeUp(velocity: .slow)
                Thread.sleep(forTimeInterval: 1.0)
                shot("design_\(lang)_\(theme)_2_home_scrolled")

                let tools = app.buttons["main-tab-Pairing"]
                XCTAssertTrue(tools.waitForExistence(timeout: 5))
                XCTAssertTrue(tools.isHittable)
                tools.tap()
                Thread.sleep(forTimeInterval: 1.2)
                XCTAssertTrue(tools.isSelected)
                shot("design_\(lang)_\(theme)_3_tools")
                let device = app.buttons["tools-section-device"]
                XCTAssertTrue(device.waitForExistence(timeout: 5))
                XCTAssertTrue(device.isHittable)
                device.tap()
                Thread.sleep(forTimeInterval: 1.2)
                XCTAssertTrue(device.isSelected)
                shot("design_\(lang)_\(theme)_4_tools_device")
                // Retained NavigationStacks must keep their section across tab switches.
                app.buttons["main-tab-Apps"].tap()
                tools.tap()
                XCTAssertTrue(device.isSelected)
                let sections = ["pairing", "device", "wallpapers", "tweaks"].map { app.buttons["tools-section-" + $0] }
                for (left, right) in zip(sections, sections.dropFirst()) {
                    XCTAssertLessThan(left.frame.midX, right.frame.midX, "Tools physical order must not mirror")
                }
                let tendies = app.buttons["tools-section-wallpapers"]
                XCTAssertTrue(tendies.isHittable)
                tendies.tap()
                XCTAssertTrue(app.buttons["wallpaper-flash"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["wallpaper-request"].exists)
                XCTAssertTrue(app.buttons["wallpaper-import"].exists)
                XCTAssertTrue(app.buttons["wallpaper-respring"].exists)
                shot("design_\(lang)_\(theme)_5_tendies")
                app.swipeUp(velocity: .slow)
                shot("design_\(lang)_\(theme)_6_tendies_scrolled")
                app.terminate()
                for detail in [false, true] {
                    let storeApp = launch(lang: lang, theme: theme, storeDetail: detail)
                    XCTAssertTrue(storeApp.buttons["store-tab-search"].waitForExistence(timeout: 10))
                    if detail {
                        XCTAssertTrue(storeApp.buttons["store-detail-get"].waitForExistence(timeout: 5))
                    } else {
                        XCTAssertTrue(storeApp.staticTexts["Notes Pro"].waitForExistence(timeout: 5))
                    }
                    shot("design_\(lang)_\(theme)_" + (detail ? "8_app_store_detail" : "7_app_store_results"))
                    storeApp.terminate()
                }
            }
        }
    }
    /// Real SwiftUI screens with fixture data only, not generated mockups.
    func testAppstoreDesignArabicLiquidScreens() {
        let store = launch(lang: "ar", theme: "liquid", storeDetail: false)
        let dock = store.descendants(matching: .any).matching(identifier: "mirsa-tab-dock").firstMatch
        let search = store.buttons["store-tab-search"]
        XCTAssertTrue(dock.waitForExistence(timeout: 10))
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertLessThan(search.frame.midY, dock.frame.minY, "Store bar must be above the Mirsa dock")
        shot("appstore_ar_liquid_store")
        store.terminate()
        let apps = launch(lang: "ar", theme: "liquid")
        XCTAssertTrue(apps.buttons["main-tab-Apps"].waitForExistence(timeout: 10))
        shot("appstore_ar_liquid_apps")
        apps.terminate()
        for page in ["settings", "mirsa-ai-chat"] {
            let app = XCUIApplication()
            app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", page,
                                   "-mirsa.appLanguage", "ar", "-mirsa.theme", "liquid",
                                   "-mirsa.store.style", "new", "-MirsaChatFixture",
                                   "-AppleLanguages", "(ar)", "-AppleLocale", "ar"]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            Thread.sleep(forTimeInterval: 3)
            shot("appstore_ar_liquid_" + page)
            app.terminate()
        }
    }

}
