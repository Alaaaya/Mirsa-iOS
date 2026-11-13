import Foundation
import XCTest
@testable import Mirsa

@MainActor
final class SourceCatalogTests: XCTestCase {
    private let appTesters = "https://repository.apptesters.org"
    private let ryp0 = "https://raw.githubusercontent.com/Sami-Wali/ryP0-repository/main/repo.json"
    private let simple = Data(#"{"apps":[{"name":"Sample","bundleIdentifier":"test.sample","version":"1.0","downloadURL":"https://example.org/sample.ipa"}]}"#.utf8)

    private func fixture(_ name: String) throws -> Data {
        guard let path = ProcessInfo.processInfo.environment["MIRSA_SOURCE_FIXTURES"] else {
            throw XCTSkip("Full feed fixtures run in scripts/appstore/package-tests.sh")
        }
        return try Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent(name + ".json"))
    }
    private func response(_ url: URL, status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
    private func makeStore(load: @escaping SourcesStore.Loader) -> SourcesStore {
        let name = "SourceCatalogTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return SourcesStore(defaults: defaults, load: load)
    }

    func testFullAppTestersJSONCountSearchAndInstallURLs() async throws {
        let data = try fixture("apptesters")
        XCTAssertEqual(data.count, 10_392_165)
        let store = makeStore { request in (data, self.response(request.url!)) }
        await store.ensureLoaded(appTesters)
        XCTAssertEqual(store.apps[appTesters]?.count, 10_098)
        XCTAssertEqual(store.listing(for: appTesters).count, 10_098)
        let found = try XCTUnwrap(store.listing(for: appTesters, query: " Sketchar ").first)
        XCTAssertEqual(found.bundleID, "tech.sketchar.ios")
        XCTAssertEqual(found.downloadURL.scheme, "https")
        XCTAssertTrue(found.downloadURL.absoluteString.contains("/releases/download/"))
        XCTAssertFalse(store.listing(for: appTesters, query: "HeyJapan").isEmpty, "tail of full JSON is searchable")
        XCTAssertEqual(store.sources.first { $0.url == appTesters }?.appCount, 10_098)
        XCTAssertNil(store.loadErrors[appTesters])
    }

    func testFullRyP0JSONCountSearchAndInstallURLs() async throws {
        let data = try fixture("ryp0")
        XCTAssertEqual(data.count, 2_366_545)
        let store = makeStore { request in (data, self.response(request.url!)) }
        await store.ensureLoaded(ryp0)
        XCTAssertEqual(store.apps[ryp0]?.count, 163)
        XCTAssertEqual(store.listing(for: ryp0).count, 163)
        let first = try XCTUnwrap(store.listing(for: ryp0, query: "wqfiles").first)
        XCTAssertEqual(first.bundleID, "cz.kolbi.wqfiles")
        XCTAssertEqual(first.downloadURL.scheme, "https")
        XCTAssertFalse(store.listing(for: ryp0, query: "Video Star").isEmpty, "tail of full JSON is searchable")
        XCTAssertEqual(store.sources.first { $0.url == ryp0 }?.appCount, 163)
    }

    func testPersistedCountsReloadButMemoryDoesNotAndDetailLoadsSelectedURL() async throws {
        let data = simple
        var requests = [String]()
        let store = makeStore { request in requests.append(request.url!.absoluteString); return (data, self.response(request.url!)) }
        var saved = store.sources
        for index in saved.indices { saved[index].appCount = saved[index].url == self.ryp0 ? 163 : 10_098 }
        store.sources = saved
        XCTAssertTrue(store.apps.isEmpty)
        XCTAssertEqual(store.sources.first { $0.url == ryp0 }?.appCount, 163)
        await store.ensureLoaded(ryp0)
        XCTAssertEqual(requests, [ryp0])
        XCTAssertEqual(store.listing(for: ryp0).count, 1)
        await store.ensureLoaded(ryp0)
        XCTAssertEqual(requests.count, 1, "re-entry does not redownload a loaded source")
    }

    func testPartialGlobalCacheDoesNotSkipOtherSources() async throws {
        let data = simple
        var requests = [String]()
        let store = makeStore { request in requests.append(request.url!.absoluteString); return (data, self.response(request.url!)) }
        store.sources = store.sources.filter { [appTesters, ryp0].contains($0.url) }
        store.apps[appTesters] = []
        XCTAssertFalse(store.apps.isEmpty, "old whole-cache gate incorrectly skipped ryP0 here")
        await store.loadMissing()
        XCTAssertEqual(requests, [ryp0])
        XCTAssertEqual(store.listing(for: ryp0).count, 1)
    }

    func testNavigationCancellationDoesNotCancelSourceOwnedLoadAndDetailJoinsIt() async throws {
        let data = simple
        var release: CheckedContinuation<Void, Never>?
        var began: CheckedContinuation<Void, Never>?
        var calls = 0
        let store = makeStore { request in
            calls += 1
            began?.resume(); began = nil
            await withCheckedContinuation { release = $0 }
            try Task.checkCancellation()
            return (data, self.response(request.url!))
        }
        var parent: Task<Bool, Never>!
        await withCheckedContinuation { continuation in
            began = continuation
            parent = Task { await store.refresh(ryp0) }
        }
        XCTAssertTrue(store.loading.contains(ryp0))
        parent.cancel() // equivalent to SwiftUI cancelling the departing list screen's .task
        let detail = Task { await store.ensureLoaded(ryp0) }
        release?.resume(); release = nil
        let succeeded = await parent.value
        await detail.value
        XCTAssertTrue(succeeded)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.listing(for: ryp0).count, 1)
        XCTAssertFalse(store.loading.contains(ryp0))
    }

    func testFailureIsPerSourceNotFalseEmptyAndRetrySucceeds() async throws {
        let data = simple
        var fail = true
        let store = makeStore { request in
            if fail { throw URLError(.notConnectedToInternet) }
            return (data, self.response(request.url!))
        }
        await store.ensureLoaded(ryp0)
        XCTAssertNil(store.apps[ryp0], "failed is distinct from successfully loaded empty")
        XCTAssertNotNil(store.loadErrors[ryp0])
        XCTAssertNil(store.loadErrors[appTesters])
        XCTAssertFalse(store.loading.contains(ryp0))
        fail = false
        await store.ensureLoaded(ryp0)
        XCTAssertNil(store.loadErrors[ryp0])
        XCTAssertEqual(store.listing(for: ryp0).count, 1)
    }

    func testHTTPErrorThenRetryAndRefreshPreservesPreviouslyLoadedRows() async throws {
        let data = simple
        var status = 200
        let store = makeStore { request in (data, self.response(request.url!, status: status)) }
        await store.ensureLoaded(ryp0)
        status = 503
        let failed = await store.refresh(ryp0)
        XCTAssertFalse(failed)
        XCTAssertEqual(store.listing(for: ryp0).count, 1)
        XCTAssertNotNil(store.loadErrors[ryp0])
        status = 200
        let succeeded = await store.refresh(ryp0)
        XCTAssertTrue(succeeded)
        XCTAssertNil(store.loadErrors[ryp0])
    }

    func testLoadedEmptyDoesNotReloadOrPretendFailure() async throws {
        var calls = 0
        let store = makeStore { request in calls += 1; return (Data(#"{"apps":[]}"#.utf8), self.response(request.url!)) }
        await store.ensureLoaded(ryp0)
        await store.ensureLoaded(ryp0)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.apps[ryp0]?.count, 0)
        XCTAssertNil(store.loadErrors[ryp0])
    }

    func testDeletingLoadingSourceDoesNotResurrectItsRowsOrCache() async throws {
        let data = simple
        var release: CheckedContinuation<Void, Never>?
        var began: CheckedContinuation<Void, Never>?
        let store = makeStore { request in
            began?.resume(); began = nil
            await withCheckedContinuation { release = $0 }
            return (data, self.response(request.url!))
        }
        let id = try XCTUnwrap(store.sources.first { $0.url == ryp0 }?.id)
        var pending: Task<Bool, Never>!
        await withCheckedContinuation { continuation in
            began = continuation
            pending = Task { await store.refresh(ryp0) }
        }
        XCTAssertTrue(store.remove(id: id))
        release?.resume(); release = nil
        let result = await pending.value
        XCTAssertFalse(result)
        XCTAssertNil(store.apps[ryp0])
        XCTAssertNil(store.loadErrors[ryp0])
        XCTAssertFalse(store.sources.contains { $0.id == id })
    }

    func testDuplicatesMalformedRowsAndUnsafeURLsDoNotBlankValidApps() async throws {
        let raw = #"{"apps":[null,7,{"name":"Missing"},{"name":"Unsafe","downloadURL":"file:///tmp/a.ipa"},{"name":"Creds","downloadURL":"https://user:pass@example.org/a.ipa"},{"name":"Valid","bundleIdentifier":"test.valid","version":"1","downloadURL":"relative.ipa"},{"name":"Duplicate","bundleIdentifier":"test.valid","version":"1","downloadURL":"relative.ipa"}]}"#
        let decoded = try SourcesStore.decodeSource(Data(raw.utf8), base: URL(string: "https://example.org/repo/source.json")!)
        XCTAssertEqual(decoded.apps.count, 1)
        XCTAssertEqual(decoded.apps.first?.name, "Valid")
        XCTAssertEqual(decoded.apps.first?.downloadURL.absoluteString, "https://example.org/repo/relative.ipa")
    }

    func testMalformedJSONIsErrorNotEmptyAndBareArrayStillWorks() async throws {
        let base = URL(string: "https://example.org/source.json")!
        XCTAssertThrowsError(try SourcesStore.decodeSource(Data("not JSON".utf8), base: base))
        let array = Data(#"[{"name":"Array app","downloadURL":"https://example.org/a.ipa"}]"#.utf8)
        XCTAssertEqual(try SourcesStore.decodeSource(array, base: base).apps.count, 1)
    }

    func testSameURLDuplicatesShareOneRefreshAndBothBadgesUpdate() async throws {
        let data = simple
        var calls = 0
        let store = makeStore { request in calls += 1; return (data, self.response(request.url!)) }
        store.sources = [RepoSource(url: ryp0, name: "A"), RepoSource(url: ryp0, name: "B")]
        await store.refreshAll()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.sources.map(\.appCount), [1, 1])
        XCTAssertTrue(store.remove(id: store.sources[0].id))
        XCTAssertEqual(store.listing(for: ryp0).count, 1)
    }
}
