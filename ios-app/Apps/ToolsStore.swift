import Foundation
import SwiftUI

// MARK: - Tools Store: models, backend client and local bookmarks
//
// The catalogue lives on the owner's backend (backend/tools-store). The app never ships or
// invents catalogue content: without a configured endpoint the store shows its unavailable state.
// Every upload is stored as `pending_review` and only appears after an admin approves it.

enum ToolsStoreCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case tweaks          // .deb / .dylib tweaks
    case wallpapers      // .tendies wallpapers (applied with the existing Tendies engine)
    case appTweaks = "app_tweaks"   // ready-made tweaks for popular apps (YouTube, Instagram, TikTok)
    case sounds          // ringtones and sounds
    case fonts
    // Keep the category and its data, but hide the placeholder directory until usable tweaks exist.
    static var visibleCases: [Self] { allCases.filter { $0 != .tweaks && $0 != .sounds } }
    var id: String { rawValue }

    var title: String {
        switch self {
        case .tweaks: return ToolsStoreText.catTweaks
        case .wallpapers: return ToolsStoreText.catWallpapers
        case .appTweaks: return ToolsStoreText.catAppTweaks
        case .sounds: return ToolsStoreText.catSounds
        case .fonts: return ToolsStoreText.catFonts
        }
    }

    var icon: String {
        switch self {
        case .tweaks: return "shippingbox.fill"
        case .wallpapers: return "photo.on.rectangle.angled"
        case .appTweaks: return "wand.and.stars"
        case .sounds: return "music.note"
        case .fonts: return "textformat"
        }
    }

    /// Lower-case file extensions accepted for this category. The server enforces the same list.
    var allowedExtensions: Set<String> {
        switch self {
        case .tweaks, .appTweaks: return ["dylib", "deb", "zip"]
        case .wallpapers: return ["tendies"]
        case .sounds: return ["m4r", "m4a", "mp3", "caf", "wav"]
        case .fonts: return ["dylib"]
        }
    }

    var isTweak: Bool { self == .tweaks || self == .appTweaks || self == .fonts }
}

/// Popular apps a ready-made tweak can target. "other" keeps a free-form bundle ID.
enum ToolsStoreTargetApp: String, CaseIterable, Identifiable {
    case youtube, instagram, tiktok, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .youtube: return "YouTube"
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .other: return ToolsStoreText.otherApp
        }
    }
}

struct ToolsStoreItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let category: String
    let title: String
    var description: String?
    var targetApp: String?
    var version: String?
    var fileName: String
    var fileSize: Int64?
    var previewURL: String?
    var previewVideoURL: String?
    var previews: [ToolsStorePreviewMedia] = []
    var authorName: String?
    var downloads: Int
    var ratingAvg: Double
    var ratingCount: Int
    var myRating: Int?
    var status: String?
    var reviewNote: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, category, title, description, version, downloads, status
        case targetApp = "target_app"
        case fileName = "file_name"
        case fileSize = "file_size"
        case previewURL = "preview_url"
        case previewVideoURL = "preview_video_url"
        case previews
        case authorName = "author_name"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
        case myRating = "my_rating"
        case reviewNote = "review_note"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        category = try c.decode(String.self, forKey: .category)
        title = try c.decode(String.self, forKey: .title)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        targetApp = try? c.decodeIfPresent(String.self, forKey: .targetApp)
        version = try? c.decodeIfPresent(String.self, forKey: .version)
        fileName = (try? c.decodeIfPresent(String.self, forKey: .fileName)) ?? ""
        fileSize = try? c.decodeIfPresent(Int64.self, forKey: .fileSize)
        previewURL = try? c.decodeIfPresent(String.self, forKey: .previewURL)
        previewVideoURL = try? c.decodeIfPresent(String.self, forKey: .previewVideoURL)
        previews = (try? c.decodeIfPresent([ToolsStorePreviewMedia].self, forKey: .previews)) ?? []
        authorName = try? c.decodeIfPresent(String.self, forKey: .authorName)
        downloads = (try? c.decodeIfPresent(Int.self, forKey: .downloads)) ?? 0
        ratingAvg = (try? c.decodeIfPresent(Double.self, forKey: .ratingAvg)) ?? 0
        ratingCount = (try? c.decodeIfPresent(Int.self, forKey: .ratingCount)) ?? 0
        myRating = try? c.decodeIfPresent(Int.self, forKey: .myRating)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        reviewNote = try? c.decodeIfPresent(String.self, forKey: .reviewNote)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
    }

    /// Gallery media: the previews array, or the legacy single image/video fields.
    var gallery: [ToolsStorePreviewMedia] {
        if !previews.isEmpty { return previews.filter { $0.mediaURL != nil } }
        var out: [ToolsStorePreviewMedia] = []
        if let u = previewURL, preview != nil { out.append(.init(id: "legacy-image", kind: "image", url: u)) }
        if let v = previewVideoURL, ToolsStorePreviewMedia.safe(v) != nil { out.append(.init(id: "legacy-video", kind: "video", url: v, posterURL: previewURL)) }
        return out
    }
    /// Still image for cards: first image, else the poster of the first video.
    var cardStill: URL? {
        if let i = gallery.first(where: { !$0.isVideo })?.stillURL { return i }
        return gallery.first?.stillURL ?? preview
    }
    var kind: ToolsStoreCategory? { ToolsStoreCategory(rawValue: category) }
    var fileExtension: String { (fileName as NSString).pathExtension.lowercased() }
    /// Preview image, only plain https without credentials.
    var preview: URL? {
        guard let raw = previewURL, let u = URL(string: raw), u.scheme?.lowercased() == "https",
              u.host?.isEmpty == false, u.user == nil, u.password == nil else { return nil }
        return u
    }
    var targetTitle: String? {
        guard let t = targetApp?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return ToolsStoreTargetApp(rawValue: t.lowercased()).map(\.title) ?? t
    }
}

struct ToolsStoreRatingResult: Decodable, Sendable {
    let ratingAvg: Double
    let ratingCount: Int
    let myRating: Int?
    enum CodingKeys: String, CodingKey {
        case ratingAvg = "rating_avg", ratingCount = "rating_count", myRating = "my_rating"
    }
}

// MARK: - Configuration

enum ToolsStoreConfig {
    /// Optional runtime override (e.g. set from a debug build): full HTTPS URL of the edge function.
    static let defaultsKey = "mirsa.toolsStore.endpoint"
    /// Build-time value in Info.plist. Empty means "not configured" and the store shows its unavailable state.
    static let infoKey = "MirsaToolsStoreEndpoint"
    /// Hard cap for an uploaded file; the backend enforces the same limit.
    static let maxUploadBytes: Int64 = 150 * 1024 * 1024

    static var endpoint: URL? {
        let raw = UserDefaults.standard.string(forKey: defaultsKey)
            ?? (Bundle.main.object(forInfoDictionaryKey: infoKey) as? String) ?? ""
        return validated(raw)
    }

    static func validated(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let u = URL(string: text), u.scheme?.lowercased() == "https",
              u.host?.isEmpty == false, u.user == nil, u.password == nil else { return nil }
        return u
    }

    static var isConfigured: Bool { endpoint != nil }
}

// MARK: - Client

enum ToolsStoreError: LocalizedError, Equatable {
    case notConfigured
    case unavailable
    case rateLimited
    case rejected(String)
    case server(Int)
    case badFile
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .notConfigured: return ToolsStoreText.notConfigured
        case .unavailable: return ToolsStoreText.unavailable
        case .rateLimited: return ToolsStoreText.rateLimited
        case .rejected(let m): return m
        case .server(let code): return ToolsStoreText.serverError + " (\(code))"
        case .badFile: return ToolsStoreText.badFile
        case .tooLarge: return ToolsStoreText.tooLarge
        }
    }
}

/// Talks to backend/tools-store with the same anonymous per-install Supabase session the other Mirsa
/// backends use (DiscoveryAuthClient). Nothing secret is stored in the app.
enum ToolsStoreClient {
    private static func token(force: Bool) async throws -> String {
        let auth = DiscoveryAuthClient(projectURL: URL(string: WebBackendConfig.defaultProject)!,
                                       publishableKey: WebBackendConfig.defaultPublishableKey,
                                       store: KeychainSessionStore(), http: SafeMetadataHTTP())
        return try await auth.token(forceRefresh: force)
    }

    private static func session(timeout: TimeInterval) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.urlCredentialStorage = nil
        cfg.timeoutIntervalForRequest = timeout
        return URLSession(configuration: cfg)
    }

    /// POST {action, ...}. At most two requests: the second only after a 401 with a refreshed token.
    static func call(_ body: [String: Any], timeout: TimeInterval = 30) async throws -> Data {
        guard let endpoint = ToolsStoreConfig.endpoint else { throw ToolsStoreError.notConfigured }
        let payload = try JSONSerialization.data(withJSONObject: body)
        var force = false
        for _ in 0..<2 {
            var req = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let bearer = try await token(force: force)
            req.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
            req.setValue(MirsaDeviceIdentity.deviceID(), forHTTPHeaderField: "x-mirsa-device")
            req.setValue(AppLanguageStore.snapshot.rawValue, forHTTPHeaderField: "x-mirsa-lang")
            req.httpBody = payload
            let s = session(timeout: timeout)
            defer { s.finishTasksAndInvalidate() }
            let (data, response) = try await s.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401, !force { force = true; continue }
            if (200..<300).contains(code) { return data }
            throw failure(code, data)
        }
        throw ToolsStoreError.server(401)
    }

    static func failure(_ code: Int, _ data: Data) -> ToolsStoreError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = object?["error"] as? String ?? ""
        switch (code, error) {
        case (404, "not_found"): return .rejected(ToolsStoreText.notFound)
        case (404, _), (502, _), (503, _): return .unavailable
        case (429, _): return .rateLimited
        case (413, _), (_, "too_large"): return .tooLarge
        case (_, "bad_file"), (_, "bad_extension"): return .badFile
        case (_, "pending_limit"): return .rejected(ToolsStoreText.pendingLimit)
        default: return .server(code)
        }
    }

    private static func decodeItems(_ data: Data) throws -> [ToolsStoreItem] {
        struct Page: Decodable { let items: [ToolsStoreItem] }
        return try JSONDecoder().decode(Page.self, from: data).items
    }

    enum Sort: String { case top = "downloads", newest = "new", rated = "rating" }

    static func list(category: ToolsStoreCategory, sort: Sort, query: String = "", limit: Int = 60, offset: Int = 0) async throws -> [ToolsStoreItem] {
        var body: [String: Any] = ["action": "list", "category": category.rawValue, "sort": sort.rawValue,
                                   "limit": max(1, min(limit, 100)), "offset": max(0, offset)]
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { body["q"] = String(q.prefix(80)) }
        guard category == .fonts else { return try decodeItems(try await call(body)) }
        return try await fontItems(limit: limit, offset: offset) { pageSize, pageOffset in
            var page = body
            page["limit"] = pageSize
            page["offset"] = pageOffset
            return try decodeItems(try await call(page))
        }
    }

    /// Scan raw pages, not filtered counts. Legacy font files stay stored but
    /// cannot hide later dylib tweaks. Match the server's 10,000 offset cap.
    static func fontItems(limit: Int, offset: Int,
                          fetchPage: (Int, Int) async throws -> [ToolsStoreItem]) async throws -> [ToolsStoreItem] {
        let wanted = max(1, min(limit, 100))
        let pageSize = 100
        var pageOffset = max(0, min(offset, 10_000))
        var matching: [ToolsStoreItem] = []
        var seen = Set<String>()
        while pageOffset <= 10_000 {
            try Task.checkCancellation()
            let items = try await fetchPage(pageSize, pageOffset)
            matching += items.filter {
                $0.kind == .fonts && $0.fileExtension == "dylib" && seen.insert($0.id).inserted
            }
            if matching.count >= wanted || items.count < pageSize { break }
            pageOffset += pageSize
        }
        return Array(matching.prefix(wanted))
    }

    static func myUploads() async throws -> [ToolsStoreItem] {
        try decodeItems(try await call(["action": "my_uploads"]))
    }

    static func rate(_ id: String, stars: Int) async throws -> ToolsStoreRatingResult {
        let data = try await call(["action": "rate", "id": id, "stars": max(1, min(5, stars))])
        return try JSONDecoder().decode(ToolsStoreRatingResult.self, from: data)
    }

    /// Asks for a short-lived signed URL. The server counts at most one download per user and item.
    static func downloadURL(_ id: String) async throws -> URL {
        struct Answer: Decodable { let url: String }
        let data = try await call(["action": "download", "id": id])
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        guard let u = URL(string: answer.url) else { throw ToolsStoreError.unavailable }
        try ForgeDylibDownload.validate(u, requireExtension: false)
        return u
    }

    /// Downloads an approved item into its own managed temporary folder, named after the item's file.
    /// The caller owns the folder and must end it with `MirsaManagedTmp.end(file.deletingLastPathComponent())`.
    static func fetchFile(_ item: ToolsStoreItem) async throws -> URL {
        guard let kind = item.kind, kind.allowedExtensions.contains(item.fileExtension) else { throw ToolsStoreError.badFile }
        let remote = try await downloadURL(item.id)
        // Reuse Mirsa's bounded streaming downloader, including validation of every redirect.
        // Signed storage URLs do not have to end in the item's original extension.
        let temp = try await ForgeDylibDownload.fetch(remote,
            maximumBytes: Int(ToolsStoreConfig.maxUploadBytes), requireExtension: false)
        let size = (try? temp.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        guard size > 0, size <= ToolsStoreConfig.maxUploadBytes else {
            try? FileManager.default.removeItem(at: temp)
            throw ToolsStoreError.tooLarge
        }
        let folder = try MirsaManagedTmp.begin("tools-store")
        let target = folder.appendingPathComponent(safeFileName(item.fileName, fallbackExtension: item.fileExtension))
        do { try FileManager.default.moveItem(at: temp, to: target) }
        catch { MirsaManagedTmp.end(folder); try? FileManager.default.removeItem(at: temp); throw error }
        return target
    }

    static func safeFileName(_ raw: String, fallbackExtension: String) -> String {
        let ext = (raw as NSString).pathExtension.lowercased()
        let base = ((raw as NSString).lastPathComponent as NSString).deletingPathExtension
        let cleaned = String(base.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" || $0 == " " }
            .map(Character.init).prefix(60)).trimmingCharacters(in: .whitespaces)
        let name = cleaned.isEmpty ? "item" : cleaned
        return name + "." + (ext.isEmpty ? fallbackExtension : ext)
    }

    struct UploadDraft {
        var category: ToolsStoreCategory
        var title: String
        var description: String
        var version: String
        var targetApp: String?
        var authorName: String
        var file: URL
        var previews: [ToolsStorePickedPreview] = []
        /// Wallpapers: the server asks for a prompt image when it cannot extract a snapshot.
        var previewRequired = false
    }

    /// preview_begin -> PUT raw bytes (matching Content-Type) -> preview_commit. Runs before upload_commit.
    static func uploadPreview(_ p: ToolsStorePickedPreview, itemID: String) async throws {
        let isVideo = p.kind == "video"
        guard p.size > 0, p.size <= (isVideo ? ToolsStorePickedPreview.maxVideoBytes : ToolsStorePickedPreview.maxImageBytes) else { throw ToolsStoreError.tooLarge }
        var body: [String: Any] = ["action": "preview_begin", "id": itemID, "file_name": p.file.lastPathComponent,
                                   "file_size": p.size, "content_type": p.contentType]
        if isVideo { body["duration_seconds"] = max(0, min(30, p.duration)) }
        struct Begin: Decodable { let preview_id: String; let upload_url: String }
        let begin = try JSONDecoder().decode(Begin.self, from: try await call(body))
        guard let url = URL(string: begin.upload_url), url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil else { throw ToolsStoreError.unavailable }
        var put = URLRequest(url: url, timeoutInterval: 300)
        put.httpMethod = "PUT"
        put.setValue(p.contentType, forHTTPHeaderField: "Content-Type")
        let s = session(timeout: 300)
        defer { s.finishTasksAndInvalidate() }
        let (_, response) = try await s.upload(for: put, fromFile: p.file)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ToolsStoreError.server(code) }
        _ = try await call(["action": "preview_commit", "id": itemID, "preview_id": begin.preview_id])
    }

    /// upload_begin (server creates the row as `uploading` and returns a signed upload URL) → PUT the bytes
    /// → upload_commit (server verifies the object and moves the row to `pending_review`).
    static func upload(_ draft: UploadDraft, progress: @escaping @Sendable (Double) -> Void) async throws {
        let ext = draft.file.pathExtension.lowercased()
        guard draft.category.allowedExtensions.contains(ext) else { throw ToolsStoreError.badFile }
        let size = Int64((try? draft.file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard size > 0 else { throw ToolsStoreError.badFile }
        guard size <= ToolsStoreConfig.maxUploadBytes else { throw ToolsStoreError.tooLarge }
        var body: [String: Any] = [
            "action": "upload_begin", "category": draft.category.rawValue,
            "title": draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            "description": draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
            "file_name": draft.file.lastPathComponent, "file_size": size,
        ]
        let version = draft.version.trimmingCharacters(in: .whitespacesAndNewlines)
        if !version.isEmpty { body["version"] = version }
        let author = draft.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !author.isEmpty { body["author_name"] = author }
        if let target = draft.targetApp?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty { body["target_app"] = target }
        if draft.previewRequired { body["preview_required"] = true }
        struct Begin: Decodable { let id: String; let upload_url: String }
        let begin = try JSONDecoder().decode(Begin.self, from: try await call(body))
        guard let uploadURL = URL(string: begin.upload_url), uploadURL.scheme?.lowercased() == "https", uploadURL.host?.isEmpty == false,
              uploadURL.user == nil, uploadURL.password == nil else { throw ToolsStoreError.unavailable }
        progress(0.05)
        var put = URLRequest(url: uploadURL, timeoutInterval: 600)
        put.httpMethod = "PUT"
        put.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let s = session(timeout: 600)
        defer { s.finishTasksAndInvalidate() }
        let (_, response) = try await s.upload(for: put, fromFile: draft.file)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ToolsStoreError.server(code) }
        progress(0.7)
        for (i, p) in draft.previews.enumerated() {
            try await uploadPreview(p, itemID: begin.id)
            progress(0.7 + 0.2 * Double(i + 1) / Double(max(draft.previews.count, 1)))
        }
        progress(0.9)
        _ = try await call(["action": "upload_commit", "id": begin.id])
        progress(1)
    }
}

// MARK: - Bookmarks (saved locally on this device)

@MainActor
final class ToolsStoreSaved: ObservableObject {
    static let shared = ToolsStoreSaved()
    static let key = "mirsa.toolsStore.saved.v1"
    @Published private(set) var items: [ToolsStoreItem] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([ToolsStoreItem].self, from: data) {
            items = saved
        }
    }

    func isSaved(_ id: String) -> Bool { items.contains { $0.id == id } }

    func toggle(_ item: ToolsStoreItem) {
        if isSaved(item.id) { items.removeAll { $0.id == item.id } }
        else { items.insert(item, at: 0) }
        persist()
    }

    /// Keeps a saved snapshot in step with fresher server values (downloads, rating).
    func refresh(_ item: ToolsStoreItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }), items[index] != item else { return }
        items[index] = item
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: Self.key) }
    }
}

// MARK: - Store state

@MainActor
final class ToolsStoreModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, loaded, failed(String) }
    @Published private(set) var availableCategories: [ToolsStoreCategory] = [.wallpapers]
    @Published var category: ToolsStoreCategory = .wallpapers
    @Published private(set) var top: [ToolsStoreItem] = []
    @Published private(set) var newest: [ToolsStoreItem] = []
    @Published private(set) var phase: Phase = .idle
    @Published var query = ""
    private var loadTask: Task<Void, Never>?

    var isConfigured: Bool { ToolsStoreConfig.isConfigured }

    /// Highest rated among the loaded items (only items that have ratings).
    var topRated: [ToolsStoreItem] {
        var seen = Set<String>()
        return (top + newest).filter { $0.ratingCount > 0 && seen.insert($0.id).inserted }
            .sorted { ($0.ratingAvg, $0.ratingCount) > ($1.ratingAvg, $1.ratingCount) }
            .prefix(10).map { $0 }
    }

    /// Directory landing pages never qualify as installable inventory.
    func refreshAvailableCategories() async {
        var available: [ToolsStoreCategory] = [.wallpapers]
        if isConfigured {
            for candidate in ToolsStoreCategory.allCases where candidate != .wallpapers && candidate != .sounds {
                guard !Task.isCancelled else { return }
                if let items = try? await ToolsStoreClient.list(category: candidate, sort: .newest, limit: 100),
                   !items.isEmpty { available.append(candidate) }
            }
        }
        availableCategories = ToolsStoreCategory.allCases.filter { available.contains($0) }
        if !availableCategories.contains(category) { category = .wallpapers }
    }

    func reload() {
        loadTask?.cancel()
        guard isConfigured else { phase = .failed(ToolsStoreText.notConfigured); top = []; newest = []; return }
        let category = self.category
        let query = self.query
        phase = .loading
        loadTask = Task { [weak self] in
            do {
                async let topItems = ToolsStoreClient.list(category: category, sort: .top, query: query, limit: 10)
                async let newItems = ToolsStoreClient.list(category: category, sort: .newest, query: query, limit: 60)
                let (t, n) = try await (topItems, newItems)
                guard !Task.isCancelled, let self else { return }
                self.top = t
                self.newest = n
                self.phase = .loaded
                for item in t + n { ToolsStoreSaved.shared.refresh(item) }
            } catch {
                guard !Task.isCancelled, let self else { return }
                if (error as? URLError)?.code == .cancelled { return }
                self.top = []
                self.newest = []
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Replaces an item everywhere after a rating or download changed its numbers.
    func update(_ item: ToolsStoreItem) {
        if let i = top.firstIndex(where: { $0.id == item.id }) { top[i] = item }
        if let i = newest.firstIndex(where: { $0.id == item.id }) { newest[i] = item }
        ToolsStoreSaved.shared.refresh(item)
    }
}

// MARK: - Text (en, ar, de, ckb, kmr)

enum ToolsStoreText {
    private static func t(_ en: String, _ ar: String, _ de: String, _ ckb: String, _ kmr: String) -> String {
        SourcesText.t(en, ar, de, ckb, kmr)
    }
    static var tab: String { t("Store", "المتجر", "Store", "فرۆشگا", "Firoşgeh") }
    static var title: String { t("Tools Store", "متجر الأدوات", "Tools-Store", "فرۆشگای ئامرازەکان", "Firoşgeha amûran") }
    static var subtitle: String { t("Tweaks, wallpapers, sounds and fonts", "تويكات وخلفيات وأصوات وخطوط", "Tweaks, Hintergründe, Töne und Schriften", "تویک، وێنەزەمینە، دەنگ و فۆنت", "Tweak, wênesazî, deng û font") }
    static var catTweaks: String { t("Deb & dylib", "تويكات deb و dylib", "Deb & dylib", "تویکی deb و dylib", "Tweakên deb û dylib") }
    static var catWallpapers: String { t("Wallpapers", "خلفيات", "Hintergründe", "وێنەزەمینە", "Wênesazî") }
    static var catAppTweaks: String { t("App tweaks", "تويكات تطبيقات", "App-Tweaks", "تویکی ئەپەکان", "Tweakên sepanan") }
    static var catSounds: String { t("Ringtones & sounds", "نغمات وأصوات", "Klingeltöne & Töne", "زەنگ و دەنگەکان", "Zeng û deng") }
    static var catFonts: String { t("Fonts", "خطوط", "Schriften", "فۆنتەکان", "Font") }
    static var otherApp: String { t("Other app", "تطبيق آخر", "Andere App", "ئەپێکی تر", "Sepaneke din") }
    static var saved: String { t("Saved", "المحفوظات", "Gemerkt", "پاشەکەوتکراوەکان", "Tomarkirî") }
    static var save: String { t("Save", "حفظ", "Merken", "پاشەکەوت", "Tomar bike") }
    static var unsave: String { t("Remove from saved", "إزالة من المحفوظات", "Nicht mehr merken", "لابردن لە پاشەکەوتکراوەکان", "Ji tomarkirîyan rake") }
    static var mostDownloaded: String { t("Most downloaded", "الأكثر تحميلاً", "Meistgeladen", "زۆرترین داگرتن", "Herî zêde hatine daxistin") }
    static var topRated: String { t("Top rated", "الأعلى تقييماً", "Bestbewertet", "باشترین هەڵسەنگاندن", "Herî baş nirxandî") }
    static var newest: String { t("Newest", "الأحدث", "Neueste", "نوێترین", "Herî nû") }
    static var download: String { t("Download", "تحميل", "Laden", "داگرتن", "Daxe") }
    static var apply: String { t("Apply", "تطبيق", "Anwenden", "جێبەجێکردن", "Bicîh bîne") }
    static var inject: String { t("Inject", "حقن", "Injizieren", "چەسپاندن", "Bixe") }
    static var upload: String { t("Upload", "رفع", "Hochladen", "بارکردن", "Bar bike") }
    static var uploadTitle: String { t("Upload to the store", "رفع للمتجر", "In den Store hochladen", "بارکردن بۆ فرۆشگا", "Li firoşgehê bar bike") }
    static var reviewBanner: String { t("Every upload, and every dylib in particular, is reviewed by the Mirsa team before it becomes available for download.",
                                        "كل ملف مرفوع، وخصوصاً كل dylib، بيمرّ على مراجعة فريق مرسى قبل ما يصير متاح للتحميل.",
                                        "Jeder Upload, insbesondere jede dylib, wird vom Mirsa-Team geprüft, bevor er zum Download verfügbar ist.",
                                        "هەر بارکراوێک، بە تایبەتی هەر dylibێک، پێش ئەوەی بۆ داگرتن بەردەست بێت لەلایەن تیمی Mirsa پشکنینی بۆ دەکرێت.",
                                        "Her barkirin, bi taybetî her dylib, berî ku ji bo daxistinê amade bibe ji aliyê tîma Mirsa ve tê kontrolkirin.") }
    static var reviewTitle: String { t("Reviewed before publishing", "مراجعة قبل النشر", "Vor Veröffentlichung geprüft", "پشکنین پێش بڵاوکردنەوە", "Berî weşanê tê kontrolkirin") }
    static var notConfigured: String { t("The store server isn't configured in this build yet.", "سيرفر المتجر مو مضبوط بهالنسخة لسا.", "Der Store-Server ist in diesem Build noch nicht eingerichtet.", "سێرڤەری فرۆشگا هێشتا لەم وەشانەدا ڕێکنەخراوە.", "Servera firoşgehê di vê guhertoyê de hê nehatiye sazkirin.") }
    static var unavailable: String { t("The store is unavailable right now. Try again later.", "المتجر مو متاح هلق. جرّب بعدين.", "Der Store ist gerade nicht verfügbar. Versuche es später erneut.", "فرۆشگا ئێستا بەردەست نییە. دواتر هەوڵ بدەرەوە.", "Firoşgeh niha ne berdest e. Paşê dîsa biceribîne.") }
    static var unavailableTitle: String { t("Store unavailable", "المتجر غير متاح", "Store nicht verfügbar", "فرۆشگا بەردەست نییە", "Firoşgeh ne berdest e") }
    static var rateLimited: String { t("Too many requests. Try again later.", "طلبات كتير. جرّب بعدين.", "Zu viele Anfragen. Versuche es später erneut.", "داواکاری زۆرە. دواتر هەوڵ بدەرەوە.", "Gelek daxwaz. Paşê dîsa biceribîne.") }
    static var serverError: String { t("Server error", "خطأ بالسيرفر", "Serverfehler", "هەڵەی سێرڤەر", "Çewtiya serverê") }
    static var notFound: String { t("This item is no longer available.", "هالعنصر ما عاد متاح.", "Dieser Eintrag ist nicht mehr verfügbar.", "ئەم بڕگەیە ئیتر بەردەست نییە.", "Ev tişt êdî ne berdest e.") }
    static var badFile: String { t("This file type isn't allowed in this category.", "نوع الملف مو مسموح بهالقسم.", "Dieser Dateityp ist in dieser Kategorie nicht erlaubt.", "ئەم جۆرە فایلە لەم بەشەدا ڕێگەپێدراو نییە.", "Ev cureyê pelê di vê beşê de nayê destûrdan.") }
    static var tooLarge: String { t("The file is larger than 150 MB.", "الملف أكبر من 150 ميغا.", "Die Datei ist größer als 150 MB.", "فایلەکە لە 150 MB گەورەترە.", "Pel ji 150 MB mezintir e.") }
    static var pendingLimit: String { t("You already have 5 uploads waiting for review.", "عندك 5 ملفات لسا بانتظار المراجعة.", "Du hast bereits 5 Uploads in Prüfung.", "پێشتر ٥ بارکراوت لە چاوەڕوانی پشکنیندان.", "Jixwe 5 barkirinên te li benda kontrolê ne.") }
    static var empty: String { t("Nothing here yet.", "ما في شي هون لسا.", "Hier ist noch nichts.", "هێشتا هیچ لێرە نییە.", "Hê tiştek li vir tune.") }
    static var emptySaved: String { t("Items you save appear here.", "العناصر يلي بتحفظها بتظهر هون.", "Gemerkte Einträge erscheinen hier.", "ئەو بڕگانەی پاشەکەوتیان دەکەیت لێرە دەردەکەون.", "Tiştên ku tu tomar dikî li vir xuya dibin.") }
    static var search: String { t("Search the store", "ابحث بالمتجر", "Store durchsuchen", "گەڕان لە فرۆشگا", "Di firoşgehê de bigere") }
    static var retry: String { t("Try again", "جرّب كمان مرة", "Erneut versuchen", "دووبارە هەوڵ بدەرەوە", "Dîsa biceribîne") }
    static var downloads: String { t("downloads", "تحميل", "Downloads", "داگرتن", "daxistin") }
    static var ratings: String { t("ratings", "تقييم", "Bewertungen", "هەڵسەنگاندن", "nirxandin") }
    static var yourRating: String { t("Your rating", "تقييمك", "Deine Bewertung", "هەڵسەنگاندنەکەت", "Nirxandina te") }
    static var rateThis: String { t("Tap a star to rate", "اضغط على نجمة لتقيّم", "Tippe auf einen Stern zum Bewerten", "پەنجە لە ئەستێرەیەک بدە بۆ هەڵسەنگاندن", "Ji bo nirxandinê li stêrkekê bitikîne") }
    static var forApp: String { t("For", "لـ", "Für", "بۆ", "Ji bo") }
    static var by: String { t("By", "من", "Von", "لەلایەن", "Ji aliyê") }
    static var addedToLibrary: String { t("Added to your tweak library. Inject it from Edit IPA or the Inject button.", "انضاف لمكتبة التويكات. احقنه من تعديل الـIPA أو زر الحقن.", "Zur Tweak-Bibliothek hinzugefügt. Injiziere ihn über IPA bearbeiten oder den Injizieren-Knopf.", "زیادکرا بۆ کتێبخانەی تویک. لە دەستکاریکردنی IPA یان دوگمەی چەسپاندنەوە بیچەسپێنە.", "Li pirtûkxaneya tweakan hate zêdekirin. Ji Guhertina IPA an bişkoja Bixe bixe.") }
    static var addedToWallpapers: String { t("Added to your wallpapers.", "انضافت لخلفياتك.", "Zu deinen Hintergründen hinzugefügt.", "زیادکرا بۆ وێنەزەمینەکانت.", "Li wênesaziyên te hate zêdekirin.") }
    static var wallpaperBusy: String { t("A wallpaper is already being applied.", "في خلفية عم تنطبّق هلق.", "Ein Hintergrund wird bereits angewendet.", "وێنەزەمینەیەک لە ئێستادا جێبەجێ دەکرێت.", "Wênesaziyek niha tê bicîhkirin.") }
    static var wallpaperApplied: String { t("Wallpaper copied to the iOS gallery.", "الخلفية انسخت لمعرض iOS.", "Hintergrund in die iOS-Galerie kopiert.", "وێنەزەمینە کۆپی کرا بۆ گالەری iOS.", "Wênesazî li galeriya iOS hate kopîkirin.") }
    static var fontHint: String { t("iOS installs fonts through a font manager app or a configuration profile. Save the file, then open it with one.", "iOS بيثبّت الخطوط عن طريق تطبيق إدارة خطوط أو بروفايل. احفظ الملف وافتحه بواحد منهم.", "iOS installiert Schriften über eine Schriftverwaltungs-App oder ein Konfigurationsprofil. Sichere die Datei und öffne sie damit.", "iOS فۆنت لە ڕێگەی ئەپی بەڕێوەبردنی فۆنت یان پرۆفایلی ڕێکخستنەوە دادەمەزرێنێت. فایلەکە پاشەکەوت بکە و پاشان بەوە بیکەرەوە.", "iOS fontan bi sepaneke rêveberiya fontan an profîleke mîhengan saz dike. Pelê tomar bike û pê veke.") }
    static var soundHint: String { t("Save the sound to Files. To use it as a ringtone, import it with GarageBand or another ringtone app.", "احفظ الصوت بالملفات. لتستعمله كنغمة، استورده بـ GarageBand أو تطبيق نغمات.", "Sichere den Ton in Dateien. Für einen Klingelton importiere ihn mit GarageBand oder einer Klingelton-App.", "دەنگەکە لە Files پاشەکەوت بکە. بۆ بەکارهێنانی وەک زەنگ، بە GarageBand یان ئەپێکی تر هاوردەی بکە.", "Deng di Files de tomar bike. Ji bo zengê, bi GarageBand an sepaneke din têxe.") }
    // Upload form
    static var category: String { t("Category", "القسم", "Kategorie", "بەش", "Beş") }
    static var itemTitle: String { t("Title", "العنوان", "Titel", "ناونیشان", "Sernav") }
    static var itemDescription: String { t("Description", "الوصف", "Beschreibung", "وەسف", "Danasîn") }
    static var itemVersion: String { t("Version (optional)", "الإصدار (اختياري)", "Version (optional)", "وەشان (ئارەزوومەندانە)", "Guherto (bijarte)") }
    static var authorName: String { t("Your name (optional)", "اسمك (اختياري)", "Dein Name (optional)", "ناوت (ئارەزوومەندانە)", "Navê te (bijarte)") }
    static var targetApp: String { t("Target app", "التطبيق المستهدف", "Ziel-App", "ئەپی ئامانج", "Sepana armanc") }
    static var bundleID: String { t("Bundle ID", "معرّف الحزمة", "Bundle-ID", "ناسنامەی بەندڵ", "Bundle ID") }
    static var chooseFile: String { t("Choose file", "اختيار ملف", "Datei wählen", "هەڵبژاردنی فایل", "Pelê hilbijêre") }
    static var allowedTypes: String { t("Allowed types", "الأنواع المسموحة", "Erlaubte Typen", "جۆرە ڕێگەپێدراوەکان", "Cureyên destûrdayî") }
    static var confirmRights: String { t("I made this or have the right to share it, and it contains nothing harmful.", "أنا عملته أو عندي حق مشاركته، وما فيه شي مؤذي.", "Ich habe es erstellt oder darf es teilen, und es enthält nichts Schädliches.", "خۆم دروستم کردووە یان مافی هاوبەشکردنیم هەیە، و هیچ شتێکی زیانبەخشی تێدا نییە.", "Min ew çêkiriye an mafê parvekirinê heye, û tiştekî zirardar tê de tune.") }
    static var submit: String { t("Submit for review", "إرسال للمراجعة", "Zur Prüfung senden", "ناردن بۆ پشکنین", "Ji bo kontrolê bişîne") }
    static var submitted: String { t("Uploaded. It is now pending review and will appear in the store once approved.", "انرفع. هلق بانتظار المراجعة ورح يظهر بالمتجر بعد الموافقة.", "Hochgeladen. Es wartet jetzt auf Prüfung und erscheint nach der Freigabe im Store.", "بارکرا. ئێستا چاوەڕێی پشکنینە و دوای پەسەندکردن لە فرۆشگا دەردەکەوێت.", "Hate barkirin. Niha li benda kontrolê ye û piştî pejirandinê di firoşgehê de xuya dibe.") }
    static var uploading: String { t("Uploading…", "عم يرفع…", "Wird hochgeladen…", "بار دەکرێت…", "Tê barkirin…") }
    static var myUploads: String { t("My uploads", "ملفاتي المرفوعة", "Meine Uploads", "بارکراوەکانم", "Barkirinên min") }
    static var statusPending: String { t("Pending review", "بانتظار المراجعة", "In Prüfung", "چاوەڕێی پشکنین", "Li benda kontrolê") }
    static var statusApproved: String { t("Published", "منشور", "Veröffentlicht", "بڵاوکراوە", "Weşandî") }
    static var statusHeld: String { t("Held for safety review", "موقوف للمراجعة الأمنية", "Zur Sicherheitsprüfung zurückgehalten", "بۆ پشکنینی ئاسایش ڕاگیراوە", "Ji bo kontrola ewlehiyê hatiye ragirtin") }
    static var statusRejected: String { t("Rejected", "مرفوض", "Abgelehnt", "ڕەتکرایەوە", "Hate redkirin") }
    static var statusUploading: String { t("Upload incomplete", "الرفع ما كمل", "Upload unvollständig", "بارکردن تەواو نەبوو", "Barkirin neqediya") }
    static var cancel: String { t("Cancel", "إلغاء", "Abbrechen", "هەڵوەشاندنەوە", "Betal") }
    static var close: String { SourcesText.close }
}
