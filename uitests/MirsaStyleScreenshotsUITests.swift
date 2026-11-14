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
                for page in pages {
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
        let bar = app.descendants(matching: .any).matching(identifier: "store-tab-\(tab)").firstMatch
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

    /// Real tools tab, dock and NavigationStack, with local DEBUG-only sample photos.
    /// No network AI call or wallpaper apply/respring is performed by this test.
    func testWallpaperMakerLayout() {
        continueAfterFailure = false
        for lang in ["ar", "en"] {
            for largeText in [false, true] {
                let extra = ["-MirsaWallpaperFixture", "-MirsaWallpaperAIFixture"] +
                    (largeText ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] : [])
                let app = launch("tools", lang: lang, extra: extra)
                XCTAssertTrue(tap(app, ["Tendies"]))
                let prefix = "\(lang)_tendies_\(largeText ? "large" : "standard")"
                shot(app, prefix + "_top")
                let field = app.descendants(matching: .any).matching(identifier: "wallpaper-description").firstMatch
                revealWallpaperElement(field, identifier: "wallpaper-description", in: app)
                XCTAssertTrue(field.isHittable)
                XCTAssertGreaterThan(field.frame.height, 65, "Multiline text needs intrinsic height")
                shot(app, prefix + "_multiline")
                if !largeText {
                    field.tap()
                    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
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
                    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "mirsa-tab-dock").firstMatch.waitForExistence(timeout: 5))
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
                app.terminate()
            }
        }
    }

    /// Original video wallpaper block sits at the TOP of the same tab, Tendies maker below it.
    func testVideoWallpaperTopThenTendiesBelow() {
        continueAfterFailure = false
        for lang in ["ar", "en"] {
            let app = launch("tools", lang: lang, extra: ["-MirsaWallpaperFixture", "-MirsaWallpaperAIFixture"])
            XCTAssertTrue(tap(app, ["Tendies"]))
            let video = app.descendants(matching: .any).matching(identifier: "video-wallpaper-from-photos").firstMatch
            XCTAssertTrue(video.waitForExistence(timeout: 10))
            XCTAssertTrue(video.isHittable, "Original video wallpaper must be visible before scrolling")
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
            revealWallpaperElement(video, identifier: "video-wallpaper-from-photos", in: app)
            XCTAssertTrue(video.isHittable)
            shot(app, "\(lang)_videowallpaper_top")
            app.terminate()
        }
    }

    private func wallpaperVisibleBottom(in app: XCUIApplication) -> CGFloat {
        let dock = app.descendants(matching: .any).matching(identifier: "mirsa-tab-dock").firstMatch
        // Assert against the actual obstruction, not a guessed 110pt inset that
        // incorrectly rejects a fully visible footer on the compact simulator.
        return dock.exists ? dock.frame.minY - 8 : app.frame.maxY - 8
    }

    private func revealWallpaperElement(_ element: XCUIElement, identifier: String, in app: XCUIApplication) {
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
            let error = frame.map { $0.midY - center } ?? 80
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
