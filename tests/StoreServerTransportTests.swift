import Foundation
import XCTest
import CryptoKit
#if canImport(MirsaStoreKit)
@testable import MirsaStoreKit
#else
@testable import Mirsa
#endif

private final class StoreServerMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class StoreServerTransportTests: XCTestCase {
    override func tearDown() { StoreServerMockURLProtocol.handler = nil; super.tearDown() }

    private func transport() throws -> MirsaStoreServerTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StoreServerMockURLProtocol.self]
        return try MirsaStoreServerTransport(origin: URL(string: "https://store.example.invalid")!,
                                             configuration: configuration)
    }

    func testOriginAndPathCannotEscapeHTTPS() throws {
        for value in ["http://store.example.invalid", "https://u:p@store.example.invalid", "https://store.example.invalid:444", "https://store.example.invalid/?secret=x"] {
            XCTAssertThrowsError(try MirsaStoreServerTransport(origin: URL(string: value)!))
        }
        let transport = try transport()
        XCTAssertEqual(try transport.url("/v1/auth/login").host, "store.example.invalid")
        for path in ["//evil.invalid/x", "https://evil.invalid/x", "/x#fragment", "/\\evil.invalid"] {
            XCTAssertThrowsError(try transport.url(path))
        }
        let session = transport.session()
        defer { session.invalidateAndCancel() }
        XCTAssertNil(session.configuration.httpCookieStorage)
        XCTAssertNil(session.configuration.urlCredentialStorage)
        XCTAssertNil(session.configuration.urlCache)
        XCTAssertFalse(session.configuration.httpShouldSetCookies)
    }

    func testMockJSONRequestHasExactBodyAndReturnsStatusWithoutRetry() async throws {
        let transport = try transport()
        var request = URLRequest(url: try transport.url("/fixture"))
        request.httpMethod = "POST"
        request.httpBody = Data("{\"fixture\":true}".utf8)
        var calls = 0
        StoreServerMockURLProtocol.handler = { incoming in
            calls += 1
            XCTAssertEqual(incoming.httpMethod, "POST")
            XCTAssertNil(incoming.value(forHTTPHeaderField: "Cookie"))
            return (HTTPURLResponse(url: incoming.url!, statusCode: 401, httpVersion: nil,
                                   headerFields: ["Content-Type": "application/json"])!,
                    Data("{\"code\":\"signed_out\"}".utf8))
        }
        let (data, status) = try await transport.json(request)
        XCTAssertEqual(status, 401)
        XCTAssertEqual(data, Data("{\"code\":\"signed_out\"}".utf8))
        XCTAssertEqual(calls, 1)
    }

    func testMockRejectsOversizedJSONAndCrossOriginBeforeNetwork() async throws {
        let transport = try transport()
        var calls = 0
        StoreServerMockURLProtocol.handler = { incoming in
            calls += 1
            return (HTTPURLResponse(url: incoming.url!, statusCode: 200, httpVersion: nil,
                                   headerFields: ["Content-Length": "1048577"])!,
                    Data(repeating: 65, count: 1_048_577))
        }
        do { _ = try await transport.json(URLRequest(url: try transport.url("/fixture"))); XCTFail() }
        catch { XCTAssertEqual(error as? MirsaStoreError, .serviceUnavailable) }
        XCTAssertEqual(calls, 1)
        do { _ = try await transport.json(URLRequest(url: URL(string: "https://evil.invalid")!)); XCTFail() }
        catch { XCTAssertEqual(error as? MirsaStoreError, .untrustedURL) }
        XCTAssertEqual(calls, 1)
    }

    func testRedirectNeverForwardsRequest() throws {
        let transport = try transport()
        let session = transport.session()
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: try transport.url("/fixture"))
        let response = HTTPURLResponse(url: try transport.url("/fixture"), statusCode: 302,
                                       httpVersion: nil, headerFields: ["Location": "https://evil.invalid"])!
        var called = false
        transport.urlSession(session, task: task, willPerformHTTPRedirection: response,
                             newRequest: URLRequest(url: URL(string: "https://evil.invalid")!)) { next in
            XCTAssertNil(next); called = true
        }
        XCTAssertTrue(called)
    }

    func testArtifactIsUnchangedAfterSizeAndHashValidation() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let bytes = Data([0x50, 0x4b, 3, 4, 0, 7, 8, 9])
        try bytes.write(to: file)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try MirsaStoreServerTransport.verifyArtifact(file, expectedBytes: Int64(bytes.count), sha256: hash, expires: Date().addingTimeInterval(60))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertThrowsError(try MirsaStoreServerTransport.verifyArtifact(file, expectedBytes: 1, sha256: hash, expires: Date().addingTimeInterval(60)))
        XCTAssertThrowsError(try MirsaStoreServerTransport.verifyArtifact(file, expectedBytes: Int64(bytes.count), sha256: String(repeating: "0", count: 64), expires: Date().addingTimeInterval(60)))
        XCTAssertThrowsError(try MirsaStoreServerTransport.verifyArtifact(file, expectedBytes: Int64(bytes.count), sha256: hash, expires: Date().addingTimeInterval(-1)))
        XCTAssertThrowsError(try MirsaStoreServerTransport.verifyArtifact(file, expectedBytes: MirsaStoreServerTransport.maximumIPABytes + 1, sha256: hash, expires: Date().addingTimeInterval(60)))
    }
}
