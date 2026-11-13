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

    private func tmpFile(_ n: Int) throws -> URL {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        try Data(repeating: 7, count: n).write(to: f); return f
    }
    func testAwaitFirstRequestTimesOutWithoutRequest() async throws {
        let f = try tmpFile(100); defer { try? FileManager.default.removeItem(at: f) }
        let s = try LocalOTAServer(file: f); _ = try await s.start(lifetime: 30); defer { s.stop() }
        let got = await s.awaitFirstRequest(timeout: 0.3)
        XCTAssertFalse(got)
    }
    func testHeadDoesNotCountButGetDoes() async throws {
        let f = try tmpFile(5000); defer { try? FileManager.default.removeItem(at: f) }
        let s = try LocalOTAServer(file: f); let port = try await s.start(lifetime: 30); defer { s.stop() }
        var head = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/\(s.token)/Mirsa.ipa")!); head.httpMethod = "HEAD"
        _ = try await URLSession.shared.data(for: head)
        let afterHead = await s.awaitFirstRequest(timeout: 0.3)
        XCTAssertFalse(afterHead)
        _ = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/\(s.token)/Mirsa.ipa")!)
        let afterGet = await s.awaitFirstRequest(timeout: 2)
        XCTAssertTrue(afterGet)
        XCTAssertEqual(s.servedBytes, 5000)
    }
    func testStopResolvesWaiterAndClosesListener() async throws {
        let f = try tmpFile(100); defer { try? FileManager.default.removeItem(at: f) }
        let s = try LocalOTAServer(file: f); let port = try await s.start(lifetime: 30)
        async let w = s.awaitFirstRequest(timeout: 10)
        try await Task.sleep(nanoseconds: 100_000_000)
        s.stop()
        let result = await w
        XCTAssertFalse(result); XCTAssertTrue(s.isStopped)
        let r = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/\(s.token)/Mirsa.ipa")!)
        XCTAssertNil(r)
    }
    func testHeaderDeadlineCutsIdleButNotActiveTransfer() async throws {
        let old = LocalOTAServer.headerTimeout; LocalOTAServer.headerTimeout = 0.5; defer { LocalOTAServer.headerTimeout = old }
        let f = try tmpFile(8 * 1024 * 1024); defer { try? FileManager.default.removeItem(at: f) }
        let s = try LocalOTAServer(file: f); let port = try await s.start(lifetime: 30); defer { s.stop() }
        // Transfer outlives the header deadline: a slow reader still receives everything.
        let url = URL(string: "http://127.0.0.1:\(port)/\(s.token)/Mirsa.ipa")!
        let (bytes, resp) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(bytes.count, 8 * 1024 * 1024)
    }
    func testManifestURLUsesGivenBaseOnlyAndBoundsInputs() throws {
        let base = URL(string: "https://ota.example.test/local-manifest")!
        let tok = String(repeating: "a", count: 32)
        let u = try XCTUnwrap(LocalOTAManifest.url(base: base, port: 51234, token: tok, bundleID: "com.alaa.mirsa", version: "1", title: "Mirsa", bytes: 10))
        XCTAssertEqual(u.host, "ota.example.test"); XCTAssertEqual(u.path, "/local-manifest")
        XCTAssertTrue(u.absoluteString.contains("action=local-manifest&port=51234&token=\(tok)"))
        XCTAssertNil(LocalOTAManifest.url(base: URL(string: "http://ota.example.test/x")!, port: 51234, token: tok, bundleID: "a", version: "1", title: "t", bytes: 1))
        XCTAssertNil(LocalOTAManifest.url(base: base, port: 80, token: tok, bundleID: "a", version: "1", title: "t", bytes: 1))
        XCTAssertNil(LocalOTAManifest.url(base: base, port: 51234, token: "short", bundleID: "a", version: "1", title: "t", bytes: 1))
        let live = try XCTUnwrap(CertificateOTA.localManifestEndpoint)
        XCTAssertEqual(live.absoluteString, "https://mirsa-app.mooo.com/local-manifest.plist")
        XCTAssertEqual(live.scheme, "https"); XCTAssertNotEqual(live.host, CertificateOTA.endpoint.host)
        let built = try XCTUnwrap(LocalOTAManifest.url(base: live, port: 51234, token: tok, bundleID: "a", version: "1", title: "t", bytes: 1))
        XCTAssertTrue(built.absoluteString.hasPrefix("https://mirsa-app.mooo.com/local-manifest.plist?action=local-manifest&port=51234"))
    }
}
