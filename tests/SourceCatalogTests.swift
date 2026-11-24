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

    func testFullAlaaCataloguesDecodeOffMainAndPublishWithoutBlockingMainActor() async throws {
        for (name, url, bytes, count) in [
            ("alaa1", SourcesStore.alaaDefaults[0].url, 7_615_167, 10_380),
            ("alaa2", SourcesStore.alaaDefaults[1].url, 9_989_723, 9_728)
        ] {
            let data = try fixture(name)
            XCTAssertEqual(data.count, bytes)
            let store = makeStore { request in (data, self.response(request.url!)) }
            var beats = 0
            let heartbeat = Task { @MainActor in
                while !Task.isCancelled {
                    beats += 1
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
            }
            let start = Date()
            await store.ensureLoaded(url)
            heartbeat.cancel()
            XCTAssertGreaterThan(beats, 0, "Main actor must run while the full catalogue decodes")
            let all = store.listing(for: url)
            XCTAssertEqual(all.count, count)
            XCTAssertEqual(store.sources.first { $0.url == url }?.appCount, count)
            XCTAssertNotNil(store.sources.first { $0.url == url }?.updated)
            XCTAssertNil(store.loadErrors[url])
            let tail = try XCTUnwrap(all.last)
            XCTAssertFalse(store.listing(for: url, query: tail.name).isEmpty)
            XCTAssertNotNil(URL(string: tail.downloadURL.absoluteString))
            print("Alaa source performance \(name): \(bytes) bytes, \(all.count) apps, \(Date().timeIntervalSince(start))s, main-actor heartbeats=\(beats)")
        }
    }

    func testSourceNewsPresentationAndSafeRelativeLinks() throws {
        let feed = Data(##"{"name":"Mirsa","headerURL":"banner.png","subtitle":"Welcome","description":"My source","website":"https://x.com/rasmtk30","news":[{"identifier":"welcome","title":"Hello","caption":"New source","imageURL":"news.png","tintColor":"#123456","date":"2026-11-18","appID":"test.sample","url":"https://example.org/story"},{"title":"Unsafe","imageURL":"file:///private/test","url":"javascript:alert(1)"},{"caption":"Missing title"},42],"apps":[]}"##.utf8)
        let parsed = try SourcesStore.decodeSource(feed, base: URL(string: "https://example.org/source.json")!)
        XCTAssertEqual(parsed.headerURL?.absoluteString, "https://example.org/banner.png")
        XCTAssertEqual(parsed.subtitle, "Welcome")
        XCTAssertEqual(parsed.description, "My source")
        XCTAssertEqual(parsed.website?.host, "x.com")
        XCTAssertEqual(parsed.news.count, 2)
        XCTAssertEqual(parsed.news.first?.appID, "test.sample")
        XCTAssertEqual(parsed.news.first?.imageURL?.absoluteString, "https://example.org/news.png")
        XCTAssertNotNil(parsed.news.first?.date)
        XCTAssertNil(parsed.news.last?.url)
        XCTAssertNil(parsed.news.last?.imageURL)
        XCTAssertTrue(parsed.apps.isEmpty)
        XCTAssertNil(SourcesStore.contentURL("https://user:secret@example.org", base: URL(string: "https://example.org")!))
    }

    func testSourceNewsMissingAndRefreshClearsRemovedMetadata() async throws {
        var branded = true
        let store = makeStore { request in
            let json = branded ? #"{"headerURL":"banner.png","news":[{"title":"News"}],"apps":[]}"# : #"{"apps":[]}"#
            return (Data(json.utf8), self.response(request.url!))
        }
        await store.refresh(ryp0)
        XCTAssertEqual(store.presentation[ryp0]?.news.count, 1)
        branded = false
        await store.refresh(ryp0)
        XCTAssertTrue(store.presentation[ryp0]?.news.isEmpty == true)
        XCTAssertNil(store.presentation[ryp0]?.headerURL)
    }

    func testFullAppTestersJSONCountSearchAndInstallURLs() async throws {
        let data = try fixture("apptesters")
        XCTAssertEqual(data.count, 10_392_165)
        let store = makeStore { request in (data, self.response(request.url!)) }
        await store.ensureLoaded(appTesters)
        XCTAssertEqual(store.apps[appTesters]?.count, 789, "10130 legacy release entries group into one card per bundleIdentifier")
        XCTAssertEqual(store.listing(for: appTesters).count, 789)
        let found = try XCTUnwrap(store.listing(for: appTesters, query: " Sketchar ").first)
        XCTAssertEqual(found.bundleID, "tech.sketchar.ios")
        XCTAssertEqual(found.downloadURL.scheme, "https")
        XCTAssertTrue(found.downloadURL.absoluteString.contains("/releases/download/"))
        XCTAssertFalse(store.listing(for: appTesters, query: "HeyJapan").isEmpty, "tail of full JSON is searchable")
        XCTAssertEqual(store.sources.first { $0.url == appTesters }?.appCount, 789)
        XCTAssertNil(store.loadErrors[appTesters])
    }

    func testFullRyP0JSONCountSearchAndInstallURLs() async throws {
        let data = try fixture("ryp0")
        XCTAssertEqual(data.count, 2_366_545)
        let store = makeStore { request in (data, self.response(request.url!)) }
        await store.ensureLoaded(ryp0)
        // 165 installable entries share 160 bundle IDs: four identities are published as several entries
        // (kazumi 2, livecontainer 3, amethyst 2, Tweetie2 2). They group into one card each (165 - 5 = 160)
        // and every release of every duplicate entry is kept with its own URL.
        XCTAssertEqual(store.apps[ryp0]?.count, 160)
        XCTAssertEqual(store.listing(for: ryp0).count, 160)
        XCTAssertEqual(Set(store.listing(for: ryp0).map(\.bundleID)).count, 160)
        typealias ReleaseFixtureRow = [String: Any]
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try XCTUnwrap(root["apps"] as? [ReleaseFixtureRow])
        func identity(_ version: String, _ date: String?, _ url: URL, _ size: Int64?) -> [String?] {
            [version, date, url.absoluteString, size.map { String($0) }]
        }
        for (bundle, releases, repeatedURLs) in [("com.example.kazumi", 82, 0), ("com.kdt.livecontainer", 69, 2),
                                                   ("org.angelauramc.amethyst", 7, 0), ("com.atebits.Tweetie2", 13, 1)] {
            let card = try XCTUnwrap(store.listing(for: ryp0).first { $0.bundleID == bundle })
            let raw = rows.filter { $0["bundleIdentifier"] as? String == bundle }
                .flatMap { $0["versions"] as? [ReleaseFixtureRow] ?? [] }
            XCTAssertEqual(raw.count, releases, bundle)
            let expected = try raw.map { row in
                let version = try XCTUnwrap(row["version"] as? String).trimmingCharacters(in: .whitespacesAndNewlines)
                let url = try XCTUnwrap(URL(string: XCTUnwrap(row["downloadURL"] as? String), relativeTo: URL(string: ryp0))).absoluteURL
                let size = (row["size"] as? NSNumber)?.int64Value ?? (row["size"] as? String).flatMap { Int64($0) }
                return identity(version, row["date"] as? String, url, size.flatMap { $0 > 0 ? $0 : nil })
            }
            let identitiesByURL = Dictionary(grouping: expected) { $0[2] }
            let sharedURLs = identitiesByURL.values.filter { $0.count > 1 }
            XCTAssertEqual(sharedURLs.count, repeatedURLs, bundle)
            for entries in sharedURLs {
                XCTAssertEqual(entries.count, 2, bundle)
                XCTAssertEqual(Set(entries.map { $0[0] }).count, entries.count, "Shared URL, distinct version identities")
            }
            XCTAssertEqual(card.versions.count, releases, bundle)
            XCTAssertEqual(Set(card.versions.map(\.id)).count, releases, bundle)
            XCTAssertEqual(Set(card.versions.map { identity($0.version, $0.date, $0.downloadURL, $0.size) }), Set(expected), bundle)
        }
        let first = try XCTUnwrap(store.listing(for: ryp0, query: "wqfiles").first)
        XCTAssertEqual(first.bundleID, "cz.kolbi.wqfiles")
        XCTAssertEqual(first.downloadURL.scheme, "https")
        XCTAssertFalse(store.listing(for: ryp0, query: "Video Star").isEmpty, "tail of full JSON is searchable")
        XCTAssertEqual(store.sources.first { $0.url == ryp0 }?.appCount, 160)
    }

    func testPersistedCountsReloadButMemoryDoesNotAndDetailLoadsSelectedURL() async throws {
        let data = simple
        var requests = [String]()
        let store = makeStore { request in requests.append(request.url!.absoluteString); return (data, self.response(request.url!)) }
        var saved = store.sources
        for index in saved.indices { saved[index].appCount = saved[index].url == self.ryp0 ? 160 : 10_098 }
        store.sources = saved
        XCTAssertTrue(store.apps.isEmpty)
        XCTAssertEqual(store.sources.first { $0.url == ryp0 }?.appCount, 160)
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
    func testGlobalSearchLoadsPartialCacheAndFindsFullTailByNameOnly() async throws {
        let data = try fixture("apptesters")
        var requests = [String]()
        let store = makeStore { request in
            requests.append(request.url!.absoluteString)
            return (data, self.response(request.url!))
        }
        store.sources = [RepoSource(url: appTesters, name: "AppTesters"),
                         RepoSource(url: ryp0, name: "Other source")]
        store.apps[ryp0] = [] // global cache is nonempty, AppTesters still missing
        let discovery = DiscoveryStore(sources: store)
        discovery.input = " tIkToK "
        await discovery.search()
        XCTAssertEqual(requests, [appTesters])
        XCTAssertFalse(discovery.results.isEmpty)
        XCTAssertTrue(discovery.results.allSatisfy { $0.app.name.localizedCaseInsensitiveContains("tiktok") })
        let expected = (store.apps[appTesters] ?? []).filter { $0.name.localizedCaseInsensitiveContains("tiktok") }
        XCTAssertEqual(discovery.results.count, Set(expected.map { $0.id + "|" + $0.downloadURL.absoluteString }).count)
        discovery.input = "HeyJapan"
        await discovery.search()
        XCTAssertFalse(discovery.results.isEmpty, "full catalogue tail, not first N entries")
        XCTAssertEqual(requests.count, 1, "loaded sources are reused")
        discovery.input = "no-match-name-473829"
        await discovery.search()
        XCTAssertTrue(discovery.results.isEmpty)
        XCTAssertTrue(discovery.failures.isEmpty)
    }

    func testSourceVersionHistoryPreservesExactURLsAndOwnMetadata() throws {
        let data = Data(#"""
        {"apps":[{"name":"History","bundleIdentifier":"test.history","version":"99","downloadURL":"root.ipa","date":"2026-11-23","size":99999,"versions":[
          {"version":"3.0","downloadUrl":"latest.ipa","date":"2026-11-21","size":12000000},
          {"version":"2.0","downloadURL":"older.ipa","date":"2026-09-10","size":"8000000"},
          {"version":"1.0","downloadURL":"oldest.ipa"}
        ]}]}
        """#.utf8)
        let base = URL(string: "https://example.org/feed/source.json")!
        let app = try XCTUnwrap(SourcesStore.decodeSource(data, base: base).apps.first)
        XCTAssertTrue(app.hasVersionHistory)
        XCTAssertEqual(app.versions.map(\.version), ["3.0", "2.0", "1.0"])
        XCTAssertEqual(app.version, "3.0")
        XCTAssertEqual(app.installURL()?.absoluteString, "https://example.org/feed/latest.ipa")
        XCTAssertEqual(app.installURL(for: app.versions[1])?.absoluteString, "https://example.org/feed/older.ipa")
        XCTAssertEqual(app.installURL(for: app.versions[2])?.absoluteString, "https://example.org/feed/oldest.ipa")
        XCTAssertEqual(app.versions[1].date, "2026-09-10")
        XCTAssertEqual(app.versions[1].size, 8_000_000)
        XCTAssertNil(app.versions[2].date, "Never copy latest/root metadata to an older version")
        XCTAssertNil(app.versions[2].size)
        XCTAssertNotEqual(app.installURL(), app.installURL(for: app.versions[1]))
        let foreign = RepoAppVersion(version: "2.0", downloadURL: URL(string: "https://other.example/wrong.ipa")!, date: nil, size: nil)
        XCTAssertNil(app.installURL(for: foreign), "A release from another app/source cannot be routed here")
        XCTAssertEqual(app.installURL()?.absoluteString, "https://example.org/feed/latest.ipa", "History selection must not mutate latest")
    }

    func testSourceHistoryZeroOneLegacyMalformedAndDuplicateEntries() throws {
        let data = Data(#"""
        {"apps":[
          {"name":"Zero","downloadURL":"zero.ipa","version":"1","versions":[]},
          {"name":"Legacy","downloadURL":"legacy.ipa","version":"4"},
          {"name":"One","versions":[{"version":"1","downloadURL":"one.ipa"}]},
          {"name":"Mixed","downloadURL":"fallback.ipa","versions":[null,7,"x",{},{"version":"unsafe","downloadURL":"file:///private/x.ipa"},{"version":"credential","downloadURL":"https://user:pass@example.org/x.ipa"},{"version":"scheme","downloadURL":"javascript:alert(1)"},{"version":"missing"},{"downloadURL":"unnamed.ipa"},{"version":"2","downloadURL":"second.ipa","size":-8},{"version":"1","downloadURL":"first.ipa"},{"version":"1","downloadURL":"first.ipa"}]},
          {"name":"Broken","downloadURL":"fallback.ipa","version":"5","versions":[null,7,{"version":"bad","downloadURL":"javascript:alert(1)"}]}
        ]}
        """#.utf8)
        let all = try SourcesStore.decodeSource(data, base: URL(string: "https://example.org/source.json")!).apps
        XCTAssertEqual(all.count, 5)
        for name in ["Zero", "Legacy", "One", "Broken"] {
            let app = try XCTUnwrap(all.first { $0.name == name })
            XCTAssertFalse(app.hasVersionHistory, name + " must never open an empty/one-version history")
            XCTAssertNotNil(app.installURL())
        }
        let mixed = try XCTUnwrap(all.first { $0.name == "Mixed" })
        XCTAssertTrue(mixed.hasVersionHistory)
        XCTAssertEqual(mixed.version, "2")
        XCTAssertEqual(mixed.installURL()?.absoluteString, "https://example.org/second.ipa")
        XCTAssertEqual(mixed.versions.map(\.version), ["2", "1"])
        XCTAssertNil(mixed.versions.first?.size)
        XCTAssertEqual(mixed.versions.last?.downloadURL.absoluteString, "https://example.org/first.ipa")
        XCTAssertEqual(all.first { $0.name == "Broken" }?.installURL()?.absoluteString, "https://example.org/fallback.ipa")
    }


    // MARK: Legacy AltStore grouped history

    func testLegacyEntriesGroupIntoOneCardWithMergedHistory() throws {
        let data = Data(#"""
        {"apps":[
          {"name":"X","downloadURL":"x.ipa","version":"1"},
          {"name":"Multi","bundleIdentifier":"t.multi","version":"1.0","versionDate":"2026-01-01","size":"100","downloadURL":"m1.ipa"},
          {"name":"Y","downloadURL":"y.ipa","version":"1"},
          {"name":"Multi","bundleIdentifier":"t.multi","version":"3.0","versionDate":"2026-03-01","size":"300","downloadURL":"m3.ipa","iconURL":"i3.png"},
          {"name":"Broken","bundleIdentifier":"t.multi","version":"9.9"},
          {"name":"Multi","bundleIdentifier":"t.multi","version":"2.0","versionDate":"2026-02-01","downloadURL":"m2.ipa","versions":[
            {"version":"2.0","downloadURL":"m2.ipa","date":"2026-02-01"},{"version":"1.0","downloadURL":"m1.ipa","date":"2026-01-01","size":100}]},
          {"name":"Multi","bundleIdentifier":"t.multi","version":"3.0","versionDate":"2026-03-01","downloadURL":"m3b.ipa"},
          {"name":"Solo","bundleIdentifier":"t.solo","version":"1","downloadURL":"s.ipa"},
          {"name":"Solo","bundleIdentifier":"t.solo","version":"1","downloadURL":"s.ipa"},
          {"name":"Other","bundleIdentifier":"t.other","version":"1","downloadURL":"o.ipa"}
        ]}
        """#.utf8)
        let apps = try SourcesStore.decodeSource(data, base: URL(string: "https://e.org/s.json")!).apps
        XCTAssertEqual(apps.map(\.bundleID), ["X", "t.multi", "Y", "t.solo", "t.other"])
        let multi = try XCTUnwrap(apps.first { $0.bundleID == "t.multi" })
        XCTAssertEqual(multi.versions.map(\.version), ["3.0", "3.0", "2.0", "1.0"])
        XCTAssertEqual(multi.versions.map(\.downloadURL.lastPathComponent), ["m3.ipa", "m3b.ipa", "m2.ipa", "m1.ipa"])
        XCTAssertEqual(multi.version, "3.0")
        XCTAssertEqual(multi.installURL()?.lastPathComponent, "m3.ipa")
        XCTAssertEqual(multi.installURL(for: multi.versions[3])?.lastPathComponent, "m1.ipa")
        XCTAssertEqual(multi.versions[0].size, 300); XCTAssertEqual(multi.versions[3].size, 100)
        XCTAssertEqual(multi.versions[2].date, "2026-02-01")
        XCTAssertEqual(multi.iconURL?.lastPathComponent, "i3.png")
        XCTAssertTrue(multi.hasVersionHistory)
        let solo = try XCTUnwrap(apps.first { $0.bundleID == "t.solo" })
        XCTAssertFalse(solo.hasVersionHistory, "identical duplicate entries collapse to one total release")
        XCTAssertFalse(try XCTUnwrap(apps.first { $0.bundleID == "t.other" }).hasVersionHistory)
        XCTAssertEqual(apps.filter { $0.bundleID == "X" || $0.bundleID == "Y" }.count, 2, "entries without bundle IDs stay distinct")
    }

    func testFullAppTestersUplensGroupedHistory() throws {
        let data = try fixture("apptesters")
        let apps = try SourcesStore.decodeSource(data, base: URL(string: "https://repository.apptesters.org/")!).apps
        XCTAssertEqual(apps.count, 789)
        XCTAssertEqual(Set(apps.map(\.bundleID)).count, apps.count)
        let uplens = try XCTUnwrap(apps.first { $0.bundleID == "app.uplens" })
        XCTAssertEqual(uplens.versions.count, 35)
        XCTAssertEqual(Set(uplens.versions.map(\.downloadURL)).count, 35)
        XCTAssertEqual(uplens.version, uplens.versions[0].version)
        XCTAssertEqual(uplens.downloadURL, uplens.versions[0].downloadURL)
        XCTAssertTrue(uplens.versions[0].downloadURL.absoluteString.contains(uplens.version))
        XCTAssertTrue(uplens.versions.allSatisfy { $0.downloadURL.absoluteString.contains("_" + $0.version + "_") })
        let dates = uplens.versions.compactMap { $0.date.flatMap(SourcesStore.date) }
        XCTAssertEqual(dates, dates.sorted(by: >), "newest first")
        XCTAssertTrue(uplens.hasVersionHistory)
    }

    func testGroupingBenchmark10kEntries() throws {
        var rows = [String]()
        for i in 0..<10_000 {
            rows.append(#"{"name":"App\#(i % 2500)","bundleIdentifier":"b.\#(i % 2500)","version":"1.\#(i / 2500).\#(i)","versionDate":"2026-0\#(1 + i / 2500)-10","downloadURL":"https://e.org/\#(i).ipa"}"#)
        }
        let data = Data(("{\"apps\":[" + rows.reversed().joined(separator: ",") + "]}").utf8)
        let start = Date()
        let apps = try SourcesStore.decodeSource(data, base: URL(string: "https://e.org/s.json")!).apps
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(apps.count, 2500)
        XCTAssertTrue(apps.allSatisfy { $0.versions.count == 4 && $0.version.hasPrefix("1.3.") })
        XCTAssertLessThan(elapsed, 5, "dictionary grouping, no quadratic scans")
    }
}
