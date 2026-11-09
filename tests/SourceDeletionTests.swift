import XCTest
@testable import Mirsa

@MainActor
final class SourceDeletionTests: XCTestCase {
    private var suite = "SourceDeletionTests"
    private var defaults: UserDefaults!
    override func setUp() {
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() { UserDefaults().removePersistentDomain(forName: suite) }
    private func makeStore() -> SourcesStore { SourcesStore(defaults: defaults) }

    func testCanonicalProtectedAndFixedIdentity() {
        let store = makeStore()
        let canon = store.sources.first { $0.isCanonical }
        XCTAssertNotNil(canon)
        XCTAssertEqual(canon?.uid, RepoSource.canonicalID)
        XCTAssertTrue(store.isProtected(canon!))
        XCTAssertFalse(store.remove(id: canon!.id))
        XCTAssertTrue(store.sources.contains { $0.isCanonical })
    }

    func testExactSameURLAndNameDuplicateDeletedIndividuallySiblingKept() {
        let store = makeStore()
        let a = RepoSource(url: "https://dup.example/s.json", name: "Dup")
        let b = RepoSource(url: "https://dup.example/s.json", name: "Dup")
        store.sources += [a, b]
        store.apps[a.url] = []
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertTrue(store.remove(id: a.id))
        XCTAssertFalse(store.sources.contains { $0.id == a.id })
        XCTAssertTrue(store.sources.contains { $0.id == b.id })
        XCTAssertNotNil(store.apps[b.url], "shared URL cache must survive while a sibling remains")
        XCTAssertTrue(store.remove(id: b.id))
        XCTAssertNil(store.apps[b.url])
    }

    func testDuplicateOfCanonicalURLIsDeletableCanonicalStays() {
        let store = makeStore()
        let dup = RepoSource(url: MirsaSourceFeed.primary, name: "Mirsa")
        store.sources.append(dup)
        XCTAssertTrue(store.remove(id: dup.id))
        XCTAssertEqual(store.sources.filter { $0.isCanonical }.count, 1)
    }

    func testPersistenceAcrossReload() {
        let store = makeStore()
        let a = RepoSource(url: "https://p.example/s.json", name: "P")
        let b = RepoSource(url: "https://p.example/s.json", name: "P")
        store.sources += [a, b]
        store.remove(id: a.id)
        let reloaded = makeStore()
        XCTAssertFalse(reloaded.sources.contains { $0.id == a.id })
        XCTAssertTrue(reloaded.sources.contains { $0.id == b.id })
        XCTAssertEqual(reloaded.sources.first { $0.isCanonical }?.uid, RepoSource.canonicalID)
    }

    func testCancelKeepsAndConfirmDeletes() {
        let store = makeStore()
        let a = RepoSource(url: "https://c.example/s.json", name: "C")
        store.sources.append(a)
        store.requestDelete(id: a.id)
        XCTAssertEqual(store.pendingDelete?.id, a.id)
        XCTAssertTrue(store.sources.contains { $0.id == a.id }, "nothing removed before confirmation")
        store.cancelDelete()
        XCTAssertNil(store.pendingDelete)
        XCTAssertTrue(store.sources.contains { $0.id == a.id })
        store.requestDelete(id: a.id)
        XCTAssertTrue(store.confirmDelete())
        XCTAssertFalse(store.sources.contains { $0.id == a.id })
        store.requestDelete(id: RepoSource.canonicalID)
        XCTAssertNil(store.pendingDelete, "canonical never offered for deletion")
    }

    func testMigrateKeepsUserDuplicatesAndIdsStable() {
        let a = RepoSource(url: "https://m.example/s.json", name: "M")
        let b = RepoSource(url: "https://m.example/s.json", name: "M")
        let once = MirsaSourceFeed.migrate([a, b])
        XCTAssertEqual(once.count, 2)
        XCTAssertEqual(MirsaSourceFeed.migrate(once).map(\.id), once.map(\.id))
    }

    func testBackwardMigrationOldSaveWithoutUID() throws {
        let old = #"[{"url":"https://mirsa-source.mooo.com/source.json","name":"Mirsa","appCount":0},{"url":"https://x.example/s.json","name":"X","appCount":0},{"url":"https://x.example/s.json","name":"X","appCount":0}]"#
        let decoded = try JSONDecoder().decode([RepoSource].self, from: Data(old.utf8))
        let out = MirsaSourceFeed.migrate(decoded)
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out[0].uid, RepoSource.canonicalID)
        XCTAssertEqual(Set(out.map { $0.id }).count, 3)
    }

    func testReorderDuplicateBeforeCanonicalKeepsIdentityAfterReload() {
        let store = makeStore()
        let dup = RepoSource(url: MirsaSourceFeed.primary, name: "Mirsa")
        store.sources.insert(dup, at: 0)
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.sources.filter { $0.isCanonical }.count, 1)
        XCTAssertEqual(reloaded.sources.map(\.id), store.sources.map(\.id))
        XCTAssertFalse(reloaded.sources.first { $0.id == dup.id }!.isCanonical)
        XCTAssertTrue(reloaded.sources.contains { $0.id == dup.id })
    }

    func testCorruptDuplicateUIDsBecomeUnique() {
        var a = RepoSource(url: "https://u.example/a.json", name: "A", uid: "same")
        var b = RepoSource(url: "https://u.example/b.json", name: "B", uid: "same")
        a.appCount = 1; b.appCount = 2
        let out = MirsaSourceFeed.migrate([a, b])
        XCTAssertEqual(Set(out.map(\.id)).count, 2)
    }

    func testHiddenIDsAreIndependentForDuplicates() {
        let store = makeStore()
        let a = RepoSource(url: "https://h.example/s.json", name: "H")
        let b = RepoSource(url: "https://h.example/s.json", name: "H")
        store.sources += [a, b]
        store.hiddenIDs.insert(a.id)
        XCTAssertFalse(store.visibleSources.contains { $0.id == a.id })
        XCTAssertTrue(store.visibleSources.contains { $0.id == b.id })
        XCTAssertEqual(makeStore().hiddenIDs, [a.id])
    }
}
