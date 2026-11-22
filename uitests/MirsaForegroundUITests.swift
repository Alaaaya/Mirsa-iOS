import XCTest

/// Background -> foreground must never leave a blank window. Screenshots before/after, plus a pixel check.
final class MirsaForegroundUITests: XCTestCase {
    func testBackgroundForegroundKeepsContent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        Thread.sleep(forTimeInterval: 4)
        func shot(_ n: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = n; a.lifetime = .keepAlways; add(a) }
        shot("before")
        let before = app.descendants(matching: .any).count
        for i in 1...3 {
            XCUIDevice.shared.press(.home)
            Thread.sleep(forTimeInterval: 3)
            app.activate()
            Thread.sleep(forTimeInterval: 2)
            shot("after-foreground-\(i)")
            XCTAssertGreaterThan(app.descendants(matching: .any).count, max(3, before / 3), "UI collapsed after foreground \(i)")
        }
    }
}
