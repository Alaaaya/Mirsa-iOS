import Foundation

/// Data only. Never imports, unpacks, installs or modifies wallpapers.
struct WallpaperCatalog: Decodable {
    let name: String
    let author: String
    let wallpapers: [Entry]
    struct Entry: Decodable, Identifiable {
        let name: String
        let author: String
        let preview: URL
        let category: String
        let size: Int
        let download: URL
        var id: String { download.absoluteString }
    }
    static let feedLimit = 1_048_576
    static let fileLimit = 32 * 1_048_576

    enum Invalid: Error { case feed, url, response, size }

    static func checkedURL(_ url: URL) throws -> URL {
        guard url.absoluteString.utf8.count <= 2048,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme?.lowercased() == "https", c.user == nil, c.password == nil,
              c.port == nil || c.port == 443, c.fragment == nil,
              let host = c.host?.lowercased(), host.count <= 253,
              host.contains("."), !host.hasSuffix("."), !host.contains(":"),
              !host.hasSuffix(".local"), !host.hasSuffix(".localhost"),
              !host.hasSuffix(".internal"), !host.hasSuffix(".home"),
              host.split(separator: ".").allSatisfy({ label in
                  !label.isEmpty && label.count <= 63 &&
                  label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
              }),
              let last = host.split(separator: ".").last,
              last.allSatisfy({ $0.isLetter }) else { throw Invalid.url }
        return url
    }

    static func decode(_ data: Data) throws -> WallpaperCatalog {
        guard !data.isEmpty, data.count <= feedLimit else { throw Invalid.size }
        let feed = try JSONDecoder().decode(Self.self, from: data)
        func text(_ s: String, max: Int) -> Bool {
            !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            s.utf8.count <= max && !s.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        }
        guard text(feed.name, max: 160), text(feed.author, max: 160),
              feed.wallpapers.count <= 200 else { throw Invalid.feed }
        var ids = Set<String>()
        for e in feed.wallpapers {
            guard text(e.name, max: 160), text(e.author, max: 160),
                  text(e.category, max: 80), (1...fileLimit).contains(e.size),
                  e.download.pathExtension.lowercased() == "tendies",
                  ids.insert(e.id).inserted else { throw Invalid.feed }
            _ = try checkedURL(e.preview)
            _ = try checkedURL(e.download)
        }
        return feed
    }
}

/// Redirects disabled, no cookies, credentials, caching or background transfer.
/// Bounded streaming applies even when Content-Length is missing or dishonest.
final class WallpaperCatalogNetwork: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func read(_ url: URL, limit: Int) async throws -> Data {
        _ = try WallpaperCatalog.checkedURL(url)
        guard limit > 0, limit <= WallpaperCatalog.fileLimit else { throw WallpaperCatalog.Invalid.size }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200 else { throw WallpaperCatalog.Invalid.response }
        guard response.expectedContentLength <= Int64(limit) else { throw WallpaperCatalog.Invalid.size }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw WallpaperCatalog.Invalid.size }
            data.append(byte)
        }
        guard !data.isEmpty else { throw WallpaperCatalog.Invalid.size }
        return data
    }

    func export(_ entry: WallpaperCatalog.Entry) async throws -> URL {
        let data = try await read(entry.download, limit: entry.size)
        guard data.count == entry.size, data.starts(with: [0x50, 0x4b, 0x03, 0x04]) else {
            throw WallpaperCatalog.Invalid.size
        }
        // Opaque ZIP, never extracted. Unique owned temp directory, never feed-derived paths.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Wallpaper.tendies")
        do { try data.write(to: file, options: .atomic) }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
        return file
    }
}
