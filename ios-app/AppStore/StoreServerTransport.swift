import Foundation
import CryptoKit

/// A closed HTTPS origin, independent of the service's JSON contract.
/// Login requests never use cookies, URL caches, credential storage or redirects.
final class MirsaStoreServerTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let maximumIPABytes: Int64 = 2 * 1024 * 1024 * 1024
    let origin: URL
    private let configuration: URLSessionConfiguration

    init(origin: URL, configuration: URLSessionConfiguration = .ephemeral) throws {
        guard origin.scheme == "https", origin.host != nil, origin.user == nil, origin.password == nil,
              origin.port == nil || origin.port == 443, origin.query == nil, origin.fragment == nil else {
            throw MirsaStoreError.untrustedURL
        }
        self.origin = origin
        self.configuration = configuration
        super.init()
    }

    func url(_ path: String) throws -> URL {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("\\"),
              let url = URL(string: path, relativeTo: origin)?.absoluteURL,
              url.scheme == origin.scheme, url.host == origin.host, url.port == origin.port,
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw MirsaStoreError.untrustedURL
        }
        return url
    }

    func session(delegate: URLSessionDelegate? = nil) -> URLSession {
        let config = configuration.copy() as! URLSessionConfiguration
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config, delegate: delegate ?? self, delegateQueue: nil)
    }

    /// Bounded response, including error bodies. Callers decode only allowlisted error codes.
    func json(_ request: URLRequest) async throws -> (Data, Int) {
        guard let target = request.url, target.scheme == origin.scheme, target.host == origin.host,
              target.port == origin.port, target.user == nil, target.password == nil, target.fragment == nil else {
            throw MirsaStoreError.untrustedURL
        }
        let session = session()
        defer { session.invalidateAndCancel() }
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, response.url == target,
              response.expectedContentLength <= 1024 * 1024 else { throw MirsaStoreError.serviceUnavailable }
        var data = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard data.count < 1024 * 1024 else { throw MirsaStoreError.serviceUnavailable }
            data.append(byte)
        }
        return (data, http.statusCode)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    /// Verify the already-downloaded artifact without modifying a single archive byte.
    /// Uses bounded blocks, never loads a multi-gigabyte IPA into RAM.
    static func verifyArtifact(_ file: URL, expectedBytes: Int64, sha256: String, expires: Date,
                               now: Date = Date()) throws {
        guard expectedBytes > 0, expectedBytes <= maximumIPABytes, expires > now,
              sha256.utf8.count == 64, sha256.utf8.allSatisfy({
                  (48...57).contains($0) || (97...102).contains($0)
              }),
              let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              Int64(size) == expectedBytes else { throw MirsaStoreError.invalidPackage }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        var read: Int64 = 0
        while let block = try handle.read(upToCount: 1024 * 1024), !block.isEmpty {
            read += Int64(block.count)
            guard read <= expectedBytes else { throw MirsaStoreError.invalidPackage }
            hasher.update(data: block)
        }
        guard read == expectedBytes,
              hasher.finalize().map({ String(format: "%02x", $0) }).joined() == sha256 else {
            throw MirsaStoreError.invalidPackage
        }
    }
}
