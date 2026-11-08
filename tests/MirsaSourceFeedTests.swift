import XCTest
@testable import Mirsa

final class MirsaSourceFeedTests: XCTestCase {
    private let good = Data(#"{"name":"Mirsa","identifier":"com.alaa.mirsa.source","apps":[{"bundleIdentifier":"com.alaa.mirsa.setup","versions":[{"version":"1.3.1","buildVersion":"3.1.1"}]}]}"#.utf8)
    private func resp(_ u: URL, _ code: Int) -> URLResponse { HTTPURLResponse(url: u, statusCode: code, httpVersion: nil, headerFields: nil)! }

    func testOrderPrimaryThenPagesThenRaw() {
        let u = MirsaSourceFeed.urls
        XCTAssertEqual(u.first, MirsaSourceFeed.primary)
        XCTAssertLessThan(u.firstIndex(of: MirsaSourceFeed.githubPages)!, u.firstIndex(of: MirsaSourceFeed.raw)!)
        XCTAssertEqual(Set(u).count, u.count)
    }
    func testMigrateLegacyPreservesMetadataAndCustom() {
        var legacy = RepoSource(url: "https://github.com/Alaaaya/Mirsa/releases/download/setup/source.json", name: "Mirsa")
        legacy.iconURL = "icon"; legacy.appCount = 3
        let custom = RepoSource(url: "https://example.com/repo.json", name: "X")
        let out = MirsaSourceFeed.migrate([custom, legacy])
        XCTAssertEqual(out.map(\.url), [custom.url, MirsaSourceFeed.primary])
        XCTAssertEqual(out[1].iconURL, "icon"); XCTAssertEqual(out[1].appCount, 3)
    }
    func testMigrateDedupesWhenCanonicalExists() {
        let canon = RepoSource(url: MirsaSourceFeed.primary, name: "Mirsa")
        let legacy = RepoSource(url: "https://github.com/Alaaaya/Mirsa-iOS/releases/download/setup/source.json", name: "Old")
        XCTAssertEqual(MirsaSourceFeed.migrate([legacy, canon]).count, 1)
        XCTAssertEqual(MirsaSourceFeed.migrate([canon, legacy]).first?.name, "Mirsa")
    }
    func testFallbackOnHTTPFailureAndInvalidPayload() async throws {
        var calls = [String]()
        let urls = ["https://a.test/s.json", "https://b.test/s.json", "https://c.test/s.json"]
        let f = try await MirsaSourceFeed.fetch(urls: urls) { req in
            let u = req.url!; calls.append(u.host!)
            switch u.host! {
            case "a.test": return (Data(), self.resp(u, 504))
            case "b.test": return (Data("{\"name\":\"Other\",\"apps\":[]}".utf8), self.resp(u, 200))
            default: return (self.good, self.resp(u, 200))
            }
        }
        XCTAssertEqual(calls, ["a.test", "b.test", "c.test"]); XCTAssertEqual(f.url.host, "c.test")
        XCTAssertEqual(MirsaSourceFeed.latestBuild(in: f.root), "3.1.1")
    }
    func testNetworkErrorFallsThroughAndAllFailThrows() async {
        do { _ = try await MirsaSourceFeed.fetch(urls: ["https://a.test/x"]) { _ in throw URLError(.timedOut) }; XCTFail() }
        catch { XCTAssertTrue(error is URLError) }
    }
    func testCancellationPropagatesWithoutNextRequest() async {
        var calls = 0
        do {
            _ = try await MirsaSourceFeed.fetch(urls: ["https://a.test/x", "https://b.test/x"]) { _ in calls += 1; throw URLError(.cancelled) }
            XCTFail()
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(calls, 1)
        let task = Task { try await MirsaSourceFeed.fetch(urls: ["https://a.test/x"]) { _ in XCTFail(); return (Data(), URLResponse()) } }
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testTimeoutIsBounded() { XCTAssertLessThanOrEqual(MirsaSourceFeed.perAttemptTimeout, 10) }
}
