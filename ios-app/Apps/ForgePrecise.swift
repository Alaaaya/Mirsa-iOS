import SwiftUI

/// "Create precisely": owner-only queue handled by a person, never an LLM. The app only sends the request
/// and later receives the built tweak through the existing fix inbox (review required, never auto-enabled).
struct ForgePreciseItem: Codable, Identifiable, Equatable {
    let id: UUID
    let tweakID: UUID
    let bundleID: String
    let name: String
    let prompt: String
    let version: Int
    let status: String
    let statusText: String?
    let inboxID: UUID?
    let errorCode: String?
    let createdAt: String?
    let updatedAt: String?
    let hasScreenshot: Bool?
    var isFinal: Bool { status == "ready" || status == "failed" }
}

enum ForgePreciseText {
    static var create: String { tr("Create precisely", "أنشئ بدقة", ckb: "بە وردی دروست بکە", kmr: "Bi rastî çêke") }
    static var subtitle: String { tr("Takes a few minutes, but it is more accurate.", "بياخد وقت (دقايق)، بس بيكون أدق.", ckb: "چەند خولەکێک دەخایەنێت، بەڵام وردترە.", kmr: "Çend deqeyan dikişîne, lê rasttir e.") }
    static var guide: String { tr("How it works: press Create precisely and your request is queued. It is written by hand, not instantly. Status shows Writing, then the finished tweak appears in Versions for your review. It never turns on by itself. Use Refresh to check.", "كيف بيشتغل: دوس أنشئ بدقة وطلبك بيدخل بالدور. بينكتب بإيد، مو فوري. الحالة بتظهر قيد الكتابة، وبعدها بتطلع النسخة الجاهزة بالنسخ لتراجعها. ما بتتفعّل لحالها. دوس تحديث تشوف الحالة.", ckb: "چۆن کار دەکات: دوگمەی بە وردی دروست بکە دابگرە و داواکارییەکەت دەچێتە ڕیز. بە دەست دەنووسرێت. دۆخ دەبێتە لە نووسیندایە، پاشان وەشانە تەواوەکە لە وەشانەکان دەردەکەوێت بۆ پێداچوونەوە. خۆی چالاک نابێت.", kmr: "Çawa dixebite: Bi rastî çêke bitikîne, daxwaz dikeve rêzê. Bi destan tê nivîsandin. Rewş dibe Tê nivîsandin, paşê guhertoya amade di Guhertoyan de ji bo kontrolê xuya dibe. Bi serê xwe naçalake.") }
    static var refresh: String { tr("Refresh", "تحديث", ckb: "نوێکردنەوە", kmr: "Nû bike") }
    static var queued: String { tr("Request queued.", "انبعت الطلب وصار بالدور.", ckb: "داواکاری چووە ڕیز.", kmr: "Daxwaz ket rêzê.") }
    static var writing: String { "قيد الكتابة" }
    static func label(_ it: ForgePreciseItem) -> String {
        switch it.status {
        case "ready": return tr("Ready, saved in Versions for review", "جاهز، انحفظ بالنسخ للمراجعة", ckb: "ئامادەیە، لە وەشانەکان پاشەکەوت کرا", kmr: "Amade ye, di Guhertoyan de hat tomarkirin")
        case "failed": return tr("Could not be completed", "ما انعمل", ckb: "تەواو نەبوو", kmr: "Neqediya") + (it.errorCode.map { " (" + $0 + ")" } ?? "")
        default: return it.statusText ?? writing
        }
    }
    static var screenshot: String { tr("Create precisely from this image", "أنشئ بدقة من هالصورة", ckb: "بە وردی لەم وێنەیە دروست بکە", kmr: "Ji vê wêneyî bi rastî çêke") }
}

enum ForgePreciseClient {
    struct Response { let status: Int; let data: Data }

    /// Unlike fixRequest this exposes the status code: nonadmin capability answers HTTP 403.
    static func request(_ body: [String: Any], credentials c: ForgeFixCredentials) async throws -> Response {
        var req = URLRequest(url: ForgeClient.endpoint, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("Bearer " + c.accessToken, forHTTPHeaderField: "Authorization")
        req.setValue(c.deviceID, forHTTPHeaderField: "x-mirsa-device")
        req.setValue(c.deviceToken, forHTTPHeaderField: "x-mirsa-device-token")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: OTANoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, resp.url == ForgeClient.endpoint, data.count <= 2 * 1024 * 1024 else {
            throw ForgeClient.Failure.message("Precise request failed.")
        }
        return Response(status: http.statusCode, data: data)
    }

    static func capability(_ c: ForgeFixCredentials) async -> Bool {
        guard let r = try? await request(["action": "precise-capability"], credentials: c), r.status == 200,
              let o = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any] else { return false }
        return o["enabled"] as? Bool == true
    }

    static func decodeItem(_ data: Data) throws -> ForgePreciseItem {
        struct Wrap: Decodable { let item: ForgePreciseItem }
        return try JSONDecoder().decode(Wrap.self, from: data).item
    }
    static func decodeList(_ data: Data) throws -> [ForgePreciseItem] {
        struct Wrap: Decodable { let items: [ForgePreciseItem] }
        return try JSONDecoder().decode(Wrap.self, from: data).items
    }
    static func ok(_ r: Response) throws -> Data {
        switch r.status {
        case 200: return r.data
        case 403: throw ForgeClient.Failure.message(tr("Not available on this device.", "مو متاح عهالجهاز.", ckb: "لەم ئامێرە بەردەست نییە.", kmr: "Li ser vê cihazê peyda nîne."))
        case 409: throw ForgeClient.Failure.message(tr("This request id was already used with different content.", "هالطلب انستخدم قبل بمحتوى مختلف.", ckb: "ئەم داواکارییە پێشتر بە ناوەڕۆکێکی جیاواز بەکارهاتووە.", kmr: "Ev daxwaz berê bi naverokeke din hatiye bikaranîn."))
        default: throw ForgeClient.Failure.message(tr("Request failed. Try again.", "فشل الطلب. جرّب مرة تانية.", ckb: "داواکاری شکستی هێنا. دووبارە هەوڵ بدە.", kmr: "Daxwaz têk çû. Dîsa biceribîne."))
        }
    }
}

/// A request keeps its client id until the server accepted it, so network retries replay instead of duplicating.
struct ForgePrecisePending: Codable { let id: UUID; let tweakID: UUID; let bundleID: String; let name: String; let prompt: String; let version: Int; let contextJSON: Data; var screenshotJSON: Data? = nil }

@MainActor final class ForgePreciseStore: ObservableObject {
    static let shared = ForgePreciseStore()
    @Published var enabled = false
    @Published var items: [ForgePreciseItem] = []
    @Published var busy = false
    private let key = "mirsa.precise.pending.v1"
    private let maxContext = 1_000_000

    private var pending: [ForgePrecisePending] {
        get { (UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([ForgePrecisePending].self, from: $0) }) ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    /// Gate is the server capability, never a local flag. Any failure hides the feature.
    func refreshCapability() async {
        guard let c = try? await ForgeClient.fixToken() else { enabled = false; return }
        enabled = await ForgePreciseClient.capability(c)
        if enabled { await refresh() }
    }

    func refresh() async {
        guard enabled, let c = try? await ForgeClient.fixToken() else { return }
        do {
            await flushPending(c)
            let list = try ForgePreciseClient.decodeList(ForgePreciseClient.ok(await ForgePreciseClient.request(["action": "precise-list"], credentials: c)))
            items = list.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            if list.contains(where: { $0.status == "ready" }) { await ForgeStore.shared.syncFixInbox() }
        } catch { /* keep the old list; user can refresh again */ }
    }

    private func flushPending(_ c: ForgeFixCredentials) async {
        for p in pending { _ = try? await send(p, c) }
    }

    @discardableResult private func send(_ p: ForgePrecisePending, _ c: ForgeFixCredentials) async throws -> ForgePreciseItem {
        let context = (try? JSONSerialization.jsonObject(with: p.contextJSON)) ?? [String: Any]()
        let body: [String: Any] = ["action": "precise-enqueue", "id": p.id.uuidString.lowercased(), "tweakID": p.tweakID.uuidString.lowercased(),
            "bundleID": p.bundleID, "name": p.name, "prompt": p.prompt, "version": p.version, "context": context]
        var body = body
        if let s = p.screenshotJSON, let shot = try? JSONSerialization.jsonObject(with: s) { body["screenshot"] = shot }
        let r = try await ForgePreciseClient.request(body, credentials: c)
        if r.status == 409 { pending.removeAll { $0.id == p.id } }
        let item = try ForgePreciseClient.decodeItem(ForgePreciseClient.ok(r))
        pending.removeAll { $0.id == p.id }
        if !items.contains(where: { $0.id == item.id }) { items.insert(item, at: 0) }
        return item
    }

    /// context: optional JSON data only (inspector facts or screenshot reference). Nothing is fetched remotely.
    func enqueue(projectID: UUID, prompt: String, context: [String: Any] = [:], screenshot: [String: Any]? = nil) async throws {
        guard enabled, let p = ForgeStore.shared.project(projectID), let v = p.currentVersion ?? p.versions.last else {
            throw ForgeClient.Failure.message(tr("Not available on this device.", "مو متاح عهالجهاز."))
        }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...2000).contains(text.count) else { throw ForgeClient.Failure.message(tr("Describe the tweak first (up to 2000 characters).", "اوصف التويك أول (لحد ٢٠٠٠ حرف).")) }
        let ctx = try JSONSerialization.data(withJSONObject: context)
        guard ctx.count <= maxContext else { throw ForgeClient.Failure.message(tr("The attached image is too large.", "الصورة المرفقة كبيرة كتير.")) }
        let shotData = try screenshot.map { try JSONSerialization.data(withJSONObject: $0) }
        let item = ForgePrecisePending(id: UUID(), tweakID: v.tweakID, bundleID: p.bundleID, name: ForgeFeaturePolicy.name(p.name),
                                        prompt: text, version: max(1, p.versions.count), contextJSON: ctx, screenshotJSON: shotData)
        pending.append(item)
        busy = true; defer { busy = false }
        let c = try await ForgeClient.fixToken()
        try await send(item, c) // on a network error the pending copy stays and is replayed with the same id
    }
}

struct ForgePreciseSection: View {
    let id: UUID
    @Binding var prompt: String
    @ObservedObject private var precise = ForgePreciseStore.shared
    @AppStorage("mirsa.precise.guideSeen") private var guideSeen = false
    @State private var error: String?
    @State private var note: String?

    var body: some View {
        Group {
            if precise.enabled {
                VStack(alignment: .leading, spacing: 8) {
                    Button { start() } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(ForgePreciseText.create, systemImage: "scope")
                            Text(ForgePreciseText.subtitle).font(.caption).foregroundStyle(.white.opacity(0.6))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.mirsaPress).disabled(precise.busy)
                    if !guideSeen {
                        HStack(alignment: .top) {
                            Text(ForgePreciseText.guide).font(.caption).foregroundStyle(.white.opacity(0.75))
                            Button { guideSeen = true } label: { Image(systemName: "xmark") }
                        }
                    }
                    if let note { Text(note).font(.caption).foregroundStyle(.green) }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    ForEach(precise.items.filter { $0.tweakID == currentTweakID }) { it in
                        HStack {
                            Image(systemName: it.status == "ready" ? "checkmark.circle" : it.status == "failed" ? "exclamationmark.triangle" : "pencil.and.outline")
                            VStack(alignment: .leading) {
                                Text(it.prompt).lineLimit(2).font(.caption)
                                Text(ForgePreciseText.label(it)).font(.caption2).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                        }
                    }
                    Button(ForgePreciseText.refresh) { Task { await precise.refresh() } }.font(.caption.bold())
                }
                .foregroundStyle(.white).padding(14).appsGlass(cornerRadius: MirsaRadius.l)
                .environment(\.layoutDirection, .leftToRight)
            }
        }
        .task { await precise.refreshCapability() }
    }
    private var currentTweakID: UUID? { ForgeStore.shared.project(id)?.currentVersion?.tweakID }
    private func start() {
        Task {
            error = nil; note = nil
            do { try await precise.enqueue(projectID: id, prompt: prompt); note = ForgePreciseText.queued; guideSeen = true; prompt = "" }
            catch { self.error = error.localizedDescription }
        }
    }
}

enum ForgePreciseImage {
    /// Backend contract: top-level screenshot {mime:image/jpeg, base64, region{x,y,w,h} normalized to the ENCODED image}.
    /// Image and region travel together. Re-encoding via UIKit drops EXIF/IPTC/XMP/comments. Max 1600px side, 1 MiB.
    static func screenshot(jpeg: Data, region: CGRect) throws -> [String: Any] {
        guard region.width > 0.02, region.height > 0.02, let src = UIImage(data: jpeg) else {
            throw ForgeClient.Failure.message(ForgeImageMarkView.hint)
        }
        let longest = max(src.size.width, src.size.height)
        let scale = min(1, 1600 / max(longest, 1))
        let size = CGSize(width: max(1, (src.size.width * scale).rounded(.down)), height: max(1, (src.size.height * scale).rounded(.down)))
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in src.draw(in: CGRect(origin: .zero, size: size)) }
        var quality: CGFloat = 0.85
        while quality > 0.2 {
            if let out = img.jpegData(compressionQuality: quality), out.count <= 1_048_576 {
                // Normalized region is resolution independent; clamp into 0...1 so it fits the image.
                let x = max(0, min(1, region.minX)), y = max(0, min(1, region.minY))
                let w = max(0, min(1 - x, region.width)), h = max(0, min(1 - y, region.height))
                return ["mime": "image/jpeg", "base64": out.base64EncodedString(), "region": ["x": x, "y": y, "w": w, "h": h]]
            }
            quality -= 0.15
        }
        throw ForgeClient.Failure.message(tr("The attached image is too large.", "الصورة المرفقة كبيرة كتير."))
    }
}
