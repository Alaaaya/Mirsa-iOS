import XCTest
@testable import Mirsa

@MainActor
final class SourceDeletionTests: XCTestCase {
    func testPrimaryIsProtected() {
        XCTAssertTrue(SourcesStore.isProtected(MirsaSourceFeed.primary))
        XCTAssertTrue(SourcesStore.isProtected(MirsaSourceFeed.primary.uppercased() + "/"))
        XCTAssertFalse(SourcesStore.isProtected("https://example.com/a.json"))
    }
    func testRemoveDuplicateOnlyAndPersist() {
        let store = SourcesStore()
        let a = "https://dup-test.example/a.json", b = "https://dup-test.example/b.json"
        store.sources.append(RepoSource(url: a, name: "Dup"))
        store.sources.append(RepoSource(url: b, name: "Dup"))
        XCTAssertFalse(store.remove(MirsaSourceFeed.primary))
        XCTAssertTrue(store.sources.contains { $0.url == MirsaSourceFeed.primary })
        XCTAssertTrue(store.remove(a))
        XCTAssertFalse(store.sources.contains { $0.url == a })
        XCTAssertTrue(store.sources.contains { $0.url == b })
        let reloaded = SourcesStore()
        XCTAssertFalse(reloaded.sources.contains { $0.url == a })
        XCTAssertTrue(reloaded.sources.contains { $0.url == b })
        XCTAssertTrue(store.remove(b))
    }
    func testCancelKeepsSource() {
        let store = SourcesStore()
        let u = "https://cancel-test.example/a.json"
        store.sources.append(RepoSource(url: u, name: "C"))
        // cancel = no remove call
        XCTAssertTrue(store.sources.contains { $0.url == u })
        store.remove(u)
    }
}
