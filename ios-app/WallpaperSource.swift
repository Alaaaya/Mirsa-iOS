import Foundation
import CryptoKit
import Combine

/// Independent wallpaper feed. App IPA feeds are never interpreted as wallpaper feeds.
struct WallpaperSourceFeed: Codable, Equatable {
    var name: String
    var author: String
    var wallpapers: [WallpaperSourceEntry]

    func validated() throws -> Self {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 160, author.count <= 160, wallpapers.count <= 1000,
              Set(wallpapers.map(\.id)).count == wallpapers.count else { throw WallpaperSourceError.invalid }
        for entry in wallpapers {
            guard !entry.id.isEmpty, entry.id.count <= 160, !entry.name.isEmpty, entry.name.count <= 160,
                  entry.author.count <= 160, entry.category.count <= 100,
                  entry.size > 0, entry.size <= 536_870_912,
                  Self.allowed(entry.url), entry.url.pathExtension.lowercased() == "tendies",
                  Self.allowed(entry.previewImage),
                  entry.previewVideo.map(Self.allowed) ?? true else { throw WallpaperSourceError.invalid }
        }
        return self
    }

    static func allowed(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil && url.user == nil && url.password == nil
    }
}

struct WallpaperSourceEntry: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var author: String
    var previewImage: URL
    var previewVideo: URL?
    var url: URL
    var size: Int64
    var category: String
}

enum WallpaperSourceError: LocalizedError {
    case invalid, response, tooLarge, sizeMismatch
    var errorDescription: String? { WallpaperSourceText.text(.failed) }
}

/// Bounded streaming, including chunked responses. Never buffers an untrusted archive in RAM.
enum WallpaperSourceNetwork {
    static func file(_ url: URL, limit: Int64) async throws -> URL {
        guard WallpaperSourceFeed.allowed(url) else { throw WallpaperSourceError.invalid }
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.setValue("Mirsa", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let final = response.url, WallpaperSourceFeed.allowed(final) else { throw WallpaperSourceError.response }
        guard response.expectedContentLength <= limit else { throw WallpaperSourceError.tooLarge }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: target.path, contents: nil)
        let handle = try FileHandle(forWritingTo: target)
        var completed = false
        defer {
            try? handle.close()
            if !completed { try? FileManager.default.removeItem(at: target) }
        }
        var buffer = Data()
        buffer.reserveCapacity(65536)
        var count: Int64 = 0
        for try await byte in bytes {
            try Task.checkCancellation()
            count += 1
            guard count <= limit else { throw WallpaperSourceError.tooLarge }
            buffer.append(byte)
            if buffer.count == 65536 { try handle.write(contentsOf: buffer); buffer.removeAll(keepingCapacity: true) }
        }
        if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
        try handle.synchronize()
        completed = true
        return target
    }

    static func feed(_ url: URL) async throws -> WallpaperSourceFeed {
        let temporary = try await file(url, limit: 2_097_152)
        defer { try? FileManager.default.removeItem(at: temporary) }
        return try JSONDecoder().decode(WallpaperSourceFeed.self, from: Data(contentsOf: temporary)).validated()
    }

    static func archive(_ entry: WallpaperSourceEntry) async throws -> URL {
        let temporary = try await file(entry.url, limit: entry.size)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            let actual = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard Int64(actual ?? -1) == entry.size else { throw WallpaperSourceError.sizeMismatch }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Filename derives from the full URL, never from untrusted source paths or names.
            let digest = SHA256.hash(data: Data(entry.url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
            let named = directory.appendingPathComponent(digest + ".tendies")
            try FileManager.default.moveItem(at: temporary, to: named)
            return named
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

@MainActor
final class WallpaperSourceStore: ObservableObject {
    static let official = URL(string: "https://mirsa-source.mooo.com/wallpapers.json")!
    @Published private(set) var urls: [URL]
    @Published private(set) var feeds: [URL: WallpaperSourceFeed] = [:]
    @Published private(set) var loading = false
    @Published var error: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.stringArray(forKey: "mirsa.wallpaper.sources.v1") ?? []
        var seen = Set<URL>()
        urls = ([Self.official] + saved.compactMap(URL.init(string:))).filter {
            WallpaperSourceFeed.allowed($0) && seen.insert($0).inserted
        }
    }
    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        error = nil
        #if DEBUG
        if WallpaperSourceFixture.active {
            feeds[Self.official] = WallpaperSourceFixture.feed
            return
        }
        #endif
        for url in urls {
            do { feeds[url] = try await WallpaperSourceNetwork.feed(url) }
            catch is CancellationError { return }
            catch { self.error = WallpaperSourceText.text(.failed) }
        }
    }
    func add(_ raw: String) async {
        guard !loading, urls.count < 32, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              WallpaperSourceFeed.allowed(url) else { error = WallpaperSourceText.text(.failed); return }
        guard !urls.contains(url) else { return }
        loading = true
        defer { loading = false }
        do {
            let feed = try await WallpaperSourceNetwork.feed(url)
            urls.append(url); feeds[url] = feed; persist(); error = nil
        } catch { self.error = WallpaperSourceText.text(.failed) }
    }
    func remove(_ url: URL) {
        guard url != Self.official else { return }
        urls.removeAll { $0 == url }; feeds[url] = nil; persist()
    }
    private func persist() { defaults.set(urls.map(\.absoluteString), forKey: "mirsa.wallpaper.sources.v1") }
}
