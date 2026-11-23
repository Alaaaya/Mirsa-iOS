import XCTest
@testable import Mirsa

final class CAPlaygroundSourceTests: XCTestCase {
    func testSyntheticAdapterPreservesCreatorAndOrigin() throws {
        let data = Data(#"{"base_url":"https://attacker.example/","wallpapers":[{"id":1,"name":"Owned fixture","creator":"Fixture artist","file":"wallpapers/Owned.tendies","preview":"previews/gif/Owned.gif"}]}"#.utf8)
        let feed = try CAPlaygroundSource.decode(data)
        let item = try XCTUnwrap(feed.wallpapers.first)
        XCTAssertEqual(item.author, "Fixture artist")
        XCTAssertEqual(item.url.host, "raw.githubusercontent.com")
        XCTAssertEqual(item.url.path, "/CAPlayground/wallpapers/main/wallpapers/Owned.tendies")
        XCTAssertEqual(item.sizeIsEstimated, true)
        XCTAssertEqual(item.size, 32 * 1_048_576)
    }
    func testRejectsEscapesAndExternalURLs() {
        for path in ["https://evil.example/a.tendies", "wallpapers/../a.tendies",
                     "wallpapers/%2e%2e/a.tendies", "wallpapers/a.tendies?x=1",
                     "wallpapers//a.tendies", "wallpapers/a.ipa"] {
            XCTAssertThrowsError(try CAPlaygroundSource.asset(path, prefix: "wallpapers/", extension: "tendies"))
        }
    }
    @MainActor func testNotEnabledByDefault() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = WallpaperSourceStore(defaults: defaults)
        XCTAssertFalse(store.urls.contains(CAPlaygroundSource.manifest))
    }
    func testMalformedAndOversized() {
        XCTAssertThrowsError(try CAPlaygroundSource.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try CAPlaygroundSource.decode(Data(repeating: 0, count: 2_097_153)))
    }
}
