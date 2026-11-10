import Foundation

/// Streams a single owner-authorized artifact. No redirects, no IPA rewriting.
final class MirsaStoreServerArtifact: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var task: URLSessionDownloadTask?
    private var cancelled = false
    private var requestURL: URL?
    private var directory: URL?
    private var result: URL?
    private var failure: Error?
    private var expectedBytes: Int64 = 0
    private var sha256 = ""
    private var expires = Date.distantPast
    private var started = false

    func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }

    private func claim() throws {
        lock.lock(); defer { lock.unlock() }
        guard !started else { throw MirsaStoreError.busy }
        started = true
    }

    func fetch(transport: MirsaStoreServerTransport, request: URLRequest,
               expectedBytes: Int64, sha256: String, expires: Date) async throws -> URL {
        try claim()
        guard expectedBytes > 0, expectedBytes <= MirsaStoreServerTransport.maximumIPABytes,
              expires > Date(), let url = request.url,
              try transport.url(url.path + (url.query.map { "?" + $0 } ?? "")) == url else {
            throw MirsaStoreError.invalidPackage
        }
        self.expectedBytes = expectedBytes
        self.sha256 = sha256
        self.expires = expires
        requestURL = url
        let directory = try MirsaManagedTmp.begin("store-server")
        self.directory = directory
        let session = transport.session(delegate: self)
        defer { session.invalidateAndCancel() }
        do {
            return try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { continuation in
                    lock.lock()
                    self.continuation = continuation
                    let task = session.downloadTask(with: request)
                    self.task = task
                    let shouldCancel = cancelled
                    lock.unlock()
                    task.resume()
                    if shouldCancel { task.cancel() }
                }
            }, onCancel: { self.cancel() })
        } catch {
            MirsaManagedTmp.end(directory)
            throw error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        failure = MirsaStoreError.untrustedURL
        completionHandler(nil)
        task.cancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > expectedBytes || totalBytesExpectedToWrite > expectedBytes || expires <= Date() {
            failure = MirsaStoreError.invalidPackage
            downloadTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            guard let http = downloadTask.response as? HTTPURLResponse,
                  http.statusCode == 200, http.url == requestURL, let directory else {
                throw MirsaStoreError.invalidPackage
            }
            try MirsaStoreServerTransport.verifyArtifact(location, expectedBytes: expectedBytes,
                                                         sha256: sha256, expires: expires)
            try Task.checkCancellation()
            let destination = directory.appendingPathComponent("App.ipa")
            try FileManager.default.moveItem(at: location, to: destination)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete],
                                                 ofItemAtPath: destination.path)
            #endif
            result = destination
        } catch { failure = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        self.task = nil
        let cancelled = cancelled
        lock.unlock()
        if cancelled { continuation?.resume(throwing: MirsaStoreError.operationCancelled) }
        else if let error = failure ?? error { continuation?.resume(throwing: error) }
        else if let result { continuation?.resume(returning: result) }
        else { continuation?.resume(throwing: MirsaStoreError.invalidPackage) }
    }
}
