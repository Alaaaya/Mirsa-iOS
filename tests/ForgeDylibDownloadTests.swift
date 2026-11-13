import XCTest
@testable import Mirsa

private final class ForgeTweakURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "tweak.example.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let status = path.contains("failure") ? 500 : 200
        let body = Data(repeating: 65, count: path.contains("large") ? 4096 : 16)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ForgeDylibDownloadTests: XCTestCase {
    private func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ForgeTweakURLProtocol.self]
        return config
    }
    func testOnlyPublicHTTPSAndNoCredentials() {
        for string in ["http://example.com/a.dylib", "file:///a.dylib", "https://user:pass@example.com/a.dylib",
                       "https://127.0.0.1/a.dylib", "https://[::1]/a.dylib", "https://localhost/a.dylib",
                       "https://a.local/a.dylib", "https://example.com:8443/a.dylib", "https://example.com/a.zip",
                       "https://2130706433/a.dylib"] {
            XCTAssertThrowsError(try ForgeDylibDownload.validate(URL(string: string)!))
        }
        XCTAssertNoThrow(try ForgeDylibDownload.validate(URL(string: "https://tweak.example.com/a.dylib?token=1")!))
        XCTAssertNoThrow(try ForgeDylibDownload.validate(URL(string: "https://tweak.example.com/a.deb")!))
    }
    func testRedirectMustBeSecureEvenWhenExtensionNotRequired() {
        for string in ["http://cdn.example.com/file", "https://192.168.1.1/file", "https://user:pass@cdn.example.com/file"] {
            XCTAssertThrowsError(try ForgeDylibDownload.validate(URL(string: string)!, requireExtension: false))
        }
        XCTAssertNoThrow(try ForgeDylibDownload.validate(URL(string: "https://cdn.example.com/download/123")!, requireExtension: false))
    }
    func testDownloadStreamsToOwnedTemporaryFile() async throws {
        let file = try await ForgeDylibDownload.fetch(URL(string: "https://tweak.example.com/small.dylib")!, configuration: configuration())
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try Data(contentsOf: file).count, 16)
    }
    func testStreamingCapAndHTTPFailureLeaveNoTemporaryFiles() async throws {
        let fm = FileManager.default
        func files() throws -> Set<String> {
            Set(try fm.contentsOfDirectory(atPath: fm.temporaryDirectory.path).filter { $0.hasPrefix("mirsa-tweak-download-") })
        }
        let before = try files()
        for path in ["large", "failure"] {
            do {
                let file = try await ForgeDylibDownload.fetch(URL(string: "https://tweak.example.com/\(path).dylib")!,
                                                            configuration: configuration(), maximumBytes: 1024)
                try? fm.removeItem(at: file)
                XCTFail("Unsafe response accepted")
            } catch {}
        }
        XCTAssertEqual(try files(), before)
    }
}
