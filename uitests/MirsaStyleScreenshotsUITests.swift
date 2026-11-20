import XCTest

/// Captures every reachable page for the style review. Each page is hosted by the
/// DEBUG-only MirsaStyleShotHost (launch argument -MirsaStylePage). No assertions on
/// content: a page that fails to render still yields a screenshot of what is shown.
final class MirsaStyleScreenshotsUITests: XCTestCase {
    private static let pages: [String] = [
        "apps", "sources", "tools", "encrypted", "more", "home-main", "home-personal", "setup",
        "settings", "login", "url-import", "discovery", "certificates", "personal-certificate",
        "signing-queue", "telemetry", "credits", "pairing-guide", "support-popup", "licenses",
        "github-sources", "expiry", "web-upload", "browser", "update", "hidden", "prompt",
        "app-info", "backups", "tweak-library", "no-profile-guide",
    ]
    /// Long pages also get a second screenshot scrolled to the bottom.
    private static let scrolled: Set<String> = ["apps", "sources", "tools", "more", "setup", "settings",
                                                 "pairing-guide", "support-popup", "certificates", "discovery", "credits"]

    override func setUpWithError() throws { continueAfterFailure = true }

    private func launch(_ page: String, lang: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", page,
                               "-mirsa.appLanguage", lang,
                               "-AppleLanguages", lang == "en" ? "(en)" : "(ar)",
                               "-AppleLocale", lang == "en" ? "en_US" : "ar"] + extra
        app.launch()
        Thread.sleep(forTimeInterval: 2.0)
        // First launch asks for notification permission; the system alert would hide the page.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 1) {
            let deny = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow", "عدم السماح"])).firstMatch
            if deny.exists { deny.tap() } else { alert.buttons.firstMatch.tap() }
        }
        Thread.sleep(forTimeInterval: 1.5)
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        guard alive(app) else { print("STYLE-SHOT-SKIPPED \(name): app not running"); return }
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func alive(_ app: XCUIApplication) -> Bool { app.state == .runningForeground }

    private func tap(_ app: XCUIApplication, _ labels: [String]) -> Bool {
        guard alive(app) else { return false }
        for l in labels {
            let b = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", l)).firstMatch
            if b.waitForExistence(timeout: 3), b.isHittable { b.tap(); Thread.sleep(forTimeInterval: 1.5); return true }
        }
        return false
    }

    private func scrollToBottom(_ app: XCUIApplication) {
        guard alive(app) else { return }
        for _ in 0..<4 where alive(app) { app.swipeUp(velocity: .fast) }
        Thread.sleep(forTimeInterval: 1.2)
    }

    func testSourceNewsApprovedBrandingArabicAndEnglish() {
        for lang in ["ar", "en"] {
            let app = launch("source-news-fixture", lang: lang)
            XCTAssertTrue(app.descendants(matching: .any)["source-detail-news"].waitForExistence(timeout: 30))
            shot(app, "\(lang)_source-news-approved-branding")
            app.swipeUp()
            shot(app, "\(lang)_source-news-approved-branding-bottom")
            app.terminate()
        }
    }

    func testSourceNewsLiveArabicAndEnglish() {
        for lang in ["ar", "en"] {
            let app = launch("source-news-live", lang: lang)
            XCTAssertTrue(app.descendants(matching: .any)["source-detail-header"].waitForExistence(timeout: 60))
            XCTAssertTrue(app.textFields["source-app-search"].exists)
            // Live source may legitimately omit branding/news. Capture exactly what it serves.
            Thread.sleep(forTimeInterval: 10)
            shot(app, "\(lang)_source-news-live")
            app.swipeUp()
            shot(app, "\(lang)_source-news-live-bottom")
            app.terminate()
        }
    }

    func testLiquidProgress() {
        for lang in ["ar", "en"] {
            let app = launch("liquid-review", lang: lang)
            XCTAssertTrue(app.scrollViews["liquid.review"].waitForExistence(timeout: 15))
            XCTAssertEqual(app.staticTexts["liquid.title"].label, lang == "ar" ? "تقدّم التنزيل" : "Liquid progress")
            let completion = app.descendants(matching: .any)["liquid.completion-orb"].firstMatch
            XCTAssertTrue(completion.exists)
            shot(app, "liquid_\(lang)_levels")
            app.buttons["liquid.complete"].tap()
            XCTAssertTrue(String(describing: completion.value ?? "").contains("100") || String(describing: completion.value ?? "").contains("١٠٠"))
            shot(app, "liquid_\(lang)_completion")
            app.terminate()
        }
    }

    private func run(lang: String) {
        for page in Self.pages {
            let app = launch(page, lang: lang)
            shot(app, "\(lang)_\(page)")
            if Self.scrolled.contains(page) && alive(app) {
                scrollToBottom(app)
                shot(app, "\(lang)_\(page)-bottom")
            }
            switch page {
            case "apps":
                app.terminate()
                let a = launch(page, lang: lang)
                if tap(a, ["Real Apps", "تطبيقات حقيقية"]) { shot(a, "\(lang)_apps-real") }
                if tap(a, ["Downloads", "التنزيلات"]) { shot(a, "\(lang)_apps-downloads") }
                a.terminate()
            case "tools":
                app.terminate()
                let a = launch(page, lang: lang)
                if tap(a, ["Device", "الجهاز"]) { shot(a, "\(lang)_tools-device") }
                if tap(a, ["Tweaks", "التويكس"]) { shot(a, "\(lang)_tools-tweaks"); if alive(a) { scrollToBottom(a); shot(a, "\(lang)_tools-tweaks-bottom") } }
                if tap(a, ["Translation", "الترجمة"]) { shot(a, "\(lang)_tools-translate") }
                a.terminate()
            default:
                app.terminate()
            }
        }
    }

    /// Exercise the actual six-tab dock and unchanged chat, never a replacement UI.
    func testMirsaAIBottomTab() {
        continueAfterFailure = false
        for lang in ["ar", "en"] {
            let app = launch("tools", lang: lang, extra: ["-MirsaChatFixture", "-MirsaChatEmptyFixture"])
            let ids = ["Apps", "Sources", "Mirsa AI", "Pairing", "Encrypted", "Personal Apps Hub"]
            let buttons = ids.map { app.buttons["main-tab-" + $0] }
            for button in buttons { XCTAssertTrue(button.waitForExistence(timeout: 10)); XCTAssertTrue(button.isHittable) }
            for index in 1..<buttons.count { XCTAssertLessThan(buttons[index - 1].frame.midX, buttons[index].frame.midX) }
            // AI is not duplicated in the top tools segments.
            XCTAssertEqual(app.buttons.matching(identifier: "main-tab-Mirsa AI").count, 1)
            XCTAssertFalse(app.buttons["chat-new"].exists)
            shot(app, lang + "_442_tools_bottom_bar")
            buttons[2].tap()
            XCTAssertTrue(app.buttons["chat-new"].waitForExistence(timeout: 10))
            shot(app, lang + "_442_ai_bottom_tab")
            app.buttons["chat-new"].tap()
            XCTAssertTrue(app.staticTexts["chat-welcome"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "chat-input").firstMatch.exists)
            shot(app, lang + "_442_ai_conversation")
            app.buttons["chat-back"].tap()
            XCTAssertTrue(app.buttons["main-tab-Pairing"].waitForExistence(timeout: 10))
            app.buttons["main-tab-Pairing"].tap()
            XCTAssertTrue(tap(app, ["Tendies"]))
            XCTAssertTrue(app.buttons["wallpaper-flash"].waitForExistence(timeout: 10))
            // The sixth destination must remain directly reachable, not replaced by More.
            app.buttons["main-tab-Personal Apps Hub"].tap()
            shot(app, lang + "_442_certificate_transition")
            XCTAssertTrue(app.buttons["main-tab-Personal Apps Hub"].isSelected)
            XCTAssertFalse(app.buttons["wallpaper-flash"].isHittable, "hidden Tools must not receive taps")
            XCTAssertFalse(app.navigationBars["More"].exists || app.navigationBars["المزيد"].exists, "sixth destination fell under native More")
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "personal-hub-root").firstMatch.waitForExistence(timeout: 10), "sixth tab content missing")
            shot(app, lang + "_442_certificate_sixth_tab")
            XCTAssertTrue(app.buttons["main-tab-Mirsa AI"].isHittable)
            // Revisit the retained Tools subtree without reselecting Tendies.
            app.buttons["main-tab-Pairing"].tap()
            shot(app, lang + "_442_tools_return_transition")
            XCTAssertTrue(app.buttons["wallpaper-flash"].isHittable, "Tools selection was not preserved")
            shot(app, lang + "_442_tools_state_restored")
            app.buttons["main-tab-Mirsa AI"].tap()
            XCTAssertTrue(app.buttons["chat-new"].isHittable, "AI root state was not restored")
            shot(app, lang + "_442_ai_state_restored")
            app.terminate()
        }
    }

    /// Physical viewport and responsive tab round trips on the actual Tools hierarchy.
    /// Does not open media pickers, apply/delete wallpapers or restart the screen.
    func testTendiesViewportAndReturn() {
        continueAfterFailure = false
        for lang in ["ar", "en"] {
            let app = launch("tools", lang: lang)
            let tools = app.buttons["main-tab-Pairing"]
            let ai = app.buttons["main-tab-Mirsa AI"]
            let tendies = app.buttons["tools-section-wallpapers"]
            XCTAssertTrue(tendies.waitForExistence(timeout: 10))
            tendies.tap()
            let flash = app.buttons["wallpaper-flash"]
            XCTAssertTrue(flash.waitForExistence(timeout: 10))
            for round in 0..<3 {
                let screen = app.windows.firstMatch.frame
                for id in ["wallpaper-flash", "wallpaper-request", "main-tab-Pairing", "main-tab-Mirsa AI"] {
                    let control = app.buttons[id]
                    XCTAssertTrue(control.isHittable, "Unresponsive or clipped " + id)
                    XCTAssertGreaterThanOrEqual(control.frame.minX, screen.minX - 1)
                    XCTAssertLessThanOrEqual(control.frame.maxX, screen.maxX + 1)
                }
                XCTAssertTrue(tools.isSelected)
                shot(app, lang + "_tendies_viewport_" + String(round))
                ai.tap()
                XCTAssertTrue(ai.isSelected)
                tools.tap()
                XCTAssertTrue(flash.waitForExistence(timeout: 5))
                XCTAssertTrue(flash.isHittable)
            }
            app.terminate()
        }
    }

    /// The actual result card must expose the wallpaper action, never IPA installation or injection.
    /// Download integrity and existing library import are exercised separately by the unit suite.
    func testTendiesArtifactCard() {
        continueAfterFailure = false
        for lang in ["ar", "en"] {
            let app = launch("mirsa-ai-chat", lang: lang, extra: ["-MirsaChatFixture", "-MirsaTendiesArtifactFixture"])
            let add = app.buttons["mirsa.chat.artifact.add-wallpaper"]
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            XCTAssertTrue(add.isHittable)
            XCTAssertEqual(add.label, lang == "ar" ? "أضف للخلفيات" : "Add to wallpapers")
            XCTAssertTrue(app.staticTexts["Naruto-Space.tendies"].exists)
            XCTAssertFalse(app.buttons["mirsa.chat.artifact.inject"].exists)
            shot(app, lang + "_449_tendies_artifact_card")
            app.terminate()
        }
    }

    /// Match identifiers only, never a translated visible label or an arbitrary descendant.
    /// Keep the button type constraint to catch accessibility-container regressions.
    private func dockButton(_ app: XCUIApplication, _ destination: String) -> XCUIElement {
        app.buttons.matching(identifier: "main-tab-" + destination).element
    }

    /// Classic theme must also expose all six destinations directly, never native More.
    func testClassicSixTabs() {
        continueAfterFailure = false
        for lang in ["ar", "en"] {
            let app = launch("tools", lang: lang, extra: ["-mirsa.theme", "classic"])
            let ids = ["Apps", "Sources", "Mirsa AI", "Pairing", "Encrypted", "Personal Apps Hub"]
            for id in ids {
                let b = dockButton(app, id)
                XCTAssertTrue(b.waitForExistence(timeout: 10), id)
                XCTAssertTrue(b.isHittable, id)
            }
            dockButton(app, "Personal Apps Hub").tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "personal-hub-root").firstMatch.waitForExistence(timeout: 10))
            XCTAssertFalse(app.navigationBars["More"].exists || app.navigationBars["المزيد"].exists)
            XCTAssertTrue(dockButton(app, "Personal Apps Hub").isSelected)
            shot(app, lang + "_445_classic_sixth_tab")
            dockButton(app, "Mirsa AI").tap()
            XCTAssertTrue(app.buttons["chat-new"].waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    /// Actual dock materials in both system appearances and all supported languages.
    func testGlassDockMaterials() {
        continueAfterFailure = false
        for lang in ["ar", "en", "de", "kmr", "ckb"] {
            for appearance in ["dark", "light"] {
                let app = launch("glass-dock-review", lang: lang,
                                 extra: appearance == "light" ? ["-GlassDockLight"] : [])
                let pill = app.descendants(matching: .any).matching(identifier: "mirsa-main-tab-pill").firstMatch
                XCTAssertTrue(pill.waitForExistence(timeout: 10))
                let ai = dockButton(app, "Mirsa AI")
                XCTAssertTrue(ai.isHittable)
                XCTAssertEqual(ai.frame.width, ai.frame.height, accuracy: 2)
                XCTAssertGreaterThan(ai.frame.minX, pill.frame.maxX)
                for id in ["Apps", "Sources", "Pairing", "Encrypted", "Personal Apps Hub", "Mirsa AI"] {
                    let b = dockButton(app, id)
                    XCTAssertTrue(b.waitForExistence(timeout: 10), "\(lang) \(id)")
                    XCTAssertTrue(b.isHittable, "\(lang) \(id)")
                    XCTAssertFalse(b.label.isEmpty)
                    b.tap()
                    XCTAssertTrue(b.isSelected, id)
                    if lang == "ar" || lang == "en" {
                        shot(app, "glass_\(lang)_\(appearance)_\(id.replacingOccurrences(of: " ", with: "_"))")
                    }
                }
                app.terminate()
            }
        }
    }

    /// Floating dock for every theme: six tabs, selected trait, tab transitions.
    func testFloatingDockAllThemes() {
        continueAfterFailure = false
        for theme in ["liquid", "classic"] {
            for lang in ["ar", "en"] {
                let app = launch("tools", lang: lang, extra: ["-mirsa.theme", theme])
                XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "mirsa-tab-dock").firstMatch.waitForExistence(timeout: 10))
                for id in ["Apps", "Sources", "Mirsa AI", "Pairing", "Encrypted", "Personal Apps Hub"] {
                    let b = dockButton(app, id)
                    XCTAssertTrue(b.waitForExistence(timeout: 10), id)
                    b.tap(); Thread.sleep(forTimeInterval: 0.8)
                    XCTAssertTrue(b.isSelected, id)
                }
                shot(app, lang + "_450_dock_" + theme)
                app.terminate()
            }
        }
    }

    /// Alternate icon selection was removed; Settings must not expose it.
    func testAppIconPickerAllIcons() {
        continueAfterFailure = false
        for lang in ["ar", "en"] {
            let app = launch("settings", lang: lang)
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            for i in 0...6 { XCTAssertFalse(app.buttons["mirsa.icon.\(i)"].exists) }
            shot(app, lang + "_primary_icon_only")
            app.terminate()
        }
    }

    /// Chat image: tap opens fullscreen with close and save controls.
    func testChatImageFullscreen() {
        continueAfterFailure = false
        for lang in ["ar", "en"] {
            let app = launch("chat-image-fixture", lang: lang)
            let thumb = app.descendants(matching: .any).matching(identifier: "chat-image-thumb").firstMatch
            XCTAssertTrue(thumb.waitForExistence(timeout: 10))
            thumb.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "chat-image-zoom").firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["chat-image-save"].exists)
            app.descendants(matching: .any).matching(identifier: "chat-image-zoom").firstMatch.pinch(withScale: 2, velocity: 1)
            shot(app, lang + "_450_image_fullscreen")
            app.buttons["chat-image-close"].tap()
            XCTAssertTrue(thumb.waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    /// Respring button is standalone under the primary actions.
    func testRespringStandalone() {
        continueAfterFailure = false
        for lang in ["ar", "en"] {
            let app = launch("tools", lang: lang)
            XCTAssertTrue(tap(app, ["Tendies"]))
            XCTAssertTrue(app.buttons["wallpaper-respring"].waitForExistence(timeout: 10) || app.descendants(matching: .any).matching(identifier: "wallpaper-respring").firstMatch.exists)
            shot(app, lang + "_450_respring")
            app.terminate()
        }
    }


    /// 3 imported, 1 selected: the apply button and respring must be visible. Never taps apply (fixture).
    func testTendiesSelectedApplyVisible() {
        continueAfterFailure = false
        for lang in ["ar", "en"] {
            let app = launch("tools", lang: lang, extra: ["-MirsaWallpaperSelectedFixture"])
            XCTAssertTrue(tap(app, ["Tendies"]))
            let apply = app.buttons["wallpaper-install-selected"]
            revealWallpaperElement(apply, identifier: "wallpaper-install-selected", in: app)
            XCTAssertTrue(apply.exists)
            XCTAssertTrue(apply.label.contains("1"))
            let respring = app.buttons["wallpaper-respring"]
            revealWallpaperElement(respring, identifier: "wallpaper-respring", in: app)
            XCTAssertTrue(respring.exists)
            XCTAssertGreaterThan(respring.frame.minY, apply.frame.minY)
            XCTAssertEqual(app.buttons.matching(identifier: "wallpaper-respring").count, 1)
            shot(app, lang + "_tendies_selected_apply")
            app.terminate()
        }
    }

    /// Real implemented page, no replacement mock. Tools must start closed, and both
    /// primary actions stay on the same row in Arabic RTL and English LTR.
    func testTendiesReorganizedPage() {
        continueAfterFailure = false
        for lang in ["ar", "en"] {
            let app = launch("tools", lang: lang, extra: ["-MirsaWallpaperFlashLogFixture"])
            XCTAssertTrue(tap(app, ["Tendies"]))
            let install = app.buttons["wallpaper-flash"]
            let request = app.buttons["wallpaper-request"]
            XCTAssertTrue(install.waitForExistence(timeout: 10))
            XCTAssertTrue(request.exists)
            XCTAssertTrue(install.isHittable)
            XCTAssertTrue(request.isHittable)
            XCTAssertLessThan(abs(install.frame.midY - request.frame.midY), 20)
            shot(app, lang + "_tendies_main_top")
            install.tap()
            let picker = app.descendants(matching: .any).matching(identifier: "wallpaper-document-picker").firstMatch
            XCTAssertTrue(picker.waitForExistence(timeout: 10), "Primary install must open the real document picker")
            XCTAssertFalse(app.alerts.firstMatch.exists, "Never confirm old selections before picking")
            shot(app, lang + "_tendies_primary_install_picker")
            app.terminate()

            app.launch()
            XCTAssertTrue(tap(app, ["Tendies"]))
            let importButton = app.buttons["wallpaper-import"]
            revealWallpaperElement(importButton, identifier: "wallpaper-import", in: app)
            XCTAssertTrue(importButton.isHittable, "Import must be on the main page with tools closed")
            shot(app, lang + "_tendies_main_import")
            let video = app.buttons["video-wallpaper-from-photos"]
            revealWallpaperElement(video, identifier: "video-wallpaper-from-photos", in: app)
            XCTAssertTrue(video.isHittable, "Video creation must remain on the main page")
            shot(app, lang + "_tendies_main_video")
            let respring = app.buttons["wallpaper-respring"]
            revealWallpaperElement(respring, identifier: "wallpaper-respring", in: app)
            XCTAssertTrue(respring.isHittable, "Respring remains an ordinary user action")
            shot(app, lang + "_tendies_main_respring")
            for page in 0..<6 {
                XCTAssertFalse(app.buttons["owner-diagnostics"].exists)
                XCTAssertFalse(app.buttons["wallpaper-tools"].exists)
                XCTAssertFalse(app.buttons["diagnostics-copy"].exists)
                XCTAssertFalse(app.descendants(matching: .any)["wallpaper-flash-log"].exists)
                shot(app, lang + "_tendies_nonowner_" + String(page))
                app.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(app.buttons["wallpaper-refresh"].exists)
            XCTAssertTrue(app.buttons["wallpaper-cleanup"].exists)
            app.terminate()

            let fresh = launch("tools", lang: lang)
            XCTAssertTrue(tap(fresh, ["Tendies"]))
            let freshInstall = fresh.buttons["wallpaper-flash"]
            XCTAssertTrue(freshInstall.waitForExistence(timeout: 10))
            XCTAssertTrue(freshInstall.isEnabled, "No imported selection is required to choose a file")
            fresh.terminate()
        }
    }

    func testNonownerHasNoDiagnostics() {
        for lang in ["ar", "en", "de", "kmr", "ckb"] {
            let app = launch("tools", lang: lang, extra: ["-MirsaWallpaperFlashLogFixture"])
            XCTAssertTrue(tap(app, ["Tendies"]))
            XCTAssertTrue(app.buttons["wallpaper-flash"].waitForExistence(timeout: 10))
            for _ in 0..<8 {
                for identifier in ["owner-diagnostics", "diagnostics-copy", "wallpaper-tools", "wallpaper-flash-log"] {
                    XCTAssertFalse(app.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists)
                }
                app.swipeUp(velocity: .slow)
            }
            shot(app, lang + "_diagnostics_absent_nonowner")
            app.terminate()
        }
    }

    /// App Store section: each page of its own tab bar, with a DEBUG-only fixture account (no Apple request).
    /// Captured in both Apple Store styles; `-mirsa.store.style` sets the same UserDefaults key the
    /// Settings picker writes (argument domain, this launch only).
    func testAppStoreSectionPages() {
        let pages: [(tab: String, route: String?, name: String)] = [
            ("search", nil, "search"), ("search", "detail", "detail"), ("downloads", nil, "downloads"),
            ("purchases", nil, "purchases"), ("account", nil, "account"), ("account", "settings", "settings"),
        ]
        for style in ["classic", "new"] {
            for lang in ["ar", "en"] {
                // The New (gallery) style opens on Discover, a page the Classic style does not have.
                let discover: [(tab: String, route: String?, name: String)] = style == "new" ? [(tab: "discover", route: nil, name: "discover")] : []
                for page in discover + pages {
                    var extra = ["-mirsa.store.style", style, "-MirsaStoreFixtureAccount", "-MirsaStoreTab", page.tab]
                    if page.route == "detail" { extra.append("-MirsaStoreFixtureDetail") }
                    else if let route = page.route { extra += ["-MirsaStoreRoute", route] }
                    let app = launch("encrypted", lang: lang, extra: extra)
                    shot(app, "\(lang)_\(style)_store-\(page.name)")
                    if page.name == "settings" || page.name == "downloads" || page.name == "detail" {
                        scrollToBottom(app)
                        shot(app, "\(lang)_\(style)_store-\(page.name)-bottom")
                    }
                    app.terminate()
                }
            }
        }
    }

    /// Mirsa's main settings scrolled to the Apple Store style option (picker + explanation).
    /// Short controlled drags so the option lands mid-screen instead of being flung past.
    func testStoreStyleSetting() {
        for lang in ["ar", "en"] {
            let app = launch("settings", lang: lang)
            let picker = app.descendants(matching: .any).matching(identifier: "store-style-picker").firstMatch
            let height = app.frame.height
            var tries = 0
            while alive(app) && tries < 30 {
                tries += 1
                let y = picker.exists ? picker.frame.midY : height
                if picker.exists && y > height * 0.25 && y < height * 0.6 { break }
                let up = !picker.exists || y >= height * 0.6
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.7 : 0.4))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.45 : 0.6))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            }
            Thread.sleep(forTimeInterval: 1.0)
            shot(app, "\(lang)_settings-store-style")
            app.terminate()
        }
    }

    // MARK: Store performance sanity (simulator, relative numbers only)
    //
    // Time to first store frame (launch until the section bar exists) is printed as
    // "STORE-PERF <style> <tab> first-frame <s>". The scroll pass is measured with
    // XCTClockMetric/XCTCPUMetric; xcodebuild prints the averages in the log
    // ("measured [Clock Monotonic Time, s]"). Gestures wait for the app to be idle,
    // so heavier rendering and running animations show up as longer times.

    private func perfLaunch(style: String, tab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "encrypted",
                               "-mirsa.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-mirsa.store.style", style, "-MirsaStoreFixtureAccount", "-MirsaStoreTab", tab]
        let t0 = Date()
        app.launch()
        // In the New (gallery) style Purchases opens from Account, so its capsule lights the Account item.
        let item = style == "new" && tab == "purchases" ? "account" : tab
        let bar = app.descendants(matching: .any).matching(identifier: "store-tab-\(item)").firstMatch
        let ok = bar.waitForExistence(timeout: 20)
        print(String(format: "STORE-PERF %@ %@ first-frame %.3f %@", style, tab, Date().timeIntervalSince(t0), ok ? "ok" : "timeout"))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 1) { alert.buttons.firstMatch.tap() }
        Thread.sleep(forTimeInterval: 1.0)
        return app
    }

    private func perfScroll(style: String, tab: String) {
        let app = perfLaunch(style: style, tab: tab)
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app)], options: options) {
            for _ in 0..<3 { app.swipeUp(velocity: .fast) }
            for _ in 0..<3 { app.swipeDown(velocity: .fast) }
        }
        app.terminate()
    }

    func testPerfClassicSearch() { perfScroll(style: "classic", tab: "search") }
    func testPerfNewSearch() { perfScroll(style: "new", tab: "search") }
    func testPerfClassicPurchases() { perfScroll(style: "classic", tab: "purchases") }
    func testPerfNewPurchases() { perfScroll(style: "new", tab: "purchases") }
    func testPerfClassicAccount() { perfScroll(style: "classic", tab: "account") }
    func testPerfNewAccount() { perfScroll(style: "new", tab: "account") }

    /// Exercise actual PHPickers. No mock picker, media selection, export or apply.
    func testWallpaperMakerPickersStayIndependent() {
        continueAfterFailure = false
        for lang in ["ar", "en"] {
            let app = launch("tools", lang: lang)
            XCTAssertTrue(tap(app, ["Tendies"]))
            // Creation is ordinary content now; the removed tools disclosure
            // held diagnostics, not the photo/video pickers.
            XCTAssertFalse(app.buttons["owner-diagnostics"].exists)
            for kind in ["photos", "video"] {
                let button = app.buttons["wallpaper-choose-" + kind]
                revealWallpaperElement(button, identifier: "wallpaper-choose-" + kind, in: app)
                XCTAssertTrue(button.isHittable)
                XCTAssertEqual(app.buttons.matching(identifier: "wallpaper-choose-" + kind).count, 1)
                button.tap()
                // Evidence split: did the action fire (state) vs did a sheet appear (host marker).
                let state = app.descendants(matching: .any).matching(identifier: "wallpaper-picker-state").firstMatch
                let fired = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    state.exists && (state.value as? String) == kind }, object: nil)
                if XCTWaiter.wait(for: [fired], timeout: 5) != .completed {
                    add(XCTAttachment(string: "state exists=\(state.exists) value=\(String(describing: state.value))" + "\n" + app.debugDescription))
                    XCTFail("Button tap did not set picker state to " + kind)
                }
                let prefix = "wallpaper-" + kind + "-picker-"
                let query = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
                let picker = query.firstMatch
                XCTAssertTrue(picker.waitForExistence(timeout: 10))
                XCTAssertEqual(query.count, 1, "One tap must create one picker host")
                let identity = picker.identifier
                let otherKind = kind == "photos" ? "video" : "photos"
                let other = app.descendants(matching: .any).matching(NSPredicate(
                    format: "identifier BEGINSWITH %@", "wallpaper-" + otherKind + "-picker-"))
                XCTAssertEqual(other.count, 0, "The other button's action must never fire")
                let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    !picker.exists || picker.identifier != identity || other.count != 0
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 4), .timedOut,
                               "Native picker must stay open with the SAME instance")
                shot(app, lang + "_maker_" + kind + "_picker_stable")
                let cancel = app.buttons.matching(NSPredicate(
                    format: "label IN %@", ["Cancel", "إلغاء"])).firstMatch
                XCTAssertTrue(cancel.waitForExistence(timeout: 3))
                cancel.tap()
                XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
                let reopened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    query.count != 0 || other.count != 0
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [reopened], timeout: 2), .timedOut,
                               "Cancel must not reopen either picker")
            }
            app.terminate()
        }
    }

    /// Real tools tab, dock and NavigationStack, with local DEBUG-only sample photos.
    /// No network AI call or wallpaper apply/respring is performed by this test.
    func testWallpaperMakerLayout() {
        continueAfterFailure = false
        for lang in ["ar", "en"] {
            for largeText in [false, true] {
              for theme in ["liquid", "classic"] {
                let extra = ["-MirsaWallpaperFixture", "-MirsaWallpaperAIFixture", "-MirsaWallpaperFlashLogFixture", "-mirsa.theme", theme] +
                    (largeText ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] : [])
                let app = launch("tools", lang: lang, extra: extra)
                XCTAssertTrue(tap(app, ["Tendies"]))
                let prefix = "\(lang)_tendies_\(theme)_\(largeText ? "large" : "standard")"
                shot(app, prefix + "_top")
                XCTAssertFalse(app.buttons["owner-diagnostics"].exists)
                let field = app.descendants(matching: .any).matching(identifier: "wallpaper-description").firstMatch
                revealWallpaperElement(field, identifier: "wallpaper-description", in: app)
                XCTAssertTrue(field.isHittable)
                XCTAssertGreaterThan(field.frame.height, 65, "Multiline text needs intrinsic height")
                shot(app, prefix + "_multiline")
                if !largeText {
                    // XCTest's automatic activation point picked (37, 511.5),
                    // inside the padded corner of the RTL 311x80 input, not its
                    // editable interior. Use the visible center; keep keyboard,
                    // editing, toolbar and whole-field clearance assertions real.
                    print("WALLPAPER-INPUT beforeTap frame=\(field.frame) matches=\(app.descendants(matching: .any).matching(identifier: "wallpaper-description").count)")
                    XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "wallpaper-description").count, 1)
                    field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
                    field.typeText("Wallpaper")
                    XCTAssertTrue((field.value as? String)?.contains("Wallpaper") == true,
                                  "The visible input must accept actual text, not just show a keyboard")
                    let done = app.buttons["wallpaper-keyboard-done"]
                    XCTAssertTrue(done.waitForExistence(timeout: 3))
                    XCTAssertEqual(app.buttons.matching(identifier: "wallpaper-keyboard-done").count, 1,
                                   "The Form must not duplicate the keyboard toolbar")
                    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "mirsa-tab-dock").firstMatch.waitForNonExistence(timeout: 5),
                                  "The floating dock must not cover the focused multiline field")
                    let inputVisible = NSPredicate { _, _ in field.frame.maxY <= done.frame.minY }
                    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: inputVisible, object: nil)], timeout: 5), .completed,
                                  "All input lines must stay above the keyboard accessory, not just the keys")
                    shot(app, prefix + "_keyboard")
                    done.tap()
                    XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
                    if theme == "liquid" {
                        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "mirsa-tab-dock").firstMatch.waitForExistence(timeout: 5))
                    } else {
                        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
                    }
                }
                let generate = app.buttons["wallpaper-generate"]
                revealWallpaperElement(generate, identifier: "wallpaper-generate", in: app)
                XCTAssertTrue(generate.isHittable)
                let compatibility = app.staticTexts["wallpaper-compatibility"]
                revealWallpaperElement(compatibility, identifier: "wallpaper-compatibility", in: app)
                shot(app, prefix + "_maker_bottom")
                let respring = app.buttons["wallpaper-respring"]
                revealWallpaperElement(respring, identifier: "wallpaper-respring", in: app)
                XCTAssertTrue(respring.isHittable, "Respring must stay above the dock")
                XCTAssertGreaterThan(respring.frame.minY, app.navigationBars.firstMatch.frame.maxY)
                XCTAssertLessThanOrEqual(respring.frame.maxY, wallpaperVisibleBottom(in: app),
                                         "The whole red action must clear the actual tab bar, not just be hittable")
                let flash = app.buttons["wallpaper-flash"]
                XCTAssertTrue(flash.exists)
                // Disabled (no selection) is correct, but the full label must be visible.
                if !largeText {
                    XCTAssertGreaterThan(flash.frame.minY, 130)
                    XCTAssertLessThan(flash.frame.maxY, wallpaperVisibleBottom(in: app))
                }
                shot(app, prefix + "_actions")
                let help = app.staticTexts["wallpaper-flash-help"]
                revealWallpaperElement(help, identifier: "wallpaper-flash-help", in: app)
                XCTAssertLessThanOrEqual(help.frame.maxY, wallpaperVisibleBottom(in: app))
                shot(app, prefix + "_screen_bottom")
                let log = app.descendants(matching: .any).matching(identifier: "wallpaper-flash-log").firstMatch
                revealWallpaperElement(log, identifier: "wallpaper-flash-log", in: app)
                XCTAssertTrue(log.exists, "The populated Flash Log must participate in layout")
                shot(app, prefix + "_populated_log")
                revealWallpaperElement(respring, identifier: "wallpaper-respring", in: app, unmaterializedDistance: -80)
                XCTAssertLessThanOrEqual(respring.frame.maxY, wallpaperVisibleBottom(in: app))
                shot(app, prefix + "_actions_after_log")
                app.terminate()
              }
            }
        }
    }

    /// Original video wallpaper block sits at the TOP of the same tab, Tendies maker below it.
    func testVideoWallpaperPreservedInsideTools() {
        continueAfterFailure = false
        for lang in ["ar", "en"] {
            let app = launch("tools", lang: lang, extra: ["-MirsaWallpaperFixture", "-MirsaWallpaperAIFixture"])
            XCTAssertTrue(tap(app, ["Tendies"]))
            let video = app.descendants(matching: .any).matching(identifier: "video-wallpaper-from-photos").firstMatch
            XCTAssertTrue(video.waitForExistence(timeout: 10))
            revealWallpaperElement(video, identifier: "video-wallpaper-from-photos", in: app)
            XCTAssertTrue(video.isHittable, "Original video wallpaper is retained within tools")
            let initialVideoFrame = video.frame
            let field = app.descendants(matching: .any).matching(identifier: "wallpaper-description").firstMatch
            // Compare frames only before scrolling; Form virtualizes upper rows.
            if field.exists && field.frame.minY > 0 {
                XCTAssertLessThan(initialVideoFrame.minY, field.frame.minY)
            }
            revealWallpaperElement(field, identifier: "wallpaper-description", in: app)
            XCTAssertTrue(field.isHittable)
            // Return using the same bounded visibility helper, not three guessed
            // swipes that depend on Dynamic Type and localized row heights.
            revealWallpaperElement(video, identifier: "video-wallpaper-from-photos", in: app, unmaterializedDistance: -80)
            XCTAssertTrue(video.isHittable)
            shot(app, "\(lang)_videowallpaper_top")
            app.terminate()
        }
    }

    private func wallpaperVisibleBottom(in app: XCUIApplication) -> CGFloat {
        let dock = app.descendants(matching: .any).matching(identifier: "mirsa-tab-dock").firstMatch
        // Assert against the actual obstruction, not a guessed 110pt inset that
        // incorrectly rejects a fully visible footer on the compact simulator.
        if dock.exists { return dock.frame.minY - 8 }
        let nativeBar = app.tabBars.firstMatch
        return nativeBar.exists ? nativeBar.frame.minY - 8 : app.frame.maxY - 8
    }

    private func revealWallpaperElement(_ element: XCUIElement, identifier: String, in app: XCUIApplication, unmaterializedDistance: CGFloat = 80) {
        let top = app.navigationBars.firstMatch.frame.maxY + 8
        let bottom = wallpaperVisibleBottom(in: app)
        // Accessibility text makes the populated three-layer form much taller.
        // The f37 run advanced normally (~69pt per drag) but exhausted 24
        // drags before even passing the layer list. Keep the precise 80pt pans
        // and full-frame assertions; allow enough travel for the large form.
        let maximumPans = 80
        for attempt in 0..<maximumPans {
            // Form virtualizes off-screen rows. Neither frame nor identifier is
            // safe to request until the query matches a materialized element.
            let frame: CGRect? = element.exists ? element.frame : nil
            if let frame, frame.minY >= top && frame.maxY <= bottom { return }
            // Fixed 32%-screen swipes overshoot the compact safe viewport at
            // accessibility sizes, alternating above/below the target forever.
            // Move toward its measured center in bounded, non-flinging steps.
            // Drag content, NOT the five-point window edge. The edge overlaps
            // UIKit's draggable scroll indicator. The failed respring screenshot
            // moved backwards to earlier effects instead of continuing down.
            let center = (top + bottom) / 2
            // A virtualized target has no measurable frame. Use the caller's
            // known document direction: video is ABOVE the maker, while the
            // other requested controls are BELOW the current viewport.
            let error = frame.map { $0.midY - center } ?? unmaterializedDistance
            let distance = min(80, max(-80, error))
            // Prefer a fully visible, non-editable text label as the pan anchor.
            // Keep both endpoints in the actual unobstructed content viewport,
            // away from sliders, text inputs, reorder handles and either edge.
            let labels = app.staticTexts.allElementsBoundByIndex.filter {
                let f = $0.frame
                return f.width > 40 && f.height < 180
                    && f.midX > 40 && f.midX < app.frame.width - 40
                    && f.midY > top + 84 && f.midY < bottom - 84
                    && $0.isHittable
            }
            let anchor = labels.min { abs($0.frame.midY - center) < abs($1.frame.midY - center) }
            let point = anchor.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
                ?? CGPoint(x: app.frame.midX, y: center)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: point.x, dy: point.y))
            let end = origin.withOffset(CGVector(dx: point.x, dy: point.y - distance))
            print("WALLPAPER-REVEAL \(identifier) pan=\(attempt + 1)/\(maximumPans) frame=\(String(describing: frame)) safe=\(top)...\(bottom) distance=\(distance) contentAnchor=\(point)")
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        // The last bounded pan may have revealed the target. Evaluate it too.
        if element.exists {
            let frame = element.frame
            if frame.minY >= top && frame.maxY <= bottom { return }
        }
        shot(app, "unreachable_" + identifier)
        let finalFrame = element.exists ? String(describing: element.frame) : "not materialized"
        XCTFail("Unreachable wallpaper control \(identifier): \(finalFrame)")
    }

    func testArabicPages() { run(lang: "ar") }
    func testEnglishPages() { run(lang: "en") }
}
