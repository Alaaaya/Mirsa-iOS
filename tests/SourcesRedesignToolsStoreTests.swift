import Foundation
import XCTest
@testable import Mirsa

@MainActor
final class SourcesRedesignToolsStoreTests: XCTestCase {
    // MARK: Sources: new optional fields come only from the feed

    func testAltStoreVersionNotesMinOSAndCategoryAreParsed() throws {
        let feed = Data(#"{"apps":[{"name":"Sample","bundleIdentifier":"test.sample","category":"utilities","versions":[{"version":"2.0","date":"2026-11-19","localizedDescription":"Fixes","minOSVersion":"16.0","downloadURL":"https://example.org/s.ipa","size":1234}]}]}"#.utf8)
        let parsed = try SourcesStore.decodeSource(feed, base: URL(string: "https://example.org/source.json")!)
        let app = try XCTUnwrap(parsed.apps.first)
        XCTAssertEqual(app.versionNotes, "Fixes")
        XCTAssertEqual(app.minOSVersion, "16.0")
        XCTAssertEqual(app.category, "utilities")
        XCTAssertEqual(app.size, 1234)
    }

    func testMissingOptionalFieldsStayNil() throws {
        let feed = Data(#"{"apps":[{"name":"Bare","bundleIdentifier":"test.bare","version":"1.0","downloadURL":"https://example.org/b.ipa"}]}"#.utf8)
        let parsed = try SourcesStore.decodeSource(feed, base: URL(string: "https://example.org/source.json")!)
        let app = try XCTUnwrap(parsed.apps.first)
        XCTAssertNil(app.versionNotes)
        XCTAssertNil(app.minOSVersion)
        XCTAssertNil(app.category)
        XCTAssertNil(app.size)
    }

    func testCategoryChipsNeedTwoRealCategories() {
        func app(_ c: String?) -> RepoApp {
            RepoApp(name: "A", bundleID: UUID().uuidString, developer: "", subtitle: "", description: "", version: "1",
                    iconURL: nil, downloadURL: URL(string: "https://example.org/a.ipa")!, size: nil, date: nil, category: c)
        }
        XCTAssertEqual(SourceDetailView.categories([app(nil), app("games")]), [])
        XCTAssertEqual(SourceDetailView.categories([app("utilities"), app("games"), app(nil), app("games")]), ["games", "utilities"])
    }

    func testNewBadgeWindow() {
        let now = Date()
        XCTAssertTrue(SourcesDates.isRecent(now.addingTimeInterval(-3600), now: now))
        XCTAssertFalse(SourcesDates.isRecent(now.addingTimeInterval(-72 * 3600), now: now))
        XCTAssertFalse(SourcesDates.isRecent(nil, now: now))
    }

    func testThemeIsPersistedUnderItsKey() {
        XCTAssertEqual(SourcesTheme.key, "mirsa.sourceTheme")
        XCTAssertEqual(SourcesTheme.allCases.map(\.rawValue), ["aurora", "sunset", "ocean", "light"])
        for language in AppLanguage.allCases {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguageStore.key)
            for theme in SourcesTheme.allCases { XCTAssertFalse(theme.title.isEmpty) }
            XCTAssertFalse(ToolsStoreText.reviewBanner.isEmpty)
            XCTAssertTrue(ToolsStoreText.reviewBanner.contains("dylib"), language.rawValue)
        }
        UserDefaults.standard.removeObject(forKey: AppLanguageStore.key)
    }

    // MARK: Tools Store

    func testItemDecodingAndAllowedExtensions() throws {
        let json = Data(#"{"items":[{"id":"6f1c2a52-3a9e-4a7f-9b55-2a7d1f0c9e01","category":"wallpapers","title":"Night","file_name":"night.tendies","file_size":2048,"downloads":7,"rating_avg":4.5,"rating_count":2,"my_rating":null}]}"#.utf8)
        struct Page: Decodable { let items: [ToolsStoreItem] }
        let item = try XCTUnwrap(try JSONDecoder().decode(Page.self, from: json).items.first)
        XCTAssertEqual(item.kind, .wallpapers)
        XCTAssertEqual(item.fileExtension, "tendies")
        XCTAssertEqual(item.downloads, 7)
        XCTAssertEqual(item.ratingCount, 2)
        XCTAssertNil(item.myRating)
        XCTAssertTrue(ToolsStoreCategory.wallpapers.allowedExtensions.contains("tendies"))
        XCTAssertFalse(ToolsStoreCategory.tweaks.allowedExtensions.contains("ipa"))
        XCTAssertEqual(ToolsStoreCategory.allCases.map(\.rawValue), ["tweaks", "wallpapers", "app_tweaks", "sounds", "fonts"])
    }

    func testEndpointMustBeHTTPS() {
        XCTAssertNil(ToolsStoreConfig.validated(""))
        XCTAssertNil(ToolsStoreConfig.validated("http://example.org/fn"))
        XCTAssertNil(ToolsStoreConfig.validated("https://user:pw@example.org/fn"))
        XCTAssertNotNil(ToolsStoreConfig.validated("https://example.supabase.co/functions/v1/mirsa-tools-store"))
    }

    func testSafeFileName() {
        XCTAssertEqual(ToolsStoreClient.safeFileName("../evil.dylib", fallbackExtension: "dylib"), "evil.dylib")
        XCTAssertEqual(ToolsStoreClient.safeFileName("", fallbackExtension: "ttf"), "item.ttf")
    }

    func testSavedItemsPersistLocally() throws {
        let name = "ToolsStoreSaved." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let json = Data(#"{"id":"a","category":"fonts","title":"Font","file_name":"f.ttf","downloads":0,"rating_avg":0,"rating_count":0}"#.utf8)
        let item = try JSONDecoder().decode(ToolsStoreItem.self, from: json)
        let saved = ToolsStoreSaved(defaults: defaults)
        saved.toggle(item)
        XCTAssertTrue(ToolsStoreSaved(defaults: defaults).isSaved("a"))
        saved.toggle(item)
        XCTAssertFalse(ToolsStoreSaved(defaults: defaults).isSaved("a"))
    }
}
