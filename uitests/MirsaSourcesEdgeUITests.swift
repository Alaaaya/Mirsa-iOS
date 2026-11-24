import XCTest
import UIKit

/// REAL ContentView on the simulator with REAL animations (no -MirsaUITestHarness; -MirsaLiveStyle only picks the page).
/// Real background->foreground, normalized-RGBA pixel sampling. Fails on near-black edge bands or collapsed content.
final class MirsaSourcesEdgeUITests: XCTestCase {
    // Mirrors SourcesTheme.allCases.
    private static let themes = ["aurora", "sunset", "ocean", "light"]
    private static var langs: [String] { MirsaUILanguages.selected(["en", "ar"]) }
    override func setUpWithError() throws { continueAfterFailure = true }

    private func launch(theme: String, lang: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaLiveStyle", "-MirsaStylePage", "sources-real",
                               "-mirsa.sourceTheme", theme, "-mirsa.appLanguage", lang,
                               "-AppleLanguages", "(\(lang))", "-AppleLocale", lang]
        app.launch()
        Thread.sleep(forTimeInterval: 3)
        return app
    }

    /// Redraws into a known RGBA8 sRGB context, so channel order/bpp/alpha never depend on the screenshot's native format.
    private func rgba(_ img: UIImage) -> (px: [UInt8], w: Int, h: Int)? {
        guard let cg = img.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (buf, w, h)
    }

    /// Fraction of near-black pixels (max channel < 6; base #090A1E is not black), full-width strip.
    private func blackFraction(_ b: (px: [UInt8], w: Int, h: Int), fromY: Double, toY: Double) -> Double {
        let y0 = Int(fromY * Double(b.h)), y1 = min(b.h, Int(toY * Double(b.h)))
        guard y1 > y0 else { return 1 }
        var black = 0, total = 0
        for y in y0..<y1 { for x in stride(from: 0, to: b.w, by: 3) {
            let o = (y * b.w + x) * 4
            if max(b.px[o], b.px[o + 1], b.px[o + 2]) < 6 { black += 1 }
            total += 1
        } }
        return Double(black) / Double(total)
    }

    private func check(_ app: XCUIApplication, _ name: String, _ tag: String) {
        let shot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: shot); a.name = "\(tag)_\(name)"; a.lifetime = .keepAlways; add(a)
        guard let b = rgba(shot.image) else { XCTFail("\(tag) \(name): cannot decode screenshot"); return }
        let top = blackFraction(b, fromY: 0, toY: 0.06), bottom = blackFraction(b, fromY: 0.94, toY: 1)
        let mid = blackFraction(b, fromY: 0.3, toY: 0.7)
        // Record every number so the BEFORE/AFTER baseline can be compared from the log.
        print("PIXELS \(tag) \(name) top=\(top) bottom=\(bottom) mid=\(mid)")
        XCTAssertLessThan(top, 0.5, "\(tag) \(name): black top band \(top)")
        XCTAssertLessThan(bottom, 0.5, "\(tag) \(name): black bottom band \(bottom)")
        XCTAssertLessThan(mid, 0.9, "\(tag) \(name): screen collapsed to black \(mid)")
    }

    private func foreground(_ app: XCUIApplication) {
        XCUIDevice.shared.press(.home); Thread.sleep(forTimeInterval: 3)
        app.activate(); Thread.sleep(forTimeInterval: 2)
    }

    func testSourcesListAndDetailSurviveForeground() {
        for lang in Self.langs { for theme in Self.themes {
            let tag = "\(theme)-\(lang)"
            let app = launch(theme: theme, lang: lang)
            let row = app.staticTexts["Small Source"]
            guard row.waitForExistence(timeout: 10) else { XCTFail("\(tag): list fixture missing"); app.terminate(); continue }
            check(app, "list-initial", tag)
            for i in 1...2 { foreground(app); check(app, "list-after-fg-\(i)", tag); XCTAssertTrue(row.exists, "\(tag): list content gone after fg \(i)") }
            row.firstMatch.tap()
            if app.staticTexts["Small 1"].waitForExistence(timeout: 8) {
                check(app, "detail-initial", tag)
                foreground(app); check(app, "detail-after-fg", tag)
                XCTAssertTrue(app.staticTexts["Small 1"].exists, "\(tag): detail content gone after fg")
            } else { XCTFail("\(tag): detail did not open") }
            app.terminate()
        } }
    }
}
