import XCTest
@testable import Mirsa

final class LocalOTATests: XCTestCase {
    func testRouteSelection() {
        XCTAssertEqual(OTARouteSelector.select(fileReadable: true, enabled: true), .local)
        XCTAssertEqual(OTARouteSelector.select(fileReadable: true, enabled: false), .upload(reason: .disabledByUser))
        XCTAssertEqual(OTARouteSelector.select(fileReadable: false, enabled: true), .upload(reason: .fileUnavailable))
    }
    func testFallbackReasonsAreLocalized() {
        for r in [OTAUploadReason.disabledByUser, .fileUnavailable, .serverStartFailed, .manifestUnreachable, .noInstallerRequest] {
            XCTAssertFalse(r.english.isEmpty); XCTAssertFalse(r.arabic.isEmpty)
        }
    }
    func testManifestURLIsHTTPSAndBounded() {
        let base = URL(string: "https://example.test/functions/v1/certificate-ota")!
        let t = String(repeating: "a", count: 32)
        let u = LocalOTAManifest.url(base: base, port: 50000, token: t, bundleID: "a.b", version: "1", title: "T", bytes: 5)
        XCTAssertEqual(u?.scheme, "https")
        XCTAssertTrue(u?.absoluteString.contains("action=local-manifest") ?? false)
        XCTAssertNil(LocalOTAManifest.url(base: base, port: 80, token: t, bundleID: "a", version: "1", title: "T", bytes: 5))
        XCTAssertNil(LocalOTAManifest.url(base: base, port: 50000, token: "bad", bundleID: "a", version: "1", title: "T", bytes: 5))
        XCTAssertNil(LocalOTAManifest.url(base: URL(string: "http://x.test/")!, port: 50000, token: t, bundleID: "a", version: "1", title: "T", bytes: 5))
    }
    func testRanges() throws {
        XCTAssertNil(try LocalOTARange.parse(nil, size: 100))
        XCTAssertEqual(try LocalOTARange.parse("bytes=0-9", size: 100), 0...9)
        XCTAssertEqual(try LocalOTARange.parse("bytes=90-", size: 100), 90...99)
        XCTAssertEqual(try LocalOTARange.parse("bytes=-10", size: 100), 90...99)
        XCTAssertEqual(try LocalOTARange.parse("bytes=50-500", size: 100), 50...99)
        for bad in ["bytes=100-", "bytes=5-2", "items=1-2", "bytes=0-1,3-4", "bytes=x-"] {
            XCTAssertThrowsError(try LocalOTARange.parse(bad, size: 100))
        }
    }
    func testServerServesTokenPathOnlyAndRange() async throws {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        try Data((0..<1000).map { UInt8($0 % 251) }).write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        let s = try LocalOTAServer(file: f)
        let port = try await s.start(lifetime: 30)
        defer { s.stop() }
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/\(s.token)/Mirsa.ipa")!)
        req.setValue("bytes=10-19", forHTTPHeaderField: "Range")
        let (d, r) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((r as? HTTPURLResponse)?.statusCode, 206)
        XCTAssertEqual(d, Data((10..<20).map { UInt8($0 % 251) }))
        let (_, bad) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/wrong/Mirsa.ipa")!)
        XCTAssertEqual((bad as? HTTPURLResponse)?.statusCode, 404)
    }
}
