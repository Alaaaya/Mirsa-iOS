import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// "Mirsa AI": a request thread with Mirsa. This is a manual queue, not an instant AI chat; replies take time.
enum ForgeChatText {
    static var title: String { tr("Mirsa AI", "مرسى AI", ckb: "میرسا AI", kmr: "Mirsa AI") }
    static var supportID: String { tr("Support ID", "رقم الدعم", ckb: "ناسنامەی پشتگیری", kmr: "Nasnameya piştgiriyê") }
    static var copySupportID: String { tr("Copy support ID", "انسخ رقم الدعم", ckb: "ناسنامەی پشتگیری کۆپی بکە", kmr: "Nasnameya piştgiriyê kopî bike") }
    static var supportIDCopied: String { tr("Copied", "اننسخ", ckb: "کۆپی کرا", kmr: "Hat kopîkirin") }
    static var supportIDHint: String { tr("Send this short ID when reporting a problem. It is not a sign-in code.", "ابعث هالرقم لما تبلّغ عن مشكلة. مو رمز تسجيل دخول.", ckb: "کاتی ڕاپۆرتکردنی کێشە ئەم ناسنامە کورتە بنێرە. کۆدی چوونەژوورەوە نییە.", kmr: "Dema tu pirsgirêkekê ragihînî vê nasnameya kurt bişîne. Ev ne koda têketinê ye.") }

    static var subtitle: String { tr("Write what you want, Mirsa takes your request and works on it. It takes time.", "اكتب شو بدك، مرسى بياخد طلبك وبيشتغل عليه، بياخد وقت", ckb: "بنووسە چیت دەوێت، میرسا داواکارییەکەت وەردەگرێت و کاری لەسەر دەکات، کاتی دەوێت.", kmr: "Binivîse tu çi dixwazî, Mirsa daxwaza te distîne û li ser dixebite. Dem dixwaze.") }
    static var guide: String { tr("Mirsa AI is not an instant chat. Your message goes into a queue and Mirsa answers by hand, so replies can take minutes or longer. Finished tweaks appear here and in Versions for your review. Nothing turns on by itself.", "مرسى AI مو شات فوري. رسالتك بتدخل بالدور ومرسى بتردّ بإيدها، فالرد ممكن ياخد دقايق أو أكتر. التويكات الجاهزة بتظهر هون وبالنسخ لتراجعها. ما بيتفعّل شي لحاله.", ckb: "میرسا AI گفتوگۆی خێرا نییە. نامەکەت دەچێتە ڕیز و میرسا بە دەست وەڵام دەداتەوە، بۆیە ڕەنگە چەند خولەکێک یان زیاتر بخایەنێت. تویکە تەواوەکان لێرە و لە وەشانەکان دەردەکەون بۆ پێداچوونەوە. هیچ شتێک خۆی چالاک نابێت.", kmr: "Mirsa AI ne sohbeteke tavilê ye. Peyama te dikeve rêzê û Mirsa bi destan bersiv dide, ji ber vê yekê dibe ku çend deqe an zêdetir bikşîne. Tweakên amade li vir û di Guhertoyan de ji bo kontrolê xuya dibin. Tiştek bi serê xwe naçalake.") }
    static var placeholder: String { tr("Write your request…", "اكتب طلبك…", ckb: "داواکارییەکەت بنووسە…", kmr: "Daxwaza xwe binivîse…") }
    /// Server titles come from the first message; tidy stray spaces before punctuation ("تعمل ؟").
    static func cleanTitle(_ t: String?) -> String {
        guard var s = t?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return newRequest }
        for p in ["؟", "?", "!", "،", ".", ","] { s = s.replacingOccurrences(of: " " + p, with: p) }
        return s
    }
    static var newRequest: String { tr("New request", "طلب جديد", ckb: "داواکاری نوێ", kmr: "Daxwaza nû") }
    static var send: String { tr("Send", "إرسال", ckb: "ناردن", kmr: "Bişîne") }
    static var deleteTitle: String { tr("Delete this request?", "حذف هالطلب؟", ckb: "ئەم داواکارییە بسڕیتەوە؟", kmr: "Ev daxwaz were jêbirin?") }
    static var deleteAction: String { tr("Delete", "حذف", ckb: "سڕینەوە", kmr: "Jê bibe") }
    static var deleteFailed: String { tr("Couldn't delete. Check your connection and try again.", "تعذّر الحذف. تأكد من الاتصال وجرّب مرة تانية.", ckb: "نەسڕایەوە. پەیوەندییەکەت بپشکنە و دووبارە هەوڵبدەرەوە.", kmr: "Jê neçû. Girêdana xwe kontrol bike û dîsa biceribîne.") }
    static func status(_ s: String?) -> String {
        switch (s ?? "").lowercased() {
        case "queued", "pending", "new": return tr("Queued", "بالانتظار", ckb: "لە ڕیزدایە", kmr: "Li benda rêzê")
        case "working", "building", "in_progress", "running": return tr("Working on it", "عم يشتغل", ckb: "کاری لەسەر دەکرێت", kmr: "Tê xebitandin")
        case "done", "ready", "completed", "delivered": return tr("Done", "تم", ckb: "تەواو بوو", kmr: "Qediya")
        case "failed", "error", "rejected": return tr("Failed", "تعذّر", ckb: "سەرنەکەوت", kmr: "Têk çû")
        default: return ""
        }
    }
    static var waiting: String { tr("Waiting for Mirsa. This can take a while.", "بانتظار مرسى، ممكن ياخد وقت", ckb: "چاوەڕێی مرسا. ڕەنگە کاتی بوێت.", kmr: "Li benda Mirsayê. Dibe ku demek bikşîne.") }
    static var sending: String { tr("Sending…", "عم يتبعت…", ckb: "دەنێردرێت…", kmr: "Tê şandin…") }
    static var welcome: String { tr("""
Hi! I can make you:
• Tweaks for your apps (dylib or deb) the way you want, for example changing the look, hiding things, adding options
• Full iPhone apps (IPA) that you install right from here
• Android apps (APK) or ZIP files
Write what you want in detail, and if you have an image of what you have in mind, send it. I'll work on it and bring you the result back here.
""", """
أهلين! بقدر أعملك:
• تويكات لتطبيقاتك (dylib أو deb) حسب ما بدك، مثلاً تغيير شكل، إخفاء أشياء، إضافة خيارات
• تطبيقات كاملة للآيفون (IPA) بتثبّتها مباشرة من هون
• تطبيقات أندرويد (APK) أو ملفات ZIP
اكتبلي شو بدك بالتفصيل، وإذا في صورة للشي اللي ببالك ابعتها، وبشتغل عليه وبرجعلك هون بالنتيجة.
""", ckb: """
سڵاو! دەتوانم بۆت دروست بکەم:
• تویکە (dylib یان deb) بۆ ئەپەکانت بەو شێوەیەی دەتەوێت، بۆ نموونە گۆڕینی دیزاین، شاردنەوەی شتەکان، زیادکردنی هەڵبژاردن
• ئەپی تەواو بۆ ئایفۆن (IPA) کە ڕاستەوخۆ لێرەوە دایدەمەزرێنیت
• ئەپی ئەندرۆید (APK) یان فایلی ZIP
بە وردی بنووسە چیت دەوێت، و ئەگەر وێنەیەکت هەیە بۆ ئەوەی لە مێشکتدایە بینێرە. کاری لەسەر دەکەم و ئەنجامەکەت لێرە بۆ دەگەڕێنمەوە.
""", kmr: """
Silav! Ez dikarim ji te re çêkim:
• Tweakên (dylib an deb) ji bo sepanên te çawa bixwazî, mînak guhertina dîmenê, veşartina tiştan, zêdekirina vebijarkan
• Sepanên tev ên iPhone (IPA) ku tu rasterast ji vir saz dikî
• Sepanên Android (APK) an pelên ZIP
Bi hûrgilî binivîse tu çi dixwazî, û heke wêneyekî tiştê di hişê te de hebe bişîne. Ez li ser dixebitim û encamê li vir ji te re vedigerînim.
""") }
    static var photo: String { tr("Add image", "أضف صورة", ckb: "وێنە زیاد بکە", kmr: "Wêne zêde bike") }
    static var attach: String { tr("Attach", "إرفاق", ckb: "هاوپێچ", kmr: "Pêvek") }
    static var attachPhoto: String { tr("Photo", "صورة", ckb: "وێنە", kmr: "Wêne") }
    static var attachFile: String { tr("Text or JSON file", "ملف نص أو JSON", ckb: "فایلی نووسین یان JSON", kmr: "Pelê nivîs an JSON") }
    static var attachLink: String { tr("Link", "رابط", ckb: "بەستەر", kmr: "Lînk") }
    static var linkPrompt: String { tr("Paste an https link", "الصق رابط https", ckb: "بەستەرێکی https بلکێنە", kmr: "Lînkek https bilêxe") }
    static var add: String { tr("Add", "إضافة", ckb: "زیاد بکە", kmr: "Zêde bike") }
    static var cancel: String { tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal bike") }
    static var attachHint: String { tr("Up to 3 attachments. Photos up to 1 MB, text or JSON files up to 256 KB. Links are only sent as text, Mirsa never opens or downloads them. Attachments are kept for 24 hours.", "لحد ٣ مرفقات. الصور لحد ١ ميغا، ملفات النص أو JSON لحد ٢٥٦ كيلو. الروابط بتنبعت كنص بس، مرسى ما بتفتحها ولا بتنزّلها. المرفقات بتنحفظ ٢٤ ساعة.", ckb: "تا ٣ هاوپێچ. وێنە تا ١ مێگا، فایلی نووسین یان JSON تا ٢٥٦ کیلۆ. بەستەرەکان تەنها وەک نووسین دەنێردرێن، میرسا نایانکاتەوە و دایانابەزێنێت. هاوپێچەکان ٢٤ کاتژمێر دەمێننەوە.", kmr: "Heta 3 pêvek. Wêne heta 1 MB, pelên nivîs an JSON heta 256 KB. Lînk tenê wekî nivîs têne şandin, Mirsa wan venake û daneqîne. Pêvek 24 saetan tên parastin.") }
    static var uploading: String { tr("Uploading…", "عم يرفع…", ckb: "بارکردن…", kmr: "Tê barkirin…") }
    static var attachmentRejected: String { tr("An attachment was rejected (wrong type, too big or an unsafe link). Remove it and try again.", "انرفض مرفق (نوع غلط أو كبير أو رابط مو آمن). شيله وجرّب مرة تانية.", ckb: "هاوپێچێک ڕەتکرایەوە (جۆری هەڵە، زۆر گەورە یان بەستەری نائارام). لایببە و دووبارە هەوڵبدەرەوە.", kmr: "Pêvekek hat redkirin (cureyê şaş, pir mezin an lînka ne ewle). Rake û dîsa biceribîne.") }
    static var attachmentExpired: String { tr("expired", "انتهت", ckb: "بەسەرچوو", kmr: "qediya") }
    static var attachmentBad: String { tr("Could not read this file. Use a UTF-8 .txt or valid .json up to 256 KB.", "ما قدرت أقرا الملف. استخدم .txt بترميز UTF-8 أو .json صحيح لحد ٢٥٦ كيلو.", ckb: "نەتوانرا فایلەکە بخوێندرێتەوە. .txt بە UTF-8 یان .json ی دروست تا ٢٥٦ کیلۆ بەکاربهێنە.", kmr: "Pel nehat xwendin. .txt bi UTF-8 an .json a derbasdar heta 256 KB bi kar bîne.") }
    static var removeImage: String { tr("Remove image", "إزالة الصورة", ckb: "لابردنی وێنە", kmr: "Wêne rake") }
    static var close: String { tr("Close", "إغلاق", ckb: "داخستن", kmr: "Bigire") }
    static var empty: String { tr("No requests yet.", "ما في طلبات لسا.", ckb: "هێشتا داواکاری نییە.", kmr: "Hê daxwaz tune.") }
    static var limit: String { tr("Daily request limit reached. Try again tomorrow.", "وصلت للحد اليومي للطلبات. جرّب بكرا.", ckb: "گەیشتیتە سنووری ڕۆژانە. سبەی هەوڵ بدەرەوە.", kmr: "Sînorê rojane gihîşt. Sibê dîsa biceribîne.") }
    static var failed: String { tr("Could not send. Your message is saved and will retry.", "ما انبعتت. رسالتك محفوظة وبنعيد المحاولة.", ckb: "نەنێردرا. نامەکەت پاشەکەوتکراوە و دووبارە هەوڵ دەدرێت.", kmr: "Neşandî. Peyam hatiye tomarkirin û dê dîsa biceribe.") }
    static let messageMax = 4000
    static func messageCount(_ text: String) -> Int { text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count }
    static var tooLong: String { tr("Maximum 4,000 characters. Shorten your message or split it into two.", "الحد ٤٠٠٠ حرف. اختصر رسالتك أو قسّمها لرسالتين.", ckb: "زۆرترین ٤٠٠٠ پیت. نامەکەت کورت بکەوە یان بیکە بە دوو نامە.", kmr: "Herî zêde 4.000 tîp. Peyamê kurt bike an bike du peyam.") }
    static func counter(_ count: Int) -> String { "\(count) / \(messageMax) " + tr("characters", "حرف", ckb: "پیت", kmr: "tîp") }
    static var resultSaved: String { tr("Finished. Saved in Versions for your review. Nothing was enabled.", "خلص. انحفظ بالنسخ لتراجعه. ما تفعّل شي.", ckb: "تەواو بوو. لە وەشانەکان پاشەکەوت کرا بۆ پێداچوونەوە. هیچ شتێک چالاک نەکرا.", kmr: "Qediya. Di Guhertoyan de ji bo kontrolê hat tomarkirin. Tiştek nehat çalakkirin.") }
}

enum ForgeChatTransient: Error { case failed(String) }

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
    /// Accepted by the server but not yet returned by chat-read. Shown so a sent message never vanishes and reappears.
    @Published var sentEcho: [ForgeChatOutgoing] = []
    @Published var error: String?
    private let key = "mirsa.chat.outgoing.v1"
    private let echoKey = "mirsa.chat.sentEcho.v1"
    private var flushing = false
    private var handledResults = Set<UUID>()

    /// UI-test only (DEBUG harness + -MirsaChatFixture): seeded store, no network, no retry loop, nothing persisted.
    static var fixture: Bool { MirsaUITestHarness.active && ProcessInfo.processInfo.arguments.contains("-MirsaChatFixture") }
    static let fixtureThreadID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!
    private var deleting = Set<UUID>()
    private var deleteEpoch: [UUID: Int] = [:]
    private static let imageCache = NSCache<NSUUID, UIImage>()

    init() {
        if Self.fixture {
            let t = Self.fixtureThreadID
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-MirsaChatEmptyFixture") {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-MirsaChatQuotaFixture") { error = ForgeChatText.limit }
                if args.contains("-MirsaChatRegistrationFailureFixture") { error = ForgeChatText.failed }
                // Empty, pending registration and exhausted quota must all render the same composer.
                return
            }
            #endif
            let long = ProcessInfo.processInfo.arguments.contains("-MirsaChatLongFixture")
            threads = [ForgeChatThread(id: t, title: "Fixture", status: "open", createdAt: nil, updatedAt: nil)]
            messages = [t: [
                ForgeChatMessage(id: UUID(), threadID: t, role: "user", text: "Make me a tweak that hides the dock labels."),
                ForgeChatMessage(id: UUID(), threadID: t, role: "kat", text: "Got it. I'll build it and send it here when it's ready."),
                ForgeChatMessage(id: UUID(), threadID: t, role: "user", text: "Thanks, no rush.")]]
            if long {
                var many: [ForgeChatMessage] = []
                for i in 1...40 { many.append(ForgeChatMessage(id: UUID(), threadID: t, role: i % 2 == 1 ? "user" : "kat", text: i == 40 ? "LAST-MESSAGE-MARK" : (i == 1 ? "FIRST-MESSAGE-MARK" : "Filler message number \(i) to make the chat taller than the screen.")))}
                messages = [t: many]
            }
            ackedThreads.insert(t)
            return
        }
        defer { startRetrying() }; outgoing = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([ForgeChatOutgoing].self, from: $0) } ?? []
        sentEcho = UserDefaults.standard.data(forKey: echoKey).flatMap { try? JSONDecoder().decode([ForgeChatOutgoing].self, from: $0) } ?? []
        for echo in sentEcho { ackedThreads.insert(echo.threadID) }
    }
    private func saveEcho() { UserDefaults.standard.set(try? JSONEncoder().encode(sentEcho), forKey: echoKey) }
    private func saveOutgoing() { UserDefaults.standard.set(try? JSONEncoder().encode(outgoing), forKey: key) }

    func callPublic(_ body: [String: Any]) async throws -> Data { try await call(body) }
    /// Last real failure (HTTP status + server code, or the network error) so the user and logs can see the true reason.
    @Published var lastDiagnostic: String?
    private func call(_ body: [String: Any], retryBind: Bool = true) async throws -> Data {
        if Self.fixture { throw ForgeChatTransient.failed("fixture") }
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
        if code == "message_too_long" { lastDiagnostic = code; throw ForgeChatTransient.failed(code) }
        if r.status == 429 { throw ForgeClient.Failure.message(ForgeChatText.limit) }
        if (body["action"] as? String) == "chat-attachment-put", [400, 409, 410, 413, 415, 422].contains(r.status) { throw ForgeClient.Failure.message(ForgeChatText.attachmentRejected) }
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
    var pendingThreadIDs: [UUID] { var seen = Set<UUID>(); return (outgoing + sentEcho).map(\.threadID).filter { id in !threads.contains { t in t.id == id } && seen.insert(id).inserted } }
    func hasInFlight(_ id: UUID) -> Bool { outgoing.contains { $0.threadID == id } }

    func send(threadID: UUID?, text: String, jpeg: Data?, attachments: [ForgeChatAttachmentDraft] = []) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        guard ForgeChatText.messageCount(t) <= ForgeChatText.messageMax else { error = ForgeChatText.tooLong; return }
        if let tid = threadID, deleting.contains(tid) { return }
        if let tid = threadID, hasInFlight(tid) { return } // no double send while a message is still unsent
        let img = jpeg.flatMap { ForgeChatImage.prepare($0) }?.base64EncodedString()
        let tid = threadID ?? UUID()
        let confirmed = messages[tid] ?? []
        let pending = ForgeChatTimeline.pending(outgoing: outgoing, echoes: sentEcho, confirmed: confirmed, threadID: tid)
        let anchor = ForgeChatTimeline.orderedIDs(confirmed: confirmed, pending: pending).last
        outgoing.append(ForgeChatOutgoing(id: UUID(), threadID: tid, newThread: !serverKnows(tid), text: t, imageBase64: attachments.isEmpty ? img : nil, afterMessageID: anchor))
        if !attachments.isEmpty { outgoing[outgoing.count - 1].attachments = Array(attachments.prefix(3)) }
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
        guard !Self.fixture, !flushing else { return }
        flushing = true; defer { flushing = false }
        for o in outgoing where !deleting.contains(o.threadID) {
            var body: [String: Any] = ["action": "chat-send", "id": o.id.uuidString.lowercased(), "threadID": o.threadID.uuidString.lowercased(), "newThread": !serverKnows(o.threadID), "text": o.text, "language": AppLanguageStore.snapshot.rawValue]
            if let b = o.imageBase64 { body["image"] = ["mime": "image/jpeg", "base64": b] }
            do {
                if let drafts = o.attachments, !drafts.isEmpty {
                    var ids = o.uploadedIDs ?? []
                    while ids.count < drafts.count {
                        let d = drafts[ids.count]
                        var put: [String: Any] = ["action": "chat-attachment-put", "threadID": o.threadID.uuidString.lowercased(), "kind": d.kind, "name": String(d.name.prefix(100))]
                        if let m = d.mime { put["mime"] = m }
                        if let b = d.base64 { put["base64"] = b }
                        if let u = d.url { put["url"] = u }
                        let data = try await call(put)
                        struct A: Decodable { struct I: Decodable { let id: String }; let attachment: I }
                        guard let a = try? JSONDecoder().decode(A.self, from: data) else { throw ForgeChatTransient.failed("attachment_response") }
                        ids.append(a.attachment.id)
                        if let i = outgoing.firstIndex(where: { $0.id == o.id }) { outgoing[i].uploadedIDs = ids; saveOutgoing() }
                    }
                    body["attachmentIDs"] = ids
                }
                _ = try await call(body)
                if deleting.contains(o.threadID) { continue } // delete started mid-send; delete waits for flush and wipes it
                ackedThreads.insert(o.threadID); let echo = ForgeChatTimeline.acceptedEcho(o); sentEcho.removeAll { $0.id == o.id }; sentEcho.append(echo); saveEcho()
                outgoing.removeAll { $0.id == o.id }; saveOutgoing(); error = nil
            } catch let f as ForgeClient.Failure {
                // Daily limit: the server refuses this message for good, so it cannot be replayed today.
                error = f.errorDescription; outgoing.removeAll { $0.id == o.id }; saveOutgoing()
            } catch {
                self.error = lastDiagnostic == "message_too_long" ? ForgeChatText.tooLong : ForgeChatText.failed
                break // keep the message, the retry loop replays it with the same id
            }
        }
        await refreshThreads()
    }

    /// Server delete first (device-owned thread). Local state is wiped only after the server confirms.
    /// While deleting, sends/flushes/reads for that thread are blocked so nothing can resurrect it.
    func deleteThread(_ id: UUID) async {
        guard !deleting.contains(id) else { return }
        deleting.insert(id); defer { deleting.remove(id) }
        while flushing { try? await Task.sleep(nanoseconds: 100_000_000) } // let an in-flight send settle first
        do {
            _ = try await call(["action": "chat-delete", "threadID": id.uuidString.lowercased()])
        } catch { self.error = ForgeChatText.deleteFailed; return } // server still has it: keep everything local
        deleteEpoch[id, default: 0] += 1
        for m in messages[id] ?? [] { Self.imageCache.removeObject(forKey: m.id as NSUUID) }
        threads.removeAll { $0.id == id }
        var all = messages; all[id] = nil; messages = all
        outgoing.removeAll { $0.threadID == id }; saveOutgoing(); sentEcho.removeAll { $0.threadID == id }; saveEcho()
        ackedThreads.remove(id)
        if UserDefaults.standard.string(forKey: draftKey).flatMap(UUID.init(uuidString:)) == id { UserDefaults.standard.removeObject(forKey: draftKey) }
        error = nil
    }

    func refreshThreads() async {
        guard !Self.fixture else { return }
        struct Lossy: Decodable { let value: ForgeChatThread?; init(from d: Decoder) throws { value = try? ForgeChatThread(from: d) } }
        struct W: Decodable { let threads: [Lossy] }
        let epochs = deleteEpoch
        guard let d = try? await call(["action": "chat-list"]), let w0 = try? JSONDecoder().decode(W.self, from: d) else { return }
        let w = (threads: w0.threads.compactMap(\.value).filter { !deleting.contains($0.id) && deleteEpoch[$0.id] == epochs[$0.id] }, ())
        let sorted = w.threads.sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
        if sorted != threads { threads = sorted }
    }

    func read(_ id: UUID) async {
        if deleting.contains(id) || Self.fixture { return }
        if !serverKnows(id) { return }
        let epoch = deleteEpoch[id] // pending first message: nothing to read yet (avoids repeated 404)
        struct Lossy: Decodable { let value: ForgeChatMessage?; init(from d: Decoder) throws { value = try? ForgeChatMessage(from: d) } }
        struct W: Decodable { let messages: [Lossy] }
        guard let d = try? await call(["action": "chat-read", "threadID": id.uuidString.lowercased()]), let raw = try? JSONDecoder().decode(W.self, from: d) else { return }
        if deleting.contains(id) || deleteEpoch[id] != epoch { return } // deleted while this read was in flight
        // One undecodable message must never hide the others (operator replies were not showing).
        let w = (messages: raw.messages.compactMap(\.value), 0)
        if w.messages.count < raw.messages.count { lastDiagnostic = "decode: skipped \(raw.messages.count - w.messages.count) of \(raw.messages.count) messages" }
        let merged = ForgeChatTimeline.mergeConfirmed(previous: messages[id] ?? [], incoming: w.messages)
        if messages[id] != merged {
            var all = messages; all[id] = merged; messages = all
        }
        // Publish confirmed rows before retiring echoes. One stable UUID stays visible throughout.
        let ids = Set(merged.map(\.id))
        if sentEcho.contains(where: { ids.contains($0.id) }) {
            sentEcho.removeAll { ids.contains($0.id) }; saveEcho()
        }
        if w.messages.contains(where: { $0.role == "result" && !handledResults.contains($0.id) }) {
            for m in w.messages where m.role == "result" { handledResults.insert(m.id) }
            await ForgeStore.shared.syncFixInbox() // existing fix-inbox/fix-download path, review required, never auto-enabled
        }
    }

    func image(_ messageID: UUID) async -> UIImage? {
        if let c = Self.imageCache.object(forKey: messageID as NSUUID) { return c }
        guard let d = try? await call(["action": "chat-image", "id": messageID.uuidString.lowercased()]), let img = UIImage(data: d) else { return nil }
        Self.imageCache.setObject(img, forKey: messageID as NSUUID)
        return img
    }
}

/// Support only, never an authentication token or a unique/account identity.
/// Read the same persistent UUID used by Forge requests, with no registration or ID reset.
private struct ForgeSupportIDBadge: View {
    @State private var supportID = String(ForgeClient.deviceID().prefix(8)).lowercased()
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = supportID
            copied = true
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(copied ? ForgeChatText.supportIDCopied : ForgeChatText.supportID)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 3) {
                    Text(supportID).font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 9))
                }
            }.foregroundStyle(.white.opacity(0.85))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 72, minHeight: 44)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityLabel(ForgeChatText.copySupportID)
        .accessibilityValue(copied ? ForgeChatText.supportIDCopied + " " + supportID : supportID)
        .accessibilityHint(ForgeChatText.supportIDHint)
        .accessibilityIdentifier("chat-support-id")
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

struct ForgeChatRoot: View {
    var embedded: Bool = false
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ForgeChatStore.shared
    @AppStorage("mirsa.chat.guideSeen") private var guideSeen = false
    @State private var path: [UUID] = []
    @State private var open: ForgeOpenThread?
    @State private var toDelete: UUID?
    var body: some View {
        NavigationStack(path: $path) {
            List {
                Text(ForgeChatText.subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !guideSeen {
                    HStack(alignment: .top) { Text(ForgeChatText.guide).font(.footnote); Button { guideSeen = true } label: { Image(systemName: "xmark") } }
                }
                if let e = store.error { Text(e).font(.footnote).foregroundStyle(.red) }
                if store.threads.isEmpty && store.pendingThreadIDs.isEmpty { Text(ForgeChatText.empty).foregroundStyle(.secondary) }
                ForEach(store.pendingThreadIDs, id: \.self) { id in
                    Button { open = ForgeOpenThread(id: id) } label: { ForgeChatRowChevron { VStack(alignment: .leading) { Text((store.outgoing + store.sentEcho).first { $0.threadID == id }?.text ?? ForgeChatText.newRequest).lineLimit(2); Text(store.hasInFlight(id) ? ForgeChatText.sending : ForgeChatText.status("queued")).font(.caption2).foregroundStyle(.secondary) } } }.buttonStyle(.plain)
                }
                ForEach(store.threads) { t in
                    Button { open = ForgeOpenThread(id: t.id) } label: { ForgeChatRowChevron {
                        HStack(spacing: 12) { MirsaSailMark().frame(width: 34, height: 34); VStack(alignment: .leading, spacing: 6) { Text(ForgeChatText.cleanTitle(t.title)).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(2); if let s = t.status, !ForgeChatText.status(s).isEmpty { MirsaChatStatusPill(raw: s) } } }.padding(.vertical, 6)
                    } }.buttonStyle(.plain)
                    .listRowBackground(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.07)).overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.5)))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { toDelete = t.id } label: { Label(ForgeChatText.deleteAction, systemImage: "trash") }.tint(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden).listRowSpacing(10).background(MirsaChatTheme.bg.ignoresSafeArea()).preferredColorScheme(.dark)
            .confirmationDialog(ForgeChatText.deleteTitle, isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
                Button(ForgeChatText.deleteAction, role: .destructive) { if let id = toDelete { Task { await store.deleteThread(id) } }; toDelete = nil }
                Button(ForgeChatText.cancel, role: .cancel) { toDelete = nil }
            }
            .navigationTitle(ForgeChatText.title).navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { ForgeChatThreadView(threadID: $0) }
            // A conversation opens full screen, over the Tools segments and the tab bar.
            .fullScreenCover(item: $open) { o in ForgeChatThreadView(threadID: o.id) }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 10) {
                        Text(ForgeChatText.title).font(.headline).lineLimit(1).minimumScaleFactor(0.85)
                        ForgeSupportIDBadge()
                    }.environment(\.layoutDirection, .leftToRight)
                }
                ToolbarItem(placement: .cancellationAction) { if !embedded { Button(ForgeChatText.close) { dismiss() } } }
                ToolbarItem(placement: .primaryAction) { Button { open = ForgeOpenThread(id: store.draftThreadID()) } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel(ForgeChatText.newRequest).accessibilityIdentifier("chat-new") }
            }
            .task { // poll only while this screen is visible
                await store.flush()
                while !Task.isCancelled { await store.refreshThreads(); try? await Task.sleep(nanoseconds: 15_000_000_000) }
            }
        }
    }
}

struct ForgeOpenThread: Identifiable, Hashable { let id: UUID }

/// List row label with the trailing chevron a NavigationLink used to draw.
struct ForgeChatRowChevron<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack { content; Spacer(minLength: 8); Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
            .contentShape(Rectangle())
    }
}

/// Mirsa sail mark used as the assistant avatar (vector, no asset needed).
struct MirsaSailMark: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.055, green: 0.165, blue: 0.33))
            Circle().stroke(Color(red: 0.18, green: 0.46, blue: 0.96), lineWidth: 1.5)
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                Path { p in
                    p.move(to: CGPoint(x: w * 0.50, y: h * 0.18)); p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.58)); p.addLine(to: CGPoint(x: w * 0.27, y: h * 0.58)); p.closeSubpath()
                    p.move(to: CGPoint(x: w * 0.55, y: h * 0.26)); p.addLine(to: CGPoint(x: w * 0.55, y: h * 0.58)); p.addLine(to: CGPoint(x: w * 0.74, y: h * 0.58)); p.closeSubpath()
                    p.move(to: CGPoint(x: w * 0.24, y: h * 0.62)); p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.62)); p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.70)); p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.70)); p.closeSubpath()
                }.fill(Color.white)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.22, y: h * 0.78)); p.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.78), control: CGPoint(x: w * 0.36, y: h * 0.70)); p.addQuadCurve(to: CGPoint(x: w * 0.78, y: h * 0.78), control: CGPoint(x: w * 0.64, y: h * 0.86))
                }.stroke(Color(red: 0.18, green: 0.46, blue: 0.96), lineWidth: 2)
            }
        }
    }
}

enum MirsaChatTheme {
    static let bg = Color(red: 0.039, green: 0.075, blue: 0.145)
    static let bubble = Color(red: 0.137, green: 0.184, blue: 0.271)
    static let blue = Color(red: 0.184, green: 0.463, blue: 0.965)
    static let muted = Color(red: 0.545, green: 0.604, blue: 0.71)
}

struct MirsaTypingDots: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in Circle().fill(MirsaChatTheme.blue).frame(width: 7, height: 7).opacity(phase == i ? 1 : 0.3).scaleEffect(phase == i ? 1.15 : 0.85) }
        }.onReceive(timer) { _ in withAnimation(.easeInOut(duration: 0.3)) { phase = (phase + 1) % 3 } }
    }
}

/// Both server and local rows share one ForEach identity until an explicit thread deletion.
private enum ForgeChatDisplayRow: Identifiable, Equatable {
    case message(ForgeChatMessage)
    case pending(ForgeChatOutgoing, sending: Bool)
    var id: UUID {
        switch self {
        case .message(let m): return m.id
        case .pending(let o, _): return o.id
        }
    }
}

/// Scoped to the active chat so only its typing mode collapses competing chrome.
struct ForgeChatComposerFocusKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

struct ForgeChatThreadView: View {
    let threadID: UUID
    @ObservedObject private var store = ForgeChatStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var text = ""
    @FocusState private var composerFocused: Bool
    @State private var photo: PhotosPickerItem?
    @State private var jpeg: Data?
    @State private var drafts: [ForgeChatAttachmentDraft] = []
    @State private var pickingPhoto = false
    @State private var pickingFile = false
    @State private var linkAlert = false
    @State private var linkText = ""
    @State private var localError: String?
    @State private var started = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var msgs: [ForgeChatMessage] { store.messages[threadID] ?? [] }
    private var queued: [ForgeChatOutgoing] {
        ForgeChatTimeline.pending(outgoing: store.outgoing, echoes: store.sentEcho, confirmed: msgs, threadID: threadID)
    }
    private var rows: [ForgeChatDisplayRow] {
        let confirmed = msgs.map { ForgeChatDisplayRow.message($0) }
        let pending = queued.map { o in ForgeChatDisplayRow.pending(o, sending: store.outgoing.contains { $0.id == o.id }) }
        let byID = Dictionary(uniqueKeysWithValues: (confirmed + pending).map { ($0.id, $0) })
        return ForgeChatTimeline.orderedIDs(confirmed: msgs, pending: queued).compactMap { byID[$0] }
    }
    private var unsent: Bool { store.hasInFlight(threadID) }
    private var isNew: Bool { !started && msgs.isEmpty && queued.isEmpty && !store.threads.contains { $0.id == threadID } }
    private var draftCount: Int { ForgeChatText.messageCount(text) }
    private var canSend: Bool { draftCount > 0 && draftCount <= ForgeChatText.messageMax && !unsent }

    private func scrollToLast(_ proxy: ScrollViewProxy, animated: Bool, delay: Double = 0) {
        let go = { withAnimation(animated && !reduceMotion ? .easeOut(duration: 0.3) : nil) { proxy.scrollTo("bottom", anchor: .bottom) } }
        if delay <= 0 { DispatchQueue.main.async(execute: go) }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: go) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        assistantBlock { Text(ForgeChatText.welcome).font(.system(size: 16)).lineSpacing(5).multilineTextAlignment(.leading).accessibilityIdentifier("chat-welcome") }
                        ForEach(rows) { row in
                            Group {
                                switch row {
                                case .message(let m): bubble(m)
                                case .pending(let o, let sending):
                                    VStack(alignment: .trailing, spacing: 4) {
                                        userBubble(o.text)
                                        if let d = o.attachments { ForEach(d) { a in chip(a.kind, a.name) } }
                                        if sending { Text(o.attachments?.isEmpty == false ? ForgeChatText.uploading : ForgeChatText.sending).font(.caption2).foregroundStyle(MirsaChatTheme.muted) }
                                    }.frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                            .id(row.id)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .identity))
                        }
                        if !unsent, (!queued.isEmpty || msgs.last?.role == "user") {
                            HStack(spacing: 10) { MirsaTypingDots(); Text(ForgeChatText.waiting).font(.system(size: 15)).foregroundStyle(MirsaChatTheme.muted) }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4).accessibilityIdentifier("chat-waiting").transition(.opacity)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(.horizontal, 18).padding(.top, 8)
                    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9), value: rows.map(\.id))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: store.outgoing.count)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .top, spacing: 0) { header }
                .onChange(of: rows.map(\.id)) { _, _ in scrollToLast(proxy, animated: true) }
                .onChange(of: msgs.last?.id) { _, _ in scrollToLast(proxy, animated: true) }
                .onChange(of: composerFocused) { _, _ in scrollToLast(proxy, animated: true, delay: 0.3) }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in scrollToLast(proxy, animated: false) }
                .onAppear { scrollToLast(proxy, animated: false); scrollToLast(proxy, animated: false, delay: 0.15); scrollToLast(proxy, animated: false, delay: 0.5) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Reserve the composer before the scroll view is laid out. A flexible sibling
        // can be placed below the visible nested NavigationStack/tab safe area.
        // This also tracks the keyboard's safe area without fixed device heights.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if !drafts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(drafts) { d in
                                HStack(spacing: 6) {
                                    Image(systemName: d.kind == "image" ? "photo" : (d.kind == "link" ? "link" : "doc.text")).font(.system(size: 13))
                                    Text(d.name).font(.caption).lineLimit(1)
                                    Button { drafts.removeAll { $0.id == d.id } } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 15)) }
                                        .accessibilityLabel(ForgeChatText.removeImage)
                                }.foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color(red: 0.118, green: 0.169, blue: 0.251)).clipShape(Capsule())
                                    .accessibilityIdentifier("chat-draft-attachment")
                            }
                        }.padding(.horizontal, 18)
                    }.padding(.top, 8).environment(\.layoutDirection, .leftToRight)
                }
                if let localError {
                    Text(localError).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.top, 4)
                }
                if let jpeg, let img = UIImage(data: jpeg) {
                    HStack { Image(uiImage: img).resizable().scaledToFill().frame(width: 56, height: 56).clipped().cornerRadius(12)
                        Button(ForgeChatText.removeImage) { self.jpeg = nil; photo = nil }.font(.caption).foregroundStyle(MirsaChatTheme.muted); Spacer() }.padding(.horizontal, 18).padding(.top, 8)
                }
                inputBar
                if let e = store.error {
                    Text(e).font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.bottom, 6)
                        .accessibilityIdentifier("chat-composer-status")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(MirsaChatTheme.bg)
        }
        .background(MirsaChatTheme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .preference(key: ForgeChatComposerFocusKey.self, value: composerFocused)
        .onAppear {
            #if DEBUG
            // Seed only the explicit no-network UI harness, never real drafts.
            if ForgeChatStore.fixture {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-MirsaChatDraft4000Fixture") { text = String(repeating: "ع", count: 4000) }
                if args.contains("-MirsaChatDraft4001Fixture") { text = String(repeating: "ع", count: 4001) }
            }
            #endif
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                defer { photo = nil }
                guard drafts.count < 3, let raw = try? await item.loadTransferable(type: Data.self), let j = ForgeChatImage.prepare(raw) else { return }
                drafts.append(ForgeChatAttachmentDraft(kind: "image", name: "photo-\(drafts.count + 1).jpg", mime: "image/jpeg", base64: j.base64EncodedString()))
            }
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.plainText, .json]) { result in
            guard drafts.count < 3, case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.lowercased()
            guard ext == "txt" || ext == "json", let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= 262_144,
                  let data = try? Data(contentsOf: url), String(data: data, encoding: .utf8) != nil,
                  ext != "json" || (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else { localError = ForgeChatText.attachmentBad; return }
            localError = nil
            drafts.append(ForgeChatAttachmentDraft(kind: "file", name: String(url.lastPathComponent.prefix(100)), mime: ext == "json" ? "application/json" : "text/plain", base64: data.base64EncodedString()))
        }
        .alert(ForgeChatText.linkPrompt, isPresented: $linkAlert) {
            TextField("https://", text: $linkText).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Button(ForgeChatText.add) {
                let s = linkText.trimmingCharacters(in: .whitespacesAndNewlines); linkText = ""
                guard drafts.count < 3, s.count <= 2048, let u = URL(string: s), u.scheme?.lowercased() == "https", let h = u.host, !h.isEmpty else { localError = ForgeChatText.attachmentRejected; return }
                localError = nil
                drafts.append(ForgeChatAttachmentDraft(kind: "link", name: String(h.prefix(100)), url: s))
            }
            Button(ForgeChatText.cancel, role: .cancel) { linkText = "" }
        }
        .onChange(of: scenePhase) { _, p in if p == .active { Task { await store.read(threadID) } } }
        .onChange(of: store.threads) { _, _ in Task { await store.read(threadID) } }
        .task {
            while !Task.isCancelled && !ForgeChatStore.fixture { await store.read(threadID); try? await Task.sleep(nanoseconds: 8_000_000_000) }
        }
    }

    private var header: some View {
        ZStack {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.9)).frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle()).overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.5)) }
                    .accessibilityLabel(ForgeChatText.close)
                Spacer()
                ForgeSupportIDBadge()
            }
        }.environment(\.layoutDirection, .leftToRight).padding(.horizontal, 18).padding(.top, 2).padding(.bottom, 6)
        .zIndex(1)
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if draftCount >= 3600 {
                Text(draftCount > ForgeChatText.messageMax ? ForgeChatText.tooLong : ForgeChatText.counter(draftCount))
                    .font(.caption).foregroundStyle(draftCount > ForgeChatText.messageMax ? Color.red : MirsaChatTheme.muted)
                    .accessibilityIdentifier("chat-character-limit")
                    .accessibilityLabel(ForgeChatText.counter(draftCount))
                    .accessibilityValue(draftCount > ForgeChatText.messageMax ? ForgeChatText.tooLong : "")
            }
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 8) {
                    Menu {
                        Button { pickingPhoto = true } label: { Label(ForgeChatText.attachPhoto, systemImage: "photo") }
                        Button { pickingFile = true } label: { Label(ForgeChatText.attachFile, systemImage: "doc.text") }
                        Button { linkAlert = true } label: { Label(ForgeChatText.attachLink, systemImage: "link") }
                        Text(ForgeChatText.attachHint)
                    } label: { Image(systemName: "paperclip").font(.system(size: 20)).foregroundStyle(.white).frame(width: 36, height: 36) }
                        .disabled(drafts.count >= 3).accessibilityLabel(ForgeChatText.attach).accessibilityIdentifier("chat-attach")
                    TextField("", text: $text, prompt: Text(ForgeChatText.placeholder).foregroundColor(MirsaChatTheme.muted), axis: .vertical).lineLimit(1...5).accessibilityIdentifier("chat-input").focused($composerFocused).foregroundStyle(.white).tint(MirsaChatTheme.blue)
                }.padding(.horizontal, 14).padding(.vertical, 10).background(.ultraThinMaterial).overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 0.5)).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                Button {
                    started = true
                    store.send(threadID: threadID, text: text, jpeg: nil, attachments: drafts)
                    text = ""; jpeg = nil; photo = nil; drafts = []; localError = nil
                } label: { Image(systemName: "paperplane.fill").font(.system(size: 20)).foregroundStyle(.white).frame(width: 52, height: 52).background(MirsaPalette.accentGradient.opacity(canSend ? 1 : 0.4)).clipShape(Circle()) }
                    .disabled(!canSend).accessibilityLabel(ForgeChatText.send).accessibilityIdentifier("chat-send")
                    .scaleEffect(canSend ? 1 : 0.94).animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: canSend)
                    .sensoryFeedback(.impact(weight: .light), trigger: store.outgoing.count)
            }
        }.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 10)
        // Do not assign an identifier to this transparent layout container.
        // SwiftUI propagates it to the text editor and buttons, replacing their
        // distinct identifiers and hiding those controls from accessibility queries.
    }

    private func userBubble(_ t: String) -> some View {
        Text(t).font(.system(size: 17)).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 11).background(MirsaPalette.accentGradient).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)).shadow(color: MirsaPalette.accent.opacity(0.25), radius: 8, y: 3).frame(maxWidth: 300, alignment: .trailing)
    }

    @ViewBuilder private func assistantBlock<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) { MirsaSailMark().frame(width: 28, height: 28); Text(ForgeChatText.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(MirsaChatTheme.muted) }
            content().foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.5))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ kind: String, _ name: String?, expired: Bool = false) -> some View {
        let icon = kind == "image" ? "photo" : (kind == "link" ? "link" : "doc.text")
        return HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13))
            Text((name?.isEmpty == false ? name! : kind) + (expired ? " · " + ForgeChatText.attachmentExpired : "")).font(.caption).lineLimit(1)
        }.foregroundStyle(.white.opacity(expired ? 0.5 : 0.9)).padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(red: 0.118, green: 0.169, blue: 0.251)).clipShape(Capsule())
            .accessibilityIdentifier("chat-attachment-chip")
    }

    @ViewBuilder private func attachmentChips(_ list: [ForgeChatAttachmentMeta]?) -> some View {
        if let list, !list.isEmpty { VStack(alignment: .trailing, spacing: 4) { ForEach(list) { a in chip(a.kind, a.name, expired: a.available == false) } } }
    }

    @ViewBuilder private func bubble(_ m: ForgeChatMessage) -> some View {
        if m.role == "user" {
            VStack(alignment: .trailing, spacing: 8) {
                if m.hasImage == true { ForgeChatImageView(messageID: m.id) }
                attachmentChips(m.attachments)
                if let t = m.text, !t.isEmpty { userBubble(t) }
            }.frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            assistantBlock {
                VStack(alignment: .leading, spacing: 8) {
                    if m.hasImage == true { ForgeChatImageView(messageID: m.id) }
                    if let t = m.text, !t.isEmpty { Text(t).font(.system(size: 16)).lineSpacing(5).multilineTextAlignment(.leading) }
                    if m.role == "result" {
                        if m.result?.artifact == nil { Label(ForgeChatText.resultSaved, systemImage: "checkmark.shield").font(.caption).foregroundStyle(.green) }
                        if let n = m.result?.name { Text(n).font(.caption.bold()) }
                        if let a = m.result?.artifact { ForgeChatArtifactCard(threadID: m.threadID, artifact: a) }
                    }
                }
            }
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


/// Small coloured pill for a request's status in the Mirsa AI list.
struct MirsaChatStatusPill: View {
    let raw: String
    private var color: Color {
        switch raw.lowercased() {
        case "working", "building", "in_progress", "running": return MirsaPalette.accent
        case "done", "ready", "completed", "delivered": return .green
        case "failed", "error", "rejected": return .red
        default: return MirsaChatTheme.muted
        }
    }
    var body: some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 6, height: 6); Text(ForgeChatText.status(raw)).font(.system(size: 12, weight: .medium)) }
            .foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}
