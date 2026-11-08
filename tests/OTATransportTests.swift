import XCTest
@testable import Mirsa

final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest, Data) throws -> (Int, Data))?
    nonisolated(unsafe) static var log: [(String, String?)] = []
    static let lock = NSLock()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func startLoading() {
        var body = Data()
        if let s = request.httpBodyStream {
            s.open(); var buf = [UInt8](repeating: 0, count: 65536)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; body.append(buf, count: n) }
            s.close()
        } else if let b = request.httpBody { body = b }
        Self.lock.lock(); Self.log.append((request.httpMethod ?? "", request.value(forHTTPHeaderField: "X-Mirsa-Offset"))); Self.lock.unlock()
        do {
            let (code, data) = try Self.handler!(request, body)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class FakeOTAServer {
    var committed = Data()
    var dropAfterCommitOnce = false, failGETOnce = false, status503Once = false
    var methods: [String] { StubProtocol.log.map { $0.0 } }
    func json(_ o: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: o) }
    func install() {
        StubProtocol.log = []
        StubProtocol.handler = { [self] req, body in
            switch req.httpMethod! {
            case "POST" where req.url!.path.hasSuffix("finalize"):
                return (200, json(["manifestURL": "https://mirsa-app.mooo.com/ota/download/0123456789abcdef0123456789abcdef?token=eyJhIjoxfQ.c2ln&kind=manifest"]))
            case "POST": return (200, json(["offset": committed.count, "total": 20]))
            case "GET":
                if failGETOnce { failGETOnce = false; throw URLError(.networkConnectionLost) }
                return (200, json(["offset": committed.count, "total": 20]))
            case "PUT":
                if status503Once { status503Once = false; return (503, Data()) }
                let off = Int(req.value(forHTTPHeaderField: "X-Mirsa-Offset")!)!
                if off != committed.count { return (409, json(["offset": committed.count])) }
                committed.append(body)
                if dropAfterCommitOnce { dropAfterCommitOnce = false; throw URLError(.networkConnectionLost) }
                return (200, json(["offset": committed.count, "total": 20]))
            default: return (204, Data())
            }
        }
    }
}

final class OTATransportTests: XCTestCase {
    let payload = Data((0..<20).map { UInt8($0) })
    var file: URL!
    let sess = OTASession(url: URL(string: "https://mirsa-app.mooo.com/ota/sessions/abc")!, token: "t", maxChunk: 8)
    func config() -> URLSessionConfiguration { let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [StubProtocol.self]; return c }
    override func setUp() {
        file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! payload.write(to: file)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: file); StubProtocol.handler = nil }

    func testHappyPathExactBytes() async throws {
        let s = FakeOTAServer(); s.install()
        let url = try await OTAChunkUploader.run(file: file, total: 20, session: sess, configuration: config(), backoff: [0], chunkSize: 8) { _ in }
        XCTAssertEqual(s.committed, payload)
        XCTAssertEqual(url.host, "mirsa-app.mooo.com")
        XCTAssertFalse(s.methods.contains("DELETE"))
    }
    func test409UsesServerOffset() async throws {
        let s = FakeOTAServer(); s.committed = payload.prefix(8)
        s.install()
        let up = OTAChunkUploader(configuration: config(), backoff: [0])
        try await up.upload(file: file, total: 20, session: sess, from: 0, chunkSize: 8) { _ in }
        XCTAssertEqual(s.committed, payload)
    }
    func testInterruptedUploadResumesWithoutDuplicate() async throws {
        let s = FakeOTAServer(); s.dropAfterCommitOnce = true; s.failGETOnce = true; s.install()
        let up = OTAChunkUploader(configuration: config(), backoff: [0, 0, 0])
        try await up.upload(file: file, total: 20, session: sess, from: 0, chunkSize: 8) { _ in }
        XCTAssertEqual(s.committed, payload)
    }
    func testTransient503Retries() async throws {
        let s = FakeOTAServer(); s.status503Once = true; s.install()
        let up = OTAChunkUploader(configuration: config(), backoff: [0, 0])
        try await up.upload(file: file, total: 20, session: sess, from: 0, chunkSize: 8) { _ in }
        XCTAssertEqual(s.committed, payload)
    }
    func testInvalidStartOffsetRejected() async {
        let s = FakeOTAServer(); s.install()
        let up = OTAChunkUploader(configuration: config(), backoff: [0])
        do { try await up.upload(file: file, total: 20, session: sess, from: 21) { _ in }; XCTFail() } catch {}
        do { try await up.upload(file: file, total: 20, session: sess, from: -1) { _ in }; XCTFail() } catch {}
    }
    func testJumpBeyondSentBytesRejected() async {
        StubProtocol.log = []
        StubProtocol.handler = { req, _ in (200, try! JSONSerialization.data(withJSONObject: ["offset": 20])) }
        let up = OTAChunkUploader(configuration: config(), backoff: [0])
        do { try await up.upload(file: file, total: 20, session: sess, from: 0, chunkSize: 8) { _ in }; XCTFail() }
        catch { XCTAssertEqual(error as? OTAChunkError, .badResponse) }
    }
    func testCancellationAbortsWithFreshSession() async {
        let s = FakeOTAServer(); s.install()
        let cfg = config()
        let t = Task { try await OTAChunkUploader.run(file: file, total: 20, session: sess, configuration: cfg, backoff: [0], chunkSize: 8) { _ in } }
        t.cancel()
        do { _ = try await t.value; XCTFail() } catch { XCTAssertEqual(error as? OTAChunkError, .cancelled) }
        XCTAssertTrue(s.methods.contains("DELETE"))
    }
    func testServerFailureAbortsSession() async {
        let s = FakeOTAServer(); s.install()
        StubProtocol.handler = { req, body in req.httpMethod == "PUT" ? (400, Data()) : (req.httpMethod == "DELETE" ? (204, Data()) : (200, try! JSONSerialization.data(withJSONObject: ["offset": 0]))) }
        do { _ = try await OTAChunkUploader.run(file: file, total: 20, session: sess, configuration: config(), backoff: [0], chunkSize: 8) { _ in }; XCTFail() } catch {}
        XCTAssertTrue(StubProtocol.log.contains { $0.0 == "DELETE" })
    }
    func testFallbackRestrictions() {
        let small: Int64 = 1000, big = OTAFallbackPolicy.limit + 1
        XCTAssertTrue(OTAFallbackPolicy.allows(URLError(.cannotConnectToHost), size: small))
        XCTAssertTrue(OTAFallbackPolicy.allows(OTAChunkError.server(503), size: small))
        XCTAssertFalse(OTAFallbackPolicy.allows(URLError(.cannotConnectToHost), size: big))
        for e: Error in [OTAChunkError.server(400), .server(401), .server(403), .server(413), .server(429), .badHost, .badResponse, .expired, .cancelled, .tooLarge] {
            XCTAssertFalse(OTAFallbackPolicy.allows(e, size: small))
        }
    }
    func testManifestValidation() {
        XCTAssertTrue(OTAHostPolicy.acceptsManifest(URL(string: "https://mirsa-app.mooo.com/ota/download/0123456789abcdef0123456789abcdef?token=eyJhIjoxfQ.c2ln&kind=manifest")!))
        let b="https://mirsa-app.mooo.com/ota/download/0123456789abcdef0123456789abcdef"
        for bad in ["\(b)?token=eyJhIjoxfQ.c2ln", "\(b)?kind=manifest", "\(b)?token=x.y&kind=manifest&kind=manifest",
                    "\(b)?token=x.y&token=x.y&kind=manifest", "\(b)?token=nodot&kind=manifest", "\(b)?token=x.y&kind=manifest&z=1",
                    "\(b)?token=x.y&kind=ipa", "\(b)?token=x.y&kind=manifest#f",
                    "https://mirsa-app.mooo.com/ota/download/abc?token=x.y&kind=manifest",
                    "https://mirsa-app.mooo.com/ota/download/0123456789abcdef0123456789abcdef/x?token=x.y&kind=manifest",
                    "https://mirsa-app.mooo.com/ota/m?token=x.y&kind=manifest",
                    "https://evil.com/ota/download/0123456789abcdef0123456789abcdef?token=x.y&kind=manifest",
                    "http://mirsa-app.mooo.com/ota/download/0123456789abcdef0123456789abcdef?token=x.y&kind=manifest"] {
            XCTAssertFalse(OTAHostPolicy.acceptsManifest(URL(string: bad)!), bad)
        }
    }
    func testWireStrictness() throws {
        for bad in [#"{"offset":true}"#, #"{"offset":-1}"#, #"{"offset":1.5}"#, #"{"offset":"3"}"#] {
            XCTAssertNil(OTAOracleWire.offset(from: Data(bad.utf8)), bad)
        }
        let past = #"{"uploadURL":"https://mirsa-app.mooo.com/ota/sessions/a","uploadToken":"t","expiresAt":"2000-01-01T00:00:00Z"}"#
        XCTAssertThrowsError(try OTAOracleWire.session(from: Data(past.utf8)))
        let fut = #"{"uploadURL":"https://mirsa-app.mooo.com/ota/sessions/a","uploadToken":"t","expiresAt":"2999-01-01T00:00:00.000Z"}"#
        XCTAssertNoThrow(try OTAOracleWire.session(from: Data(fut.utf8)))
    }
}
