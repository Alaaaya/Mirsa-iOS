import XCTest
import UIKit

final class MirsaKeyboardReturn22UITests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: shot)
        a.name = name; a.lifetime = .keepAlways; add(a)
        guard let cg = shot.image.cgImage else { XCTFail("Screenshot decode"); return }
        let w = cg.width, h = cg.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { XCTFail("Pixel context"); return }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var bright = 0, count = 0
        var bins = Set<Int>()
        for y in stride(from: h / 6, to: h * 4 / 5, by: 4) {
            for x in stride(from: w / 12, to: w * 11 / 12, by: 4) {
                let o = (y * w + x) * 4
                let r = Int(bytes[o]), g = Int(bytes[o + 1]), b = Int(bytes[o + 2])
                if max(r, g, b) > 90 { bright += 1 }
                bins.insert((r / 32) * 64 + (g / 32) * 8 + b / 32)
                count += 1
            }
        }
        print("KEYBOARD_PIXELS \(name) bright=\(Double(bright)/Double(count)) bins=\(bins.count)")
        XCTAssertGreaterThan(Double(bright)/Double(count), 0.005, "Opaque/empty body")
        XCTAssertGreaterThan(bins.count, 8, "Uniform body")
    }

    private func verify(_ requestedLanguage: String) throws {
        let lang = MirsaUILanguages.language(requestedLanguage)
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaLiveStyle", "-MirsaStylePage", "sources-real",
            "-mirsa.sourceTheme", "sunset", "-mirsa.appLanguage", lang,
            "-AppleLanguages", "(\(lang))", "-AppleLocale", lang]
        app.launch()
        let row = app.staticTexts["Small Source"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow", "عدم السماح"])).firstMatch
        if deny.waitForExistence(timeout: 2) { deny.tap() }
        let toggle = app.buttons["sources-search-toggle"]
        XCTAssertTrue(toggle.isHittable)
        capture(app, "keyboard-\(lang)-cold")
        toggle.tap()
        let field = app.textFields["sources-list-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Small")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        capture(app, "keyboard-\(lang)-visible")
        // Background once while keyboard is live, then again after dismissing.
        for i in 1...2 {
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            XCTAssertTrue(toggle.isHittable)
            capture(app, "keyboard-\(lang)-return-\(i)")
            if i == 1 { toggle.tap() }
        }
        XCTAssertTrue(row.isHittable)
        row.tap()
        let first = app.staticTexts["Small 1"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        capture(app, "keyboard-\(lang)-source-detail")
        first.tap()
        XCTAssertTrue(app.buttons["source-detail-install"].waitForExistence(timeout: 10))
        capture(app, "keyboard-\(lang)-app-detail")
        app.terminate()
    }
    func testEnglishKeyboardBackgroundReturn() throws { try verify("en") }
    func testArabicKeyboardBackgroundReturn() throws { try verify("ar") }
}
