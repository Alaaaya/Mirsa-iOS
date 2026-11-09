import Foundation
@preconcurrency import ApplePackage
import ZIPFoundation

protocol MirsaStorePackages {
    func cancel()
    func fetch(output: DownloadOutput, bundleID: String) async throws -> URL
}

/// A private, transient download. No Authorization/Cookie headers are forwarded to the CDN.
final class AppleStorePackages: MirsaStorePackages {
    private let lock = NSLock()
    private var download: StoreCDNDownload?
    func cancel() {
        lock.lock()
        let download = self.download
        lock.unlock()
        download?.cancel()
    }
    private func register(_ download: StoreCDNDownload?) {
        lock.lock()
        self.download = download
        lock.unlock()
    }
    func fetch(output: DownloadOutput, bundleID: String) async throws -> URL {
        guard let url = URL(string: output.downloadURL) else { throw MirsaStoreError.untrustedURL }
        try MirsaStorePolicy.downloadURL(url)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MirsaStore", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: Self.protection)
        let destination = directory.appendingPathComponent("App.ipa")
        do {
            let download = StoreCDNDownload()
            register(download)
            defer { register(nil) }
            try await download.download(url, to: destination)
            try Task.checkCancellation()
            try Self.assemble(destination, output: output, bundleID: bundleID)
            try FileManager.default.setAttributes(Self.protection, ofItemAtPath: destination.path)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static var protection: [FileAttributeKey: Any] {
        #if os(iOS)
        return [.protectionKey: FileProtectionType.complete]
        #else
        return [:]
        #endif
    }

    /// Modifies only SINF/metadata entries, never executable bytes. No filesystem extraction.
    static func assemble(_ url: URL, output: DownloadOutput, bundleID: String) throws {
        let archive = try Archive(url: url, accessMode: .update)
        var paths = Set<String>()
        var expanded: UInt64 = 0
        var count = 0
        for entry in archive {
            try MirsaStorePolicy.archivePath(entry.path)
            count += 1
            guard count <= 100_000, paths.insert(entry.path).inserted, entry.type != .symlink else {
                throw MirsaStoreError.invalidPackage
            }
            let (sum, overflow) = expanded.addingReportingOverflow(UInt64(entry.uncompressedSize))
            guard !overflow, sum <= 16 * 1024 * 1024 * 1024 else { throw MirsaStoreError.invalidPackage }
            expanded = sum
        }
        let infos = paths.filter {
            let components = $0.split(separator: "/")
            return components.count == 3 && components[0] == "Payload" &&
                components[1].hasSuffix(".app") && components[2] == "Info.plist"
        }
        guard infos.count == 1, let infoPath = infos.first, let infoEntry = archive[infoPath] else {
            throw MirsaStoreError.invalidPackage
        }
        let info = try plist(archive, entry: infoEntry)
        guard info["CFBundleIdentifier"] as? String == bundleID,
              info["CFBundleShortVersionString"].map({ String(describing: $0) }) == output.bundleShortVersionString,
              info["CFBundleVersion"].map({ String(describing: $0) }) == output.bundleVersion,
              let executable = info["CFBundleExecutable"] as? String, !executable.contains("/"),
              !executable.isEmpty else { throw MirsaStoreError.invalidPackage }
        try MirsaStorePolicy.archivePath(executable)
        let root = String(infoPath.dropLast("Info.plist".count))
        guard archive[root + executable] != nil else { throw MirsaStoreError.invalidPackage }
        let sinfPaths: [String]
        if let manifest = archive[root + "SC_Info/Manifest.plist"] {
            guard let relative = try plist(archive, entry: manifest)["SinfPaths"] as? [String],
                  relative.count == output.sinfs.count, !relative.isEmpty else {
                throw MirsaStoreError.invalidPackage
            }
            for path in relative {
                try MirsaStorePolicy.archivePath(path)
                guard path.hasPrefix("SC_Info/"), path.hasSuffix(".sinf") else { throw MirsaStoreError.invalidPackage }
            }
            sinfPaths = relative.map { root + $0 }
        } else {
            guard output.sinfs.count == 1 else { throw MirsaStoreError.invalidPackage }
            sinfPaths = [root + "SC_Info/" + executable + ".sinf"]
        }
        guard Set(sinfPaths).count == sinfPaths.count else { throw MirsaStoreError.invalidPackage }
        for (path, sinf) in zip(sinfPaths, output.sinfs) { try add(sinf.sinf, path: path, archive: archive) }
        // Replace vendor metadata, if present, with the exact account-bound Apple response.
        if let old = archive["iTunesMetadata.plist"] { try archive.remove(old) }
        try add(output.iTunesMetadata, path: "iTunesMetadata.plist", archive: archive)
    }

    private static func plist(_ archive: Archive, entry: Entry) throws -> [String: Any] {
        guard entry.type == .file, entry.uncompressedSize <= 2 * 1024 * 1024 else {
            throw MirsaStoreError.invalidPackage
        }
        var bytes = Data()
        _ = try archive.extract(entry) { chunk in
            guard bytes.count + chunk.count <= 2 * 1024 * 1024 else { throw MirsaStoreError.invalidPackage }
            bytes.append(chunk)
        }
        guard let result = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any] else {
            throw MirsaStoreError.invalidPackage
        }
        return result
    }
    private static func add(_ data: Data, path: String, archive: Archive) throws {
        guard archive[path] == nil else { throw MirsaStoreError.invalidPackage }
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                             compressionMethod: .deflate) { position, size in
            let start = Int(position)
            guard start >= 0, start <= data.count, size >= 0, size <= data.count - start else {
                throw MirsaStoreError.invalidPackage
            }
            return data.subdata(in: start..<(start + size))
        }
    }
}

private final class StoreCDNDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var destination: URL?
    private var failure: Error?
    private var redirects = 0
    private var moved = false
    private var task: URLSessionDownloadTask?
    private var cancelled = false
    private let maxBytes: Int64 = 4 * 1024 * 1024 * 1024

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func download(_ url: URL, to destination: URL) async throws {
        try MirsaStorePolicy.downloadURL(url)
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                self.destination = destination
                self.continuation = continuation
                let task = session.downloadTask(with: url)
                self.task = task
                let cancel = cancelled
                lock.unlock()
                if cancel { task.cancel() }
                task.resume()
            }
        }, onCancel: {
            self.cancel()
        })
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        do {
            guard let url = request.url, redirects < 5 else { throw MirsaStoreError.untrustedURL }
            try MirsaStorePolicy.downloadURL(url)
            redirects += 1
            // Reconstruct to avoid forwarding server-provided credentials or cookies.
            completionHandler(URLRequest(url: url))
        } catch { failure = error; completionHandler(nil); task.cancel() }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maxBytes || totalBytesExpectedToWrite > maxBytes {
            failure = MirsaStoreError.invalidPackage
            downloadTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200,
                  let url = response.url, let destination,
                  let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size > 0, Int64(size) <= maxBytes else { throw MirsaStoreError.invalidPackage }
            try MirsaStorePolicy.downloadURL(url)
            try FileManager.default.moveItem(at: location, to: destination)
            moved = true
        } catch { failure = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        self.task = nil
        lock.unlock()
        if let error = failure ?? error { continuation?.resume(throwing: error) }
        else if !moved { continuation?.resume(throwing: MirsaStoreError.invalidPackage) }
        else { continuation?.resume() }
    }
}
