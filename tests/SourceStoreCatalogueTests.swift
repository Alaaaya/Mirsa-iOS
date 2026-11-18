import XCTest
@testable import Mirsa

final class SourceStoreCatalogueTests: XCTestCase {
    private let base = URL(string: "https://catalogue.example/source.json")!

    func testRealCategoriesAndFeaturedDecodeWithoutFakeEntries() throws {
        let data = Data(#"{"featuredApps":["app.two"],"apps":[{"name":"One","bundleIdentifier":"app.one","downloadURL":"one.ipa","category":"Games"},{"name":"Two","bundleIdentifier":"app.two","downloadURL":"two.ipa","versions":[{"version":"2","date":"2026-11-18"}]}]}"#.utf8)
        let decoded = try SourcesStore.decodeSource(data, base: base)
        XCTAssertEqual(decoded.apps.count, 2)
        XCTAssertEqual(decoded.apps.first?.category, "Games")
        XCTAssertNil(decoded.apps.last?.category)
        XCTAssertEqual(decoded.featuredIDs, ["app.two"])
    }

    func testVisibleInputOnlyDedupesAndSortsActualDates() throws {
        let data = Data(#"{"apps":[{"name":"Old","bundleIdentifier":"app.old","downloadURL":"old.ipa","date":"2025-01-01"},{"name":"New","bundleIdentifier":"app.new","downloadURL":"new.ipa","date":"2026-11-18"}]}"#.utf8)
        let decoded = try SourcesStore.decodeSource(data, base: base)
        let first = RepoSource(url: base.absoluteString, name: "First", uid: "first")
        let duplicate = RepoSource(url: "https://duplicate.example", name: "Duplicate", uid: "duplicate")
        let entries = SourceStoreCatalogue.entries(sources: [first, duplicate], apps: [first.url: decoded.apps, duplicate.url: decoded.apps])
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map { $0.source.id }), ["first"])
        XCTAssertEqual(SourceStoreCatalogue.recent(entries).first?.app.name, "New")
        XCTAssertTrue(SourceStoreCatalogue.entries(sources: [], apps: [first.url: decoded.apps]).isEmpty)
    }

    func testStoreIsDefaultWithoutChangingExistingClassicPreference() {
        XCTAssertEqual(SourceStoreLayout.store, "store")
        let defaults = UserDefaults(suiteName: "sources-layout-test")!
        defaults.removePersistentDomain(forName: "sources-layout-test")
        XCTAssertEqual(defaults.string(forKey: SourceStoreLayout.key) ?? SourceStoreLayout.store, "store")
        defaults.set(SourceStoreLayout.classic, forKey: SourceStoreLayout.key)
        XCTAssertEqual(defaults.string(forKey: SourceStoreLayout.key), "classic")
        defaults.removePersistentDomain(forName: "sources-layout-test")
    }
}
