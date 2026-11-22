import XCTest
@testable import Mirsa

final class WallpaperCatalogTests: XCTestCase {
    // Synthetic, never fetches third-party content.
    private func fixture(_ change: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var entry: [String: Any] = [
            "name": "Test orbit", "author": "Synthetic fixture",
            "category": "Abstract", "size": 32,
            "preview": "https://example.com/preview.png",
            "download": "https://example.com/orbit.tendies"
        ]
        change(&entry)
        return try JSONSerialization.data(withJSONObject: [
            "name": "Owned test catalog", "author": "Mirsa tests", "wallpapers": [entry]
        ])
    }

    func testSyntheticValidCatalog() throws {
        let feed = try WallpaperCatalog.decode(fixture())
        XCTAssertEqual(feed.wallpapers.count, 1)
        XCTAssertEqual(feed.wallpapers.first?.size, 32)
    }

    func testRejectsUnsafeURLs() {
        for raw in [
            "http://example.com/a.tendies", "file:///tmp/a.tendies",
            "https://user:password@example.com/a.tendies",
            "https://example.com:8443/a.tendies", "https://localhost/a",
            "https://127.0.0.1/a", "https://192.168.1.2/a",
            "https://[::1]/a", "https://printer.local/a",
            "https://example.com/a#fragment", "https://2130706433/a"
        ] {
            XCTAssertThrowsError(try WallpaperCatalog.checkedURL(URL(string: raw)!), raw)
        }
    }

    func testAllowsHTTPSQuery() throws {
        _ = try WallpaperCatalog.checkedURL(URL(string: "https://example.com/a.tendies?version=1")!)
    }

    func testInvalidEntrySizesTypesAndNames() throws {
        for size in [-1, 0, WallpaperCatalog.fileLimit + 1] {
            XCTAssertThrowsError(try WallpaperCatalog.decode(fixture { $0["size"] = size }))
        }
        for value in ["", String(repeating: "x", count: 161), "bad\nname"] {
            XCTAssertThrowsError(try WallpaperCatalog.decode(fixture { $0["name"] = value }))
        }
        XCTAssertThrowsError(try WallpaperCatalog.decode(fixture { $0["size"] = "32" }))
        XCTAssertThrowsError(try WallpaperCatalog.decode(fixture { $0["download"] = "https://example.com/a.ipa" }))
        XCTAssertThrowsError(try WallpaperCatalog.decode(fixture { $0["preview"] = "http://example.com/p.png" }))
        XCTAssertThrowsError(try WallpaperCatalog.decode(fixture { $0.removeValue(forKey: "author") }))
    }

    func testFeedBoundsDuplicateAndMalformed() throws {
        XCTAssertThrowsError(try WallpaperCatalog.decode(Data(repeating: 32, count: WallpaperCatalog.feedLimit + 1)))
        XCTAssertThrowsError(try WallpaperCatalog.decode(Data("not JSON".utf8)))
        var feed = try JSONSerialization.jsonObject(with: fixture()) as! [String: Any]
        let entry = (feed["wallpapers"] as! [[String: Any]])[0]
        feed["wallpapers"] = [entry, entry]
        XCTAssertThrowsError(try WallpaperCatalog.decode(JSONSerialization.data(withJSONObject: feed)))
        feed["wallpapers"] = Array(repeating: entry, count: 201)
        XCTAssertThrowsError(try WallpaperCatalog.decode(JSONSerialization.data(withJSONObject: feed)))
    }

    func testAllFiveLocales() {
        XCTAssertEqual(AppLanguage.allCases.count, 5)
        for key in WallpaperCatalogText.Key.allCases {
            XCTAssertEqual(WallpaperCatalogText.values[key]?.count, 5)
            for language in AppLanguage.allCases {
                XCTAssertFalse(WallpaperCatalogText.text(key, language: language).isEmpty)
            }
        }
    }

    func testRedirectRejected() {
        let network = WallpaperCatalogNetwork()
        let u = URL(string: "https://example.com/source.json")!
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: u)
        let response = HTTPURLResponse(url: u, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var called = false
        network.urlSession(session, task: task, willPerformHTTPRedirection: response,
                           newRequest: URLRequest(url: URL(string: "https://127.0.0.1/private")!)) {
            XCTAssertNil($0)
            called = true
        }
        XCTAssertTrue(called)
        task.cancel()
    }
}
