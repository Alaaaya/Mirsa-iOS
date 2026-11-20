import Foundation

/// The pattern tables `PremiumScanner` matches against, as one decodable
/// document. Same shape as the bundled `patterns.json` and as the remote
/// copy served at `PremiumPatternStore.remoteURL`.
struct PremiumPatternSet: Codable, Equatable {
    /// One SDK (or ad SDK): `id` is the stable key used for merging
    /// (and, for ad SDKs, the lowercase id the dylib recognises),
    /// `name` is the display name shown in findings.
    struct SDK: Codable, Equatable {
        var id: String
        var name: String
        var classes: [String]
    }

    /// Detection patterns for one extra feature (paywall, tracking,
    /// watermark, …): method-name substrings, class-name substrings and
    /// string constants. Keyed by feature id in `features`.
    struct FeaturePatterns: Codable, Equatable {
        var symbols: [String] = []
        var classes: [String] = []
        var strings: [String] = []
    }

    var version: Int
    var updated: String
    var sdks: [SDK]
    var premiumSymbols: [String]
    var adSDKs: [SDK]
    var serverIndicators: [String]
    /// Usage-limit method names (remainingUses, dailyLimit, …).
    var limitSymbols: [String] = []
    /// Usage-limit string constants ("free uses", "daily limit", …).
    var limitStrings: [String] = []
    /// Per-feature detection patterns, keyed by feature id.
    var features: [String: FeaturePatterns] = [:]
}

/// Owns the Premium Unlock pattern tables: bundled `patterns.json`,
/// merged with the remotely fetched copy when one is available.
///
/// Flow:
/// - At startup the bundled file is loaded, then the on-disk cache (if
///   any) is merged over it, so the last fetched patterns apply at once.
/// - `refreshInBackground()` fetches the remote copy with a ~5 s timeout
///   on a background URLSession. On success the raw JSON is cached to the
///   app caches directory and merged in; on failure (offline, timeout,
///   bad status, undecodable) the cached/bundled patterns keep working.
/// - Merge rule: remote ADDS to bundled; an entry with the same `id` as
///   a bundled one (same SDK id or same ad-SDK id) is replaced by the
///   remote one (remote wins). Plain string lists (premium symbols,
///   server indicators) are unioned, bundled order first.
/// - Scans never wait on the network: `PremiumScanner` reads the current
///   merged set synchronously via `snapshot()`.
final class PremiumPatternStore: ObservableObject {
    static let shared = PremiumPatternStore()

    /// Remote copy, served next to the ESign source on the same host.
    static let remoteURL = URL(string: "https://alaa-mirsa.duckdns.org/patterns.json")!
    static let cacheFileName = "patterns.json"

    /// The fetched copy lives here (app caches directory — the system may
    /// purge it under storage pressure, the bundled file is the fallback).
    static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(cacheFileName)
    }

    /// The merged set the scanner uses; also what the UI shows the
    /// version/date of. Updated on the main thread only.
    @Published private(set) var current: PremiumPatternSet
    @Published private(set) var isUpdating = false
    @Published private(set) var updateError: String?

    /// "الأنماط v2 — 2026-11-20" for the update row in the Unlock flow.
    var versionText: String {
        tr("Patterns v\(current.version) — \(current.updated)",
           "الأنماط v\(current.version) — \(current.updated)",
           ckb: "نەخشەکان v\(current.version) — \(current.updated)",
           kmr: "Nimûne v\(current.version) — \(current.updated)")
    }

    private let lock = NSLock()
    private var _snapshot: PremiumPatternSet
    private var _refreshing = false
    private let bundled: PremiumPatternSet

    private init() {
        let bundled = Self.loadBundled() ?? PremiumPatternSet(
            version: 1, updated: "", sdks: [], premiumSymbols: [], adSDKs: [], serverIndicators: [])
        self.bundled = bundled
        var merged = bundled
        if let cached = Self.loadCached() { merged = Self.merged(bundled: bundled, remote: cached) }
        _snapshot = merged
        current = merged
    }

    // MARK: - Synchronous access for the scanner

    /// The merged patterns, safe to call from any thread (including the
    /// `Task.detached` the scan runs in). Never touches the network.
    func snapshot() -> PremiumPatternSet {
        lock.lock()
        defer { lock.unlock() }
        return _snapshot
    }

    // MARK: - Remote refresh

    /// Fire-and-forget background fetch; never blocks the caller and never
    /// blocks a scan. Concurrent calls are coalesced into one fetch.
    func refreshInBackground() {
        Task { await refresh() }
    }

    /// Fetches the remote copy, caches it on disk and merges it in.
    /// Any failure leaves the current patterns untouched.
    func refresh() async {
        lock.lock()
        if _refreshing { lock.unlock(); return }
        _refreshing = true
        lock.unlock()
        defer {
            lock.lock()
            _refreshing = false
            lock.unlock()
        }
        publish { self.isUpdating = true }
        defer { publish { self.isUpdating = false } }
        do {
            let fetched = try await Self.fetchRemote()
            let remote = fetched.set
            // Refuse an empty document: it would add nothing but would
            // still overwrite the cache and the version label.
            guard !remote.sdks.isEmpty || !remote.premiumSymbols.isEmpty
                    || !remote.adSDKs.isEmpty || !remote.serverIndicators.isEmpty
                    || !remote.limitSymbols.isEmpty || !remote.features.isEmpty else {
                throw URLError(.badServerResponse)
            }
            if let url = Self.cacheURL {
                try? fetched.data.write(to: url, options: .atomic)
            }
            apply(remote: remote)
            publish { self.updateError = nil }
        } catch {
            publish {
                self.updateError = tr("Couldn't update patterns. Check your internet and try again.",
                                      "ما قدرنا نحدّث الأنماط. تأكد من الإنترنت وحاول مرة تانية.",
                                      ckb: "نەتوانرا نەخشەکان نوێ بکرێنەوە. ئینتەرنێتەکە بپشکنە و دووبارە هەوڵبدەرەوە.",
                                      kmr: "Nimûne nehatin nûvekirin. Înternetê kontrol bike û dîsa biceribîne.")
            }
        }
    }

    private func apply(remote: PremiumPatternSet) {
        let merged = Self.merged(bundled: bundled, remote: remote)
        lock.lock()
        _snapshot = merged
        lock.unlock()
        publish { self.current = merged }
    }

    /// Runs `update` on the main thread (immediately when already there).
    private func publish(_ update: @escaping () -> Void) {
        if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
    }

    // MARK: - Fetch / load / merge

    private struct Fetched {
        var set: PremiumPatternSet
        var data: Data
    }

    private static func fetchRemote() async throws -> Fetched {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        var request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession(configuration: config).data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return Fetched(set: try JSONDecoder().decode(PremiumPatternSet.self, from: data), data: data)
    }

    private static func loadBundled() -> PremiumPatternSet? {
        let url = Bundle.main.url(forResource: "patterns", withExtension: "json")
            ?? Bundle.main.url(forResource: "patterns", withExtension: "json", subdirectory: "Apps")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PremiumPatternSet.self, from: data)
    }

    private static func loadCached() -> PremiumPatternSet? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PremiumPatternSet.self, from: data)
    }

    /// Remote ADDS to bundled; same `id` → remote wins. String lists are
    /// unioned (bundled order first, remote-only entries appended).
    /// Feature sections merge per feature id: same id → the remote
    /// section replaces the bundled one wholesale (remote wins).
    static func merged(bundled: PremiumPatternSet, remote: PremiumPatternSet) -> PremiumPatternSet {
        var out = bundled
        out.version = remote.version
        out.updated = remote.updated
        out.sdks = mergedSDKs(bundled.sdks, remote.sdks)
        out.adSDKs = mergedSDKs(bundled.adSDKs, remote.adSDKs)
        out.premiumSymbols = union(bundled.premiumSymbols, remote.premiumSymbols)
        out.serverIndicators = union(bundled.serverIndicators, remote.serverIndicators)
        out.limitSymbols = union(bundled.limitSymbols, remote.limitSymbols)
        out.limitStrings = union(bundled.limitStrings, remote.limitStrings)
        var features = bundled.features
        for (id, pats) in remote.features { features[id] = pats }
        out.features = features
        return out
    }

    private static func mergedSDKs(_ base: [PremiumPatternSet.SDK], _ extra: [PremiumPatternSet.SDK]) -> [PremiumPatternSet.SDK] {
        var out = base
        for sdk in extra {
            if let i = out.firstIndex(where: { $0.id == sdk.id }) { out[i] = sdk } else { out.append(sdk) }
        }
        return out
    }

    private static func union(_ base: [String], _ extra: [String]) -> [String] {
        var out = base
        for s in extra where !out.contains(where: { $0.lowercased() == s.lowercased() }) { out.append(s) }
        return out
    }
}
