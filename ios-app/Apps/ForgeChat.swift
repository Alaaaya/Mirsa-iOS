import SwiftUI
import PhotosUI

/// Mirsa AI: a manually handled request thread. This is a manual queue, not an instant AI chat; replies take time.
enum ForgeChatText {
    static var title: String { tr("Mirsa AI", "مرسى AI", ckb: "میرسا AI", kmr: "Mirsa AI") }
    static var subtitle: String { tr("Write what you want, Mirsa takes your request and works on it. It takes time.", "اكتب شو بدك، مرسى بياخد طلبك وبيشتغل عليه، بياخد وقت", ckb: "بنووسە چیت دەوێت، میرسا داواکارییەکەت وەردەگرێت و کاری لەسەر دەکات، کاتی دەوێت.", kmr: "Binivîse tu çi dixwazî, Mirsa daxwaza te distîne û li ser dixebite. Dem dixwaze.") }
    static var guide: String { tr("Mirsa AI is not an instant chat. Your message goes into a queue and Mirsa answers by hand, so replies can take minutes or longer. Finished tweaks appear here and in Versions for your review. Nothing turns on by itself.", "مرسى AI مو شات فوري. رسالتك بتدخل بالدور ومرسى بتردّ بإيدها، فالرد ممكن ياخد دقايق أو أكتر. التويكات الجاهزة بتظهر هون وبالنسخ لتراجعها. ما بيتفعّل شي لحاله.", ckb: "میرسا AI گفتوگۆی خێرا نییە. نامەکەت دەچێتە ڕیز و میرسا بە دەست وەڵام دەداتەوە، بۆیە ڕەنگە چەند خولەکێک یان زیاتر بخایەنێت. تویکە تەواوەکان لێرە و لە وەشانەکان دەردەکەون بۆ پێداچوونەوە. هیچ شتێک خۆی چالاک نابێت.", kmr: "Mirsa AI ne sohbeteke tavilê ye. Peyama te dikeve rêzê û Mirsa bi destan bersiv dide, ji ber vê yekê dibe ku çend deqe an zêdetir bikşîne. Tweakên amade li vir û di Guhertoyan de ji bo kontrolê xuya dibin. Tiştek bi serê xwe naçalake.") }
    static var placeholder: String { tr("Write your request…", "اكتب طلبك…", ckb: "داواکارییەکەت بنووسە…", kmr: "Daxwaza xwe binivîse…") }
    static var newRequest: String { tr("New request", "طلب جديد", ckb: "داواکاری نوێ", kmr: "Daxwaza nû") }
    static var send: String { tr("Send", "إرسال", ckb: "ناردن", kmr: "Bişîne") }
    static var waiting: String { tr("Waiting for Mirsa. This can take a while.", "بانتظار مرسى. ممكن ياخد وقت.", ckb: "چاوەڕێی میرسا. ڕەنگە کاتی بوێت.", kmr: "Li benda Mirsa. Dibe ku demek bikşîne.") }
    static var sending: String { tr("Sending…", "عم يتبعت…", ckb: "دەنێردرێت…", kmr: "Tê şandin…") }
    static var photo: String { tr("Add image", "أضف صورة", ckb: "وێنە زیاد بکە", kmr: "Wêne zêde bike") }
    static var removeImage: String { tr("Remove image", "إزالة الصورة", ckb: "لابردنی وێنە", kmr: "Wêne rake") }
    static var close: String { tr("Close", "إغلاق", ckb: "داخستن", kmr: "Bigire") }
    static var empty: String { tr("No requests yet.", "ما في طلبات لسا.", ckb: "هێشتا داواکاری نییە.", kmr: "Hê daxwaz tune.") }
    static var limit: String { tr("Daily request limit reached. Try again tomorrow.", "وصلت للحد اليومي للطلبات. جرّب بكرا.", ckb: "گەیشتیتە سنووری ڕۆژانە. سبەی هەوڵ بدەرەوە.", kmr: "Sînorê rojane gihîşt. Sibê dîsa biceribîne.") }
    static var failed: String { tr("Could not send. Your message is saved and will retry.", "ما انبعتت. رسالتك محفوظة وبنعيد المحاولة.", ckb: "نەنێردرا. نامەکەت پاشەکەوتکراوە و دووبارە هەوڵ دەدرێت.", kmr: "Neşandî. Peyam hatiye tomarkirin û dê dîsa biceribe.") }
    static var resultSaved: String { tr("Finished. Saved in Versions for your review. Nothing was enabled.", "خلص. انحفظ بالنسخ لتراجعه. ما تفعّل شي.", ckb: "تەواو بوو. لە وەشانەکان پاشەکەوت کرا بۆ پێداچوونەوە. هیچ شتێک چالاک نەکرا.", kmr: "Qediya. Di Guhertoyan de ji bo kontrolê hat tomarkirin. Tiştek nehat çalakkirin.") }
}

struct ForgeChatThread: Codable, Identifiable, Equatable {
    let id: UUID; let title: String?; let status: String?; let createdAt: String?; let updatedAt: String?
}
struct ForgeChatArtifact: Codable, Equatable { let id: UUID; let kind: String; let name: String?; let size: Int64?; let sha256: String?; let expiresAt: String? }
struct ForgeChatResult: Codable, Equatable { let inboxID: UUID?; let tweakID: UUID?; let bundleID: String?; let name: String?; let version: Int?; let artifact: ForgeChatArtifact? }
struct ForgeChatMessage: Codable, Identifiable, Equatable {
    let id: UUID; let threadID: UUID; let role: String; let text: String?; let createdAt: String?; let hasImage: Bool?; let result: ForgeChatResult?
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

    init() { outgoing = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([ForgeChatOutgoing].self, from: $0) } ?? [] }
    private func saveOutgoing() { UserDefaults.standard.set(try? JSONEncoder().encode(outgoing), forKey: key) }

    func callPublic(_ body: [String: Any]) async throws -> Data { try await call(body) }
    private func call(_ body: [String: Any]) async throws -> Data {
        let c = try await ForgeClient.fixToken()
        let r = try await ForgePreciseClient.request(body, credentials: c)
        switch r.status {
        case 200: return r.data
        case 429: throw ForgeClient.Failure.message(ForgeChatText.limit)
        default: throw ForgeClient.Failure.message(ForgeChatText.failed)
        }
    }

    func send(threadID: UUID?, text: String, jpeg: Data?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let img = jpeg.flatMap { ForgeChatImage.prepare($0) }?.base64EncodedString()
        outgoing.append(ForgeChatOutgoing(id: UUID(), threadID: threadID ?? UUID(), newThread: threadID == nil, text: String(t.prefix(4000)), imageBase64: img))
        saveOutgoing()
        Task { await flush() }
    }

    func flush() async {
        guard !flushing else { return }
        flushing = true; defer { flushing = false }
        for o in outgoing {
            var body: [String: Any] = ["action": "chat-send", "id": o.id.uuidString.lowercased(), "threadID": o.threadID.uuidString.lowercased(), "newThread": o.newThread, "text": o.text]
            if let b = o.imageBase64 { body["image"] = ["mime": "image/jpeg", "base64": b] }
            do { _ = try await call(body); error = nil }
            catch let f as ForgeClient.Failure {
                if case .message(let m) = f, m == ForgeChatText.limit { error = m; outgoing.removeAll { $0.id == o.id } } else { error = ForgeChatText.failed }
            } catch { self.error = ForgeChatText.failed; continue } // network error: keep and replay with same id
            outgoing.removeAll { $0.id == o.id && error == nil }
            saveOutgoing()
        }
        outgoing = outgoing.filter { o in !(error == ForgeChatText.limit && false) && true }
        saveOutgoing()
        await refreshThreads()
    }

    func refreshThreads() async {
        struct W: Decodable { let threads: [ForgeChatThread] }
        guard let d = try? await call(["action": "chat-list"]), let w = try? JSONDecoder().decode(W.self, from: d) else { return }
        threads = w.threads.sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
    }

    func read(_ id: UUID) async {
        struct W: Decodable { let messages: [ForgeChatMessage] }
        guard let d = try? await call(["action": "chat-read", "threadID": id.uuidString.lowercased()]), let w = try? JSONDecoder().decode(W.self, from: d) else { return }
        messages[id] = w.messages
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

struct ForgeChatRoot: View {
    var embedded: Bool = false
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ForgeChatStore.shared
    @AppStorage("mirsa.chat.guideSeen") private var guideSeen = false
    @State private var path: [UUID] = []
    var body: some View {
        NavigationStack(path: $path) {
            List {
                Text(ForgeChatText.subtitle).font(.subheadline).foregroundStyle(.secondary)
                if !guideSeen {
                    HStack(alignment: .top) { Text(ForgeChatText.guide).font(.footnote); Button { guideSeen = true } label: { Image(systemName: "xmark") } }
                }
                if let e = store.error { Text(e).font(.footnote).foregroundStyle(.red) }
                if store.threads.isEmpty && store.outgoing.isEmpty { Text(ForgeChatText.empty).foregroundStyle(.secondary) }
                ForEach(store.threads) { t in
                    NavigationLink(value: t.id) {
                        VStack(alignment: .leading) { Text(t.title ?? ForgeChatText.newRequest).lineLimit(2); if let s = t.status { Text(s).font(.caption2).foregroundStyle(.secondary) } }
                    }
                }
            }
            .navigationTitle(ForgeChatText.title).navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { ForgeChatThreadView(threadID: $0) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { if !embedded { Button(ForgeChatText.close) { dismiss() } } }
                ToolbarItem(placement: .primaryAction) { Button { path.append(UUID()) } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel(ForgeChatText.newRequest) }
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
    private var msgs: [ForgeChatMessage] { store.messages[threadID] ?? [] }
    private var queued: [ForgeChatOutgoing] { store.outgoing.filter { $0.threadID == threadID } }
    private var isNew: Bool { !started && msgs.isEmpty && queued.isEmpty && !store.threads.contains { $0.id == threadID } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(msgs) { m in bubble(m) }
                    ForEach(queued) { o in
                        HStack { Spacer(); VStack(alignment: .trailing) { Text(o.text); Text(ForgeChatText.sending).font(.caption2).opacity(0.7) }.padding(10).background(Color.blue.opacity(0.5)).cornerRadius(12) }
                    }
                    if let last = msgs.last, last.role == "user", queued.isEmpty {
                        Label(ForgeChatText.waiting, systemImage: "hourglass").font(.caption).foregroundStyle(.secondary)
                    }
                    if let e = store.error { Text(e).font(.caption).foregroundStyle(.red) }
                }.padding()
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
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(10)
        }
        .navigationTitle(ForgeChatText.title).navigationBarTitleDisplayMode(.inline)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { jpeg = (try? await item.loadTransferable(type: Data.self)).flatMap { ForgeChatImage.prepare($0) } }
        }
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
