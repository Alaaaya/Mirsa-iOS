import Foundation

/// A dedicated cookie-free stream, bounded before each disk write. No download is executed.
final class ForgeDylibDownload: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var file: FileHandle?
    private var location: URL?
    private var bytes = 0
    private let maximumBytes: Int
    init(maximumBytes: Int = ForgeDylibInspector.maximumBytes) {
        self.maximumBytes = min(max(1, maximumBytes), ForgeDylibInspector.maximumBytes)
        super.init()
    }
    private var redirects = 0
    private var failure: Error?
    private let stateLock = NSLock()
    private var cancelled = false

    /// Check every redirect independently; arbitrary HTTP, credentialed, literal-IP and local-network URLs are disallowed.
    static func validate(_ url: URL, requireExtension: Bool = true) throws {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let rawHost = url.host?.lowercased(), !rawHost.isEmpty else { throw ForgeDylibImportError.invalidURL }
        let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
        guard host.contains("."), host.utf8.count <= 253,
              !host.contains(":"), !host.contains("["), !host.contains("]"),
              !host.allSatisfy({ $0.isNumber || $0 == "." }),
              !["localhost", "local", "internal", "lan", "home", "test", "invalid", "onion"].contains(host.split(separator: ".").last.map(String.init) ?? ""),
              !host.hasSuffix(".localhost"), !host.hasSuffix(".local"),
              !host.contains(".."),
              host.split(separator: ".").allSatisfy({ label in
                  label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
                  label.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) || $0 == 45 }
              }) else { throw ForgeDylibImportError.invalidURL }
        if requireExtension && !["dylib", "deb"].contains(url.pathExtension.lowercased()) { throw ForgeDylibImportError.invalidURL }
    }

    static func fetch(_ url: URL, configuration: URLSessionConfiguration = .ephemeral, maximumBytes: Int = ForgeDylibInspector.maximumBytes) async throws -> URL {
        try validate(url)
        let delegate = ForgeDylibDownload(maximumBytes: maximumBytes)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.stateLock.lock()
                defer { delegate.stateLock.unlock() }
                guard !delegate.cancelled else { continuation.resume(throwing: ForgeDylibImportError.cancelled); return }
                delegate.continuation = continuation
                let config = configuration
                config.httpCookieStorage = nil
                config.httpShouldSetCookies = false
                config.urlCredentialStorage = nil
                config.requestCachePolicy = .reloadIgnoringLocalCacheData
                config.urlCache = nil
                config.timeoutIntervalForRequest = 45
                config.timeoutIntervalForResource = 180
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: config, delegate: delegate, delegateQueue: queue)
                delegate.session = session
                var request = URLRequest(url: url)
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                let task = session.dataTask(with: request)
                delegate.task = task
                task.resume()
            }
        } onCancel: {
            delegate.stateLock.lock()
            delegate.cancelled = true
            delegate.task?.cancel()
            delegate.stateLock.unlock()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        do {
            redirects += 1
            guard redirects <= 5, let url = request.url else { throw ForgeDylibImportError.invalidURL }
            try Self.validate(url, requireExtension: false)
            // Do not forward credentials or cookies if the redirect crosses hosts.
            var safe = URLRequest(url: url)
            safe.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            completionHandler(safe)
        } catch {
            failure = ForgeDylibImportError.invalidURL
            completionHandler(nil); task.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        do {
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let url = http.url else { throw ForgeDylibImportError.download }
            try Self.validate(url, requireExtension: false)
            guard response.expectedContentLength <= Int64(maximumBytes) else { throw ForgeDylibImportError.tooLarge }
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("mirsa-tweak-download-" + UUID().uuidString)
            guard FileManager.default.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw ForgeDylibImportError.download }
            location = temp
            file = try FileHandle(forWritingTo: temp)
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            guard data.count <= maximumBytes - bytes else { throw ForgeDylibImportError.tooLarge }
            guard let file else { throw ForgeDylibImportError.download }
            try file.write(contentsOf: data)
            bytes += data.count
        } catch { failure = error; dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? file?.close()
        file = nil
        stateLock.lock()
        let wasCancelled = cancelled
        stateLock.unlock()
        let resultError = failure ?? (wasCancelled ? ForgeDylibImportError.cancelled : (error == nil ? nil : ForgeDylibImportError.download))
        if let resultError {
            if let location { try? FileManager.default.removeItem(at: location) }
            continuation?.resume(throwing: resultError)
        } else if let location, bytes > 0 {
            continuation?.resume(returning: location)
        } else {
            if let location { try? FileManager.default.removeItem(at: location) }
            continuation?.resume(throwing: ForgeDylibImportError.download)
        }
        continuation = nil
        self.task = nil
        self.session = nil
        session.finishTasksAndInvalidate()
    }
}
