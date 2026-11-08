import Foundation

/// One place for Mirsa's own source feed: ordered URLs, identity validation,
/// legacy migration. Source refresh and self-update both use this, so they cannot drift.
enum MirsaSourceFeed {
    /// Build-time primary. Switch to https://mirsa-source.mooo.com/source.json only after DNS + HTTPS are verified.
    static let primary = "https://mirsa-app.mooo.com/source.json"
    static let githubPages = "https://mirsa-app.github.io/source.json"
    static let raw = "https://raw.githubusercontent.com/Mirsa-App/mirsa-app.github.io/main/source.json"
    /// Ordered, de-duplicated.
    static var urls: [String] { orderedUnique([primary, "https://mirsa-app.mooo.com/source.json", githubPages, raw]) }
    static let legacyURLs: Set<String> = [
        "https://github.com/alaaaya/mirsa/releases/download/setup/source.json",
        "https://github.com/alaaaya/mirsa-ios/releases/download/setup/source.json",
    ]
    static let perAttemptTimeout: TimeInterval = 8

    static func orderedUnique(_ list: [String]) -> [String] {
        var seen = Set<String>(); return list.filter { seen.insert(norm($0)).inserted }
    }
    static func norm(_ u: String) -> String { u.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/ \n")) }
    static func isOwned(_ u: String) -> Bool { urls.contains { norm($0) == norm(u) } || legacyURLs.contains(norm(u)) }

    /// Replaces Mirsa-owned legacy URLs by the primary, keeps custom sources and user metadata, de-duplicates.
    static func migrate(_ list: [RepoSource], primary: String = MirsaSourceFeed.primary) -> [RepoSource] {
        var out: [RepoSource] = []
        for var s in list {
            if legacyURLs.contains(norm(s.url)) { s.url = primary }
            if let i = out.firstIndex(where: { norm($0.url) == norm(s.url) }) {
                // keep first entry, fill gaps from the duplicate
                if out[i].iconURL == nil { out[i].iconURL = s.iconURL }
                if out[i].tint == nil { out[i].tint = s.tint }
                continue
            }
            out.append(s)
        }
        return out
    }

    struct SourceError: Error { let message: String }

    static func validate(_ data: Data) throws -> [String: Any] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (root["name"] as? String) == "Mirsa" || (root["identifier"] as? String) == "com.alaa.mirsa.source",
              let apps = root["apps"] as? [[String: Any]], !apps.isEmpty else { throw SourceError(message: "Not the Mirsa source") }
        return root
    }

    typealias Loader = (URLRequest) async throws -> (Data, URLResponse)

    /// Tries each URL in order. Network/status/invalid JSON moves on; user cancellation is propagated.
    static func fetch(urls: [String] = MirsaSourceFeed.urls,
                      load: Loader = { try await URLSession.shared.data(for: $0) }) async throws -> (url: URL, data: Data, root: [String: Any]) {
        var last: Error = SourceError(message: "No source URL")
        for s in urls {
            try Task.checkCancellation()
            guard let u = URL(string: s) else { continue }
            var req = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: perAttemptTimeout)
            req.setValue("Mirsa", forHTTPHeaderField: "User-Agent")
            do {
                let (d, r) = try await load(req)
                if let h = r as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
                    throw SourceError(message: "HTTP \(h.statusCode)")
                }
                return (u, d, try validate(d))
            } catch is CancellationError { throw CancellationError() }
            catch let e as URLError where e.code == .cancelled { throw CancellationError() }
            catch { last = error }
        }
        throw last
    }

    /// Highest buildVersion/version advertised for a bundle id, for update checks.
    static func latestBuild(in root: [String: Any]) -> String? {
        guard let apps = root["apps"] as? [[String: Any]],
              let app = apps.first(where: { ($0["bundleIdentifier"] as? String)?.hasPrefix("com.alaa.mirsa") == true }),
              let v = (app["versions"] as? [[String: Any]])?.first else { return nil }
        return v["buildVersion"] as? String
    }
}
