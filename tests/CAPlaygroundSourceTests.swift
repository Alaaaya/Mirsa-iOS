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
    func testMixedNumericAndZeroPrefixedStringIDsMatchLiveSchema() throws {
        let data = Data(#"{"wallpapers":[{"id":42,"name":"Numeric","file":"wallpapers/Numeric.tendies","preview":"previews/gif/Numeric.gif"},{"id":"0000001","name":"Textual","creator":"Original artist","file":"wallpapers/Textual.tendies","preview":"previews/gif/Textual.gif"}]}"#.utf8)
        let feed = try CAPlaygroundSource.decode(data)
        XCTAssertEqual(feed.wallpapers.map(\.id), ["42", "0000001"])
        XCTAssertEqual(feed.wallpapers[1].author, "Original artist")
    }
    func testPlaceholderCategoryHiddenWithoutDeletingItsDataModel() {
        XCTAssertFalse(ToolsStoreCategory.visibleCases.contains(.tweaks))
        XCTAssertFalse(ToolsStoreCategory.visibleCases.contains(.sounds))
        XCTAssertTrue(ToolsStoreCategory.allCases.contains(.sounds))
        XCTAssertTrue(ToolsStoreCategory.allCases.contains(.tweaks))
        XCTAssertEqual(ToolsStoreCategory.visibleCases, [.wallpapers, .appTweaks, .fonts])
        XCTAssertTrue(ToolsStoreCategory.tweaks.allowedExtensions.contains("dylib"))
        XCTAssertEqual(ToolsStoreCategory.fonts.allowedExtensions, ["dylib"])
        XCTAssertTrue(ToolsStoreCategory.fonts.isTweak)
    }
    private func fontItem(_ id: String, extension ext: String) throws -> ToolsStoreItem {
        let object: [String: Any] = ["id": id, "category": "fonts", "title": id, "file_name": id + "." + ext,
                                      "downloads": 0, "rating_avg": 0, "rating_count": 0]
        return try JSONDecoder().decode(ToolsStoreItem.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testFontPaginationSkipsFullLegacyPagesAndCollectsDylibsInOrder() async throws {
        var offsets: [Int] = []
        let legacy = try (0..<100).map { try fontItem("legacy-\($0)", extension: "ttf") }
        let first = try fontItem("font-first", extension: "DYLIB")
        let second = try fontItem("font-second", extension: "dylib")
        let result = try await ToolsStoreClient.fontItems(limit: 2, offset: 0) { size, offset in
            XCTAssertEqual(size, 100)
            offsets.append(offset)
            if offset == 0 { return legacy }
            if offset == 100 { return [first] + legacy.prefix(99) }
            return [first, second]
        }
        XCTAssertEqual(offsets, [0, 100, 200])
        XCTAssertEqual(result.map(\.id), ["font-first", "font-second"])
    }

    func testFontPaginationStopsAtServerOffsetCapAndEmptyPage() async throws {
        let legacy = try (0..<100).map { try fontItem("legacy-\($0)", extension: "otf") }
        var offsets: [Int] = []
        let capped = try await ToolsStoreClient.fontItems(limit: 1, offset: 10_000) { _, offset in
            offsets.append(offset)
            return legacy
        }
        XCTAssertTrue(capped.isEmpty)
        XCTAssertEqual(offsets, [10_000])
        offsets = []
        let empty = try await ToolsStoreClient.fontItems(limit: 60, offset: -1) { _, offset in
            offsets.append(offset)
            return []
        }
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(offsets, [0])
    }

    func testInvalidIDTypesRemainRejected() {
        for id in ["null", "true", "1.5", "{}", "[]"] {
            let json = "{\"wallpapers\":[{\"id\":\(id),\"name\":\"Invalid\",\"file\":\"wallpapers/A.tendies\",\"preview\":\"previews/gif/A.gif\"}]}"
            XCTAssertThrowsError(try CAPlaygroundSource.decode(Data(json.utf8)))
        }
    }
    func testRejectsEscapesAndExternalURLs() {
        for path in ["https://evil.example/a.tendies", "wallpapers/../a.tendies",
                     "wallpapers/%2e%2e/a.tendies", "wallpapers/a.tendies?x=1",
                     "wallpapers//a.tendies", "wallpapers/a.ipa"] {
            XCTAssertThrowsError(try CAPlaygroundSource.asset(path, prefix: "wallpapers/", extension: "tendies"))
        }
    }
    @MainActor func testEnabledByDefault() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WallpaperSourceStore(defaults: defaults)
        XCTAssertEqual(store.urls, [WallpaperSourceStore.official, CAPlaygroundSource.manifest])
    }
    func testMalformedAndOversized() {
        XCTAssertThrowsError(try CAPlaygroundSource.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try CAPlaygroundSource.decode(Data(repeating: 0, count: 2_097_153)))
    }
}
