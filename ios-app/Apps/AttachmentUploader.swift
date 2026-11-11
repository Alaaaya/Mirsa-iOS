import Foundation
import UIKit

// MARK: - Feature switch and config (Mirsa 2.1 chat attachments)

enum MirsaFeatures {
    /// Owner-approved production attachments, verified against the live contract.
    static let chatAttachments21 = true
    /// .zip / .deb / .dylib chat attachments (5 MiB each). OFF until Kat confirms the server rollout.
    static let binaryAttachmentsEnabled = false
    /// Sends the optional device_udid field (read from lockdown) next to the existing device ID. OFF until the server is ready.
    static let stableDeviceLink = false
}

@MainActor enum ChatAttachmentConfig {
    /// Same production endpoint and identity as the existing chat.
    static let productionBaseURL = URL(string: "https://hirebeofomiyumwysppj.supabase.co/functions/v1/mirsa-forge")!

    /// Fixtures never access production, even when the release feature is enabled.
    static var endpoint: URL? {
        guard MirsaFeatures.chatAttachments21, !ForgeChatStore.fixture,
              productionBaseURL == ForgeClient.endpoint else { return nil }
        return productionBaseURL
    }

    /// Show the attachments menu instead of the legacy photo button.
    static var uiEnabled: Bool { endpoint != nil || fixtureUI }

    /// DEBUG UI-test harness only: shows the menu with local, network-free uploads.
    static var fixtureUI: Bool {
        #if DEBUG
        return ForgeChatStore.fixture && ProcessInfo.processInfo.arguments.contains("-MirsaChatAttachmentsFixture")
        #else
        return false
        #endif
    }
}

// MARK: - Errors (every code in the contract)

struct ChatAttachmentError: Error, Equatable {
    let status: Int
    let code: String

    static let disabled = ChatAttachmentError(status: 0, code: "attachments_disabled")
    static let network = ChatAttachmentError(status: 0, code: "network")

    /// 410: expired. The client keeps an unavailable chip with Upload again and never retries the ID silently.
    var isExpired: Bool { status == 410 }
    /// Only transient server/runtime failures keep a queued message for the retry loop (same message UUID, same IDs).
    var isTransient: Bool { status == 503 || code == "network" }

    var message: String {
        switch (status, code) {
        case (401, _): return tr("Sign-in expired. Reopen Mirsa and try again.", "انتهت الجلسة. افتح مرسى من جديد وجرّب.", ckb: "نشستەکە بەسەرچوو. میرسا دووبارە بکەرەوە و هەوڵ بدەرەوە.", kmr: "Danişîn qediya. Mirsa ji nû ve veke û dîsa biceribîne.")
        case (403, _): return tr("This device could not be verified. Reopen Mirsa and try again.", "ما قدرنا نتحقق من هالجهاز. افتح مرسى من جديد وجرّب.", ckb: "ئەم ئامێرە پشتڕاست نەکرایەوە. میرسا دووبارە بکەرەوە.", kmr: "Ev cihaz nehat piştrastkirin. Mirsa ji nû ve veke.")
        case (404, _): return tr("This attachment or request was not found.", "المرفق أو الطلب مو موجود.", ckb: "ئەم هاوپێچە یان داواکارییە نەدۆزرایەوە.", kmr: "Ev pêvek an daxwaz nehat dîtin.")
        case (410, _): return tr("This attachment expired. Upload it again.", "صلاحية المرفق خلصت. ارفعه من جديد.", ckb: "ئەم هاوپێچە بەسەرچووە. دووبارە باری بکەرەوە.", kmr: "Dema vê pêvekê qediya. Dîsa bar bike.")
        case (422, "attachment_type") where MirsaFeatures.binaryAttachmentsEnabled: return tr("Only photos, .txt, .json, .zip, .deb and .dylib files, or https links.", "بس صور، أو ملفات ‎.txt‎ و ‎.json‎ و ‎.zip‎ و ‎.deb‎ و ‎.dylib‎، أو روابط https.", ckb: "تەنها وێنە، فایلی ‎.txt‎، ‎.json‎، ‎.zip‎، ‎.deb‎ و ‎.dylib‎، یان بەستەری https.", kmr: "Tenê wêne, pelên .txt, .json, .zip, .deb û .dylib, an girêdanên https.")
        case (422, "attachment_type"): return tr("Only photos, .txt and .json files, or https links.", "بس صور، أو ملفات ‎.txt‎ و ‎.json‎، أو روابط https.", ckb: "تەنها وێنە، فایلی ‎.txt‎ و ‎.json‎، یان بەستەری https.", kmr: "Tenê wêne, pelên .txt û .json, an girêdanên https.")
        case (422, "attachment_url"): return tr("This link is not allowed. Use a public https page, not a download.", "هالرابط مو مسموح. استعمل صفحة https عامة، مو ملف تحميل.", ckb: "ئەم بەستەرە ڕێگەپێدراو نییە. پەڕەیەکی گشتی https بەکاربهێنە، نەک داگرتن.", kmr: "Ev girêdan nayê qebûlkirin. Rûpeleke giştî ya https bi kar bîne, ne daxistinek.")
        case (422, "attachment_utf8"): return tr("The file must be UTF-8 text.", "لازم يكون الملف نص UTF-8.", ckb: "فایلەکە دەبێت دەقی UTF-8 بێت.", kmr: "Pel divê nivîsa UTF-8 be.")
        case (422, "attachment_json"): return tr("The JSON file is not valid.", "ملف JSON مو صالح.", ckb: "فایلی JSON دروست نییە.", kmr: "Pelê JSON ne derbasdar e.")
        case (422, "attachment_size"): return tr("The attachment is too large.", "المرفق كبير كتير.", ckb: "هاوپێچەکە زۆر گەورەیە.", kmr: "Pêvek pir mezin e.")
        case (422, "bad_attachment_ids"): return tr("These attachments can't be sent together. Remove and add them again.", "ما فينا نبعت هالمرفقات سوا. شيلهم وضيفهم من جديد.", ckb: "ناتوانرێت ئەم هاوپێچانە پێکەوە بنێردرێن. لایان ببە و دووبارە زیادیان بکە.", kmr: "Ev pêvek bi hev re nayên şandin. Rake û dîsa zêde bike.")
        case (422, _): return tr("This attachment is not valid.", "هالمرفق مو صالح.", ckb: "ئەم هاوپێچە دروست نییە.", kmr: "Ev pêvek ne derbasdar e.")
        case (409, "attachment_storage_limit") where MirsaFeatures.binaryAttachmentsEnabled: return tr("Attachment storage for this device is full (20 MB). Remove older drafts or wait until they expire (24 hours).", "مساحة المرفقات لهالجهاز امتلت (20 ميغا). شيل مسودات قديمة أو استنى لتنتهي صلاحيتها (24 ساعة).", ckb: "شوێنی هاوپێچەکانی ئەم ئامێرە پڕ بووە (20 MB). ڕەشنووسە کۆنەکان لابەرە یان چاوەڕێ بکە تا بەسەردەچن (24 کاتژمێر).", kmr: "Cihê pêvekan li ser vê cihazê tije ye (20 MB). Pêşnûmeyên kevn rake an li benda qedandina wan bimîne (24 demjimêr).")
        case (409, "attachment_storage_limit"): return tr("Attachment storage is full on this device. Remove older drafts or wait until they expire (24 hours).", "مساحة المرفقات لهالجهاز امتلت. شيل مسودات قديمة أو استنى لتنتهي صلاحيتها (24 ساعة).", ckb: "شوێنی هاوپێچەکانی ئەم ئامێرە پڕ بووە. ڕەشنووسە کۆنەکان لابەرە یان چاوەڕێ بکە تا بەسەردەچن (24 کاتژمێر).", kmr: "Cihê pêvekan li ser vê cihazê tije ye. Pêşnûmeyên kevn rake an li benda qedandina wan bimîne (24 demjimêr).")
        case (409, "attachment_in_use"): return tr("This attachment is already part of a sent message.", "هالمرفق صار جزء من رسالة انبعتت.", ckb: "ئەم هاوپێچە بەشێکە لە نامەیەکی نێردراو.", kmr: "Ev pêvek jixwe beşek ji peyameke şandî ye.")
        case (409, _): return tr("This attachment conflicts with an earlier one. Upload it again.", "هالمرفق متعارض مع واحد قبله. ارفعه من جديد.", ckb: "ئەم هاوپێچە لەگەڵ یەکێکی پێشوو ناکۆکە. دووبارە باری بکەرەوە.", kmr: "Ev pêvek bi yekî berê re li hev nake. Dîsa bar bike.")
        case (503, _): return tr("Attachments are temporarily unavailable. Try again shortly.", "المرفقات مو متاحة هلأ. جرّب بعد شوي.", ckb: "هاوپێچەکان بۆ ماوەیەک بەردەست نین. کەمێکی تر هەوڵ بدەرەوە.", kmr: "Pêvek niha ne berdest in. Piştî demekê dîsa biceribîne.")
        case (_, "attachments_disabled"): return ChatAttachmentText.comingSoon
        default: return tr("Could not upload. Check your connection and try again.", "ما انرفع. تأكد من الاتصال وجرّب مرة تانية.", ckb: "بار نەکرا. پەیوەندی بپشکنە و دووبارە هەوڵ بدەرەوە.", kmr: "Nehat barkirin. Girêdanê kontrol bike û dîsa biceribîne.")
        }
    }
}

// MARK: - Payloads (kept in memory so an expired item can be uploaded again)

enum ChatAttachmentPayload: Equatable {
    case image(jpeg: Data, name: String)
    case text(data: Data, name: String, mime: String)
    /// .zip / .deb / .dylib, uploaded as kind=file. Stored opaque; never extracted, loaded or run.
    case binary(data: Data, name: String, mime: String)
    case link(url: URL, name: String)

    var kind: String {
        switch self { case .image: return "image"; case .text, .binary: return "file"; case .link: return "link" }
    }
    var name: String {
        switch self { case .image(_, let n), .text(_, let n, _), .binary(_, let n, _), .link(_, let n): return n }
    }
    var byteCount: Int? {
        switch self { case .image(let d, _), .text(let d, _, _), .binary(let d, _, _): return d.count; case .link: return nil }
    }
    var isBinary: Bool { if case .binary = self { return true }; return false }
}

enum ChatAttachmentReadResult: Equatable {
    case bytes(Data, mime: String)
    case link(URL)
}

// MARK: - Image normalisation

enum ChatAttachmentImage {
    /// JPEG, each side <= 1600 px, <= 2.56 MP and <= 1 MiB. Metadata is dropped by re-rendering.
    static func normalize(_ data: Data) -> Data? {
        guard let src = UIImage(data: data), src.size.width >= 1, src.size.height >= 1 else { return nil }
        var target = ChatAttachmentRules.imageTargetSize(width: Int(src.size.width * src.scale), height: Int(src.size.height * src.scale))
        for _ in 0..<6 {
            let size = CGSize(width: target.width, height: target.height)
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
            let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
                UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size)) // JPEG has no alpha
                src.draw(in: CGRect(origin: .zero, size: size))
            }
            var q: CGFloat = 0.85
            while q > 0.2 {
                if let o = img.jpegData(compressionQuality: q), o.count <= ChatAttachmentRules.imageMaxBytes { return o }
                q -= 0.15
            }
            target = (max(1, Int(Double(target.width) * 0.8)), max(1, Int(Double(target.height) * 0.8)))
        }
        return nil
    }
}

// MARK: - Uploader

/// Talks to the attachments contract with the SAME credentials the chat uses now
/// (Authorization Bearer JWT, apikey, x-mirsa-device, x-mirsa-device-token). No new identity or secret.
/// While `ChatAttachmentConfig.endpoint` is nil every call returns `.disabled` without touching the network.
@MainActor final class AttachmentUploader {
    static let shared = AttachmentUploader()

    var isEnabled: Bool { ChatAttachmentConfig.endpoint != nil }
    /// Metadata of items this device uploaded, for rendering queued/echoed messages.
    private(set) var known: [UUID: ChatAttachmentMeta] = [:]
    /// Payload per uploaded ID, in memory only, so 410 can offer Upload again.
    private(set) var payloads: [UUID: ChatAttachmentPayload] = [:]
    private let readCache = NSCache<NSUUID, NSData>()
    /// Binary uploads go one at a time.
    private var binaryBusy = false
    private var binaryWaiters: [CheckedContinuation<Void, Never>] = []

    private func acquireBinarySlot() async {
        if !binaryBusy { binaryBusy = true; return }
        await withCheckedContinuation { binaryWaiters.append($0) }
    }
    private func releaseBinarySlot() {
        if binaryWaiters.isEmpty { binaryBusy = false } else { binaryWaiters.removeFirst().resume() }
    }

    nonisolated static func isBinaryMime(_ mime: String?) -> Bool {
        guard let mime else { return false }
        return ChatAttachmentRules.binaryMimes.values.contains(mime.lowercased())
    }

    func put(_ payload: ChatAttachmentPayload, threadID: UUID) async throws -> ChatAttachmentMeta {
        if payload.isBinary {
            guard MirsaFeatures.binaryAttachmentsEnabled || ChatAttachmentConfig.fixtureUI else { throw ChatAttachmentError(status: 422, code: "attachment_type") }
            await acquireBinarySlot()
            defer { releaseBinarySlot() }
            return try await putNow(payload, threadID: threadID)
        }
        return try await putNow(payload, threadID: threadID)
    }

    private func putNow(_ payload: ChatAttachmentPayload, threadID: UUID) async throws -> ChatAttachmentMeta {
        if ChatAttachmentConfig.fixtureUI && !isEnabled { return remember(fixtureMeta(payload), payload) }
        var body: [String: Any] = ["action": "chat-attachment-put", "threadID": threadID.uuidString.lowercased(),
                                   "kind": payload.kind, "name": ChatAttachmentRules.safeName(payload.name)]
        switch payload {
        case .image(let jpeg, _): body["mime"] = "image/jpeg"; body["base64"] = jpeg.base64EncodedString()
        case .text(let data, _, let mime), .binary(let data, _, let mime): body["mime"] = mime; body["base64"] = data.base64EncodedString()
        case .link(let url, _): body["url"] = url.absoluteString
        }
        // 5 MiB decoded is ~7 MB of JSON: give the upload more time on slow connections.
        let (data, _) = try await post(body, maxBytes: 64 * 1024, timeout: payload.isBinary ? 180 : 60)
        struct W: Decodable { let attachment: ChatAttachmentMeta; let replayed: Bool? }
        guard let w = try? JSONDecoder().decode(W.self, from: data) else { throw ChatAttachmentError(status: 503, code: "attachment_unavailable") }
        return remember(w.attachment, payload)
    }

    /// Binary for image/file (validated MIME), {url, contextOnly:true} for a link. Links are never fetched.
    func read(_ id: UUID, threadID: UUID) async throws -> ChatAttachmentReadResult {
        if let c = readCache.object(forKey: id as NSUUID), let mime = known[id]?.mime { return .bytes(c as Data, mime: mime) }
        if ChatAttachmentConfig.fixtureUI && !isEnabled, let p = payloads[id] {
            switch p { case .image(let d, _): return .bytes(d, mime: "image/jpeg"); case .text(let d, _, let m), .binary(let d, _, let m): return .bytes(d, mime: m); case .link(let u, _): return .link(u) }
        }
        let binaryOK = MirsaFeatures.binaryAttachmentsEnabled
        let (data, http) = try await post(["action": "chat-attachment-read", "id": id.uuidString.lowercased(), "threadID": threadID.uuidString.lowercased()],
                                          maxBytes: (binaryOK ? ChatAttachmentRules.binaryMaxBytes : ChatAttachmentRules.imageMaxBytes) + 1024,
                                          timeout: binaryOK ? 180 : 60)
        let mime = (http.mimeType ?? "").lowercased()
        if mime == "application/json", let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], o["contextOnly"] as? Bool == true,
           let s = o["url"] as? String, case .success(let url) = ChatAttachmentRules.validateLink(s) {
            return .link(url)
        }
        guard ["image/jpeg", "text/plain", "application/json"].contains(mime) || (binaryOK && Self.isBinaryMime(mime)) else { throw ChatAttachmentError(status: 422, code: "attachment_type") }
        if Self.isBinaryMime(mime) { return .bytes(data, mime: mime) } // not cached: up to 5 MiB
        readCache.setObject(data as NSData, forKey: id as NSUUID)
        return .bytes(data, mime: mime)
    }

    /// Only unattached drafts can be deleted (attached items answer 409 attachment_in_use).
    func delete(_ id: UUID, threadID: UUID) async throws {
        defer { payloads[id] = nil }
        if ChatAttachmentConfig.fixtureUI && !isEnabled { known[id] = nil; return }
        let (data, _) = try await post(["action": "chat-attachment-delete", "id": id.uuidString.lowercased(), "threadID": threadID.uuidString.lowercased()], maxBytes: 16 * 1024)
        guard (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["deleted"] as? Bool == true else { throw ChatAttachmentError(status: 503, code: "attachment_unavailable") }
        known[id] = nil
    }

    func markUnavailable(_ ids: [UUID]) {
        for id in ids { if let m = known[id] { known[id] = ChatAttachmentMeta(id: m.id, kind: m.kind, name: m.name, mime: m.mime, size: m.size, sha256: m.sha256, expiresAt: m.expiresAt, available: false, url: m.url) } }
    }

    private func remember(_ meta: ChatAttachmentMeta, _ payload: ChatAttachmentPayload) -> ChatAttachmentMeta {
        known[meta.id] = meta; payloads[meta.id] = payload
        return meta
    }

    private func fixtureMeta(_ p: ChatAttachmentPayload) -> ChatAttachmentMeta {
        let size: Int64?
        switch p { case .image(let d, _): size = Int64(d.count); case .text(let d, _, _), .binary(let d, _, _): size = Int64(d.count); case .link: size = nil }
        var url: String?
        if case .link(let u, _) = p { url = u.absoluteString }
        let mime: String? = { switch p { case .image: return "image/jpeg"; case .text(_, _, let m), .binary(_, _, let m): return m; case .link: return nil } }()
        return ChatAttachmentMeta(id: UUID(), kind: p.kind, name: ChatAttachmentRules.safeName(p.name), mime: mime, size: size,
                                  expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(86_400)), available: true, url: url)
    }

    /// One request with the chat's existing credentials. Errors are {error:<code>} with 401/403/404/410/422/409/503.
    private func post(_ body: [String: Any], maxBytes: Int, timeout: TimeInterval = 60) async throws -> (Data, HTTPURLResponse) {
        guard let url = ChatAttachmentConfig.endpoint else { throw ChatAttachmentError.disabled }
        let c: ForgeFixCredentials
        do { c = try await ForgeClient.fixToken() } catch { throw ChatAttachmentError(status: 401, code: "session") }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        for (k, v) in Self.headers(c) { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: OTANoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let pair: (Data, URLResponse)
        do { pair = try await session.data(for: req) } catch { throw ChatAttachmentError.network }
        let (data, resp) = pair
        guard let http = resp as? HTTPURLResponse, resp.url == url, data.count <= maxBytes else { throw ChatAttachmentError.network }
        guard http.statusCode == 200 else { throw Self.failure(http.statusCode, data) }
        return (data, http)
    }

    /// The same headers the chat sends today, plus the existing anon/publishable apikey. Nothing new.
    nonisolated static func headers(_ c: ForgeFixCredentials) -> [String: String] {
        ["Authorization": "Bearer " + c.accessToken,
         "apikey": WebBackendConfig.defaultPublishableKey,
         "x-mirsa-device": c.deviceID,
         "x-mirsa-device-token": c.deviceToken,
         "Content-Type": "application/json"]
    }

    nonisolated static func failure(_ status: Int, _ data: Data) -> ChatAttachmentError {
        let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? ""
        return ChatAttachmentError(status: status, code: code)
    }
}

// MARK: - Composer drafts (per thread, survive closing the conversation)

struct ChatDraftAttachment: Identifiable, Equatable {
    enum State: Equatable { case uploading, ready(ChatAttachmentMeta), failed(String), unavailable(String) }
    let id: UUID
    var payload: ChatAttachmentPayload
    var state: State
    var meta: ChatAttachmentMeta? { if case .ready(let m) = state { return m }; return nil }
}

@MainActor final class ChatAttachmentDrafts: ObservableObject {
    static let shared = ChatAttachmentDrafts()
    @Published private(set) var byThread: [UUID: [ChatDraftAttachment]] = [:]

    func items(_ thread: UUID) -> [ChatDraftAttachment] { byThread[thread] ?? [] }
    var uploader: AttachmentUploader { .shared }

    func canAdd(_ thread: UUID) -> Bool { items(thread).count < ChatAttachmentRules.maxPerMessage }

    func add(_ payload: ChatAttachmentPayload, thread: UUID) {
        guard canAdd(thread) else { return }
        let d = ChatDraftAttachment(id: UUID(), payload: payload, state: .uploading)
        byThread[thread, default: []].append(d)
        upload(d.id, thread: thread)
    }

    /// Fresh upload of the same payload (after 410 or a failure). Expired IDs are never re-sent.
    func uploadAgain(_ id: UUID, thread: UUID) { set(id, thread: thread, .uploading); upload(id, thread: thread) }

    private func upload(_ id: UUID, thread: UUID) {
        guard let d = items(thread).first(where: { $0.id == id }) else { return }
        Task {
            do { let m = try await uploader.put(d.payload, threadID: thread); set(id, thread: thread, .ready(m)) }
            catch let e as ChatAttachmentError { set(id, thread: thread, e.isExpired ? .unavailable(e.message) : .failed(e.message)) }
            catch { set(id, thread: thread, .failed(ChatAttachmentError.network.message)) }
        }
    }

    func remove(_ id: UUID, thread: UUID) {
        guard let d = items(thread).first(where: { $0.id == id }) else { return }
        byThread[thread]?.removeAll { $0.id == id }
        if let m = d.meta { Task { try? await uploader.delete(m.id, threadID: thread) } } // unattached draft only
    }

    /// Marks chips whose 24 h TTL already passed, so they are never sent.
    func expireStale(_ thread: UUID) {
        for d in items(thread) { if let m = d.meta, m.isExpired() { set(d.id, thread: thread, .unavailable(ChatAttachmentError(status: 410, code: "").message)) } }
    }

    /// IDs bound to the next message, or nil while any chip is uploading or unusable.
    func readyIDs(_ thread: UUID) -> [UUID]? {
        let all = items(thread)
        guard all.allSatisfy({ $0.meta != nil }) else { return nil }
        return ChatAttachmentRules.sendIDs(all.compactMap { $0.meta?.id })
    }

    /// Sent: the IDs now belong to the message. Payloads stay with the uploader for Upload again.
    func clearAfterSend(_ thread: UUID) { byThread[thread] = nil }

    /// A send was refused (410/404/409/422): put the items back as chips so the user can upload again.
    func restore(_ ids: [UUID], thread: UUID, problem: ChatAttachmentError) {
        uploader.markUnavailable(ids)
        var list = items(thread)
        for id in ids {
            guard let p = uploader.payloads[id], !list.contains(where: { $0.meta?.id == id }) else { continue }
            list.append(ChatDraftAttachment(id: UUID(), payload: p, state: problem.isExpired ? .unavailable(problem.message) : .failed(problem.message)))
        }
        byThread[thread] = Array(list.prefix(ChatAttachmentRules.maxPerMessage))
    }

    private func set(_ id: UUID, thread: UUID, _ s: ChatDraftAttachment.State) {
        guard var list = byThread[thread], let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].state = s; byThread[thread] = list
    }
}

// MARK: - Strings

enum ChatAttachmentText {
    static var attach: String { tr("Attach", "إرفاق", ckb: "هاوپێچ", kmr: "Pêve bike") }
    static var photos: String { tr("Photos", "الصور", ckb: "وێنەکان", kmr: "Wêne") }
    static var files: String { tr("Files", "ملفات", ckb: "فایلەکان", kmr: "Pel") }
    static var fromLink: String { tr("From link", "من رابط", ckb: "لە بەستەرەوە", kmr: "Ji girêdanê") }
    static var linkTitle: String { tr("Add a link", "أضف رابط", ckb: "بەستەرێک زیاد بکە", kmr: "Girêdanekê zêde bike") }
    static var add: String { tr("Add", "إضافة", ckb: "زیادکردن", kmr: "Zêde bike") }
    static var uploadAgain: String { tr("Upload again", "ارفع من جديد", ckb: "دووبارە بارکردن", kmr: "Dîsa bar bike") }
    static var uploading: String { tr("Uploading…", "عم يرفع…", ckb: "بار دەکرێت…", kmr: "Tê barkirin…") }
    static var unavailable: String { tr("Unavailable", "مو متاح", ckb: "بەردەست نییە", kmr: "Ne berdest e") }
    static var contextOnly: String { tr("Context only, not opened", "للسياق بس، ما بينفتح", ckb: "تەنها بۆ زانیاری، ناکرێتەوە", kmr: "Tenê ji bo çarçoveyê, nayê vekirin") }
    static var copyLink: String { tr("Copy link", "انسخ الرابط", ckb: "بەستەر کۆپی بکە", kmr: "Girêdanê kopî bike") }
    static var removeAttachment: String { tr("Remove attachment", "شيل المرفق", ckb: "هاوپێچ لابە", kmr: "Pêvekê rake") }
    static var comingSoon: String { tr("Attachment upload is coming soon. Your text still sends.", "رفع المرفقات جاي قريباً. نصّك بينبعت عادي.", ckb: "بارکردنی هاوپێچ بەم زووانە دێت. دەقەکەت هەر دەنێردرێت.", kmr: "Barkirina pêvekan nêzîk e. Nivîsa te dîsa tê şandin.") }
    static var needsUpload: String { tr("Wait for uploads to finish, or remove the unavailable ones.", "استنى ليخلص الرفع، أو شيل المرفقات المو متاحة.", ckb: "چاوەڕێ بکە تا بارکردن تەواو دەبێت، یان ئەوانەی بەردەست نین لابە.", kmr: "Li benda qedandina barkirinê bimîne, an yên ne berdest rake.") }
    /// Short in-app explanation of the feature (shown above the chips).
    static var help: String { MirsaFeatures.binaryAttachmentsEnabled ? helpBinary : helpText }
    static var helpBinary: String { tr("Attachments help Mirsa understand your request: up to 3 per message, photos, .txt/.json files (max 256 KB), .zip/.deb/.dylib files (max 5 MB each) or https links. Files are stored privately, never opened or run, and expire after 24 hours. Up to 20 MB per device.", "المرفقات بتساعد مرسى يفهم طلبك: لحد 3 بالرسالة، صور، ملفات ‎.txt/.json‎ (لحد 256 KB)، ملفات ‎.zip/.deb/.dylib‎ (لحد 5 ميغا للملف) أو روابط https. الملفات بتنحفظ بشكل خاص، ما بتنفتح ولا بتشتغل، وبتنحذف بعد 24 ساعة. لحد 20 ميغا للجهاز.", ckb: "هاوپێچەکان یارمەتی میرسا دەدەن داواکارییەکەت تێبگات: تا 3 بۆ هەر نامەیەک، وێنە، فایلی ‎.txt/.json‎ (تا 256 KB)، فایلی ‎.zip/.deb/.dylib‎ (تا 5 MB بۆ هەر فایلێک) یان بەستەری https. فایلەکان بە تایبەتی هەڵدەگیرێن، ناکرێنەوە و کار ناکەن، و دوای 24 کاتژمێر بەسەردەچن. تا 20 MB بۆ هەر ئامێرێک.", kmr: "Pêvek alîkariya Mirsa dikin ku daxwaza te fêm bike: heta 3 di peyamekê de, wêne, pelên .txt/.json (herî zêde 256 KB), pelên .zip/.deb/.dylib (her yek herî zêde 5 MB) an girêdanên https. Pel bi taybetî tên tomarkirin, nayên vekirin û naxebitin, û piştî 24 demjimêran diqedin. Heta 20 MB ji bo her cihazekê.") }
    static var helpText: String { tr("Attachments help Mirsa understand your request: up to 3 photos, .txt/.json files (max 256 KB) or https links. Links are context only and never opened. Attachments expire after 24 hours.", "المرفقات بتساعد مرسى يفهم طلبك: لحد 3 صور، ملفات ‎.txt/.json‎ (لحد 256 KB) أو روابط https. الروابط للسياق بس وما بتنفتح. المرفقات بتنتهي بعد 24 ساعة.", ckb: "هاوپێچەکان یارمەتی میرسا دەدەن داواکارییەکەت تێبگات: تا 3 وێنە، فایلی ‎.txt/.json‎ (تا 256 KB) یان بەستەری https. بەستەرەکان تەنها بۆ زانیارین و ناکرێنەوە. هاوپێچەکان دوای 24 کاتژمێر بەسەردەچن.", kmr: "Pêvek alîkariya Mirsa dikin ku daxwaza te fêm bike: heta 3 wêne, pelên .txt/.json (herî zêde 256 KB) an girêdanên https. Girêdan tenê ji bo çarçoveyê ne û nayên vekirin. Pêvek piştî 24 demjimêran diqedin.") }
    static var linkHelp: String { tr("Paste a public https link. Mirsa keeps it as context only and never opens or downloads it. App, archive and installer files (IPA, APK, ZIP, DEB…) are not accepted.", "الصق رابط https عام. مرسى بيحتفظ فيه للسياق بس، وما بيفتحه ولا بينزّله. ملفات التطبيقات والأرشيف والتثبيت (IPA، APK، ZIP، DEB…) مو مقبولة.", ckb: "بەستەرێکی گشتی https بلکێنە. میرسا تەنها وەک زانیاری هەڵیدەگرێت و هەرگیز نایکاتەوە یان دایناگرێت. فایلی ئەپ، ئەرشیف و دامەزراندن (IPA، APK، ZIP، DEB…) وەرناگیرێن.", kmr: "Girêdaneke giştî ya https bi cih bike. Mirsa wê tenê ji bo çarçoveyê digire û qet venake an danaxe. Pelên sepan, arşîv û sazkirinê (IPA, APK, ZIP, DEB…) nayên qebûlkirin.") }

    static func link(_ p: ChatAttachmentRules.LinkProblem) -> String {
        switch p {
        case .empty: return tr("Paste a link.", "الصق رابط.", ckb: "بەستەرێک بلکێنە.", kmr: "Girêdanekê bi cih bike.")
        case .notHTTPS: return tr("Only https links are accepted.", "بس روابط https مقبولة.", ckb: "تەنها بەستەری https وەردەگیرێت.", kmr: "Tenê girêdanên https tên qebûlkirin.")
        case .blockedFile: return tr("Links to IPA, APK, ZIP, DEB or other app/archive files are not accepted.", "روابط ملفات IPA أو APK أو ZIP أو DEB أو أي تطبيق/أرشيف مو مقبولة.", ckb: "بەستەری فایلی IPA، APK، ZIP، DEB یان هەر ئەپ/ئەرشیفێک وەرناگیرێت.", kmr: "Girêdanên pelên IPA, APK, ZIP, DEB an sepan/arşîvên din nayên qebûlkirin.")
        case .tooLong: return tr("This link is too long.", "الرابط طويل كتير.", ckb: "ئەم بەستەرە زۆر درێژە.", kmr: "Ev girêdan pir dirêj e.")
        case .credentials, .host, .port, .invalid: return tr("Use a normal public https address (no IPs, local hosts, ports or passwords).", "استعمل عنوان https عام عادي (بلا IP أو أجهزة محلية أو بورت أو كلمة سر).", ckb: "ناونیشانێکی ئاسایی گشتی https بەکاربهێنە (بێ IP، هۆستی ناوخۆیی، پۆرت یان وشەی نهێنی).", kmr: "Navnîşaneke giştî ya https a asayî bi kar bîne (bê IP, hosta herêmî, port an şîfre).")
        }
    }

    static func file(_ p: ChatAttachmentRules.FileProblem) -> String {
        switch p {
        case .type where MirsaFeatures.binaryAttachmentsEnabled: return tr("Only .txt, .json, .zip, .deb and .dylib files.", "بس ملفات ‎.txt‎ و ‎.json‎ و ‎.zip‎ و ‎.deb‎ و ‎.dylib‎.", ckb: "تەنها فایلی ‎.txt‎، ‎.json‎، ‎.zip‎، ‎.deb‎ و ‎.dylib‎.", kmr: "Tenê pelên .txt, .json, .zip, .deb û .dylib.")
        case .type: return tr("Only .txt and .json files.", "بس ملفات ‎.txt‎ و ‎.json‎.", ckb: "تەنها فایلی ‎.txt‎ و ‎.json‎.", kmr: "Tenê pelên .txt û .json.")
        case .size: return tr("The file must be under 256 KB.", "لازم يكون الملف أقل من 256 KB.", ckb: "فایلەکە دەبێت کەمتر لە 256 KB بێت.", kmr: "Pel divê ji 256 KB kêmtir be.")
        case .utf8, .control: return ChatAttachmentError(status: 422, code: "attachment_utf8").message
        case .json: return ChatAttachmentError(status: 422, code: "attachment_json").message
        case .binarySize: return tr("The file must be 5 MB or smaller.", "لازم يكون الملف 5 ميغا أو أقل.", ckb: "فایلەکە دەبێت 5 MB یان کەمتر بێت.", kmr: "Pel divê 5 MB an kêmtir be.")
        case .signature: return tr("This file doesn't look like a real .zip, .deb or .dylib.", "هالملف ما بيبين إنه ‎.zip‎ أو ‎.deb‎ أو ‎.dylib‎ حقيقي.", ckb: "ئەم فایلە وەک ‎.zip‎، ‎.deb‎ یان ‎.dylib‎ ی ڕاستەقینە دیار نییە.", kmr: "Ev pel wekî .zip, .deb an .dylib a rastîn xuya nake.")
        }
    }
    static var downloading: String { tr("Downloading…", "عم ينزل…", ckb: "دادەگیرێت…", kmr: "Tê daxistin…") }
    static var downloadFailed: String { tr("Couldn't download the file.", "ما قدرنا ننزّل الملف.", ckb: "فایلەکە دانەگیرا.", kmr: "Pel nehat daxistin.") }
    static var imageFailed: String { tr("This photo could not be prepared.", "ما قدرنا نجهّز هالصورة.", ckb: "ئەم وێنەیە ئامادە نەکرا.", kmr: "Ev wêne nehat amadekirin.") }
}
