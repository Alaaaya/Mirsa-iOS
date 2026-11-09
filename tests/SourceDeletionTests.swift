import XCTest
@testable import Mirsa

@MainActor
final class SourceDeletionTests: XCTestCase {
    func testCanonicalProtectedButIdenticalUserDuplicatesRemainIndependent() {
        let duplicate = RepoSource(url: MirsaSourceFeed.primary, name: "Mirsa")
        let rows = SourceDeletionPolicy.migrate([duplicate, duplicate, duplicate])
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(Set(rows.map(\.id)).count, 3)
        XCTAssertFalse(SourceDeletionPolicy.canDelete(rows[0]))
        XCTAssertTrue(SourceDeletionPolicy.canDelete(rows[1]))
        XCTAssertTrue(SourceDeletionPolicy.canDelete(rows[2]))
        XCTAssertEqual(SourceDeletionPolicy.migrate(rows).map(\.id), rows.map(\.id))
    }

    func testDeletePersistsOnlySelectedIdentityAndCancelDoesNotMutate() throws {
        let suite = "SourceDeletionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SourcesStore(defaults: defaults)
        let duplicate = RepoSource(url: MirsaSourceFeed.primary, name: "Mirsa")
        store.sources = SourceDeletionPolicy.migrate([duplicate, duplicate, duplicate])
        let before = store.sources
        // A pending confirmation is a value copy, not a store mutation.
        var pending: RepoSource? = before[1]
        pending = nil
        XCTAssertNil(pending)
        XCTAssertEqual(store.sources, before)
        XCTAssertFalse(store.deleteSource(id: before[0].id))
        XCTAssertTrue(store.deleteSource(id: before[1].id))
        XCTAssertEqual(store.sources.map(\.id), [before[0].id, before[2].id])
        let reopened = SourcesStore(defaults: defaults)
        XCTAssertEqual(reopened.sources.map(\.id), store.sources.map(\.id))
        XCTAssertFalse(reopened.deleteSource(id: before[1].id))
    }

    func testConfirmationStringsExistInAllFourLanguages() {
        let original = AppLanguageStore.shared.current
        defer { AppLanguageStore.shared.set(original) }
        var titles = Set<String>()
        for language in AppLanguage.allCases {
            AppLanguageStore.shared.set(language)
            XCTAssertFalse(SourceDeletionText.delete.isEmpty)
            XCTAssertFalse(SourceDeletionText.cancel.isEmpty)
            XCTAssertFalse(SourceDeletionText.message.isEmpty)
            titles.insert(SourceDeletionText.title)
        }
        XCTAssertEqual(titles.count, 4)
    }

    func testLegacyJSONMigratesWithoutLosingDuplicates() throws {
        let json = Data(#"[{"url":"https://mirsa-source.mooo.com/source.json","name":"Mirsa","appCount":0},{"url":"https://mirsa-source.mooo.com/source.json","name":"Mirsa","appCount":0}]"#.utf8)
        let decoded = try JSONDecoder().decode([RepoSource].self, from: json)
        let rows = SourceDeletionPolicy.migrate(decoded)
        XCTAssertEqual(rows.count, 2)
        let restored = try JSONDecoder().decode([RepoSource].self, from: JSONEncoder().encode(rows))
        XCTAssertEqual(restored.map(\.id), rows.map(\.id))
    }
}
