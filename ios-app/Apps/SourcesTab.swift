import SwiftUI
import ImageIO

// MARK: - Model (AltStore / SideStore / Feather source format)

/// Copy/share of a source's stored URL. Only plain http(s) URLs without embedded credentials are allowed.
enum SourceURLAction {
    static func shareableURL(_ stored: String) -> URL? {
        let t = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let c = URLComponents(string: t),
              let scheme = c.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, let u = c.url else { return nil }
        return u
    }
    @MainActor static func copy(_ stored: String) {
        guard let u = shareableURL(stored) else { return }
        UIPasteboard.general.string = u.absoluteString
    }
}

private struct SharedSourceURL: Identifiable { let url: URL; var id: String { url.absoluteString } }

private struct SourceShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

private struct SourceURLButtons: View {
    let stored: String
    @Binding var sharing: URL?
    var body: some View {
        let ok = SourceURLAction.shareableURL(stored) != nil
        Button { SourceURLAction.copy(stored) } label: { Label(tr("Copy URL", "نسخ الرابط"), systemImage: "doc.on.doc") }.disabled(!ok)
        Button { sharing = SourceURLAction.shareableURL(stored) } label: { Label(tr("Share URL", "مشاركة الرابط"), systemImage: "square.and.arrow.up") }.disabled(!ok)
    }
}

struct RepoApp: Identifiable, Hashable, Sendable {
    var id: String { bundleID + "|" + version }
    let name: String
    let bundleID: String
    let developer: String
    let subtitle: String
    let description: String
    let version: String
    let iconURL: URL?
    let downloadURL: URL
    let size: Int64?
    let date: String?
    var screenshots: [URL] = []
    /// Release notes of the latest version (AltStore `versions[0].localizedDescription`), when the source has them.
    var versionNotes: String? = nil
    /// Minimum iOS version declared by the source (`minOSVersion`), when present.
    var minOSVersion: String? = nil
    /// Source-declared category (AltStore `category`), when present. Never inferred.
    var category: String? = nil
    /// Only downloadable releases explicitly declared in this app's source versions array, in source order.
    var versions: [RepoAppVersion] = []

    var displayVersion: String {
        let value = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let bare = value.drop(while: { $0 == "v" || $0 == "V" })
        return bare.isEmpty ? "" : "v" + String(bare)
    }

    var hasVersionHistory: Bool { versions.count > 1 }

    /// A history selection must be a member of this exact app's decoded source, never a guessed/latest URL.
    func installURL(for release: RepoAppVersion? = nil) -> URL? {
        guard let release else { return downloadURL }
        return versions.contains(release) ? release.downloadURL : nil
    }
}

struct RepoAppVersion: Identifiable, Hashable, Sendable {
    var id: String { version + "|" + downloadURL.absoluteString }
    let version: String
    let downloadURL: URL
    let date: String?
    let size: Int64?
}

struct RepoNews: Identifiable, Sendable {
    let id: String
    let title: String
    let caption: String
    let imageURL: URL?
    let tint: String?
    let date: Date?
    let url: URL?
    let appID: String?
}

struct RepoSource: Codable, Identifiable, Hashable {
    /// Fixed identity of the built-in Mirsa source.
    static let canonicalID = "mirsa.canonical-source"
    /// Stable stored identity, independent of the URL, so exact same-URL duplicates stay separate rows.
    var uid: String = ""
    var id: String { uid.isEmpty ? url : uid }
    var isCanonical: Bool { uid == Self.canonicalID }
    var url: String
    var name: String
    var iconURL: String?
    var tint: String?
    var updated: Date?
    var appCount: Int = 0

    init(url: String, name: String, uid: String = UUID().uuidString) {
        self.url = url; self.name = name; self.uid = uid
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = (try? c.decode(String.self, forKey: .uid)) ?? ""   // old saves: assigned by MirsaSourceFeed.migrate
        url = try c.decode(String.self, forKey: .url)
        name = try c.decode(String.self, forKey: .name)
        iconURL = try? c.decode(String.self, forKey: .iconURL)
        tint = try? c.decode(String.self, forKey: .tint)
        updated = try? c.decode(Date.self, forKey: .updated)
        appCount = (try? c.decode(Int.self, forKey: .appCount)) ?? 0
    }
}

@MainActor
final class SourcesStore: ObservableObject {
    static let shared = SourcesStore()
    private let key = "mirsa.sources.v1"

    @Published var sources: [RepoSource] = [] { didSet { save(); catalogueRevision &+= 1 } }
    @Published var apps: [String: [RepoApp]] = [:] { didSet { catalogueRevision &+= 1 } }   // by source url
    @Published var presentation: [String: DecodedSource] = [:]
    @Published var loading: Set<String> = []
    @Published private(set) var loadErrors: [String: String] = [:]
    private var requests: [String: Task<Bool, Never>] = [:]
    typealias Loader = (URLRequest) async throws -> (Data, URLResponse)
    private let load: Loader
    @Published var error: String?
    @Published var updatingAll = false
    @Published var hiddenIDs: Set<String> = [] {
        didSet { defaults.set(Array(hiddenIDs), forKey: "mirsa.sources.hiddenIDs"); catalogueRevision &+= 1 }
    }

    // MARK: Render memo
    //
    // Source screens re-render on every AppsStore publish (download progress ticks several
    // times a second) and on every keystroke. Filtering/sorting a 10,000-app catalogue and
    // scanning every catalogue per installed app in `body` stalled scrolling. Results are
    // memoised per catalogue revision; nothing here is published, so reads stay side-effect free.
    private var catalogueRevision = 0
    private var memoRevision = -1
    private var memo: [String: Any] = [:]
    private func memoized<T>(_ key: String, _ compute: () -> T) -> T {
        if memoRevision != catalogueRevision || memo.count > 96 {
            memo.removeAll(keepingCapacity: true)
            memoRevision = catalogueRevision
        }
        if let hit = memo[key] as? T { return hit }
        let value = compute()
        memo[key] = value
        return value
    }
    /// Memoised derived value of one catalogue (category chips, grid pairs).
    func derived<T>(_ kind: String, url: String, query: String = "", _ compute: () -> T) -> T {
        memoized(kind + "\u{1F}" + url + "\u{1F}" + query, compute)
    }
    /// Delete awaiting confirmation. Nothing is removed until `confirmDelete()`.
    @Published var pendingDelete: RepoSource?
    private let defaults: UserDefaults

    func requestDelete(id: String) {
        guard let s = sources.first(where: { $0.id == id }), !s.isCanonical else { return }
        pendingDelete = s
    }
    func cancelDelete() { pendingDelete = nil }
    @discardableResult
    func confirmDelete() -> Bool {
        defer { pendingDelete = nil }
        guard let p = pendingDelete else { return false }
        return remove(id: p.id)
    }

    var visibleSources: [RepoSource] { sources.filter { !hiddenIDs.contains($0.id) } }
    var hiddenSources: [RepoSource] { sources.filter { hiddenIDs.contains($0.id) } }

    func moveVisible(from offsets: IndexSet, to destination: Int) {
        var reordered = visibleSources
        reordered.move(fromOffsets: offsets, toOffset: destination)
        var iterator = reordered.makeIterator()
        sources = sources.map { hiddenIDs.contains($0.id) ? $0 : iterator.next()! }
    }

    /// One candidate per installed app, visible source order breaks equal-version ties.
    func availableUpdates() -> [(RepoApp, AppLocation)] {
        // Bundle-ID index over the visible catalogues, in visible source order, built once per
        // revision instead of flattening every catalogue for every installed app on each render.
        let index: [String: [RepoApp]] = memoized("updates-index") {
            var index: [String: [RepoApp]] = [:]
            for source in visibleSources {
                for app in apps[source.url] ?? [] { index[app.bundleID, default: []].append(app) }
            }
            return index
        }
        return AppsStore.shared.apps.compactMap { installed in
            let candidates = (index[installed.id] ?? []).filter {
                $0.bundleID == installed.id && !$0.version.isEmpty &&
                $0.version.compare(installed.version, options: .numeric) == .orderedDescending
            }
            guard let newest = candidates.max(by: {
                $0.version.compare($1.version, options: .numeric) == .orderedAscending
            }) else { return nil }
            return (newest, installed.location)
        }
    }

    func updateAll() async {
        guard !updatingAll, AppsStore.shared.busy == nil else { return }
        updatingAll = true
        defer { updatingAll = false }
        await refreshAll()
        let queue = availableUpdates()
        for (app, location) in queue {
            guard !Task.isCancelled else { break }
            if !(await AppsStore.shared.installFromURL(app.downloadURL, location: location, appID: app.bundleID)) { break }
        }
    }


    /// Sources that ship with Mirsa: present on first launch (added once, so a
    /// user who deletes one keeps it deleted).
    static let alaaDefaults: [(url: String, name: String)] = [
        ("https://mirsa-app.duckdns.org/source.json", "Alaa IPA"),
        ("https://alaa-mirsa.duckdns.org/source2.json", "Alaa IPA 2"),
    ]
    static let builtIn: [(url: String, name: String)] = [
        ("https://repository.apptesters.org", "AppTesters IPA Repo"),
        (MirsaSourceFeed.primary, "Mirsa"),
        ("https://itslevii.dev/repo.json", "itslevii"),
        ("https://raw.githubusercontent.com/Sami-Wali/ryP0-repository/main/repo.json", "ryP0"),
    ] + alaaDefaults
    private let alaaSeededKey = "mirsa.sources.builtin.alaa.294"
    private let seededKey = "mirsa.sources.builtin.v2"

    init(defaults: UserDefaults = .standard, load: @escaping Loader = { try await URLSession.shared.data(for: $0) }) {
        self.defaults = defaults
        self.load = load
        hiddenIDs = Set(defaults.stringArray(forKey: "mirsa.sources.hiddenIDs") ?? [])
        var list: [RepoSource] = []
        if let d = defaults.data(forKey: key),
           let s = try? JSONDecoder().decode([RepoSource].self, from: d) { list = s }
        if !defaults.bool(forKey: seededKey) {
            for b in Self.builtIn where !list.contains(where: { MirsaSourceFeed.norm($0.url) == MirsaSourceFeed.norm(b.url) }) {
                list.append(RepoSource(url: b.url, name: b.name))
            }
            defaults.set(true, forKey: seededKey)
        }
        // Separate additive migration also reaches users who already seeded v2.
        // Keep existing rows, identities, order and hidden/deleted choices intact.
        if !defaults.bool(forKey: alaaSeededKey) {
            for b in Self.alaaDefaults where !list.contains(where: {
                MirsaSourceFeed.norm($0.url) == MirsaSourceFeed.norm(b.url)
            }) {
                list.append(RepoSource(url: b.url, name: b.name))
            }
            defaults.set(true, forKey: alaaSeededKey)
        }
        sources = MirsaSourceFeed.migrate(list)
        // Old builds hid sources by URL; carry that over to the stable ids once.
        if let old = defaults.stringArray(forKey: "mirsa.sources.hidden"), !old.isEmpty {
            for src in sources where old.contains(src.url) { hiddenIDs.insert(src.id) }
            defaults.removeObject(forKey: "mirsa.sources.hidden")
        }
        save()
    }

    /// Only the canonical built-in Mirsa source (fixed identity) is protected; every other row, including
    /// an exact same-URL or same-name duplicate, can be deleted on its own.
    func isProtected(_ source: RepoSource) -> Bool { source.isCanonical }

    /// Removes exactly one source by identity. The shared per-URL cache/loading state is only cleared
    /// when no remaining source uses that URL.
    @discardableResult
    func remove(id: String) -> Bool {
        guard let src = sources.first(where: { $0.id == id }), !src.isCanonical else { return false }
        sources.removeAll { $0.id == id }
        hiddenIDs.remove(id)
        if !sources.contains(where: { MirsaSourceFeed.norm($0.url) == MirsaSourceFeed.norm(src.url) }) {
            apps[src.url] = nil
            presentation[src.url] = nil
            requests[src.url]?.cancel()
            loadErrors[src.url] = nil
            loading.remove(src.url)
        }
        return true
    }

    private func save() {
        if let d = try? JSONEncoder().encode(sources) { defaults.set(d, forKey: key) }
    }

    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Accept altstore://source?url=… and sidestore://source?url=…
        if let c = URLComponents(string: s), ["altstore", "sidestore", "feather"].contains(c.scheme?.lowercased() ?? ""),
           let u = c.queryItems?.first(where: { $0.name == "url" })?.value { s = u }
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        guard let u = URL(string: s), u.host != nil else { return nil }
        return u
    }

    func add(_ raw: String) async -> Bool {
        guard let u = Self.normalize(raw) else { error = tr("That link isn't valid.", "الرابط مو صحيح."); return false }
        if sources.contains(where: { $0.url == u.absoluteString }) { return true }
        let new = RepoSource(url: u.absoluteString, name: u.host ?? "Source")
        sources.append(new)
        let ok = await refresh(u.absoluteString)
        if !ok { sources.removeAll { $0.id == new.id } }
        return ok
    }

    /// A persisted badge is metadata, not a loaded catalogue. Load each missing URL independently.
    func ensureLoaded(_ url: String) async {
        guard apps[url] == nil else { return }
        _ = await refresh(url)
    }

    func loadMissing() async {
        await withTaskGroup(of: Void.self) { group in
            for url in Set(visibleSources.map(\.url)) where apps[url] == nil {
                group.addTask { await self.ensureLoaded(url) }
            }
        }
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for url in Set(visibleSources.map(\.url)) {
                group.addTask { _ = await self.refresh(url) }
            }
        }
    }

    func listing(for url: String, query: String = "") -> [RepoApp] {
        let all = apps[url] ?? []
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return all }
        return derived("listing", url: url, query: term) {
            all.filter {
                $0.name.localizedCaseInsensitiveContains(term) || $0.developer.localizedCaseInsensitiveContains(term)
            }
        }
    }

    /// One source-owned request, not a child of the list screen's cancellable navigation task.
    /// Entering a detail page must not cancel the catalogue it is about to display.
    @discardableResult
    func refresh(_ url: String) async -> Bool {
        if let running = requests[url] { return await running.value }
        loading.insert(url)
        loadErrors[url] = nil
        let request = Task { @MainActor in
            defer { self.requests[url] = nil; self.loading.remove(url) }
            return await self.fetchSource(url)
        }
        requests[url] = request
        return await request.value
    }

    private func fetchSource(_ url: String) async -> Bool {
        do {
            guard let u = URL(string: url) else { throw URLError(.badURL) }
            if u.host?.contains("release-assets.githubusercontent.com") == true || u.host?.contains("objects.githubusercontent.com") == true {
                throw NSError(domain: "Mirsa", code: 0, userInfo: [NSLocalizedDescriptionKey:
                    tr("That's a temporary GitHub download link and it expires. Use the release link (github.com/…/releases/download/…) instead.",
                       "هاد رابط تحميل مؤقت من GitHub وبينتهي. استعمل رابط الإصدار github.com/…/releases/download/… بداله.")])
            }
            let data: Data, base: URL
            if MirsaSourceFeed.isOwned(url) {
                let feed = try await MirsaSourceFeed.fetch(load: load)
                data = feed.data; base = feed.url
            } else {
                var req = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
                req.setValue("Mirsa", forHTTPHeaderField: "User-Agent")
                let (bytes, response) = try await load(req)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw NSError(domain: "Mirsa", code: http.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: MirsaTr.f("sourceAnswered", http.statusCode)])
                }
                data = bytes; base = response.url ?? u
            }
            try Task.checkCancellation()
            // Full catalogues (including 10,098 AppTesters entries) are decoded off the UI actor.
            let parsed = try await Self.decodeSourceInBackground(data, base: base)
            try Task.checkCancellation()
            // Deleting a source while it loads must not resurrect its cache or row.
            guard sources.contains(where: { $0.url == url }) else { return false }
            apps[url] = parsed.apps
            presentation[url] = parsed
            loadErrors[url] = nil
            var refreshed = sources
            for i in refreshed.indices where refreshed[i].url == url {
                var source = refreshed[i]
                source.name = parsed.name ?? source.name
                source.iconURL = parsed.iconURL ?? source.iconURL
                source.tint = parsed.tint ?? source.tint
                source.updated = parsed.updated ?? source.updated
                source.appCount = parsed.apps.count
                refreshed[i] = source
            }
            // One persistence write and one row-list publication per catalogue.
            sources = refreshed
            return true
        } catch {
            guard sources.contains(where: { $0.url == url }) else { return false }
            let message = error.localizedDescription
            loadErrors[url] = message
            self.error = message
            return false
        }
    }

    struct DecodedSource: Sendable {
        let apps: [RepoApp]
        let name: String?
        let iconURL: String?
        let tint: String?
        let updated: Date?
        let headerURL: URL?
        let subtitle: String?
        let description: String?
        let website: URL?
        let news: [RepoNews]
    }

    /// Source content is untrusted. Never open executable/custom URL schemes or credential URLs.
    nonisolated static func contentURL(_ raw: Any?, base: URL) -> URL? {
        guard let text = raw as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let resolved = URL(string: text, relativeTo: base)?.absoluteURL else { return nil }
        guard let scheme = resolved.scheme?.lowercased(), ["http", "https"].contains(scheme),
              resolved.host?.isEmpty == false, resolved.user == nil, resolved.password == nil else { return nil }
        return resolved
    }

    /// Detached work never inherits the store's main actor, even for immediate/cache loaders.
    nonisolated static func decodeSourceInBackground(_ data: Data, base: URL) async throws -> DecodedSource {
        try await Task.detached(priority: .userInitiated) {
            assert(!Thread.isMainThread, "Source catalogue decoding must stay off the UI thread")
            return try decodeSource(data, base: base)
        }.value
    }

    nonisolated static func decodeSource(_ data: Data, base: URL) throws -> DecodedSource {
        let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let root = (json as? [String: Any]) ?? ((json as? [Any]).map { ["apps": $0] })
        guard let root else { throw URLError(.cannotParseResponse) }
        let parsed = parseApps(root, base: base)
        let meta = (root["META"] as? [String: Any]) ?? (root["meta"] as? [String: Any]) ?? [:]
        return DecodedSource(apps: parsed,
            name: (root["name"] as? String) ?? (meta["repoName"] as? String) ?? (meta["name"] as? String),
            iconURL: (root["iconURL"] as? String) ?? (root["icon"] as? String) ?? (meta["repoIcon"] as? String),
            tint: (root["tintColor"] as? String) ?? (root["tint"] as? String),
            // Feeds repeat dates across thousands of apps. Parse each distinct date only once.
            updated: Set(parsed.compactMap(\.date)).compactMap(Self.date).max(),
            headerURL: contentURL(root["headerURL"], base: base),
            subtitle: root["subtitle"] as? String,
            description: (root["description"] as? String) ?? (root["localizedDescription"] as? String),
            website: contentURL(root["website"], base: base),
            news: ((root["news"] as? [Any]) ?? []).enumerated().compactMap { index, value in
                guard let item = value as? [String: Any],
                      let title = item["title"] as? String,
                      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return RepoNews(id: "\(index)|\(item["identifier"] as? String ?? title)", title: title,
                    caption: item["caption"] as? String ?? "",
                    imageURL: contentURL(item["imageURL"], base: base), tint: item["tintColor"] as? String,
                    date: (item["date"] as? String).flatMap(Self.date),
                    url: contentURL(item["url"], base: base), appID: item["appID"] as? String)
            })
    }

    nonisolated static func date(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    nonisolated static func parseApps(_ root: [String: Any], base: URL) -> [RepoApp] {
        // AltStore / SideStore / Feather / ESign: "apps". Scarlet and others:
        // apps grouped in arrays under any key. A bare array also works.
        var list: [[String: Any]] = []
        let appKeys = ["apps", "Apps", "applications", "items", "data"]
        for k in appKeys { if let a = root[k] as? [Any] { list = a.compactMap { $0 as? [String: Any] }; break } }
        if list.isEmpty {
            for (k, v) in root where k != "news" && k != "featuredApps" {
                if let a = v as? [Any] { list += a.compactMap { $0 as? [String: Any] } }
                if let d = v as? [String: Any], let a = d["apps"] as? [Any] { list += a.compactMap { $0 as? [String: Any] } }
            }
        }
        func url(_ v: Any?) -> URL? {
            guard let raw = v as? String else { return nil }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let url = URL(string: text, relativeTo: base)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
                  url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
            return url
        }
        func str(_ d: [String: Any], _ keys: String...) -> String? {
            for k in keys { if let s = d[k] as? String, !s.isEmpty { return s } }
            return nil
        }
        func int(_ v: Any?) -> Int64? {
            if let n = v as? NSNumber { return n.int64Value }
            if let s = v as? String { return Int64(s) }
            return nil
        }
        var seen = Set<String>()
        var explicitBundle = Set<String>()
        let entries: [RepoApp] = list.compactMap { a -> RepoApp? in
            // Decode mixed/malformed arrays entry by entry, never discard the entire history.
            let declared = ((a["versions"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
            let dlKeys = ["downloadURL", "downloadUrl", "download_url", "down", "download", "ipa", "ipaURL", "ipa_url", "link", "url"]
            func downloadURL(_ entry: [String: Any]) -> URL? {
                dlKeys.lazy.compactMap { url(entry[$0]) }.first
            }
            let latest = declared.first {
                downloadURL($0) != nil && str($0, "version")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            } ?? declared.first { downloadURL($0) != nil }
            // A historical release must supply its OWN URL and version. Never inherit the latest file or metadata.
            var releaseIDs = Set<String>()
            let releases: [RepoAppVersion] = declared.compactMap { entry in
                guard let version = str(entry, "version")?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !version.isEmpty, let download = downloadURL(entry) else { return nil }
                let bytes = int(entry["size"]) ?? int(entry["fileSize"])
                let release = RepoAppVersion(version: version, downloadURL: download,
                    date: str(entry, "date", "versionDate"), size: bytes.flatMap { $0 > 0 ? $0 : nil })
                return releaseIDs.insert(release.id).inserted ? release : nil
            }
            let dl = latest.flatMap(downloadURL) ?? downloadURL(a)
            guard let dl else { return nil }
            let name = str(a, "name", "title") ?? "App"
            if let b = str(a, "bundleIdentifier", "bundleID", "bundleId", "bundle", "identifier", "bundle_id") { explicitBundle.insert(b) }
            let app = RepoApp(
                name: name,
                bundleID: str(a, "bundleIdentifier", "bundleID", "bundleId", "bundle", "identifier", "bundle_id") ?? name,
                developer: str(a, "developerName", "developer", "dev", "author") ?? "",
                subtitle: str(a, "subtitle") ?? "",
                description: str(a, "localizedDescription", "description", "desc", "subtitle") ?? "",
                version: (latest.flatMap { str($0, "version") }) ?? str(a, "version") ?? "",
                iconURL: url(a["iconURL"]) ?? url(a["icon"]) ?? url(a["iconUrl"]) ?? url(a["image"]) ?? url(a["icon_url"]),
                downloadURL: dl,
                size: int(latest?["size"]) ?? int(a["size"]) ?? int(a["fileSize"]),
                date: (latest.flatMap { str($0, "date") }) ?? str(a, "versionDate", "date", "updated"),
                screenshots: ScreenshotPolicy.sourceScreenshots(a, latest: latest, base: base),
                versionNotes: (latest.flatMap { str($0, "localizedDescription", "changelog", "whatsNew") })
                    ?? str(a, "versionDescription", "changelog", "whatsNew"),
                minOSVersion: (latest.flatMap { str($0, "minOSVersion", "minimumOSVersion") }) ?? str(a, "minOSVersion", "minimumOSVersion", "minOS"),
                category: str(a, "category", "genre"),
                versions: releases
            )
            return app
        }
        return groupByBundle(entries, explicit: explicitBundle).filter { seen.insert($0.id).inserted }
    }

    /// One card per source-scoped bundle ID. Dictionary grouping, O(n); only multi-entry groups are sorted.
    nonisolated static func groupByBundle(_ entries: [RepoApp], explicit: Set<String>) -> [RepoApp] {
        var order: [String] = []
        var groups: [String: [(Int, RepoApp)]] = [:]
        var out: [Int: RepoApp] = [:]
        for (i, e) in entries.enumerated() {
            if explicit.contains(e.bundleID) {
                if groups[e.bundleID] == nil { order.append(e.bundleID) }
                groups[e.bundleID, default: []].append((i, e))
            } else { out[i] = e }
        }
        var slots: [(Int, RepoApp)] = out.map { ($0.key, $0.value) }
        for key in order {
            let g = groups[key]!
            if g.count == 1 { slots.append((g[0].0, g[0].1)); continue }
            var seenRel = Set<String>(); var merged: [(Int, RepoAppVersion)] = []
            var parsed: [String: Date?] = [:]   // each distinct date string parsed once
            func when(_ r: RepoAppVersion) -> Date {
                guard let raw = r.date else { return .distantPast }
                if let hit = parsed[raw] { return hit ?? .distantPast }
                let d = Self.date(raw); parsed[raw] = .some(d); return d ?? .distantPast
            }
            for (i, e) in g {
                var rels = e.versions
                // Legacy entries (no versions[]) contribute their own version/URL/date/size.
                if !e.version.isEmpty { rels.append(RepoAppVersion(version: e.version, downloadURL: e.downloadURL, date: e.date, size: e.size.flatMap { $0 > 0 ? $0 : nil })) }
                for r in rels where seenRel.insert(r.id).inserted { merged.append((i, r)) }
            }
            let ranked = merged.sorted { l, r in
                let ld = when(l.1), rd = when(r.1)
                if ld != rd { return ld > rd }
                let c = l.1.version.compare(r.1.version, options: .numeric)
                if c != .orderedSame { return c == .orderedDescending }
                return l.0 < r.0
            }
            let newest = ranked[0].1
            // Card metadata comes from the entry that owns the newest release.
            let owner = g.first { $0.1.downloadURL == newest.downloadURL && $0.1.version == newest.version }?.1 ?? g.first { $0.1.versions.contains(newest) }?.1 ?? g[0].1
            let card = RepoApp(name: owner.name, bundleID: owner.bundleID, developer: owner.developer, subtitle: owner.subtitle,
                description: owner.description, version: newest.version, iconURL: owner.iconURL, downloadURL: newest.downloadURL,
                size: newest.size ?? owner.size, date: newest.date ?? owner.date, screenshots: owner.screenshots,
                versionNotes: owner.versionNotes, minOSVersion: owner.minOSVersion, category: owner.category, versions: ranked.map(\.1))
            slots.append((g[0].0, card))
        }
        return slots.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

extension Color {
    init?(hex: String?) {
        guard var h = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - Views

struct SourcesTab: View {
    var onSelectIPA: ((URL) async throws -> Void)? = nil
    @StateObject private var store: SourcesStore
    @ObservedObject private var installedApps = AppsStore.shared
    @State private var adding = false
    @State private var sharingURL: URL?
    @State private var input = ""
    @State private var searching = false
    @State private var query = ""
    @State private var editMode: EditMode = .inactive
    @AppStorage(SourcesTheme.key) private var themeRaw = SourcesTheme.aurora.rawValue
    private var theme: SourcesTheme { SourcesTheme(rawValue: themeRaw) ?? .aurora }

    init(onSelectIPA: ((URL) async throws -> Void)? = nil, store: SourcesStore = .shared) {
        self.onSelectIPA = onSelectIPA
        _store = StateObject(wrappedValue: store)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isFiltering: Bool { !trimmedQuery.isEmpty }
    /// Search shows app matches only; clearing restores the sortable source list.
    private var shownSources: [RepoSource] { isFiltering ? [] : store.visibleSources }
    private var appMatches: [DiscoveryStore.Match] { store.appMatches(query: trimmedQuery) }

    var body: some View {
        let t = theme
        NavigationStack {
            List {
                Group {
                    header(t)
                    if searching {
                        SourcesSearchField(placeholder: SourcesText.searchApps, theme: t, text: $query, identifier: "sources-list-search")
                    }
                    if !store.visibleSources.isEmpty {
                        statsCard(t)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: MirsaSpacing.page, bottom: 6, trailing: MirsaSpacing.page))
                .moveDisabled(true)
                .deleteDisabled(true)

                if store.sources.isEmpty {
                    Text(tr("Add a source link (AltStore, SideStore or Feather format) to browse its apps.",
                            "ضيف رابط سورس (بصيغة AltStore أو SideStore أو Feather) لتتصفّح تطبيقاته."))
                        .foregroundStyle(t.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if !isFiltering && (!store.availableUpdates().isEmpty || store.updatingAll) {
                    Button {
                        Task { await store.updateAll() }
                    } label: {
                        Label(store.updatingAll ? tr("Updating apps…", "عم يحدّث التطبيقات…") : tr("Update All", "تحديث الكل"),
                              systemImage: "arrow.down.circle")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(t.accentGradient))
                    }
                    .buttonStyle(.mirsaPress)
                    .disabled(store.updatingAll || AppsStore.shared.busy != nil)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: MirsaSpacing.page, bottom: 4, trailing: MirsaSpacing.page))
                }
                ForEach(shownSources) { s in
                    // The row is the card; the link stays invisible so the system chevron
                    // no longer floats outside the card.
                    ZStack {
                        NavigationLink { SourceDetailView(source: s, store: store, onSelectIPA: onSelectIPA) } label: { EmptyView() }.opacity(0)
                        SourceRow(source: s, loading: store.loading.contains(s.url), theme: t)
                    }
                        .deleteDisabled(store.isProtected(s))
                        .moveDisabled(isFiltering)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 5, leading: MirsaSpacing.page, bottom: 5, trailing: MirsaSpacing.page))
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .leading) {
                            Button { store.hiddenIDs.insert(s.id) } label: {
                                Label(tr("Hide", "إخفاء"), systemImage: "eye.slash")
                            }.tint(.orange)
                            SourceURLButtons(stored: s.url, sharing: $sharingURL).tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !store.isProtected(s) {
                                Button(role: .destructive) { store.requestDelete(id: s.id) } label: {
                                    Label(tr("Delete", "حذف", ckb: "سڕینەوە", kmr: "Jêbirin"), systemImage: "trash")
                                }.tint(.red)
                            }
                            SourceURLButtons(stored: s.url, sharing: $sharingURL).tint(.blue)
                        }
                        .contextMenu {
                            SourceURLButtons(stored: s.url, sharing: $sharingURL)
                            Button { store.hiddenIDs.insert(s.id) } label: {
                                Label(tr("Hide source", "إخفاء السورس"), systemImage: "eye.slash")
                            }
                        }
                }
                // Rows are move-disabled while a search filter is active; the guard keeps offsets honest.
                .onMove { from, to in
                    guard !isFiltering else { return }
                    store.moveVisible(from: from, to: to)
                }
                .onDelete { offsets in
                    // Edit-mode delete goes through the same confirmation; protected source is skipped.
                    let list = shownSources
                    if let first = offsets.compactMap({ list.indices.contains($0) ? list[$0] : nil }).first(where: { !store.isProtected($0) }) {
                        store.requestDelete(id: first.id)
                    }
                }
                if isFiltering {
                    if !store.loading.isEmpty {
                        ProgressView().listRowBackground(Color.clear)
                    }
                    ForEach(appMatches) { match in
                        DiscoveryAppResultRow(match: match, onSelectIPA: onSelectIPA)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    if appMatches.isEmpty && store.loading.isEmpty {
                        Text(tr("No matching apps.", "ما لقيت تطبيقات بهالاسم."))
                            .foregroundStyle(t.secondary).listRowBackground(Color.clear)
                    }
                    ForEach(store.visibleSources.filter { store.loadErrors[$0.url] != nil }) { source in
                        Text(source.name + " · " + (store.loadErrors[source.url] ?? ""))
                            .font(.caption).foregroundStyle(.orange).listRowBackground(Color.clear)
                    }
                }
                if !isFiltering && !store.hiddenSources.isEmpty {
                    Section {
                        ForEach(store.hiddenSources) { source in
                            HStack {
                                Text(source.name).foregroundStyle(t.text)
                                    .mirsaNaturalDirection(source.name)
                                Spacer()
                                Button {
                                    store.hiddenIDs.remove(source.id)
                                    Task { await store.refresh(source.url) }
                                } label: {
                                    Label(tr("Unhide", "إظهار"), systemImage: "eye")
                                }
                                .buttonStyle(.borderless)
                            }
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        Text(tr("Hidden Sources", "السورسات المخفية")).foregroundStyle(t.secondary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .mirsaHidesScrollEdgeEffect()
            // Inset the content, not the viewport: cards scroll behind the dock
            // while the complete last row can still rest above it.
            .mirsaDockClearance()
            .ignoresSafeArea(.container, edges: .bottom)
            .environment(\.editMode, $editMode)
            .environment(\.defaultMinListRowHeight, 44)
            .refreshable { await store.refreshAll() }
            .background(SourcesThemeBackground(theme: t))
            .mirsaStatusBarScrim()
            .navigationTitle(SourcesText.title)
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog(tr("Delete this source?", "تحذف هالسورس؟", ckb: "ئەم سەرچاوەیە بسڕدرێتەوە؟", kmr: "Ev çavkanî were jêbirin?"), isPresented: Binding(get: { store.pendingDelete != nil }, set: { if !$0 { store.cancelDelete() } }), titleVisibility: .visible, presenting: store.pendingDelete) { src in
                Button(tr("Delete", "حذف", ckb: "سڕینەوە", kmr: "Jêbirin"), role: .destructive) { store.confirmDelete() }
                Button(tr("Cancel", "إلغاء", ckb: "پاشگەزبوونەوە", kmr: "Betal"), role: .cancel) { store.cancelDelete() }
            } message: { src in
                Text(src.name + " — " + tr("Apps already installed stay installed.", "التطبيقات المثبّتة بتضل مثبّتة.", ckb: "ئەو ئەپانەی دامەزراون وەک خۆیان دەمێننەوە.", kmr: "Sepanên ku hatine saz kirin dimînin."))
            }
            .sheet(item: Binding(get: { sharingURL.map { SharedSourceURL(url: $0) } }, set: { if $0 == nil { sharingURL = nil } })) { SourceShareSheet(url: $0.url).presentationDetents([.medium, .large]) }
            .alert(tr("Add Source", "أضف سورس"), isPresented: $adding) {
                TextField("https://…/source.json", text: $input)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button(tr("Cancel", "إلغاء"), role: .cancel) {}
                Button(tr("Add", "أضف")) { let t = input; Task { _ = await store.add(t) } }
            }
            .alert(tr("Source", "السورس"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button(MirsaTr.lit("OK")) { store.error = nil }
            } message: { Text(store.error ?? "") }
            .task { await store.loadMissing() }
        }
        .tint(t.accent[0])
        .environment(\.colorScheme, t.colorScheme)
        .environment(\.sourcesTheme, t)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func header(_ t: SourcesTheme) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(SourcesText.library)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(t.secondary)
                    .lineLimit(1)
                Text(SourcesText.title)
                    .font(MirsaFont.pageTitle)
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 4)
            SourcesThemeMenu()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    searching.toggle()
                    if !searching { query = "" }
                }
            } label: { SourcesCircleLabel(systemName: searching ? "xmark" : "magnifyingglass", theme: t) }
            .buttonStyle(.mirsaPress)
            .accessibilityLabel(SourcesText.searchApps)
            .accessibilityIdentifier("sources-search-toggle")
            if editMode.isEditing {
                Button { withAnimation { editMode = .inactive } } label: {
                    Text(SourcesText.done)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(t.text)
                        .padding(.horizontal, 14).frame(height: 42)
                        .background(Capsule().fill(t.card).overlay(Capsule().stroke(t.stroke)))
                }
                .buttonStyle(.mirsaPress)
                .accessibilityIdentifier("sources-edit-done")
            } else {
                Menu {
                    Button { withAnimation { editMode = .active } } label: {
                        Label(SourcesText.edit, systemImage: "arrow.up.arrow.down")
                    }
                } label: { SourcesCircleLabel(systemName: "ellipsis", theme: t) }
                .accessibilityIdentifier("sources-more-menu")
            }
            Button { input = UIPasteboard.general.string ?? ""; adding = true } label: {
                SourcesCircleLabel(systemName: "plus", theme: t, filled: true)
            }
            .buttonStyle(.mirsaPress)
            .accessibilityLabel(SourcesText.addSource)
            .accessibilityIdentifier("sources-add")
        }
        .padding(.top, 8)
    }

    private func statsCard(_ t: SourcesTheme) -> some View {
        let visible = store.visibleSources
        let total = visible.reduce(0) { $0 + $1.appCount }
        let updatedToday = visible.filter { source in source.updated.map { Calendar.current.isDateInToday($0) } ?? false }.count
        return HStack(spacing: 0) {
            stat(visible.count.formatted(), SourcesText.statSources, t)
            Rectangle().fill(t.stroke).frame(width: 1, height: 36)
            stat(total.formatted(), SourcesText.statApps, t)
            Rectangle().fill(t.stroke).frame(width: 1, height: 36)
            stat(updatedToday.formatted(), SourcesText.statUpdatedToday, t, color: t.success)
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [t.accent[0].opacity(t.isLight ? 0.18 : 0.35), t.accent[1].opacity(t.isLight ? 0.08 : 0.15)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(t.stroke))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sources-stats")
    }

    private func stat(_ value: String, _ label: String, _ t: SourcesTheme, color: Color? = nil) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold)).monospacedDigit()
                .foregroundStyle(color ?? t.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 11)).foregroundStyle(t.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SourceRow: View {
    let source: RepoSource
    let loading: Bool
    let theme: SourcesTheme
    var body: some View {
        let tint = Color(hex: source.tint) ?? Color(red: 0.45, green: 0.38, blue: 0.95)
        HStack(spacing: 12) {
            RemoteIcon(url: source.iconURL.flatMap(URL.init(string:)), size: 48, corner: MirsaRadius.icon)
                .shadow(color: tint.opacity(0.45), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(source.name).font(.system(size: 15.5, weight: .bold)).foregroundStyle(theme.text)
                        .lineLimit(1)
                        .mirsaNaturalDirection(source.name)
                    if SourcesDates.isRecent(source.updated) {
                        Text(SourcesText.newBadge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(sourcesRGB: 0x04210F))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(sourcesRGB: 0x22C55E)))
                            .fixedSize()
                            .accessibilityIdentifier("source-new-badge")
                    }
                }
                if let d = source.updated {
                    Text(SourcesText.lastUpdated + " · " + d.formatted(date: .numeric, time: .omitted))
                        .font(.system(size: 11.5)).foregroundStyle(theme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: MirsaSpacing.xs)
            if loading { ProgressView().tint(theme.text) }
            else {
                VStack(spacing: 0) {
                    Text(source.appCount.formatted()).font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(theme.text).lineLimit(1).fixedSize()
                    Text(SourcesText.statApps).font(.system(size: 9.5)).foregroundStyle(theme.secondary).lineLimit(1)
                }
            }
        }
        .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 10)
        .sourcesGlass(theme, radius: 20)
        .overlay(alignment: .leading) {
            Capsule().fill(tint).frame(width: 3).padding(.vertical, 14)
        }
        // No fade-in here: List rows are re-created as they scroll back on screen, so the
        // one-shot appear animation replayed on every row while scrolling (visible pop/stutter).
    }
}

/// Two apps per list row, so a 10,000-app catalogue keeps the List's lazy row loading.
private struct SourceAppPair: Identifiable {
    let id: String
    let apps: [RepoApp]
}

struct SourceDetailView: View {
    let source: RepoSource
    var onSelectIPA: ((URL) async throws -> Void)? = nil
    @ObservedObject private var store: SourcesStore
    @ObservedObject private var apps = AppsStore.shared
    @State private var query = ""
    @State private var category: String?
    /// nil = automatic (grid for large catalogues), otherwise the user's choice for this page.
    @State private var gridOverride: Bool?
    @State private var newThisWeek: Int?
    @State private var sharingURL: URL?
    @Environment(\.openURL) private var openURL
    @AppStorage(SourcesTheme.key) private var themeRaw = SourcesTheme.aurora.rawValue
    private var theme: SourcesTheme { SourcesTheme(rawValue: themeRaw) ?? .aurora }

    /// Catalogues with at least this many apps open as a two-column grid with stat boxes.
    static let largeCatalogue = 40

    init(source: RepoSource, store: SourcesStore = .shared, onSelectIPA: ((URL) async throws -> Void)? = nil) {
        self.source = source
        self.store = store
        self.onSelectIPA = onSelectIPA
    }

    /// Category chips only exist when the source itself declares at least two categories.
    static func categories(_ apps: [RepoApp]) -> [String] {
        var seen = Set<String>()
        for app in apps {
            if let c = app.category?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty { seen.insert(c) }
        }
        return seen.count >= 2 ? seen.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } : []
    }

    var body: some View {
        let t = theme
        let all = store.listing(for: source.url)
        let categories = store.derived("categories", url: source.url) { Self.categories(all) }
        let activeCategory = category.flatMap { categories.contains($0) ? $0 : nil }
        let searched = store.listing(for: source.url, query: query)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = activeCategory.map { c in
            store.derived("category:" + c, url: source.url, query: trimmed) {
                searched.filter { $0.category?.trimmingCharacters(in: .whitespacesAndNewlines) == c }
            }
        } ?? searched
        let large = all.count >= Self.largeCatalogue
        let grid = gridOverride ?? large
        List {
            Group {
                sourceHeader(t, all: all, large: large)
                searchRow(t, grid: grid, hasApps: !all.isEmpty)
                if !categories.isEmpty {
                    categoryChips(categories, active: activeCategory, t: t)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: MirsaSpacing.page, bottom: 6, trailing: MirsaSpacing.page))

            if grid {
                ForEach(store.derived("pairs:" + (activeCategory ?? ""), url: source.url, query: trimmed) { Self.pairs(shown) }) { pair in
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(pair.apps) { app in
                            RepoAppRow(app: app, installed: apps.apps.first { $0.id == app.bundleID }, onSelectIPA: onSelectIPA,
                                       style: .tile, sourceName: currentSource.name)
                        }
                        if pair.apps.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: MirsaSpacing.page, bottom: 5, trailing: MirsaSpacing.page))
                }
            } else {
                ForEach(shown) { app in
                    RepoAppRow(app: app, installed: apps.apps.first { $0.id == app.bundleID }, onSelectIPA: onSelectIPA,
                               sourceName: currentSource.name)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(t.stroke)
                        .listRowInsets(EdgeInsets(top: 8, leading: MirsaSpacing.page, bottom: 8, trailing: MirsaSpacing.page))
                }
            }
            Group {
                if store.loading.contains(source.url) || (store.apps[source.url] == nil && store.loadErrors[source.url] == nil) {
                    ProgressView(tr("Loading source…", "عم تتحمّل تطبيقات السورس…", ckb: "ئەپەکانی سەرچاوە بار دەکرێن…", kmr: "Sepanên çavkaniyê tên barkirin…"))
                        .tint(t.text)
                        .foregroundStyle(t.secondary)
                } else if let message = store.loadErrors[source.url] {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr("Couldn't load this source.", "ما قدرت حمّل تطبيقات هالسورس.", ckb: "نەتوانرا ئەپەکانی سەرچاوە بار بکرێن.", kmr: "Sepanên vê çavkaniyê nehatin barkirin."))
                            .foregroundStyle(t.text)
                        Text(message).font(.caption).foregroundStyle(t.secondary)
                        Button(tr("Try again", "جرّب كمان مرة", ckb: "دووبارە هەوڵ بدە", kmr: "Dîsa biceribîne")) { Task { await store.refresh(source.url) } }
                            .buttonStyle(.borderless)
                    }
                } else if all.isEmpty {
                    Text(tr("No apps in this source.", "ما في تطبيقات بهالسورس.", ckb: "هیچ ئەپێک لەم سەرچاوەیە نییە.", kmr: "Di vê çavkaniyê de sepan tune ne."))
                        .foregroundStyle(t.secondary)
                } else if shown.isEmpty {
                    Text(tr("No matching apps.", "ما لقيت تطبيقات بهالاسم.", ckb: "هیچ ئەپێکی گونجاو نەدۆزرایەوە.", kmr: "Sepanên lihevhatî nehatin dîtin."))
                        .foregroundStyle(t.secondary)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
            .mirsaHidesScrollEdgeEffect()
            // Inset the content, not the viewport: cards scroll behind the dock
            // while the complete last row can still rest above it.
            .mirsaDockClearance()
            .ignoresSafeArea(.container, edges: .bottom)
        .background(SourcesThemeBackground(theme: t, glowTint: large ? sourceTint : t.accent[0]))
        .task(id: source.url) { await store.ensureLoaded(source.url) }
        .task(id: "\(source.url)|\(all.count)") { await countNewThisWeek(all) }
        .refreshable { await store.refresh(source.url) }
        .navigationTitle(currentSource.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    SourceURLButtons(stored: currentSource.url, sharing: $sharingURL)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(SourcesText.shareSource)
                .accessibilityIdentifier("source-detail-share")
            }
        }
        .sheet(item: Binding(get: { sharingURL.map { SharedSourceURL(url: $0) } }, set: { if $0 == nil { sharingURL = nil } })) {
            SourceShareSheet(url: $0.url).presentationDetents([.medium, .large])
        }
        .tint(t.accent[0])
        .environment(\.colorScheme, t.colorScheme)
        .environment(\.sourcesTheme, t)
    }

    private var currentSource: RepoSource { store.sources.first { $0.id == source.id } ?? source }
    private var sourceTint: Color { Color(hex: currentSource.tint) ?? theme.accent[0] }

    private static func pairs(_ list: [RepoApp]) -> [SourceAppPair] {
        stride(from: 0, to: list.count, by: 2).map { i in
            let chunk = Array(list[i..<min(i + 2, list.count)])
            return SourceAppPair(id: chunk.map(\.id).joined(separator: "||"), apps: chunk)
        }
    }

    /// Counts apps whose version date (from the source) falls in the last 7 days. Off the main actor for big catalogues.
    private func countNewThisWeek(_ all: [RepoApp]) async {
        let dates = all.compactMap(\.date)
        guard !dates.isEmpty else { newThisWeek = nil; return }
        let count = await Task.detached(priority: .utility) { () -> Int in
            let now = Date()
            let cutoff = now.addingTimeInterval(-7 * 86_400)
            let future = now.addingTimeInterval(86_400)
            var n = 0
            for raw in dates {
                if let d = SourcesStore.date(raw), d >= cutoff, d <= future { n += 1 }
            }
            return n
        }.value
        guard !Task.isCancelled else { return }
        newThisWeek = count
    }

    @ViewBuilder
    private func sourceHeader(_ t: SourcesTheme, all: [RepoApp], large: Bool) -> some View {
        let metadata = store.presentation[source.url]
        VStack(alignment: large ? .leading : .center, spacing: 0) {
            if let url = metadata?.headerURL {
                sourceImage(url, height: 132)
                    .accessibilityIdentifier("source-detail-banner")
                    .padding(.bottom, 14)
            }
            if large {
                HStack(spacing: 14) {
                    RemoteIcon(url: SourceURLAction.shareableURL(currentSource.iconURL ?? ""), size: 72, corner: 18)
                        .shadow(color: sourceTint.opacity(0.5), radius: 14, y: 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(currentSource.name).font(.system(size: 24, weight: .bold)).foregroundStyle(t.text)
                            .lineLimit(2).minimumScaleFactor(0.8)
                            .mirsaNaturalDirection(currentSource.name)
                        if let subtitle = metadata?.subtitle, !subtitle.isEmpty {
                            Text(subtitle).font(.system(size: 12.5)).foregroundStyle(t.secondary).lineLimit(2)
                                .mirsaNaturalDirection(subtitle)
                        }
                        websiteLink(metadata?.website, t: t, compact: true)
                    }
                    Spacer(minLength: 0)
                }
                if let description = metadata?.description, !description.isEmpty {
                    Text(description).font(.system(size: 12.5)).foregroundStyle(t.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .mirsaNaturalParagraph(description)
                        .padding(.top, 10)
                }
                HStack(spacing: 8) {
                    statBox(all.count.formatted(), SourcesText.statApps, t)
                    if let updated = currentSource.updated {
                        statBox(SourcesDates.label(updated), SourcesText.lastUpdated, t)
                    }
                    if let n = newThisWeek, n > 0 {
                        statBox("+" + n.formatted(), SourcesText.newThisWeek, t, color: t.success)
                    }
                }
                .padding(.top, 12)
            } else {
                RemoteIcon(url: SourceURLAction.shareableURL(currentSource.iconURL ?? ""), size: 96, corner: 26)
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.2)))
                    .shadow(color: t.accent[0].opacity(0.55), radius: 18, y: 6)
                    .padding(.top, 8)
                Text(currentSource.name).font(.system(size: 30, weight: .bold)).foregroundStyle(t.text)
                    .multilineTextAlignment(.center)
                    .mirsaNaturalDirection(currentSource.name)
                    .padding(.top, 10)
                if let subtitle = metadata?.subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12.5)).foregroundStyle(t.secondary)
                        .multilineTextAlignment(.center)
                        .mirsaNaturalDirection(subtitle)
                }
                if let description = metadata?.description, !description.isEmpty {
                    Text(description).font(.system(size: 13)).foregroundStyle(t.text.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .mirsaNaturalDirection(description)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8).padding(.horizontal, 10)
                }
                HStack(spacing: 8) {
                    websiteLink(metadata?.website, t: t, compact: false)
                    if !all.isEmpty {
                        chip(Label(all.count.formatted(), systemImage: "square.grid.2x2"), t: t)
                    }
                    if let updated = currentSource.updated {
                        chip(Label(SourcesDates.label(updated), systemImage: "clock"), t: t)
                    }
                }
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: large ? .leading : .center)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("source-detail-header")
    }

    @ViewBuilder
    private func websiteLink(_ website: URL?, t: SourcesTheme, compact: Bool) -> some View {
        if let website {
            Link(destination: website) {
                if compact {
                    Label(website.host ?? website.absoluteString, systemImage: "arrow.up.right")
                        .font(.system(size: 12)).foregroundStyle(t.secondary).lineLimit(1)
                } else {
                    chip(Label(website.host ?? website.absoluteString, systemImage: "link"), t: t)
                }
            }
            .accessibilityIdentifier("source-detail-website")
        }
    }

    private func chip<C: View>(_ content: C, t: SourcesTheme) -> some View {
        content
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(t.text)
            .lineLimit(1)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .sourcesGlassCapsule(t)
    }

    private func statBox(_ value: String, _ label: String, _ t: SourcesTheme, color: Color? = nil) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 17, weight: .bold)).foregroundStyle(color ?? t.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 10.5)).foregroundStyle(t.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 9)
        .sourcesGlass(t, radius: 16)
    }

    private func searchRow(_ t: SourcesTheme, grid: Bool, hasApps: Bool) -> some View {
        HStack(spacing: 8) {
            SourcesSearchField(placeholder: SourcesText.searchApps, theme: t, text: $query, identifier: "source-app-search")
            if hasApps {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { gridOverride = !grid }
                } label: {
                    SourcesCircleLabel(systemName: grid ? "list.bullet" : "square.grid.2x2", theme: t)
                }
                .buttonStyle(.mirsaPress)
                .accessibilityLabel(grid ? SourcesText.list : SourcesText.grid)
                .accessibilityIdentifier("source-layout-toggle")
            }
        }
    }

    private func categoryChips(_ categories: [String], active: String?, t: SourcesTheme) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                categoryButton(SourcesText.all, selected: active == nil, t: t) { category = nil }
                ForEach(categories, id: \.self) { c in
                    categoryButton(c.capitalized, selected: active == c, t: t) { category = c }
                }
            }
        }
        .accessibilityIdentifier("source-categories")
    }

    private func categoryButton(_ title: String, selected: Bool, t: SourcesTheme, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            Text(title).font(.system(size: 13, weight: .bold))
                .foregroundStyle(selected ? (t.isLight ? Color.white : Color(sourcesRGB: 0x1A1238)) : t.text)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background {
                    if selected {
                        Capsule().fill(t.isLight ? AnyShapeStyle(t.accentGradient) : AnyShapeStyle(Color.white))
                    } else {
                        Capsule().fill(t.card).overlay(Capsule().stroke(t.stroke))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sourceImage(_ url: URL, height: CGFloat) -> some View {
        MirsaRemoteImage(url: url, maxPixel: 1200) {
            Rectangle().fill(sourceTint.opacity(0.12)).overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .frame(height: height).frame(maxWidth: .infinity)
        .clipped().clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityHidden(true)
    }

    private var searchPrompt: String {
        switch L.lang {
        case .english: return "Search apps"
        case .arabic: return "ابحث عن تطبيق"
        case .german: return "Apps suchen"
        case .sorani: return "گەڕان بۆ ئەپ"
        case .kurmanji: return "Li sepanan bigere"
        }
    }
}

struct RepoAppRow: View {
    enum Style { case row, tile }
    let app: RepoApp
    let installed: ManagedApp?
    var onSelectIPA: ((URL) async throws -> Void)? = nil
    var style: Style = .row
    /// Shown in the detail sheet's info row when the caller knows the source.
    var sourceName: String? = nil
    @ObservedObject private var apps = AppsStore.shared
    @StateObject private var downloader = PersonalIPADownloader()
    @State private var selecting = false
    @State private var selectionError: String?
    @State private var showInfo = false
    @State private var selectToken: UUID?
    @ObservedObject private var tracker = InstallTracker.shared
    /// Themed inside the Sources screens; elsewhere (Discovery) the dark default matches that screen.
    @Environment(\.sourcesTheme) private var sourcesTheme
    private var theme: SourcesTheme { sourcesTheme ?? .aurora }
    /// Identity is the exact URL the user tapped, never a feed-supplied bundle ID.
    private var requestKey: String { InstallTracker.urlKey(app.downloadURL) }

    var body: some View {
        Group {
            switch style {
            case .row: rowBody
            case .tile: tileBody
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showInfo = true }
        .onChange(of: downloader.fraction) { _, f in
            if onSelectIPA != nil, downloader.active { tracker.set(selectToken, phase: .downloading, fraction: f) }
        }
        .sheet(isPresented: $showInfo) {
            SourceAppDetailSheet(app: app, sourceName: sourceName, requestKey: requestKey, installTitle: detailInstallTitle,
                                 theme: theme, install: { install() }, installVersion: { install(version: $0) })
        }
        .alert(tr("Notice", "تنبيه"), isPresented: Binding(get: { selectionError != nil }, set: { if !$0 { selectionError = nil } })) { Button(tr("OK", "تمام")) { selectionError = nil } } message: { Text(selectionError ?? "") }
    }

    private var rowBody: some View {
        HStack(spacing: 12) {
            RemoteIcon(url: app.iconURL, size: 52, corner: MirsaRadius.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.system(size: 15.5, weight: .bold)).foregroundStyle(theme.text).lineLimit(1)
                    .mirsaNaturalDirection(app.name)
                let meta = [app.developer, app.displayVersion.isEmpty ? nil : app.displayVersion]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
                if !meta.isEmpty {
                    Text(meta).font(.caption).foregroundStyle(theme.secondary).lineLimit(1)
                        .mirsaNaturalDirection(meta)
                }
                if !app.subtitle.isEmpty {
                    Text(app.subtitle).font(.caption2).foregroundStyle(theme.secondary).lineLimit(1)
                        .mirsaNaturalDirection(app.subtitle)
                }
            }
            Spacer(minLength: 8)
            actionButton(expand: false)
        }
    }

    private var tileBody: some View {
        VStack(spacing: 6) {
            RemoteIcon(url: app.iconURL, size: 62, corner: 15)
            Text(app.name).font(.system(size: 14.5, weight: .bold)).foregroundStyle(theme.text).lineLimit(1)
                .mirsaNaturalDirection(app.name)
            let meta = [app.displayVersion.isEmpty ? nil : app.displayVersion,
                        app.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }]
                .compactMap { $0 }.joined(separator: " · ")
            Text(meta.isEmpty ? " " : meta).font(.system(size: 11)).foregroundStyle(theme.secondary).lineLimit(1)
            if let category = app.category?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty {
                Text(category.capitalized).font(.system(size: 9.5, weight: .semibold))
                    .mirsaNaturalDirection(category)
                    .foregroundStyle(theme.isLight ? Color(sourcesRGB: 0xB45309) : Color(sourcesRGB: 0xFCD34D))
                    .lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(sourcesRGB: 0xF59E0B).opacity(0.14)))
            }
            actionButton(expand: true)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .sourcesGlass(theme, radius: 20)
    }

    private func actionButton(expand: Bool) -> some View {
        Button {
            if tracker.isActive(requestKey) { tracker.cancelIfSupported(requestKey) }
            else { install() }
        } label: {
            InstallKeyedLabel(key: requestKey) {
                SourcesPillLabel(title: buttonTitle, theme: theme, installed: isCurrentInstalled, expand: expand)
            }
        }
        .buttonStyle(.mirsaPress)
        .disabled(!downloading && (selecting || apps.busy != nil || apps.downloadTask != nil || tracker.current != nil))
        .accessibilityIdentifier("source-app-action")
    }

    private var downloading: Bool {
        onSelectIPA != nil ? downloader.active : apps.isDownloading && apps.sourceDownloadURL == app.downloadURL
    }

    private var downloadFraction: Double? {
        if onSelectIPA != nil { return downloader.fraction }
        return apps.downloadHasKnownSize ? apps.progress : nil
    }

    /// Installed with the same version (or the source has none). Still tappable: it reinstalls, as before.
    private var isCurrentInstalled: Bool {
        guard onSelectIPA == nil, let i = installed else { return false }
        return i.version == app.version || app.version.isEmpty
    }

    private var buttonTitle: String {
        if onSelectIPA != nil { return selecting ? SourcesText.downloading : SourcesText.choose }
        guard installed != nil else { return SourcesText.get }
        return isCurrentInstalled ? SourcesText.installed : SourcesText.update
    }

    private var detailInstallTitle: String {
        if onSelectIPA != nil { return selecting ? SourcesText.downloading : SourcesText.choose }
        guard installed != nil else { return SourcesText.installNow }
        return isCurrentInstalled ? SourcesText.reinstall : SourcesText.updateNow
    }

    private func install(version: RepoAppVersion? = nil) {
        guard let url = app.installURL(for: version) else { return }
        let selectedKey = InstallTracker.urlKey(url)
#if DEBUG
        // Offline UI routing proof. Only the explicitly selected test fixture can intercept installation.
        if ProcessInfo.processInfo.arguments.contains("-MirsaSourceVersionsFixture24"),
           app.bundleID.hasPrefix("test.versions24.") {
            SourceVersions24Probe.shared.url = url.absoluteString
            return
        }
#endif
        if let onSelectIPA {
            guard !selecting else { return }
            selecting = true
            Task { @MainActor in
                var file: URL?
                let token = tracker.begin(key: selectedKey, cancel: { downloader.cancel() })
                selectToken = token
                defer { tracker.end(token); selectToken = nil; if let file { MirsaManagedTmp.end(file.deletingLastPathComponent()) }; selecting = false }
                do {
                    let url = try await downloader.download(url.absoluteString)
                    file = url
                    tracker.set(token, phase: .preparing)
                    try await onSelectIPA(url)
                } catch { selectionError = error.localizedDescription }
            }
            return
        }
        let target = installed?.location   // update keeps its place; new apps ask Container or Real
        Task { await apps.installFromURL(url, location: target, appID: app.bundleID) }
    }
}

/// App detail sheet: every value comes from the source entry; anything the source does not provide is hidden.
private struct SourceAppDetailSheet: View {
    let app: RepoApp
    let sourceName: String?
    let requestKey: String
    let installTitle: String
    let theme: SourcesTheme
    let install: () -> Void
    let installVersion: (RepoAppVersion) -> Void
    @State private var showingVersions = false
    @ObservedObject private var tracker = InstallTracker.shared
    @Environment(\.dismiss) private var dismiss

    private struct InfoItem: Identifiable { let id: String; let label: String; let value: String }

    private var infoItems: [InfoItem] {
        var out: [InfoItem] = []
        if !app.version.isEmpty { out.append(InfoItem(id: "version", label: SourcesText.version, value: app.version)) }
        if let s = app.size, s > 0 { out.append(InfoItem(id: "size", label: SourcesText.size, value: ByteCountFormatter.string(fromByteCount: s, countStyle: .file))) }
        if let sourceName, !sourceName.isEmpty { out.append(InfoItem(id: "source", label: SourcesText.source, value: sourceName)) }
        if let os = app.minOSVersion?.trimmingCharacters(in: .whitespacesAndNewlines), !os.isEmpty {
            out.append(InfoItem(id: "os", label: SourcesText.compatibility, value: "iOS " + os + "+"))
        }
        return out
    }

    var body: some View {
        let t = theme
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    RemoteIcon(url: app.iconURL, size: 88, corner: 22)
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.system(size: 24, weight: .bold)).foregroundStyle(t.text)
                            .lineLimit(2).minimumScaleFactor(0.8)
                            .mirsaNaturalDirection(app.name)
                        if !app.subtitle.isEmpty {
                            Text(app.subtitle).font(.system(size: 12.5)).foregroundStyle(t.secondary).lineLimit(2)
                                .mirsaNaturalDirection(app.subtitle)
                        }
                        if !app.developer.isEmpty {
                            Text(app.developer).font(.system(size: 12.5)).foregroundStyle(t.secondary).lineLimit(1)
                                .mirsaNaturalDirection(app.developer)
                        }
                    }
                    Spacer(minLength: 0)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(t.text)
                            .frame(width: 34, height: 34).background(Circle().fill(t.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(SourcesText.close)
                }

                let items = infoItems
                if !items.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Rectangle().fill(t.stroke).frame(width: 1, height: 34) }
                            VStack(spacing: 3) {
                                Text(item.label).font(.system(size: 10)).foregroundStyle(t.secondary).lineLimit(1)
                                Text(item.value).font(.system(size: 15, weight: .bold)).foregroundStyle(t.text)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                                    .mirsaNaturalDirection(item.value)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 52)
                    .padding(.vertical, 8)
                    .overlay(alignment: .top) { Rectangle().fill(t.stroke).frame(height: 1) }
                    .overlay(alignment: .bottom) { Rectangle().fill(t.stroke).frame(height: 1) }
                    .padding(.top, 16)
                }

                HStack(spacing: 10) {
                    Button {
                        if tracker.isActive(requestKey) { tracker.cancelIfSupported(requestKey) } else { install() }
                    } label: {
                        InstallKeyedLabel(key: requestKey) {
                            Text(installTitle).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(t.accentGradient))
                        .shadow(color: t.accent[0].opacity(0.45), radius: 12, y: 6)
                    }
                    .buttonStyle(.mirsaPress)
                    .disabled(!tracker.isActive(requestKey) && tracker.current != nil)
                    .accessibilityIdentifier("source-detail-install")
                    Button { showingVersions = true } label: {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(t.text)
                            .frame(width: 52, height: 52)
                            .sourcesGlass(t, radius: 18)
                    }
                    .buttonStyle(.mirsaPress)
                    .disabled(!app.hasVersionHistory)
                    .opacity(app.hasVersionHistory ? 1 : 0.35)
                    .accessibilityLabel(SourcesText.versions)
                    .accessibilityHint(app.hasVersionHistory ? SourcesText.sourceVersions : SourcesText.noVersionHistory)
                    .accessibilityIdentifier("source-detail-versions")
                }
                .padding(.top, 16)
                ArabicTranslateRow(bundleID: app.bundleID, theme: t)
                    .padding(.top, 12)
#if DEBUG
                SourceVersions24RoutingProof()
#endif

                AppScreenshotGallery(app: app)
                    .foregroundStyle(t.text)
                    .padding(.top, 20)

                if let notes = app.versionNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    Text(SourcesText.whatsNew).font(.system(size: 18, weight: .bold)).foregroundStyle(t.text).padding(.top, 20)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if !app.version.isEmpty {
                                Text(SourcesText.version + " " + app.version).font(.system(size: 13, weight: .bold))
                            }
                            Spacer()
                            if let raw = app.date, let date = SourcesStore.date(raw) {
                                Text(SourcesDates.label(date)).font(.system(size: 12)).foregroundStyle(t.secondary)
                            }
                        }
                        Text(notes).font(.system(size: 13)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                            .mirsaNaturalParagraph(notes)
                    }
                    .foregroundStyle(t.text.opacity(0.9))
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .sourcesGlass(t, radius: 18)
                    .padding(.top, 10)
                }

                if !app.description.isEmpty && app.description != app.subtitle {
                    Text(SourcesText.about).font(.system(size: 18, weight: .bold)).foregroundStyle(t.text).padding(.top, 20)
                    Text(app.description).font(.system(size: 14)).foregroundStyle(t.text.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                        .mirsaNaturalParagraph(app.description)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 18).padding(.top, 24).padding(.bottom, 30)
        }
        .mirsaHidesScrollEdgeEffect()
        .background(LinearGradient(colors: t.sheetBase, startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .tint(t.accent[0])
        .environment(\.colorScheme, t.colorScheme)
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingVersions) {
            SourceAppVersionsSheet(app: app, theme: theme, install: installVersion)
        }
    }
}

/// No network discovery here. These are only the validated releases already supplied in this app's source.
private struct SourceAppVersionsSheet: View {
    let app: RepoApp
    let theme: SourcesTheme
    let install: (RepoAppVersion) -> Void
    @ObservedObject private var tracker = InstallTracker.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = theme
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40).background(Circle().fill(t.card))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(SourcesText.close)
                .accessibilityIdentifier("source-versions-close")
                VStack(alignment: .leading, spacing: 3) {
                    Text(SourcesText.versions).font(.system(size: 23, weight: .bold))
                    Text(app.name).font(.subheadline).foregroundStyle(t.secondary).lineLimit(1)
                        .mirsaNaturalDirection(app.name)
                }
                Spacer(minLength: 0)
            }
#if DEBUG
            SourceVersions24RoutingProof()
#endif
            Text(SourcesText.sourceVersions).font(.footnote).foregroundStyle(t.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(app.versions) { release in
                        let key = InstallTracker.urlKey(release.downloadURL)
                        Button {
                            if tracker.isActive(key) { tracker.cancelIfSupported(key) }
                            else { install(release) }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(SourcesText.version + " " + release.version)
                                        .font(.system(size: 17, weight: .bold))
                                        .mirsaNaturalDirection(release.version)
                                    HStack(spacing: 12) {
                                        if let raw = release.date, let date = SourcesStore.date(raw) {
                                            Label(SourcesDates.label(date), systemImage: "calendar")
                                        }
                                        if let size = release.size, size > 0 {
                                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                        }
                                    }
                                    .font(.caption).foregroundStyle(t.secondary)
                                }
                                Spacer(minLength: 8)
                                InstallKeyedLabel(key: key) {
                                    Image(systemName: "arrow.down.app").font(.system(size: 20, weight: .semibold))
                                }
                            }
                            .foregroundStyle(t.text)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .sourcesGlass(t, radius: 18)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.mirsaPress)
                        .disabled(!tracker.isActive(key) && tracker.current != nil)
                        .accessibilityIdentifier("source-version-" + release.version)
                        .accessibilityHint(SourcesText.installNow)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .padding(18)
        .foregroundStyle(t.text)
        .background(LinearGradient(colors: t.sheetBase, startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .environment(\.colorScheme, t.colorScheme)
        .environment(\.layoutDirection, .leftToRight)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}


struct RemoteIcon: View {
    let url: URL?
    let size: CGFloat
    let corner: CGFloat
    var body: some View {
        MirsaRemoteImage(url: url, maxPixel: size * 3) { Image(systemName: "app.dashed").font(.system(size: size * 0.45)).foregroundStyle(.secondary) }
            .frame(width: size, height: size)
            .background(MirsaPalette.cardRaised)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(MirsaPalette.stroke, lineWidth: 0.5))
    }
}


/// Downsampled thumbnails of in-memory image bytes (wallpaper previews, chat photo chips).
/// List rows used to run `UIImage(data:)` on full-resolution images in `body`, so every
/// re-render (a toggle, a keystroke in the composer) decoded megabytes on the main thread.
/// Thread-safe (NSCache); decodes at most once per key, at the size the row draws.
enum MirsaThumbnailCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 300
        c.totalCostLimit = 64 * 1024 * 1024
        return c
    }()

    /// `key` identifies the owner (an item id); byte count and hash guard against edits.
    static func image(_ data: Data, key: String, maxPixel: CGFloat) -> UIImage? {
        guard !data.isEmpty else { return nil }
        let cacheKey = "\(key)|\(data.count)|\(data.hashValue)|\(Int(maxPixel))" as NSString
        if let hit = cache.object(forKey: cacheKey) { return hit }
        let image = downsample(data, maxPixel: maxPixel) ?? UIImage(data: data)
        if let image, let cg = image.cgImage {
            cache.setObject(image, forKey: cacheKey, cost: cg.bytesPerRow * cg.height)
        }
        return image
    }

    /// ImageIO thumbnail decode at `maxPixel` (longest side). Safe off the main thread.
    static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Memory-cached, downsampled remote images for list rows. `AsyncImage` keeps no decoded
/// cache, so in a 10,000-app catalogue every icon was fetched and decoded again each time
/// its row scrolled back on screen (flicker + main-thread decode while scrolling).
final class MirsaRemoteImageCache: @unchecked Sendable {
    static let shared = MirsaRemoteImageCache()
    private let memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 800
        c.totalCostLimit = 96 * 1024 * 1024
        return c
    }()
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.timeoutIntervalForRequest = 30
        c.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: c)
    }()
    /// Same ceiling the screenshot loader uses for a single image.
    private let maxBytes = 20 * 1024 * 1024

    private func key(_ url: URL, _ maxPixel: CGFloat) -> NSString { "\(Int(maxPixel))|\(url.absoluteString)" as NSString }

    func cached(_ url: URL, maxPixel: CGFloat) -> UIImage? { memory.object(forKey: key(url, maxPixel)) }

    func load(_ url: URL, maxPixel: CGFloat) async -> UIImage? {
        if let hit = cached(url, maxPixel: maxPixel) { return hit }
        guard let scheme = url.scheme?.lowercased(), ["https", "http", "file"].contains(scheme) else { return nil }
        let data: Data
        do {
            let (bytes, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            data = bytes
        } catch { return nil }
        guard !data.isEmpty, data.count <= maxBytes, !Task.isCancelled else { return nil }
        let image = await Task.detached(priority: .utility) {
            MirsaThumbnailCache.downsample(data, maxPixel: maxPixel) ?? UIImage(data: data)?.preparingForDisplay()
        }.value
        if let image, let cg = image.cgImage {
            memory.setObject(image, forKey: key(url, maxPixel), cost: cg.bytesPerRow * cg.height)
        }
        return image
    }
}

/// Drop-in for `AsyncImage` in rows: shows a cached image synchronously, loads off-main otherwise.
struct MirsaRemoteImage<Placeholder: View>: View {
    let url: URL?
    /// Longest side in pixels to decode at (about 3× the point size drawn).
    let maxPixel: CGFloat
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var loaded: (url: URL, image: UIImage)? = nil

    private var image: UIImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        return MirsaRemoteImageCache.shared.cached(url, maxPixel: maxPixel)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url, image == nil else { return }
            if let fetched = await MirsaRemoteImageCache.shared.load(url, maxPixel: maxPixel), !Task.isCancelled {
                loaded = (url, fetched)
            }
        }
    }
}

/// Inline transfer control. Unknown length stays indeterminate, never a made-up percent.
struct SourceDownloadIndicator: View {
    let fraction: Double?
    var phase: InstallRequest.Phase = .downloading
    var cancellable = true

    private var cancelLabel: String {
        switch L.lang {
        case .english: return "Cancel download"
        case .arabic: return "إلغاء التحميل"
        case .german: return "Download abbrechen"
        case .sorani: return "هەڵوەشاندنەوەی داگرتن"
        case .kurmanji: return "Daxistinê betal bike"
        }
    }

    private var phaseLabel: String {
        switch (phase, L.lang) {
        case (.downloading, _): return ""
        case (.preparing, .english): return "Preparing…"
        case (.preparing, .arabic): return "عم نجهّز…"
        case (.preparing, .german): return "Vorbereiten…"
        case (.preparing, .sorani): return "ئامادە دەکرێت…"
        case (.preparing, .kurmanji): return "Tê amadekirin…"
        case (.installing, .english): return "Installing…"
        case (.installing, .arabic): return "عم نثبّت…"
        case (.installing, .german): return "Installieren…"
        case (.installing, .sorani): return "دادەمەزرێت…"
        case (.installing, .kurmanji): return "Tê sazkirin…"
        }
    }

    private var shown: Double? { phase == .downloading ? fraction : nil }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                MirsaLiquidProgress(value: shown, diameter: 22)
                if shown != nil && cancellable { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
            }
            .frame(width: 22, height: 22)
            if let value = shown {
                Text(min(1, max(0, value)), format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
            } else if phase != .downloading {
                Text(phaseLabel).font(.caption).lineLimit(1)
            }
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase == .downloading && cancellable ? cancelLabel : phaseLabel)
        .accessibilityValue(shown.map { String(Int(min(1, max(0, $0)) * 100)) + "%" } ?? "")
        .accessibilityIdentifier("source-inline-download")
    }
}
