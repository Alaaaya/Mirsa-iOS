import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// "Mirsa AI": a request thread with Mirsa. This is a manual queue, not an instant AI chat; replies take time.
enum ForgeChatText {
    static var title: String { tr("Mirsa AI", "مرسى AI", ckb: "میرسا AI", kmr: "Mirsa AI") }
    static var subtitle: String { tr("Write what you want, Mirsa takes your request and works on it. It takes time.", "اكتب شو بدك، مرسى بياخد طلبك وبيشتغل عليه، بياخد وقت", ckb: "بنووسە چیت دەوێت، میرسا داواکارییەکەت وەردەگرێت و کاری لەسەر دەکات، کاتی دەوێت.", kmr: "Binivîse tu çi dixwazî, Mirsa daxwaza te distîne û li ser dixebite. Dem dixwaze.") }
    static var guide: String { tr("Mirsa AI is not an instant chat. Your message goes into a queue and Mirsa answers by hand, so replies can take minutes or longer. Finished tweaks appear here and in Versions for your review. Nothing turns on by itself.", "مرسى AI مو شات فوري. رسالتك بتدخل بالدور ومرسى بتردّ بإيدها، فالرد ممكن ياخد دقايق أو أكتر. التويكات الجاهزة بتظهر هون وبالنسخ لتراجعها. ما بيتفعّل شي لحاله.", ckb: "میرسا AI گفتوگۆی خێرا نییە. نامەکەت دەچێتە ڕیز و میرسا بە دەست وەڵام دەداتەوە، بۆیە ڕەنگە چەند خولەکێک یان زیاتر بخایەنێت. تویکە تەواوەکان لێرە و لە وەشانەکان دەردەکەون بۆ پێداچوونەوە. هیچ شتێک خۆی چالاک نابێت.", kmr: "Mirsa AI ne sohbeteke tavilê ye. Peyama te dikeve rêzê û Mirsa bi destan bersiv dide, ji ber vê yekê dibe ku çend deqe an zêdetir bikşîne. Tweakên amade li vir û di Guhertoyan de ji bo kontrolê xuya dibin. Tiştek bi serê xwe naçalake.") }
    static var placeholder: String { tr("Write your request…", "اكتب طلبك…", ckb: "داواکارییەکەت بنووسە…", kmr: "Daxwaza xwe binivîse…") }
    /// Server titles come from the first message; tidy stray spaces before punctuation ("تعمل ؟").
    static func cleanTitle(_ t: String?) -> String {
        guard var s = t?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return newRequest }
        for p in ["؟", "?", "!", "،", ".", ","] { s = s.replacingOccurrences(of: " " + p, with: p) }
        return s
    }
    static var shortIDLabel: String { tr("ID", "المعرّف", ckb: "ناسنامە", kmr: "Nasname") }
    // Mirsa 2.1: report a problem with a Mirsa AI reply (server action "chat-report").
    static var reportButton: String { tr("Report a problem", "بلّغ عن مشكلة", ckb: "ڕاپۆرتی کێشەیەک بکە", kmr: "Pirsgirêkekê ragihîne") }
    static var reportQuestion: String { tr("What's the problem?", "شو المشكلة؟", ckb: "کێشەکە چییە؟", kmr: "Pirsgirêk çi ye?") }
    static var reportOptional: String { tr("Optional", "اختياري", ckb: "ئارەزوومەندانە", kmr: "Ne mecbûrî") }
    static var reportSend: String { tr("Send", "إرسال", ckb: "ناردن", kmr: "Bişîne") }
    static var reportThanks: String { tr("We got your report. We'll look into it and reply to you in this conversation.", "وصلنا بلاغك، رح نشوفو ونرد عليك بنفس المحادثة", ckb: "ڕاپۆرتەکەت گەیشت. سەیری دەکەین و لە هەمان گفتوگۆدا وەڵامت دەدەینەوە.", kmr: "Ragihandina te gihîşt me. Em ê lê binêrin û di heman sohbetê de bersiva te bidin.") }
    static var reportFailed: String { tr("Something went wrong, try again in a bit.", "صار خطأ، جرّب كمان شوي", ckb: "هەڵەیەک ڕوویدا، کەمێکی تر هەوڵ بدەرەوە.", kmr: "Çewtiyek çêbû, piştî demekê dîsa biceribîne.") }
    static var reportGone: String { tr("This reply no longer exists.", "هالرد مو موجود أو انحذف", ckb: "ئەم وەڵامە بوونی نییە یان سڕاوەتەوە.", kmr: "Ev bersiv tune ye an hatiye jêbirin.") }
    static var reportInvalid: String { tr("The note must be 500 characters or fewer.", "الملاحظة لازم تكون 500 حرف أو أقل", ckb: "تێبینییەکە دەبێت ٥٠٠ پیت یان کەمتر بێت.", kmr: "Nîşe divê 500 tîp an kêmtir be.") }
    static var reportHint: String { tr("Your note goes to support.", "ملاحظتك بتوصل للدعم", ckb: "تێبینییەکەت دەگاتە پشتگیری.", kmr: "Nîşeya te digihîje piştgiriyê.") }
    static var copied: String { tr("Copied", "انتسخ", ckb: "کۆپی کرا", kmr: "Hat kopîkirin") }
    static var shortIDHelp: String { tr("Your short chat ID is at the top of each conversation. Tap it to copy, then send it to Mirsa support so they can find your requests.", "معرّفك المختصر موجود فوق بكل محادثة. دوس عليه لتنسخه، وابعته لدعم مرسى ليلاقوا طلباتك.", ckb: "ناسنامە کورتەکەت لە سەرەوەی هەر گفتوگۆیەکە. دەستی لێ بدە بۆ کۆپیکردن، پاشان بینێرە بۆ پشتگیری میرسا تا داواکارییەکانت بدۆزنەوە.", kmr: "Nasnameya te ya kurt li jorê her sohbetê ye. Bitikîne da ku kopî bikî, paşê ji piştgiriya Mirsa re bişîne da ku daxwazên te bibînin.") }
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

struct ForgeChatConversationConflict: Error, Equatable {
    let code: String

    static func response(status: Int, code: String) -> Self? {
        guard status == 409, !ChatAttachmentError.isAttachmentCode(code) else { return nil }
        return Self(code: code.isEmpty ? "conversation_conflict" : code)
    }

    var message: String {
        tr5("This send was not accepted because of a conversation conflict. Your text and attachments are saved. Review the conversation, then send the same text to retry. No need to upload the attachments again.",
           "الإرسال ما انقبل بسبب تعارض بالمحادثة. نصّك ومرفقاتك محفوظين. راجع المحادثة، وبعدين ابعت نفس النص لتعيد المحاولة. ما في داعي ترفع المرفقات من جديد.",
           de: "Die Nachricht wurde wegen eines Konflikts im Gespräch nicht angenommen. Text und Anhänge sind gespeichert. Prüfe das Gespräch und sende denselben Text erneut. Du musst die Anhänge nicht erneut hochladen.",
           ckb: "گفتوگۆکە گۆڕاوە یان پێویستی بە پشتڕاستکردنەوە هەیە. نامە و هاوپێچەکانت پاشەکەوت کراون، نەنێردراون. گفتوگۆکە بپشکنە، پاشان هەمان دەق بنێرەوە. پێویست ناکات هاوپێچەکان دووبارە بار بکەیتەوە.",
           kmr: "Sohbet guherî an pejirandin dixwaze. Peyam û pêvekên te hatine tomarkirin, nehatine şandin. Sohbetê kontrol bike, paşê heman nivîsê dîsa bişîne. Pêdivî bi barkirina pêvekan ji nû ve tune ye.")
    }
}

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
    /// Mirsa 2.1: text of a message the server refused because of its attachments (410/404/409/422),
    /// handed back to that thread's composer together with its chips. Never filled while attachments are off.
    @Published var returnedText: [UUID: String] = [:]
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

    #if DEBUG
    /// Unit-test transport exercises the real queue without credentials, persistence or background retries.
    private var testRequest: (([String: Any]) async throws -> Data)?
    init(testRequest: @escaping ([String: Any]) async throws -> Data) {
        self.testRequest = testRequest
    }
    #endif

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
            threads = [ForgeChatThread(id: t, title: "Fixture", status: "open", createdAt: nil, updatedAt: nil)]
            messages = [t: [
                ForgeChatMessage(id: UUID(), threadID: t, role: "user", text: "Make me a tweak that hides the dock labels."),
                ForgeChatMessage(id: UUID(), threadID: t, role: "kat", text: "Got it. I'll build it and send it here when it's ready."),
                ForgeChatMessage(id: UUID(), threadID: t, role: "user", text: "Thanks, no rush.")]]
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-MirsaTendiesArtifactFixture") {
                // Actual authenticated backend artifact metadata; no issued URL or network access.
                let artifact = ForgeChatArtifact(id: UUID(), kind: "tendies", name: "Naruto-Space.tendies",
                    size: 1_349_699, sha256: "8720c01d9d5f486e03500441b9b75bf202c8147573c45367625143ef1370acf1", expiresAt: nil)
                let result = ForgeChatResult(inboxID: nil, tweakID: nil, bundleID: nil, name: nil, version: nil, artifact: artifact)
                messages[t] = [ForgeChatMessage(id: UUID(), threadID: t, role: "result", text: nil, result: result)]
            }
            #endif
            ackedThreads.insert(t)
            return
        }
        defer { startRetrying() }; outgoing = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([ForgeChatOutgoing].self, from: $0) } ?? []
        sentEcho = UserDefaults.standard.data(forKey: echoKey).flatMap { try? JSONDecoder().decode([ForgeChatOutgoing].self, from: $0) } ?? []
        for echo in sentEcho { ackedThreads.insert(echo.threadID) }
        if let paused = outgoing.first(where: { $0.conversationConflict != nil }) {
            error = ForgeChatConversationConflict(code: paused.conversationConflict ?? "").message
        }
    }
    private func saveEcho() {
        #if DEBUG
        if testRequest != nil { return }
        #endif
        UserDefaults.standard.set(try? JSONEncoder().encode(sentEcho), forKey: echoKey)
    }
    private func saveOutgoing() {
        #if DEBUG
        if testRequest != nil { return }
        #endif
        UserDefaults.standard.set(try? JSONEncoder().encode(outgoing), forKey: key)
    }

    func callPublic(_ body: [String: Any]) async throws -> Data { try await call(body) }
    /// Last real failure (HTTP status + server code, or the network error) so the user and logs can see the true reason.
    @Published var lastDiagnostic: String?
    private func call(_ body: [String: Any], retryBind: Bool = true) async throws -> Data {
        #if DEBUG
        if let testRequest { return try await testRequest(body) }
        #endif
        if Self.fixture { throw ForgeChatTransient.failed("fixture") }
        let r: ForgePreciseClient.Response
        do {
            let c = try await ForgeClient.fixToken()
            if let attachmentEndpoint = ChatAttachmentConfig.endpoint, let ids = body["attachmentIDs"] as? [String], !ids.isEmpty {
                // Attachment-bearing messages use the verified production contract with the same identity.
                r = try await ForgePreciseClient.request(body, credentials: c, endpoint: attachmentEndpoint, apikey: WebBackendConfig.defaultPublishableKey)
            } else {
                r = try await ForgePreciseClient.request(body, credentials: c)
            }
        } catch {
            let d = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastDiagnostic = d
            throw ForgeChatTransient.failed(d)
        }
        if r.status == 200 { lastDiagnostic = nil; return r.data }
        let code = (try? JSONSerialization.jsonObject(with: r.data) as? [String: Any])?["error"] as? String ?? ""
        if code == "message_too_long" { lastDiagnostic = code; throw ForgeChatTransient.failed(code) }
        if let conflict = ForgeChatConversationConflict.response(status: r.status, code: code) {
            lastDiagnostic = "HTTP \(r.status) \(code)"
            throw conflict
        }
        if let ids = body["attachmentIDs"] as? [String], !ids.isEmpty, [401, 404, 409, 410, 422, 503].contains(r.status) || (r.status == 403 && !retryBind) {
            lastDiagnostic = "HTTP \(r.status) \(code)"
            throw ChatAttachmentError(status: r.status, code: code)
        }
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
    var pendingThreadIDs: [UUID] { var seen = Set<UUID>(); return (outgoing + sentEcho).map(\.threadID).filter { id in !threads.contains { t in t.id == id } && seen.insert(id).inserted } }
    func hasInFlight(_ id: UUID) -> Bool { outgoing.contains { $0.threadID == id } }

    @discardableResult
    func send(threadID: UUID?, text: String, jpeg: Data?, attachmentIDs: [UUID] = [], replyTo: ForgeChatReplyRef? = nil) -> UUID? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        guard ForgeChatText.messageCount(t) <= ForgeChatText.messageMax else { error = ForgeChatText.tooLong; return nil }
        if let tid = threadID, deleting.contains(tid) { return nil }
        let ids = ChatAttachmentRules.sendIDs(attachmentIDs)
        // Only an explicit Send of the same text can resume a paused conflict.
        // Reuse the saved attachment IDs when the composer has no new chips.
        // Never synthesize approval text or assign a second message UUID.
        if let tid = threadID, let index = outgoing.firstIndex(where: {
            $0.threadID == tid && $0.conversationConflict != nil && $0.text == t &&
            jpeg == nil && (ids.isEmpty || ids == ($0.attachmentIDs ?? []))
        }) {
            let id = outgoing[index].id
            outgoing[index].conversationConflict = nil
            saveOutgoing()
            Task { await flush() }
            startRetrying()
            return id
        }
        // Never the legacy image together with attachmentIDs.
        let img = ids.isEmpty ? jpeg.flatMap { ForgeChatImage.prepare($0) }?.base64EncodedString() : nil
        let tid = threadID ?? UUID()
        let confirmed = messages[tid] ?? []
        let pending = ForgeChatTimeline.pending(outgoing: outgoing, echoes: sentEcho, confirmed: confirmed, threadID: tid)
        let anchor = ForgeChatTimeline.orderedIDs(confirmed: confirmed, pending: pending).last
        let newID = UUID()
        // Mirsa 2.2: the quote is kept on this device under the message's own UUID (same UUID once the server confirms it).
        if let replyTo { ForgeChatLocal.shared.setReply(replyTo, for: newID) }
        outgoing.append(ForgeChatOutgoing(id: newID, threadID: tid, newThread: !serverKnows(tid), text: t, imageBase64: img, afterMessageID: anchor, attachmentIDs: ids.isEmpty ? nil : ids))
        saveOutgoing()
        UserDefaults.standard.set(true, forKey: ForgeChatLocal.usedKey)
        Task { await flush() }
        startRetrying()
        return newID
    }

    private var retrying = false
    /// Keeps replaying saved messages (same id, server dedupes) with backoff until the server accepts them. Nothing is dropped silently.
    func startRetrying() {
        #if DEBUG
        if testRequest != nil { return }
        #endif
        guard !retrying, outgoing.contains(where: { $0.conversationConflict == nil }) else { return }
        retrying = true
        Task { [weak self] in
            var delay: UInt64 = 5
            while let self, self.outgoing.contains(where: { $0.conversationConflict == nil }) {
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
        // One attempt per saved message per pass. A failed older row stays saved but
        // cannot starve later rows, including messages appended while a request awaits.
        var attempted = Set<UUID>()
        while let o = outgoing.first(where: { !deleting.contains($0.threadID) && $0.conversationConflict == nil && !attempted.contains($0.id) }) {
            attempted.insert(o.id)
            var body: [String: Any] = ["action": "chat-send", "id": o.id.uuidString.lowercased(), "threadID": o.threadID.uuidString.lowercased(), "newThread": !serverKnows(o.threadID), "text": o.text, "language": AppLanguageStore.snapshot.rawValue]
            if let ids = o.attachmentIDs, !ids.isEmpty {
                body["attachmentIDs"] = ChatAttachmentRules.sendIDs(ids).map { $0.uuidString.lowercased() } // same IDs on every retry
            } else if let b = o.imageBase64 { body["image"] = ["mime": "image/jpeg", "base64": b] }
            if ForgeChatFeatures.serverReplyAndReactions, let ref = ForgeChatLocal.shared.replies[o.id] {
                body["replyToMessageID"] = ref.messageID.uuidString.lowercased() // PROPOSED field, off until Kat confirms
            }
            do {
                let sent = try await call(body)
                if deleting.contains(o.threadID) { continue } // delete started mid-send; delete waits for flush and wipes it
                ackedThreads.insert(o.threadID); let echo = ForgeChatTimeline.acceptedEcho(o); sentEcho.removeAll { $0.id == o.id }; sentEcho.append(echo); saveEcho()
                outgoing.removeAll { $0.id == o.id }; saveOutgoing(); if outgoing.isEmpty { error = nil }
                if let ids = o.attachmentIDs, !ids.isEmpty { applySentAttachments(sent, threadID: o.threadID) }
            } catch let conflict as ForgeChatConversationConflict {
                if let index = outgoing.firstIndex(where: { $0.id == o.id }) {
                    outgoing[index].conversationConflict = conflict.code
                    saveOutgoing()
                }
                self.error = conflict.message
                // Preserve text, UUID and valid uploaded IDs. Do not invalidate
                // attachments, restore unusable chips, auto-confirm or auto-retry.
            } catch let a as ChatAttachmentError {
                if a.isTransient || a.status == 401 || a.status == 403 {
                    self.error = a.message
                    continue // preserve identity/attachments; still attempt newer messages
                }
                // 410/404/409/422: refused before the message existed. Never retry these IDs silently:
                // hand the text and the chips back to the composer, expired ones with Upload again.
                outgoing.removeAll { $0.id == o.id }; saveOutgoing()
                ChatAttachmentDrafts.shared.restore(o.attachmentIDs ?? [], thread: o.threadID, problem: a)
                returnedText[o.threadID] = o.text
                self.error = a.message
            } catch let f as ForgeClient.Failure {
                // Keep quota failures saved too. A limit must not silently erase user text.
                error = f.errorDescription
            } catch {
                self.error = lastDiagnostic == "message_too_long" ? ForgeChatText.tooLong : ForgeChatText.failed
                continue // saved for retry, without blocking the rest of the queue
            }
        }
        await refreshThreads()
    }

    /// Kat, 2026-11-10: chat-send answers {message:{...}} with message.attachments, same shape as chat-read
    /// (expired ones come back available:false with no bytes). Publish it right away; the next read confirms it.
    private func applySentAttachments(_ data: Data, threadID: UUID) {
        struct W: Decodable { let message: ForgeChatMessage }
        guard let m = (try? JSONDecoder().decode(W.self, from: data))?.message, m.threadID == threadID,
              m.attachments?.isEmpty == false else { return }
        let merged = ForgeChatTimeline.mergeConfirmed(previous: messages[threadID] ?? [], incoming: [m])
        if messages[threadID] != merged { var all = messages; all[threadID] = merged; messages = all }
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

    /// Mirsa 2.1 «بلّغ عن مشكلة» (Kat's contract, 2026-11-10): POST {action:"chat-report", threadID, messageID, note}
    /// to the chat-send endpoint with the same headers. messageID is the Mirsa AI reply under which the button was tapped.
    /// 200 ok (a repeat report also answers 200) · 401 refresh session, retry once · 403 rebind device, retry once
    /// · 404 thread/message gone · 422 bad UUID or note > 500 · 503 unavailable.
    enum ReportResult: Equatable { case ok, gone, invalid, unavailable }
    func report(threadID: UUID, messageID: UUID, note: String) async -> ReportResult {
        if Self.fixture { return .ok }
        let n = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        let body: [String: Any] = ["action": "chat-report", "threadID": threadID.uuidString.lowercased(), "messageID": messageID.uuidString.lowercased(), "note": n]
        var refreshed = false, rebound = false
        while true {
            let r: ForgePreciseClient.Response
            do { r = try await ForgePreciseClient.request(body, credentials: try await ForgeClient.fixToken(forceRefresh: refreshed)) }
            catch { lastDiagnostic = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription; return .unavailable }
            switch r.status {
            case 200: return .ok
            case 401 where !refreshed: refreshed = true; continue
            case 403 where !rebound: rebound = true; _ = try? await ForgeClient.get(["action": "gallery"]); continue
            case 404: return .gone
            case 422: return .invalid
            default: lastDiagnostic = "chat-report HTTP \(r.status)"; return .unavailable
            }
        }
    }

    func refreshThreads() async {
        guard !Self.fixture else { return }
        struct Lossy: Decodable { let value: ForgeChatThread?; init(from d: Decoder) throws { value = try? ForgeChatThread(from: d) } }
        struct W: Decodable { let threads: [Lossy] }
        let epochs = deleteEpoch
        guard let d = try? await call(["action": "chat-list"]), let w0 = try? JSONDecoder().decode(W.self, from: d) else { return }
        let w = (threads: w0.threads.compactMap(\.value).filter { !deleting.contains($0.id) && deleteEpoch[$0.id] == epochs[$0.id] }, ())
        let sorted = w.threads.sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
        MirsaRequestReadyNotifications.activeStore = self
        await MirsaRequestReadyNotifications.observe(sorted)
        if sorted != threads { threads = sorted }
    }

    /// Preserve the same delete-epoch guard as foreground refresh.
    func mergeReadyNotificationThreads(_ incoming: [ForgeChatThread]) {
        let known = Set(threads.map(\.id))
        let fresh = incoming.filter { !deleting.contains($0.id) && (deleteEpoch[$0.id] == nil || known.contains($0.id)) }
        if fresh != threads { threads = fresh.sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") } }
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
        // A timed-out send may already have reached the server. Its canonical UUID
        // in chat-read confirms delivery even when the POST never returned locally.
        if outgoing.contains(where: { $0.threadID == id && ids.contains($0.id) }) {
            outgoing.removeAll { $0.threadID == id && ids.contains($0.id) }
            saveOutgoing()
            if outgoing.isEmpty && error == ForgeChatText.failed { error = nil }
        }
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

struct ForgeChatRoot: View {
    var embedded: Bool = false
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ForgeChatStore.shared
    @AppStorage("mirsa.chat.guideSeen") private var guideSeen = false
    @State private var path: [UUID] = []
    @State private var open: ForgeOpenThread?
    @State private var toDelete: UUID?
    @State private var showIDHelp = false
    @ObservedObject private var local = ForgeChatLocal.shared
    @Environment(\.scenePhase) private var scenePhase
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
                        HStack(spacing: 12) { MirsaSailMark().frame(width: 34, height: 34); VStack(alignment: .leading, spacing: 6) { Text(ForgeChatText.cleanTitle(t.title)).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(2); if let s = t.status, !ForgeChatText.status(s).isEmpty { MirsaChatStatusPill(raw: s) } }
                            if local.isUnread(t) { Spacer(minLength: 0); Circle().fill(MirsaChatTheme.blue).frame(width: 11, height: 11).accessibilityLabel(ForgeChatExtrasText.newMessages).accessibilityIdentifier("chat-row-unread") } }.padding(.vertical, 6)
                    } }.buttonStyle(.plain)
                    .listRowBackground(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.07)).overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.5)))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { toDelete = t.id } label: { Label(ForgeChatText.deleteAction, systemImage: "trash") }.tint(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden).listRowSpacing(10).background(AuroraBackground().ignoresSafeArea()).preferredColorScheme(.dark)
            .onChange(of: store.threads) { _, t in
                local.baselineIfNeeded(t)
                if !t.isEmpty { UserDefaults.standard.set(true, forKey: ForgeChatLocal.usedKey) }
            }
            .confirmationDialog(ForgeChatText.deleteTitle, isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
                Button(ForgeChatText.deleteAction, role: .destructive) { if let id = toDelete { Task { await store.deleteThread(id) } }; toDelete = nil }
                Button(ForgeChatText.cancel, role: .cancel) { toDelete = nil }
            }
            .navigationTitle(ForgeChatText.title).navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { ForgeChatThreadView(threadID: $0) }
            // A conversation opens full screen, over the Tools segments and the tab bar.
            .fullScreenCover(item: $open) { o in ForgeChatThreadView(threadID: o.id).environment(\.layoutDirection, .leftToRight) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { if !embedded { Button(ForgeChatText.close) { dismiss() } } }
                // Short-ID hint: a small icon opposite the new-chat button; the text shows in a small popover.
                ToolbarItem(placement: .topBarLeading) {
                    Button { showIDHelp = true } label: { Image(systemName: "number.circle") }
                        .accessibilityLabel(ForgeChatText.shortIDLabel).accessibilityIdentifier("chat-id-help")
                        .popover(isPresented: $showIDHelp, arrowEdge: .top) {
                            Text(ForgeChatText.shortIDHelp).font(.footnote).multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true).frame(width: 260).padding(14)
                                .presentationCompactAdaptation(.popover)
                        }
                }
                ToolbarItem(placement: .primaryAction) { Button { open = ForgeOpenThread(id: store.draftThreadID()) } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel(ForgeChatText.newRequest).accessibilityIdentifier("chat-new") }
            }
            .task { // poll only while this screen is visible
                await store.flush()
                while !Task.isCancelled { if scenePhase == .active { await store.refreshThreads() }; try? await Task.sleep(nanoseconds: 15_000_000_000) }
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

/// Mirsa's own app icon, read once from the bundle (CFBundleIcons), so the chat avatar always matches the installed icon.
enum MirsaAppIconImage {
    static let image: UIImage? = {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let p = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = p["CFBundleIconFiles"] as? [String] else { return UIImage(named: "AppIcon") }
        for f in files.reversed() { if let i = UIImage(named: f) { return i } }
        return UIImage(named: "AppIcon")
    }()
}

/// Assistant avatar: the Mirsa AI artwork (asset MirsaAIAvatar, round), then the app icon, then the vector sail mark.
struct MirsaSailMark: View {
    private static let avatar = UIImage(named: "MirsaAIAvatar")
    var body: some View {
        if let img = Self.avatar {
            Image(uiImage: img).resizable().interpolation(.high).aspectRatio(1, contentMode: .fit)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else if let img = MirsaAppIconImage.image {
            GeometryReader { g in
                Image(uiImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: g.size.width, height: g.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: g.size.width * 0.225, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: g.size.width * 0.225, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.5))
            }
            .accessibilityHidden(true)
        } else {
            MirsaSailVector()
        }
    }
}

/// Vector fallback when the bundle icon cannot be read.
private struct MirsaSailVector: View {
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

/// Original soft breathing/merging orbs, rendered only while the waiting row is visible.
private struct MirsaBreathingOrbs: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !visible || reduceMotion || scenePhase != .active)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                context.addFilter(.alphaThreshold(min: 0.32, color: MirsaPalette.accent))
                context.addFilter(.blur(radius: 3))
                context.drawLayer { layer in
                    for index in 0..<3 {
                        let phase = time * 1.8 + Double(index) * 1.9
                        let radius = reduceMotion ? 5.5 : 5.5 + sin(phase) * 1.2
                        let x = 10 + Double(index) * 12 + (reduceMotion ? 0 : sin(phase * 0.7) * 3)
                        let y = Double(size.height) / 2 + (reduceMotion ? 0 : cos(phase) * 2)
                        layer.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(MirsaPalette.accent))
                    }
                }
            }
        }
        .frame(width: 46, height: 28)
        .onAppear { visible = true }.onDisappear { visible = false }
        .accessibilityHidden(true)
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
    // The rest of Mirsa can force dark appearance. Read the scene's system
    // traits, not that inherited SwiftUI override, until the user chooses.
    @State private var systemDark = false
    @AppStorage("mirsa.chat.appearance") private var chatAppearance = "system"
    private var darkChat: Bool {
        switch chatAppearance {
        case "light": return false
        case "dark": return true
        default: return systemDark
        }
    }
    private var chatInk: Color { darkChat ? Color(white: 0.95) : Color(white: 0.10) }
    private var chatMuted: Color { darkChat ? Color(white: 0.65) : Color(white: 0.43) }
    private var chatCanvas: Color { darkChat ? Color(white: 0.055) : Color(red: 0.973, green: 0.973, blue: 0.969) }
    private var chatCard: Color { darkChat ? Color(white: 0.105) : .white }
    private var chatRim: Color { darkChat ? .white.opacity(0.09) : .black.opacity(0.06) }
    @Environment(\.scenePhase) private var scenePhase
    @State private var text = ""
    @AppStorage("mirsa.chat.catEnabled") private var catEnabled = true
    @State private var showChatSettings = false
    @State private var catTouch = CGPoint(x: 0.78, y: 0)
    @State private var catAwake = Date()
    @State private var catCelebration = Date.distantPast
    @FocusState private var composerFocused: Bool
    @State private var photo: PhotosPickerItem?
    @State private var jpeg: Data?
    @State private var started = false
    /// First 8 characters of the device ID the chat already sends as x-mirsa-device.
    @State private var shortID = ""
    @State private var reportTarget: ForgeChatMessage?
    @State private var reportDone = false
    // Mirsa 2.1 attachments (only used when ChatAttachmentConfig.uiEnabled).
    @ObservedObject private var drafts = ChatAttachmentDrafts.shared
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var showLink = false
    @State private var attachPhoto: PhotosPickerItem?
    @State private var attachNote: String?
    @State private var copiedTick = 0
    @State private var showCopied = false
    // Mirsa 2.2: reply, long-press menu, edit/delete.
    @ObservedObject private var local = ForgeChatLocal.shared
    @State private var replyTo: ForgeChatReplyRef?
    @State private var editingID: UUID?
    @State private var menuTarget: ForgeChatMenuTarget?
    // Mirsa 2.3: the reactions tip shows once above the composer when the chat opens; ✕ hides it for good.
    @AppStorage("mirsa.chat.reactionsTipDismissed") private var reactionsTipDismissed = false
    @State private var deleteTarget: ForgeChatMenuTarget?
    @State private var jumpTo: UUID?
    @State private var flashID: UUID?
    @State private var actionError: String?
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
    private var catThinking: Bool {
        #if DEBUG
        if ForgeChatStore.fixture && ProcessInfo.processInfo.arguments.contains("-MirsaCatThinkingFixture") { return true }
        #endif
        return unsent || !queued.isEmpty || msgs.last?.role == "user"
    }
    private var unsent: Bool { store.hasInFlight(threadID) }
    private var isNew: Bool { !started && msgs.isEmpty && queued.isEmpty && !store.threads.contains { $0.id == threadID } }
    private var draftCount: Int { ForgeChatText.messageCount(text) }
    private var attachmentsUI: Bool { ChatAttachmentConfig.uiEnabled }
    private var attachmentsReady: Bool { !attachmentsUI || drafts.readyIDs(threadID) != nil }
    private var canSend: Bool { draftCount > 0 && draftCount <= ForgeChatText.messageMax && (editingID != nil || attachmentsReady) }
    private var threadStatus: String { (store.threads.first { $0.id == threadID }?.status ?? "").lowercased() }
    /// Edit only while nothing has started on it: the newest row, a user message, and the request not yet being built.
    private func canEdit(_ id: UUID) -> Bool {
        ForgeChatFeatures.serverEditDelete && ForgeChatMutationPolicy.canMutate(messageID: id, messages: msgs, hasPending: !queued.isEmpty, status: threadStatus)
    }
    private func messageText(_ id: UUID) -> String? {
        if let m = msgs.first(where: { $0.id == id }) { return m.text }
        return queued.first { $0.id == id }?.text
    }
    private func openMenu(id: UUID, text: String, isUser: Bool, confirmed: Bool) {
        menuTarget = ForgeChatMenuTarget(id: id, threadID: threadID, text: text, isUser: isUser,
                                         canEdit: isUser && confirmed && canEdit(id),
                                         canDelete: isUser && confirmed && canEdit(id),
                                         reactable: confirmed)
    }
    private func startReply(id: UUID, text: String?, isUser: Bool) {
        editingID = nil
        withAnimation(.easeOut(duration: 0.18)) { replyTo = ForgeChatReplyRef(messageID: id, snippet: ForgeChatLocal.snippet(text), fromUser: isUser) }
        composerFocused = true
    }
    private func reaction(_ id: UUID) -> String? {
        if ForgeChatFeatures.serverReplyAndReactions { return msgs.first { $0.id == id }?.reaction }
        return local.reactions[id]
    }
    private func quote(_ id: UUID, confirmed: Bool) -> ForgeChatReplyRef? {
        guard confirmed, ForgeChatFeatures.serverReplyAndReactions else { return local.replies[id] }
        guard let m = msgs.first(where: { $0.id == id }), let target = m.replyToMessageID else { return nil }
        return ForgeChatReplyRef(messageID: target, snippet: ForgeChatLocal.snippet(m.replyQuoteText), fromUser: m.replyQuoteRole == "user")
    }
    /// Quote above, reaction below, swipe right to reply, long press for the menu.
    @ViewBuilder private func chrome<C: View>(id: UUID, text: String?, isUser: Bool, confirmed: Bool, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            if let ref = quote(id, confirmed: confirmed) {
                ForgeChatQuote(ref: ref, exists: messageText(ref.messageID) != nil || ref.messageID == id) { jumpTo = ref.messageID }
            }
            content()
                .modifier(ForgeChatHoldToMenu { openMenu(id: id, text: text ?? "", isUser: isUser, confirmed: confirmed) })
            if let e = reaction(id) {
                ForgeChatReactionChip(emoji: e).onTapGesture { openMenu(id: id, text: text ?? "", isUser: isUser, confirmed: confirmed) }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(flashID == id ? 0.12 : 0)).padding(-6)
                .animation(.easeOut(duration: 0.5), value: flashID)
        }
        // The whole row, empty space beside the bubble included, takes the swipe.
        .modifier(ForgeChatSwipeToReply(enabled: menuTarget == nil) { startReply(id: id, text: text, isUser: isUser) })
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
                                    chrome(id: o.id, text: o.text, isUser: true, confirmed: false) {
                                        VStack(alignment: .trailing, spacing: 4) {
                                            if let ids = o.attachmentIDs, !ids.isEmpty {
                                                ChatAttachmentStrip(metas: ids.compactMap { AttachmentUploader.shared.known[$0] }, threadID: o.threadID)
                                            }
                                            userBubble(o.text)
                                            if sending { Text(ForgeChatText.sending).font(.caption2).foregroundStyle(chatMuted) }
                                        }
                                    }
                                }
                            }
                            .id(row.id)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .identity))
                        }
                        if !unsent, (!queued.isEmpty || msgs.last?.role == "user") {
                            HStack(spacing: 10) { MirsaBreathingOrbs(); Text(ForgeChatText.waiting).font(.system(size: 14)).foregroundStyle(chatMuted) }
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(chatCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4).accessibilityIdentifier("chat-waiting").transition(.opacity)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 12)
                    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9), value: rows.map(\.id))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: store.outgoing.count)
                }
                .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { gesture in
                    guard catEnabled, !reduceMotion else { return }
                    catTouch = CGPoint(x: min(1, max(0, gesture.location.x / max(1, UIScreen.main.bounds.width))), y: min(1, abs(gesture.translation.height) / 180))
                    catAwake = Date()
                }.onEnded { _ in catTouch.y = 0 })
                .scrollDismissesKeyboard(.interactively)
                // No header bar: the conversation runs to the top edge and scrolls under a floating back button.
                .safeAreaInset(edge: .top, spacing: 0) { header }
                // Opens on the last message and stays pinned to the bottom (new reply, keyboard, composer focus).
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                .onChange(of: rows.map(\.id)) { _, _ in pinToBottom(proxy) }
                .onChange(of: jumpTo) { _, target in
                    guard let target else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { proxy.scrollTo(target, anchor: .center) }
                    flashID = target
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { if flashID == target { flashID = nil } }
                    jumpTo = nil
                }
                .onChange(of: msgs.last?.text) { _, _ in pinToBottom(proxy) }
                .onChange(of: composerFocused) { _, focused in if focused { pinToBottom(proxy, after: 0.35) } }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in pinToBottom(proxy) }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                    // Again once the lazy rows (and the full-screen cover) finished laying out.
                    pinToBottom(proxy, animated: false, after: 0.05)
                    pinToBottom(proxy, animated: false, after: 0.3)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Reserve the composer before the scroll view is laid out. A flexible sibling
        // can be placed below the visible nested NavigationStack/tab safe area.
        // This also tracks the keyboard's safe area without fixed device heights.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if !reactionsTipDismissed {
                    ForgeChatReactionsTip { withAnimation(.easeOut(duration: 0.18)) { reactionsTipDismissed = true } }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let editingID {
                    ForgeChatComposerContext(title: ForgeChatExtrasText.editing, line: ForgeChatLocal.snippet(messageText(editingID)), icon: "pencil") {
                        withAnimation(.easeOut(duration: 0.18)) { self.editingID = nil; text = "" }
                    }.transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let replyTo {
                    ForgeChatComposerContext(title: replyTo.fromUser ? ForgeChatExtrasText.replyToYou : ForgeChatExtrasText.replyToMirsa,
                                             line: replyTo.snippet, icon: "arrowshape.turn.up.left") {
                        withAnimation(.easeOut(duration: 0.18)) { self.replyTo = nil }
                    }.transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if attachmentsUI && editingID == nil { attachmentTray }
                if let jpeg, let img = UIImage(data: jpeg) {
                    HStack { Image(uiImage: img).resizable().scaledToFill().frame(width: 56, height: 56).clipped().cornerRadius(12)
                        Button(ForgeChatText.removeImage) { self.jpeg = nil; photo = nil }.font(.caption).foregroundStyle(chatMuted); Spacer() }.padding(.horizontal, 18).padding(.top, 8)
                }
                if catEnabled {
                    MirsaChatCat(thinking: catThinking, touch: catTouch, awake: catAwake, celebration: catCelebration)
                        .frame(height: 52)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                inputBar
                if let e = actionError ?? store.error {
                    Text(e).font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.bottom, 6)
                        .accessibilityIdentifier("chat-composer-status")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            // Keep the floating composer separate from message cards without covering the last row.
            .background(chatCanvas.opacity(0.96).ignoresSafeArea(edges: .bottom))
        }
        .background(chatCanvas.ignoresSafeArea())
        .background(ForgeChatSystemAppearanceReader { dark in
            if systemDark != dark { systemDark = dark }
        }.frame(width: 0, height: 0))
        // Local environment only. Never change the hosting window or other tabs.
        .environment(\.colorScheme, darkChat ? .dark : .light)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showChatSettings) {
            NavigationStack {
                Form {
                    Section {
                        HStack {
                            Text(MirsaCatText.title)
                            Spacer()
                            // Keep the native switch's hit target separate from the
                            // full-width Form label (including in RTL layouts).
                            Toggle(MirsaCatText.title, isOn: $catEnabled)
                                .labelsHidden()
                                .accessibilityIdentifier("chat-cat-toggle")
                        }
                    } footer: {
                        Text(MirsaCatText.explanation)
                    }
                }
                .navigationTitle(MirsaCatText.settings)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(ForgeChatText.close) { showChatSettings = false }.accessibilityIdentifier("chat-settings-close")
                } }
            }.presentationDetents([.medium, .large])
        }
        .onChange(of: text) { _, _ in catAwake = Date() }
        .onChange(of: msgs.last?.id) { _, _ in
            catAwake = Date()
            catTouch = CGPoint(x: msgs.last?.role == "user" ? 0.78 : 0.22, y: 0)
            if let last = msgs.last, last.role != "user" { catCelebration = Date() }
        }
        .sheet(item: $reportTarget) { m in
            ForgeChatReportSheet { note in await store.report(threadID: m.threadID, messageID: m.id, note: note) } onSent: { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { reportDone = true } }
                .environment(\.layoutDirection, .leftToRight)
        }
        .alert(ForgeChatText.reportThanks, isPresented: $reportDone) {}
        .overlay {
            if let t = menuTarget {
                ForgeChatMessageMenu(target: t, current: reaction(t.id),
                    onReact: { e in
                        if ForgeChatFeatures.serverReplyAndReactions {
                            let selected = reaction(t.id) == e ? nil : e
                            Task {
                                let result = await store.sendReaction(threadID: t.threadID, messageID: t.id, reaction: selected)
                                if result != .ok { actionError = ForgeChatText.reportFailed }
                            }
                        } else {
                            local.toggleReaction(e, on: t.id)
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        closeMenu()
                    },
                    onCopy: { UIPasteboard.general.string = t.text; closeMenu() },
                    onReply: { closeMenu(); startReply(id: t.id, text: t.text, isUser: t.isUser) },
                    onEdit: { closeMenu(); replyTo = nil; editingID = t.id; text = t.text; composerFocused = true },
                    onDelete: { closeMenu(); deleteTarget = t },
                    onClose: closeMenu)
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .confirmationDialog(ForgeChatExtrasText.deleteTitle, isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button(ForgeChatExtrasText.delete, role: .destructive) {
                guard let t = deleteTarget else { return }
                deleteTarget = nil
                Task {
                    let r = await store.deleteMessage(threadID: t.threadID, messageID: t.id)
                    actionError = r == .ok ? nil : ForgeChatExtrasText.deleteFailed
                }
            }
            Button(ForgeChatText.cancel, role: .cancel) { deleteTarget = nil }
        }
        .onAppear { markSeen() }
        .onDisappear { markSeen() }
        .onChange(of: store.threads) { _, _ in markSeen() }
        .preference(key: ForgeChatComposerFocusKey.self, value: composerFocused)
        .onAppear {
            if shortID.isEmpty { shortID = String(ForgeClient.deviceID().prefix(8)) }
            #if DEBUG
            // Seed only the explicit no-network UI harness, never real drafts.
            if ForgeChatStore.fixture {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-MirsaCatSleepingFixture") { catAwake = Date().addingTimeInterval(-60) }
                if args.contains("-MirsaCatHappyFixture") { catCelebration = Date().addingTimeInterval(4) }
                if args.contains("-MirsaChatDraft4000Fixture") { text = String(repeating: "ع", count: 4000) }
                if args.contains("-MirsaChatDraft4001Fixture") { text = String(repeating: "ع", count: 4001) }
            }
            #endif
        }
        #if DEBUG
        .overlay(alignment: .center) { if ForgeChatStore.fixture && ProcessInfo.processInfo.arguments.contains("-MirsaAttachmentRulesSelfTest") { ChatAttachmentSelfTestBadge() } }
        #endif
        .modifier(ChatAttachmentPickers(enabled: attachmentsUI, threadID: threadID, showPhotos: $showPhotos, showFiles: $showFiles,
                                        showLink: $showLink, attachPhoto: $attachPhoto, note: $attachNote))
        .onChange(of: store.returnedText[threadID]) { _, returned in
            // A send refused for its attachments comes back here with its chips; never resent silently.
            guard let returned else { return }
            if text.isEmpty { text = returned }
            store.returnedText[threadID] = nil
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { jpeg = (try? await item.loadTransferable(type: Data.self)).flatMap { ForgeChatImage.prepare($0) } }
        }
        .onChange(of: scenePhase) { _, p in if p == .active { Task { await store.read(threadID) } } }
        .onChange(of: store.threads) { _, _ in Task { await store.read(threadID) } }
        .task {
            while !Task.isCancelled && !ForgeChatStore.fixture { if scenePhase == .active { await store.read(threadID) }; try? await Task.sleep(nanoseconds: 8_000_000_000) } // stops reading in the background
        }
    }

    /// Paperclip menu with exactly Photos / Files / From link (no camera).
    private var attachMenu: some View {
        Menu {
            Button { showPhotos = true } label: { Label(ChatAttachmentText.photos, systemImage: "photo.on.rectangle") }.accessibilityIdentifier("chat-attach-photos")
            Button { showFiles = true } label: { Label(ChatAttachmentText.files, systemImage: "doc") }.accessibilityIdentifier("chat-attach-files")
            Button { showLink = true } label: { Label(ChatAttachmentText.fromLink, systemImage: "link") }.accessibilityIdentifier("chat-attach-link")
        } label: {
            Image(systemName: "paperclip").font(.system(size: 20)).foregroundStyle(chatMuted).frame(width: 36, height: 36)
        }
        .disabled(!drafts.canAdd(threadID))
        .accessibilityLabel(ChatAttachmentText.attach)
        .accessibilityIdentifier("chat-attach")
    }

    /// Chips above the composer, removable, with a short explanation of the feature.
    @ViewBuilder private var attachmentTray: some View {
        let items = drafts.items(threadID)
        if !items.isEmpty || attachNote != nil {
            VStack(alignment: .leading, spacing: 6) {
                if !items.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(items) { item in
                                ChatDraftAttachmentChip(item: item,
                                                        onRemove: { drafts.remove(item.id, thread: threadID) },
                                                        onUploadAgain: { drafts.uploadAgain(item.id, thread: threadID) })
                            }
                        }
                    }
                    Text(ChatAttachmentText.help).font(.caption2).foregroundStyle(chatMuted).fixedSize(horizontal: false, vertical: true)
                }
                if let attachNote {
                    Text(attachNote).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("chat-attachment-note")
                }
            }
            .padding(.horizontal, 18).padding(.top, 8)
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    private var shortIDCapsule: some View {
        Button {
            UIPasteboard.general.string = shortID
            copiedTick += 1
            withAnimation(.easeOut(duration: 0.2)) { showCopied = true }
            let tick = copiedTick
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if copiedTick == tick { withAnimation(.easeIn(duration: 0.2)) { showCopied = false } } }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc").font(.system(size: 11, weight: .semibold))
                Text(showCopied ? ForgeChatText.copied : ForgeChatText.shortIDLabel + " " + shortID)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced)).lineLimit(1)
            }
            .foregroundStyle(showCopied ? Color.green : chatMuted)
            .padding(.horizontal, 12).frame(height: 32)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(chatRim, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .environment(\.layoutDirection, .leftToRight)
        .sensoryFeedback(.success, trigger: copiedTick)
        .accessibilityIdentifier("chat-short-id")
        .accessibilityLabel(ForgeChatText.shortIDLabel + " " + shortID)
        .accessibilityHint(ForgeChatText.shortIDHelp)
    }

    private func closeMenu() {
        withAnimation(.easeOut(duration: 0.18)) { menuTarget = nil }
    }
    private func markSeen() { local.markSeen(threadID, updatedAt: store.threads.first { $0.id == threadID }?.updatedAt) }

    private func pinToBottom(_ proxy: ScrollViewProxy, animated: Bool = true, after delay: Double = 0) {
        let go = {
            if animated && !reduceMotion { withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            else { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        if delay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: go) } else { DispatchQueue.main.async(execute: go) }
    }

    /// Familiar circular navigation actions and a quiet conversation identity.
    private var header: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).foregroundStyle(chatInk).frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle()).overlay(Circle().stroke(chatRim, lineWidth: 0.5)) }
                .accessibilityLabel(ForgeChatText.close).accessibilityIdentifier("chat-back")
            VStack(alignment: .leading, spacing: 1) {
                Text(ForgeChatText.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(chatInk)
                if !shortID.isEmpty { shortIDCapsule }
            }
            Spacer(minLength: 0)
            blackBackgroundToggle
            Button { showChatSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 16))
                    .foregroundStyle(chatInk).frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }.accessibilityLabel(MirsaCatText.settings).accessibilityIdentifier("chat-settings")

        }
        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 10)
        .background(chatCanvas.opacity(0.94))
        .zIndex(1)
    }

    /// Switch the whole thread palette and materials, persisting an explicit choice.
    private var blackBackgroundToggle: some View {
        Button { chatAppearance = darkChat ? "light" : "dark" } label: {
            Image(systemName: darkChat ? "moon.fill" : "moon")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(chatInk)
                .frame(width: 28, height: 28).background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(chatRim, lineWidth: 0.5))
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MirsaChatBackground.label(black: darkChat))
        .accessibilityValue(darkChat ? "dark" : "light")
        .accessibilityIdentifier("chat-black-background")
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if draftCount >= 3600 {
                Text(draftCount > ForgeChatText.messageMax ? ForgeChatText.tooLong : ForgeChatText.counter(draftCount))
                    .font(.caption).foregroundStyle(draftCount > ForgeChatText.messageMax ? Color.red : chatMuted)
                    .accessibilityIdentifier("chat-character-limit")
                    .accessibilityLabel(ForgeChatText.counter(draftCount))
                    .accessibilityValue(draftCount > ForgeChatText.messageMax ? ForgeChatText.tooLong : "")
            }
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 8) {
                    if attachmentsUI {
                        attachMenu
                    } else {
                        PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo").font(.system(size: 20)).foregroundStyle(chatMuted).frame(width: 36, height: 36) }.accessibilityLabel(ForgeChatText.photo)
                    }
                    TextField("", text: $text, prompt: Text(ForgeChatText.placeholder).foregroundColor(chatMuted), axis: .vertical).lineLimit(1...5).accessibilityIdentifier("chat-input").focused($composerFocused).foregroundStyle(chatInk).tint(MirsaPalette.accent)
                }.padding(.leading, 10).padding(.vertical, 8)
                Button {
                    started = true
                    if let eid = editingID {
                        let newText = text
                        Task {
                            let r = await store.editMessage(threadID: threadID, messageID: eid, text: newText)
                            if r == .ok { editingID = nil; text = ""; actionError = nil } else { actionError = ForgeChatExtrasText.editFailed }
                        }
                        return
                    }
                    let quote = replyTo
                    replyTo = nil
                    if attachmentsUI {
                        drafts.expireStale(threadID)
                        guard let ids = drafts.readyIDs(threadID) else { attachNote = ChatAttachmentText.needsUpload; return }
                        // Same draft thread UUID the uploads used; the first send still says newThread true.
                        store.send(threadID: threadID, text: text, jpeg: nil, attachmentIDs: ids, replyTo: quote)
                        drafts.clearAfterSend(threadID); attachNote = nil
                        text = ""; jpeg = nil; photo = nil
                    } else {
                        store.send(threadID: threadID, text: text, jpeg: jpeg, replyTo: quote)
                        text = ""; jpeg = nil; photo = nil
                    }
                } label: { Image(systemName: "arrow.up").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44).background((canSend ? MirsaPalette.accent : Color(white: 0.30)).opacity(canSend ? 1 : 0.45), in: Circle()) }
                    .disabled(!canSend).accessibilityLabel(ForgeChatText.send).accessibilityIdentifier("chat-send")
                    .scaleEffect(canSend ? 1 : 0.94).animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: canSend)
                    .sensoryFeedback(.impact(weight: .light), trigger: store.outgoing.count)
            }
            .padding(.trailing, 7).padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(chatRim, lineWidth: 1))
            .shadow(color: .black.opacity(darkChat ? 0.16 : 0.05), radius: 18, y: 5)
        }.padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
        // Do not assign an identifier to this transparent layout container.
        // SwiftUI propagates it to the text editor and buttons, replacing their
        // distinct identifiers and hiding those controls from accessibility queries.
    }

    private func userBubble(_ t: String) -> some View {
        Text(t).font(.system(size: 16)).foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 13)
            .background(Color(white: darkChat ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .frame(maxWidth: 300, alignment: .trailing)
    }

    @ViewBuilder private func assistantBlock<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content().foregroundStyle(chatInk)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(chatCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(chatRim, lineWidth: 0.7))
        .shadow(color: .black.opacity(darkChat ? 0.08 : 0.025), radius: 14, y: 4)
        .padding(.trailing, 14)
    }

    @ViewBuilder private func bubble(_ m: ForgeChatMessage) -> some View {
        if m.role == "user" {
            chrome(id: m.id, text: m.text, isUser: true, confirmed: true) {
                VStack(alignment: .trailing, spacing: 8) {
                    if m.hasImage == true { ForgeChatImageView(messageID: m.id) }
                    if let a = m.attachments, !a.isEmpty { ChatAttachmentStrip(metas: a, threadID: m.threadID) }
                    if let t = m.text, !t.isEmpty { userBubble(t) }
                }
            }
        } else {
            chrome(id: m.id, text: m.text, isUser: false, confirmed: true) { assistantBlock {
                VStack(alignment: .leading, spacing: 8) {
                    if m.hasImage == true { ForgeChatImageView(messageID: m.id) }
                    if let a = m.attachments, !a.isEmpty { ChatAttachmentStrip(metas: a, threadID: m.threadID, alignment: .leading) }
                    if let t = m.text, !t.isEmpty { Text(ForgeChatMarkdown.attributed(t)).font(.system(size: 16)).lineSpacing(5).multilineTextAlignment(.leading) }
                    if m.role == "result" {
                        if m.result?.artifact == nil { Label(ForgeChatText.resultSaved, systemImage: "checkmark.shield").font(.caption).foregroundStyle(.green) }
                        if let n = m.result?.name { Text(n).font(.caption.bold()) }
                        if let a = m.result?.artifact { ForgeChatArtifactCard(threadID: m.threadID, artifact: a) }
                    }
                }
            } }
            Button { reportTarget = m } label: {
                Label(ForgeChatText.reportButton, systemImage: "exclamationmark.bubble").font(.caption).foregroundStyle(chatMuted)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(.ultraThinMaterial.opacity(0.6)))
            }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading).padding(.top, -2)
            .accessibilityIdentifier("chat-report")
        }
    }
}

struct ForgeChatImageView: View {
    let messageID: UUID
    @State private var image: UIImage?
    var body: some View {
        Group { if let image { MirsaTappableImage(image: image) } else { ProgressView().frame(height: 60) } }
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


/// Mirsa 2.1 «بلّغ عن مشكلة»: optional note (max 500), Send. Aurora style, left-to-right.
struct ForgeChatReportSheet: View {
    let send: (String) async -> ForgeChatStore.ReportResult
    let onSent: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var sending = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(ForgeChatText.reportButton).font(.headline).foregroundStyle(.white)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8)) }.accessibilityLabel(ForgeChatText.cancel)
            }
            TextField(ForgeChatText.reportQuestion + " (" + ForgeChatText.reportOptional + ")", text: $note, axis: .vertical)
                .lineLimit(3...6).padding(12).foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 0.5))
                .onChange(of: note) { _, v in if v.count > 500 { note = String(v.prefix(500)) } }
                .accessibilityIdentifier("chat-report-note")
            Text(ForgeChatText.reportHint).font(.caption).foregroundStyle(.white.opacity(0.6))
            HStack {
                Text("\(note.count)/500").font(.caption2).foregroundStyle(.white.opacity(0.5))
                Spacer()
                if let error { Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.trailing) }
            }
            Button {
                Task {
                    sending = true; error = nil
                    let r = await send(note)
                    sending = false
                    switch r {
                    case .ok: dismiss(); onSent()
                    case .gone: error = ForgeChatText.reportGone
                    case .invalid: error = ForgeChatText.reportInvalid
                    case .unavailable: error = ForgeChatText.reportFailed
                    }
                }
            } label: {
                HStack { Spacer(); if sending { ProgressView().tint(.white) } else { Text(ForgeChatText.reportSend).font(.body.weight(.semibold)) }; Spacer() }
                    .padding(.vertical, 12).foregroundStyle(.white).background(MirsaPalette.accentGradient).clipShape(Capsule())
            }.buttonStyle(.plain).disabled(sending).accessibilityIdentifier("chat-report-send")
        }
        .padding(20)
        .presentationDetents([.height(350)])
        .presentationBackground { AuroraBackground() }
        .preferredColorScheme(.dark)
    }
}

/// The slice of the full-screen Aurora that sits under this view, so a bar over the chat
/// shows exactly the colours of the background around it (both instances follow the same clock).
struct MirsaAuroraSlice: View {
    var body: some View {
        GeometryReader { g in
            let f = g.frame(in: .global)
            let screen = UIScreen.main.bounds.size
            AuroraBackground()
                .frame(width: screen.width, height: screen.height)
                .offset(x: -f.minX, y: -f.minY)
                .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        }
        .clipped()
        .allowsHitTesting(false)
    }
}


/// Mirsa 2.3: one-time reactions tip above the Mirsa AI composer, same text as before in all four languages.
struct ForgeChatReactionsTip: View {
    let onDismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hand.tap").foregroundStyle(MirsaPalette.accentGradient)
            Text(ForgeChatExtrasText.reactionsHint).font(.footnote).foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(MirsaChatTheme.muted)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ForgeChatText.close)
            .accessibilityIdentifier("chat-reactions-tip-close")
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MirsaPalette.cardRaised))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MirsaPalette.accent.opacity(0.4), lineWidth: 0.8))
        .padding(.horizontal, 14).padding(.top, 8)
        .accessibilityIdentifier("chat-reactions-tip")
    }
}


/// Per-device choice for the Mirsa AI chat background. Default is the original gradient.
enum MirsaChatBackground {
    static let key = "mirsa.chat.blackBackground.v1"
    static func label(black: Bool) -> String {
        let on = black
        switch L.lang {
        case .english: return on ? "Use gradient background" : "Use black background"
        case .german: return on ? "Farbverlauf-Hintergrund verwenden" : "Schwarzen Hintergrund verwenden"
        case .arabic: return on ? "استخدم الخلفية المتدرجة" : "استخدم الخلفية السوداء"
        case .kurmanji: return on ? "Paşxaneya gradient bikar bîne" : "Paşxaneya reş bikar bîne"
        case .sorani: return on ? "پاشبنەمای گرادیەنت بەکاربهێنە" : "پاشبنەمای ڕەش بەکاربهێنە"
        }
    }
}


// MARK: - A quiet, hand-drawn chat companion
// All motion stays in a reserved 52pt lane, never over a message, attachment or input.
// The parent observes touches simultaneously, leaving scroll/reply/tap gestures intact.
private enum MirsaCatText {
    static var settings: String { tr5("Chat settings", "إعدادات المحادثة", de: "Chat-Einstellungen", ckb: "ڕێکخستنەکانی گفتوگۆ", kmr: "Mîhengên sohbetê") }
    static var title: String { tr5("Little cat companion", "رفيقك القط الصغير", de: "Kleiner Katzenbegleiter", ckb: "پشیلە بچووکە هاوڕێکە", kmr: "Hevalê pisîkê biçûk") }
    static var explanation: String {
        tr5("A little cat follows your scrolling, watches while Mirsa thinks, celebrates replies and naps when you pause. It never covers your messages or buttons. Reduce Motion keeps it still.",
            "قط صغير بيلحق حركتك بالمحادثة، بينتظر معك لما مرسى يفكّر، بيفرح بالرد وبينام لما ترتاح. ما بيغطّي الرسائل أو الأزرار. مع تقليل الحركة بيضل ثابت.",
            de: "Eine kleine Katze folgt deinem Scrollen, wartet mit dir auf Mirsa, freut sich über Antworten und schläft bei Pausen. Nachrichten und Tasten bleiben frei. Bei reduzierter Bewegung bleibt sie still.",
            ckb: "پشیلەیەکی بچووک شوێن جووڵەی گفتوگۆکەت دەکەوێت، کاتێک میرسا بیر دەکاتەوە چاوەڕێ دەکات، بە وەڵام دڵخۆش دەبێت و لە پشوودا دەخەوێت. نامە و دوگمەکان داناپۆشێت. بە کەمکردنەوەی جووڵە جێگیر دەمێنێت.",
            kmr: "Pisîkeke biçûk li pey tevgera sohbetê diçe, dema Mirsa difikire li bendê dimîne, bi bersivan şa dibe û di bêdengiyê de radizê. Peyam û bişkokan nagire. Bi Kêmkirina Tevgerê re bêliv dimîne.")
    }
}

private struct MirsaChatCat: View {
    let thinking: Bool
    let touch: CGPoint
    let awake: Date
    let celebration: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.layoutDirection) private var direction
    @State private var position: CGFloat = 0.78

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduceMotion || scenePhase != .active)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let sleeping = !thinking && timeline.date.timeIntervalSince(awake) > 25
                let happyAge = timeline.date.timeIntervalSince(celebration)
                let happy = happyAge >= 0 && happyAge < 1.1
                let phase = reduceMotion ? 0 : now
                let bounce = !reduceMotion && happy ? -abs(sin(happyAge * .pi * 3)) * 9 : 0
                let breath = reduceMotion ? 0 : sin(phase * (sleeping ? 1.7 : 2.5)) * 0.7
                MirsaCatDrawing(phase: phase, sleeping: sleeping, thinking: thinking, happy: happy,
                                look: reduceMotion ? 0 : Double(touch.x - 0.5) * 2)
                    .frame(width: 66, height: 48)
                    .scaleEffect(x: 1, y: 1 + breath * 0.012, anchor: .bottom)
                    .offset(y: bounce - (reduceMotion ? 0 : touch.y * 3))
                    .position(x: 40 + max(0, geometry.size.width - 80) * (reduceMotion ? 0.78 : position), y: 28)
            }
            .onChange(of: touch) { _, next in
                withAnimation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.82)) {
                    position = direction == .rightToLeft ? 1 - next.x : next.x
                }
            }
        }
    }
}

/// Cream and apricot, tiny ink eyes and a curled tail. No assets or external runtime.
private struct MirsaCatDrawing: View {
    let phase: Double
    let sleeping: Bool
    let thinking: Bool
    let happy: Bool
    let look: Double
    private let fur = Color(red: 1, green: 0.85, blue: 0.64)
    private let ink = Color(red: 0.20, green: 0.16, blue: 0.17)

    var body: some View {
        Canvas { context, _ in
            func ellipse(_ rect: CGRect, _ color: Color) {
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
            func line(_ points: [CGPoint], _ color: Color, _ width: CGFloat = 1.4) {
                guard let first = points.first else { return }
                var path = Path(); path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            ellipse(CGRect(x: 9, y: 43, width: 48, height: 4), .black.opacity(0.16))
            var tail = Path()
            tail.move(to: CGPoint(x: 47, y: 37))
            tail.addCurve(to: CGPoint(x: 58, y: 22 + sin(phase * 2) * 2),
                          control1: CGPoint(x: 68, y: 40), control2: CGPoint(x: 60, y: 12))
            context.stroke(tail, with: .color(fur.opacity(0.9)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            ellipse(CGRect(x: 18, y: 23, width: 33, height: 22), fur)
            ellipse(CGRect(x: 26, y: 29, width: 18, height: 15), .white.opacity(0.35))
            var ears = Path()
            ears.move(to: CGPoint(x: 14, y: 19)); ears.addLine(to: CGPoint(x: 13, y: 3))
            ears.addQuadCurve(to: CGPoint(x: 28, y: 13), control: CGPoint(x: 18, y: 1)); ears.closeSubpath()
            ears.move(to: CGPoint(x: 35, y: 12)); ears.addLine(to: CGPoint(x: 49, y: 3))
            ears.addQuadCurve(to: CGPoint(x: 48, y: 23), control: CGPoint(x: 52, y: 4)); ears.closeSubpath()
            context.fill(ears, with: .color(fur))
            line([CGPoint(x: 17, y: 9), CGPoint(x: 18, y: 16), CGPoint(x: 23, y: 14)], .pink.opacity(0.5), 3)
            line([CGPoint(x: 41, y: 14), CGPoint(x: 47, y: 9), CGPoint(x: 46, y: 17)], .pink.opacity(0.5), 3)
            ellipse(CGRect(x: 12, y: 11, width: 39, height: 27), fur)
            ellipse(CGRect(x: 17, y: 27, width: 7, height: 3), .pink.opacity(0.32))
            ellipse(CGRect(x: 39, y: 27, width: 7, height: 3), .pink.opacity(0.32))
            let blink = phase > 0 && phase.truncatingRemainder(dividingBy: 5.3) < 0.15
            for x in [23.0, 39.0] {
                if sleeping || happy || blink {
                    line([CGPoint(x: x-3, y: 23), CGPoint(x: x, y: happy ? 21 : 25), CGPoint(x: x+3, y: 23)], ink)
                } else {
                    ellipse(CGRect(x: x-2 + look, y: thinking ? 20 : 21, width: 4, height: 6), ink)
                    ellipse(CGRect(x: x-0.7 + look, y: thinking ? 20.5 : 21.5, width: 1.2, height: 1.5), .white)
                }
            }
            ellipse(CGRect(x: 29.5, y: 26, width: 3.5, height: 2.5), Color(red: 0.77, green: 0.41, blue: 0.42))
            line([CGPoint(x: 31, y: 29), CGPoint(x: 28, y: 31), CGPoint(x: 26, y: 30)], ink, 1)
            line([CGPoint(x: 31, y: 29), CGPoint(x: 34, y: 31), CGPoint(x: 36, y: 30)], ink, 1)
            let paw = thinking ? sin(phase * 7) * 1.5 : 0
            ellipse(CGRect(x: 20, y: 39 + paw, width: 10, height: 6), fur)
            ellipse(CGRect(x: 37, y: 39 - paw, width: 10, height: 6), fur)
            // A sleepy curl or three tiny thinking motes, never status text.
            if sleeping {
                var curl = Path()
                curl.move(to: CGPoint(x: 53, y: 12)); curl.addLine(to: CGPoint(x: 59, y: 12))
                curl.addLine(to: CGPoint(x: 53, y: 17)); curl.addLine(to: CGPoint(x: 59, y: 17))
                context.stroke(curl, with: .color(fur.opacity(0.6)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            } else if thinking {
                for i in 0..<3 {
                    let alpha = 0.35 + (sin(phase * 4 - Double(i)) + 1) * 0.3
                    ellipse(CGRect(x: 54 + Double(i) * 4, y: 9 - Double(i) * 3, width: 2.5, height: 2.5), fur.opacity(alpha))
                }
            }
        }
    }
}

/// Window-scene traits retain the iPhone's appearance even when an ancestor
/// applies a SwiftUI color-scheme override. The callback is deferred out of layout.
private struct ForgeChatSystemAppearanceReader: UIViewRepresentable {
    let changed: (Bool) -> Void
    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.changed = changed
        return view
    }
    func updateUIView(_ view: ReaderView, context: Context) {
        view.changed = changed
        view.reportAppearance()
    }
    final class ReaderView: UIView {
        var changed: ((Bool) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            reportAppearance()
        }
        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            reportAppearance()
        }
        func reportAppearance() {
            guard let scene = window?.windowScene else { return }
            let dark = scene.traitCollection.userInterfaceStyle == .dark
            DispatchQueue.main.async { [weak self] in self?.changed?(dark) }
        }
    }
}
