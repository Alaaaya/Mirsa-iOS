import XCTest
import UIKit

/// REAL ContentView, real background->foreground, real pixels. Fails on near-black edge bands or a collapsed screen.
final class MirsaSourcesEdgeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private func launch(theme: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", "sources-real",
                               "-mirsa.sourceTheme", theme, "-mirsa.appLanguage", "en",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        Thread.sleep(forTimeInterval: 3)
        return app
    }

    /// Fraction of near-black pixels (max channel < 6; the app base #090A1E is not black) in a horizontal strip.
    private func blackFraction(_ img: UIImage, fromY: CGFloat, toY: CGFloat) -> Double {
        guard let cg = img.cgImage else { return 1 }
        let w = cg.width, h = cg.height
        let y0 = max(0, Int(fromY * CGFloat(h))), y1 = min(h, Int(toY * CGFloat(h)))
        guard let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data), y1 > y0 else { return 1 }
        let bpp = cg.bitsPerPixel / 8, bpr = cg.bytesPerRow
        var black = 0, total = 0
        for y in y0..<y1 { for x in stride(from: 0, to: w, by: 4) {
            let o = y * bpr + x * bpp
            if max(ptr[o], ptr[o + 1], ptr[o + 2]) < 6 { black += 1 }
            total += 1
        } }
        return total == 0 ? 1 : Double(black) / Double(total)
    }

    private func check(_ app: XCUIApplication, _ name: String, theme: String) {
        let shot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: shot); a.name = "\(theme)_\(name)"; a.lifetime = .keepAlways; add(a)
        let top = blackFraction(shot.image, fromY: 0, toY: 0.06)
        let bottom = blackFraction(shot.image, fromY: 0.94, toY: 1)
        XCTAssertLessThan(top, 0.5, "\(theme) \(name): black top band \(top)")
        XCTAssertLessThan(bottom, 0.5, "\(theme) \(name): black bottom band \(bottom)")
        XCTAssertTrue(app.staticTexts["Small Source"].exists || app.staticTexts["Small 1"].exists || app.staticTexts["Large Source"].exists,
                      "\(theme) \(name): Sources content not visible")
    }

    func testSourcesListAndDetailSurviveForeground() {
        for theme in ["aurora", "light"] {
            let app = launch(theme: theme)
            XCTAssertTrue(app.staticTexts["Small Source"].waitForExistence(timeout: 10), "list fixture missing")
            check(app, "list-initial", theme: theme)
            for i in 1...2 {
                XCUIDevice.shared.press(.home); Thread.sleep(forTimeInterval: 3)
                app.activate(); Thread.sleep(forTimeInterval: 2)
                check(app, "list-after-fg-\(i)", theme: theme)
            }
            app.staticTexts["Small Source"].firstMatch.tap()
            if app.staticTexts["Small 1"].waitForExistence(timeout: 8) {
                check(app, "detail-initial", theme: theme)
                XCUIDevice.shared.press(.home); Thread.sleep(forTimeInterval: 3)
                app.activate(); Thread.sleep(forTimeInterval: 2)
                check(app, "detail-after-fg", theme: theme)
            } else { XCTFail("\(theme): detail did not open or fixture apps missing") }
            app.terminate()
        }
    }
}
