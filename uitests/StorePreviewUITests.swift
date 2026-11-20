import XCTest

/// Evidence only: the item is a local fixture carrying real Naruto package preview pixels.
final class StorePreviewUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ page: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MirsaUITestHarness", "-MirsaStylePage", page,
                               "-MirsaPreviewFixture", "/tmp/naruto-preview.jpg",
                               "-mirsa.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        Thread.sleep(forTimeInterval: 3.5)
        return app
    }
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func testPreviewCardAndDetail() {
        let card = launch("store-preview-card")
        XCTAssertTrue(card.buttons["tools-store-card-fixture-naruto"].waitForExistence(timeout: 8))
        shot("store-preview-card")
        card.terminate()
        let detail = launch("store-preview-detail")
        shot("store-preview-detail")
        detail.terminate()
    }
}
