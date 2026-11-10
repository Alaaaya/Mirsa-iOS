import Foundation

/// One place for Mirsa's own source feed: ordered URLs, identity validation,
/// legacy migration. Source refresh and self-update both use this, so they cannot drift.
enum MirsaSourceFeed {
    /// Dedicated Oracle static feed, DNS and trusted HTTPS verified before enabling.
    static let primary = "https://mirsa-source.mooo.com/source.json"
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
        var mergedAway = Set<String>()   // ids of entries that came from a legacy Mirsa URL
        var usedIDs = Set<String>()
        for var s in list {
            let wasLegacy = legacyURLs.contains(norm(s.url))
            if wasLegacy { s.url = primary }
            if let i = out.firstIndex(where: { norm($0.url) == norm(s.url) }),
               wasLegacy || mergedAway.contains(out[i].id) {
                // legacy Mirsa URL collapses into its replacement; keep first entry, fill gaps
                if out[i].iconURL == nil { out[i].iconURL = s.iconURL }
                if out[i].tint == nil { out[i].tint = s.tint }
                continue
            }
            // stable identity: keep an existing fixed canonical id wherever it sits; ids must be unique
            if s.uid.isEmpty || usedIDs.contains(s.uid) || (s.uid == RepoSource.canonicalID && norm(s.url) != norm(primary)) {
                s.uid = UUID().uuidString
            }
            usedIDs.insert(s.uid)
            if wasLegacy { mergedAway.insert(s.id) }
            out.append(s)
        }
        // no row carries the fixed id yet (old saves): the first primary row becomes canonical
        if !out.contains(where: { $0.uid == RepoSource.canonicalID }), let i = out.firstIndex(where: { norm($0.url) == norm(primary) }) {
            out[i].uid = RepoSource.canonicalID
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
