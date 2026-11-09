import SwiftUI
import PhotosUI

/// "Create anything": a request thread with Mirsa. This is a manual queue, not an instant AI chat; replies take time.
enum ForgeChatText {
    static var title: String { tr("Create anything", "إنشاء كل شي", ckb: "هەموو شتێک دروست بکە", kmr: "Her tiştî çêke") }
    static var subtitle: String { tr("Write what you want. Mirsa takes your request and works on it. It takes time.", "اكتب شو بدك، مرسى بتاخد طلبك وبتشتغل عليه، بياخد وقت", ckb: "بنووسە چیت دەوێت، مرسا داواکارییەکەت وەردەگرێت و کاری لەسەر دەکات. کاتی دەوێت.", kmr: "Binivîse tu çi dixwazî, Mirsa daxwaza te distîne û li ser dixebite. Dem dixwaze.") }
    static var guide: String { tr("This is not an instant chat. Your message goes into a queue and Mirsa answers by hand, so replies can take minutes or longer. Finished tweaks appear here and in Versions for your review. Nothing turns on by itself.", "هاد مو شات فوري. رسالتك بتدخل بالدور ومرسى بتردّ بإيدها، فالرد ممكن ياخد دقايق أو أكتر. التويكات الجاهزة بتظهر هون وبالنسخ لتراجعها. ما بيتفعّل شي لحاله.", ckb: "ئەمە گفتوگۆی خێرا نییە. نامەکەت دەچێتە ڕیز و مرسا بە دەست وەڵام دەداتەوە، بۆیە ڕەنگە چەند خولەکێک یان زیاتر بخایەنێت. تویکە تەواوەکان لێرە و لە وەشانەکان دەردەکەون بۆ پێداچوونەوە. هیچ شتێک خۆی چالاک نابێت.", kmr: "Ev ne sohbeteke tavilê ye. Peyama te dikeve rêzê û Mirsa bi destan bersiv dide, ji ber vê yekê dibe ku çend deqe an zêdetir bikşîne. Tweakên amade li vir û di Guhertoyan de ji bo kontrolê xuya dibin. Tiştek bi serê xwe naçalake.") }
    static var placeholder: String { tr("Write your request…", "اكتب طلبك…", ckb: "داواکارییەکەت بنووسە…", kmr: "Daxwaza xwe binivîse…") }
    static var newRequest: String { tr("New request", "طلب جديد", ckb: "داواکاری نوێ", kmr: "Daxwaza nû") }
    static var send: String { tr("Send", "إرسال", ckb: "ناردن", kmr: "Bişîne") }
    static var waiting: String { tr("Waiting for Mirsa. This can take a while.", "بانتظار مرسى، ممكن ياخد وقت", ckb: "چاوەڕێی مرسا. ڕەنگە کاتی بوێت.", kmr: "Li benda Mirsayê. Dibe ku demek bikşîne.") }
    static var sending: String { tr("Sending…", "عم يتبعت…", ckb: "دەنێردرێت…", kmr: "Tê şandin…") }
    static var photo: String { tr("Add image", "أضف صورة", ckb: "وێنە زیاد بکە", kmr: "Wêne zêde bike") }
    static var removeImage: String { tr("Remove image", "إزالة الصورة", ckb: "لابردنی وێنە", kmr: "Wêne rake") }
    static var close: String { tr("Close", "إغلاق", ckb: "داخستن", kmr: "Bigire") }
    static var empty: String { tr("No requests yet.", "ما في طلبات لسا.", ckb: "هێشتا داواکاری نییە.", kmr: "Hê daxwaz tune.") }
    static var limit: String { tr("Daily request limit reached. Try again tomorrow.", "وصلت للحد اليومي للطلبات. جرّب بكرا.", ckb: "گەیشتیتە سنووری ڕۆژانە. سبەی هەوڵ بدەرەوە.", kmr: "Sînorê rojane gihîşt. Sibê dîsa biceribîne.") }
    static var failed: String { tr("Could not send. Your message is saved and will retry.", "ما انبعتت. رسالتك محفوظة وبنعيد المحاولة.", ckb: "نەنێردرا. نامەکەت پاشەکەوتکراوە و دووبارە هەوڵ دەدرێت.", kmr: "Neşandî. Peyam hatiye tomarkirin û dê dîsa biceribe.") }
    static var resultSaved: String { tr("Finished. Saved in Versions for your review. Nothing was enabled.", "خلص. انحفظ بالنسخ لتراجعه. ما تفعّل شي.", ckb: "تەواو بوو. لە وەشانەکان پاشەکەوت کرا بۆ پێداچوونەوە. هیچ شتێک چالاک نەکرا.", kmr: "Qediya. Di Guhertoyan de ji bo kontrolê hat tomarkirin. Tiştek nehat çalakkirin.") }
}

enum ForgeChatTransient: Error { case failed(String) }

struct ForgeChatThread: Codable, Identifiable, Equatable {
    let id: UUID; let title: String?; let status: String?; let createdAt: String?; let updatedAt: String?
}
struct ForgeChatArtifact: Codable, Equatable { let id: UUID; let kind: String; let name: String?; let size: Int64?; let sha256: String?; let expiresAt: String? }
struct ForgeChatResult: Codable, Equatable { let inboxID: UUID?; let tweakID: UUID?; let bundleID: String?; let name: String?; let version: Int?; let artifact: ForgeChatArtifact? }
struct ForgeChatMessage: Codable, Identifiable, Equatable {
    let id: UUID; let threadID: UUID; let role: String; let text: String?; let createdAt: String?; let hasImage: Bool?; let result: ForgeChatResult?
    init(id: UUID, threadID: UUID, role: String, text: String?, createdAt: String? = nil, hasImage: Bool? = nil, result: ForgeChatResult? = nil) {
        self.id = id; self.threadID = threadID; self.role = role; self.text = text; self.createdAt = createdAt; self.hasImage = hasImage; self.result = result
    }
    enum K: String, CodingKey { case id, threadID, role, text, createdAt, hasImage, result }
    /// Tolerant on purpose: unknown roles (kat, operator...), missing threadID, odd optional types must never drop a reply.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(UUID.self, forKey: .id)
        threadID = (try? c.decode(UUID.self, forKey: .threadID)) ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        role = (try? c.decode(String.self, forKey: .role)) ?? "kat"
        text = try? c.decode(String.self, forKey: .text)
        createdAt = try? c.decode(String.self, forKey: .createdAt)
        hasImage = try? c.decode(Bool.self, forKey: .hasImage)
        result = try? c.decode(ForgeChatResult.self, forKey: .result)
    }
}

/// A message keeps its UUID until the server accepted it, so retries replay instead of duplicating.
struct ForgeChatOutgoing: Codable, Identifiable { let id: UUID; let threadID: UUID; let newThread: Bool; let text: String; var imageBase64: String? }

enum ForgeChatImage {
    /// Re-encode: strips metadata, max 1600px side and 1 MiB.
    static func prepare(_ data: Data) -> Data? {
        guard let src = UIImage(data: data) else { return nil }
        let scale = min(1, 1600 / max(max(src.size.width, src.size.height), 1))
        let size = CGSize(width: max(1, (src.size.width * scale).rounded(.down)), height: max(1, (src.size.height * scale).rounded(.down)))
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in src.draw(in: CGRect(origin: .zero, size: size)) }
        var q: CGFloat = 0.85
        while q > 0.2 { if let o = img.jpegData(compressionQuality: q), o.count <= 1_048_576 { return o }; q -= 0.15 }
        return nil
    }
}

@MainActor final class ForgeChatStore: ObservableObject {
    static let shared = ForgeChatStore()
    @Published var threads: [ForgeChatThread] = []
    @Published var messages: [UUID: [ForgeChatMessage]] = [:]
    @Published var outgoing: [ForgeChatOutgoing] = []
    @Published var error: String?
    private let key = "mirsa.chat.outgoing.v1"
    private var flushing = false
    private var handledResults = Set<UUID>()

    init() { defer { startRetrying() }; outgoing = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([ForgeChatOutgoing].self, from: $0) } ?? [] }
    private func saveOutgoing() { UserDefaults.standard.set(try? JSONEncoder().encode(outgoing), forKey: key) }

    func callPublic(_ body: [String: Any]) async throws -> Data { try await call(body) }
    /// Last real failure (HTTP status + server code, or the network error) so the user and logs can see the true reason.
    @Published var lastDiagnostic: String?
    private func call(_ body: [String: Any], retryBind: Bool = true) async throws -> Data {
        let r: ForgePreciseClient.Response
        do {
            let c = try await ForgeClient.fixToken()
            r = try await ForgePreciseClient.request(body, credentials: c)
        } catch {
            let d = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastDiagnostic = d
            throw ForgeChatTransient.failed(d)
        }
        if r.status == 200 { lastDiagnostic = nil; return r.data }
        let code = (try? JSONSerialization.jsonObject(with: r.data) as? [String: Any])?["error"] as? String ?? ""
        if r.status == 429 { throw ForgeClient.Failure.message(ForgeChatText.limit) }
        if r.status == 403, retryBind, code == "device_not_bound" || code == "device_auth_required" {
            // A fresh install is bound to the account by one ordinary Forge call, then registration is repeated.
            _ = try? await ForgeClient.get(["action": "gallery"])
            return try await call(body, retryBind: false)
        }
        lastDiagnostic = "HTTP \(r.status) \(code)"
        throw ForgeChatTransient.failed(lastDiagnostic ?? "")
    }

    /// Threads the server has accepted a message for. A thread is "new" until then, never merely because its UUID exists locally.
    private var ackedThreads = Set<UUID>()
    func serverKnows(_ id: UUID) -> Bool { ackedThreads.contains(id) || threads.contains { $0.id == id } || !(messages[id] ?? []).isEmpty }

    /// One stable draft thread id for "New request" until its first message is accepted, so reopening never makes a second thread.
    private let draftKey = "mirsa.chat.draftThread.v1"
    func draftThreadID() -> UUID {
        if let pending = outgoing.first(where: { !serverKnows($0.threadID) }) { return pending.threadID }
        if let s = UserDefaults.standard.string(forKey: draftKey), let u = UUID(uuidString: s), !serverKnows(u) { return u }
        let u = UUID(); UserDefaults.standard.set(u.uuidString, forKey: draftKey); return u
    }
    var pendingThreadIDs: [UUID] { var seen = Set<UUID>(); return outgoing.map(\.threadID).filter { !threads.contains { t in t.id == $0 } && seen.insert($0).inserted } }
    func hasInFlight(_ id: UUID) -> Bool { outgoing.contains { $0.threadID == id } }

    func send(threadID: UUID?, text: String, jpeg: Data?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let tid = threadID, hasInFlight(tid) { return } // no double send while a message is still unsent
        let img = jpeg.flatMap { ForgeChatImage.prepare($0) }?.base64EncodedString()
        outgoing.append(ForgeChatOutgoing(id: UUID(), threadID: threadID ?? UUID(), newThread: !serverKnows(threadID ?? UUID()), text: String(t.prefix(4000)), imageBase64: img))
        saveOutgoing()
        Task { await flush() }
        startRetrying()
    }

    private var retrying = false
    /// Keeps replaying saved messages (same id, server dedupes) with backoff until the server accepts them. Nothing is dropped silently.
    func startRetrying() {
        guard !retrying, !outgoing.isEmpty else { return }
        retrying = true
        Task { [weak self] in
            var delay: UInt64 = 5
            while let self, !self.outgoing.isEmpty {
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                await self.flush()
                delay = min(delay * 2, 60)
            }
            self?.retrying = false
        }
    }

    func flush() async {
        guard !flushing else { return }
        flushing = true; defer { flushing = false }
        for o in outgoing {
            var body: [String: Any] = ["action": "chat-send", "id": o.id.uuidString.lowercased(), "threadID": o.threadID.uuidString.lowercased(), "newThread": !serverKnows(o.threadID), "text": o.text]
            if let b = o.imageBase64 { body["image"] = ["mime": "image/jpeg", "base64": b] }
            do {
                _ = try await call(body)
                ackedThreads.insert(o.threadID); outgoing.removeAll { $0.id == o.id }; saveOutgoing(); error = nil
            } catch let f as ForgeClient.Failure {
                // Daily limit: the server refuses this message for good, so it cannot be replayed today.
                error = f.errorDescription; outgoing.removeAll { $0.id == o.id }; saveOutgoing()
            } catch {
                self.error = ForgeChatText.failed + (lastDiagnostic.map { " (" + $0 + ")" } ?? "")
                break // keep the message, the retry loop replays it with the same id
            }
        }
        await refreshThreads()
    }

    func refreshThreads() async {
        struct Lossy: Decodable { let value: ForgeChatThread?; init(from d: Decoder) throws { value = try? ForgeChatThread(from: d) } }
        struct W: Decodable { let threads: [Lossy] }
        guard let d = try? await call(["action": "chat-list"]), let w0 = try? JSONDecoder().decode(W.self, from: d) else { return }
        let w = (threads: w0.threads.compactMap(\.value), ())
        threads = w.threads.sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
    }

    func read(_ id: UUID) async {
        if !serverKnows(id) { return } // pending first message: nothing to read yet (avoids repeated 404)
        struct Lossy: Decodable { let value: ForgeChatMessage?; init(from d: Decoder) throws { value = try? ForgeChatMessage(from: d) } }
        struct W: Decodable { let messages: [Lossy] }
        guard let d = try? await call(["action": "chat-read", "threadID": id.uuidString.lowercased()]), let raw = try? JSONDecoder().decode(W.self, from: d) else { return }
        // One undecodable message must never hide the others (operator replies were not showing).
        let w = (messages: raw.messages.compactMap(\.value), 0)
        var all = messages; all[id] = w.messages; messages = all // reassign whole dictionary so SwiftUI always sees the change
        if w.messages.contains(where: { $0.role == "result" && !handledResults.contains($0.id) }) {
            for m in w.messages where m.role == "result" { handledResults.insert(m.id) }
            await ForgeStore.shared.syncFixInbox() // existing fix-inbox/fix-download path, review required, never auto-enabled
        }
    }

    func image(_ messageID: UUID) async -> UIImage? {
        guard let d = try? await call(["action": "chat-image", "id": messageID.uuidString.lowercased()]) else { return nil }
        return UIImage(data: d)
    }
}

struct ForgeChatEntry: View {
    @State private var open = false
    var body: some View {
        Button { open = true } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(ForgeChatText.title, systemImage: "bubble.left.and.bubble.right")
                Text(ForgeChatText.subtitle).font(.caption).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.leading)
            }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white).padding(14).appsGlass(cornerRadius: MirsaRadius.l)
        }.buttonStyle(.mirsaPress)
        .fullScreenCover(isPresented: $open) { ForgeChatRoot().environment(\.layoutDirection, .leftToRight) }
    }
}

struct ForgeChatRoot: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ForgeChatStore.shared
    @AppStorage("mirsa.chat.guideSeen") private var guideSeen = false
    @State private var path: [UUID] = []
    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !guideSeen {
                    HStack(alignment: .top) { Text(ForgeChatText.guide).font(.footnote); Button { guideSeen = true } label: { Image(systemName: "xmark") } }
                }
                if let e = store.error { Text(e).font(.footnote).foregroundStyle(.red) }
                if store.threads.isEmpty && store.outgoing.isEmpty { Text(ForgeChatText.empty).foregroundStyle(.secondary) }
                ForEach(store.pendingThreadIDs, id: \.self) { id in
                    NavigationLink(value: id) { VStack(alignment: .leading) { Text(store.outgoing.first { $0.threadID == id }?.text ?? ForgeChatText.newRequest).lineLimit(2); Text(ForgeChatText.sending).font(.caption2).foregroundStyle(.secondary) } }
                }
                ForEach(store.threads) { t in
                    NavigationLink(value: t.id) {
                        VStack(alignment: .leading) { Text(t.title ?? ForgeChatText.newRequest).lineLimit(2); if let s = t.status { Text(s).font(.caption2).foregroundStyle(.secondary) } }
                    }
                }
            }
            .navigationTitle(ForgeChatText.title).navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { ForgeChatThreadView(threadID: $0) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(ForgeChatText.close) { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { path.append(store.draftThreadID()) } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel(ForgeChatText.newRequest) }
            }
            .task { // poll only while this screen is visible
                await store.flush()
                while !Task.isCancelled { await store.refreshThreads(); try? await Task.sleep(nanoseconds: 15_000_000_000) }
            }
        }
    }
}

struct ForgeChatThreadView: View {
    let threadID: UUID
    @ObservedObject private var store = ForgeChatStore.shared
    @State private var text = ""
    @State private var photo: PhotosPickerItem?
    @State private var jpeg: Data?
    @State private var started = false
    @Environment(\.scenePhase) private var scenePhase
    private var msgs: [ForgeChatMessage] { store.messages[threadID] ?? [] }
    private var queued: [ForgeChatOutgoing] { store.outgoing.filter { o in o.threadID == threadID && !msgs.contains { $0.id == o.id } } }
    private var isNew: Bool { !started && msgs.isEmpty && queued.isEmpty && !store.threads.contains { $0.id == threadID } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(msgs) { m in bubble(m).id(m.id) }
                    ForEach(queued) { o in
                        HStack { Spacer(); VStack(alignment: .trailing) { Text(o.text); Text(ForgeChatText.sending).font(.caption2).opacity(0.7) }.padding(10).background(Color.blue.opacity(0.5)).cornerRadius(12) }
                    }
                    if let last = msgs.last, last.role == "user", queued.isEmpty {
                        Label(ForgeChatText.waiting, systemImage: "hourglass").font(.caption).foregroundStyle(.secondary)
                    }
                    if let e = store.error { Text(e).font(.caption).foregroundStyle(.red) }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding()
            }
            .onChange(of: msgs.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            Divider()
            if let jpeg, let img = UIImage(data: jpeg) {
                HStack { Image(uiImage: img).resizable().scaledToFill().frame(width: 56, height: 56).clipped().cornerRadius(8)
                    Button(ForgeChatText.removeImage) { self.jpeg = nil; photo = nil }.font(.caption); Spacer() }.padding(.horizontal)
            }
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo").frame(width: 40, height: 40) }.accessibilityLabel(ForgeChatText.photo)
                TextField(ForgeChatText.placeholder, text: $text, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                Button(ForgeChatText.send) {
                    started = true
                    store.send(threadID: threadID, text: text, jpeg: jpeg)
                    text = ""; jpeg = nil; photo = nil
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !queued.isEmpty)
            }.padding(10)
        }
        .navigationTitle(ForgeChatText.title).navigationBarTitleDisplayMode(.inline)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { jpeg = (try? await item.loadTransferable(type: Data.self)).flatMap { ForgeChatImage.prepare($0) } }
        }
        .onChange(of: scenePhase) { _, p in if p == .active { Task { await store.read(threadID) } } }
        .onChange(of: store.threads) { _, _ in Task { await store.read(threadID) } }
        .task {
            while !Task.isCancelled { await store.read(threadID); try? await Task.sleep(nanoseconds: 8_000_000_000) }
        }
    }

    @ViewBuilder private func bubble(_ m: ForgeChatMessage) -> some View {
        let mine = m.role == "user"
        HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                if m.hasImage == true { ForgeChatImageView(messageID: m.id) }
                if let t = m.text, !t.isEmpty { Text(t) }
                if m.role == "result" {
                    if m.result?.artifact == nil { Label(ForgeChatText.resultSaved, systemImage: "checkmark.shield").font(.caption).foregroundStyle(.green) }
                    if let n = m.result?.name { Text(n).font(.caption.bold()) }
                    if let a = m.result?.artifact { ForgeChatArtifactCard(threadID: m.threadID, artifact: a) }
                }
            }
            .padding(10).background(mine ? Color.blue.opacity(0.5) : Color.gray.opacity(0.25)).cornerRadius(12)
            if !mine { Spacer(minLength: 40) }
        }
    }
}

struct ForgeChatImageView: View {
    let messageID: UUID
    @State private var image: UIImage?
    var body: some View {
        Group { if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200).cornerRadius(8) } else { ProgressView().frame(height: 60) } }
            .task { image = await ForgeChatStore.shared.image(messageID) }
    }
}
