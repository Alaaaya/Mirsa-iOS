import SwiftUI
import PhotosUI

/// Uses the existing manual-create contract, never a new wallpaper endpoint.
/// The draft and upload IDs stay alive in the parent while the sheet is closed.
@MainActor final class WallpaperRequestDraft: ObservableObject {
    @Published var text = ""
    @Published var photos: [Data] = []
    @Published var busy = false
    @Published var error: String?
    @Published var receipt: ForgeQueuedReceipt?
    let threadID = UUID()
    let requestID = UUID()
    private var uploaded: [Int: UUID] = [:]
    private var frozenBody: [String: Any]?

    var canEdit: Bool { frozenBody == nil && uploaded.isEmpty && !busy && receipt == nil }

    static func photo(_ data: Data) -> Data? {
        guard let normalized = ChatAttachmentImage.normalize(data),
              let image = UIImage(data: normalized) else { return nil }
        // Manual-create snapshots, including base64, share a 256 KiB budget.
        // Three <=40 KiB reference images leave room for verbatim text/metadata.
        for side in [800.0, 600.0, 400.0, 240.0] {
            let scale = min(1, side / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let preview = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                UIColor.white.setFill(); UIRectFill(CGRect(origin: .zero, size: size))
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            for quality in [0.8, 0.6, 0.4] {
                if let jpeg = preview.jpegData(compressionQuality: quality), jpeg.count <= 40 * 1024 { return jpeg }
            }
        }
        return nil
    }

    func submit() async {
        guard !busy, receipt == nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 16000, photos.count <= 3 else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            if frozenBody == nil {
                for (index, bytes) in photos.enumerated() where uploaded[index] == nil {
                    let meta = try await AttachmentUploader.shared.put(.image(jpeg: bytes, name: "reference-\(index + 1).jpg"), threadID: threadID)
                    uploaded[index] = meta.id
                }
                frozenBody = [
                    "action": "generate", "id": requestID.uuidString.lowercased(),
                    "threadID": threadID.uuidString.lowercased(), "newThread": true,
                    "name": "Custom Tendies wallpaper", "bundleID": "com.alaa.mirsa",
                    // Do not trim, translate, categorize or prepend to the owner's words.
                    "prompt": text, "language": AppLanguageStore.snapshot.rawValue,
                    "attachmentIDs": photos.indices.compactMap { uploaded[$0]?.uuidString.lowercased() }
                ]
            }
            guard let body = frozenBody else { return }
            let data: Data
            let status: Int
            if let transport = ForgeQueued.transport {
                (data, status) = try await transport(body, requestID.uuidString.lowercased())
            } else {
                (data, status) = try await ForgeClient.postStatus(body, allowAccepted: true, idempotencyKey: requestID.uuidString.lowercased())
            }
            let outcome = try ForgeQueued.decode(status: status, data: data, expectedThreadID: threadID.uuidString.lowercased())
            guard case .queued(let saved) = outcome else { throw ForgeClient.Failure.message(WallpaperRequestText.failed) }
            receipt = saved
            await ForgeChatStore.shared.refreshThreads()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? WallpaperRequestText.failed
        }
    }
}

enum WallpaperRequestText {
    static var title: String { storeText("Request a custom wallpaper", "طلب خلفية مخصصة", de: "Eigenes Hintergrundbild anfragen", ckb: "داوای پاشبنەمای تایبەت", kmr: "Daxwaza paşxaneyeke taybet") }
    static var help: String { storeText("Describe your .tendies wallpaper and add up to 3 reference photos. Your exact text goes to the build queue. Follow the reply in your request thread.", "اكتب كيف بدك خلفية .tendies وضيف لحد ٣ صور مرجعية. كلامك بينبعت متل ما كتبته لدور التنفيذ. تابع الرد بمحادثة طلبك.", de: "Beschreibe dein .tendies-Hintergrundbild und füge bis zu 3 Referenzfotos hinzu. Dein genauer Text geht in die Warteschlange. Die Antwort findest du im Anfrage-Chat.", ckb: "پاشبنەمای .tendies باس بکە و تا ٣ وێنە زیاد بکە. دەقەکەت وەک خۆی بۆ ڕیزی دروستکردن دەنێردرێت. وەڵام لە گفتوگۆی داواکەت ببینە.", kmr: "Paşxaneya .tendies şirove bike û heta 3 wêneyan zêde bike. Nivîsa te bê guhertin diçe rêza çêkirinê. Bersivê di axaftina daxwazê de bibîne.") }
    static var send: String { storeText("Send request", "ابعث الطلب", de: "Anfrage senden", ckb: "داواکاری بنێرە", kmr: "Daxwazê bişîne") }
    static var received: String { storeText("Your request arrived and is in the queue.", "طلبك وصل وبالدور.", de: "Deine Anfrage ist angekommen und in der Warteschlange.", ckb: "داواکارییەکەت گەیشت و لە ڕیزدایە.", kmr: "Daxwaza te gihîşt û di rêzê de ye.") }
    static var thread: String { storeText("Open request conversation", "افتح محادثة الطلب", de: "Anfrage-Chat öffnen", ckb: "گفتوگۆی داواکاری بکەرەوە", kmr: "Axaftina daxwazê veke") }
    static var failed: String { storeText("Could not confirm your request was saved. Your draft is kept here. Try again.", "ما تأكدنا إن طلبك انحفظ. مسودتك بعدها هون، جرّب مرة تانية.", de: "Das Speichern wurde nicht bestätigt. Dein Entwurf bleibt hier. Versuche es erneut.", ckb: "پاشەکەوتکردنی داواکە پشتڕاست نەکرایەوە. ڕەشنووسەکەت لێرە ماوەتەوە. دووبارە هەوڵ بدە.", kmr: "Tomarkirina daxwazê nehat piştrastkirin. Pêşnûmeya te li vir dimîne. Dîsa biceribîne.") }
    static var photos: String { storeText("Add reference photos", "ضيف صور مرجعية", de: "Referenzfotos hinzufügen", ckb: "وێنەی نموونە زیاد بکە", kmr: "Wêneyên mînak zêde bike") }
}

struct WallpaperRequestView: View {
    @ObservedObject var draft: WallpaperRequestDraft
    @State private var selection: [PhotosPickerItem] = []
    @State private var loadingPhotos = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(WallpaperRequestText.title, systemImage: "sparkles.rectangle.stack")
                        .font(.title3.bold())
                    Text(WallpaperRequestText.help).font(.callout).foregroundStyle(.secondary)
                    TextEditor(text: $draft.text).frame(minHeight: 150)
                        .accessibilityLabel(WallpaperRequestText.title)
                        .disabled(!draft.canEdit || loadingPhotos)
                    Text("\(draft.text.utf8.count) / 16000").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    PhotosPicker(selection: $selection, maxSelectionCount: 3, matching: .images) {
                        Label(WallpaperRequestText.photos, systemImage: "photo.on.rectangle.angled")
                    }.disabled(!draft.canEdit || loadingPhotos)
                    ForEach(Array(draft.photos.enumerated()), id: \.offset) { _, bytes in
                        if let image = UIImage(data: bytes) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160)
                        }
                    }
                }
                Section {
                    if draft.receipt != nil {
                        Label(WallpaperRequestText.received, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        NavigationLink(WallpaperRequestText.thread) {
                            ForgeChatThreadView(threadID: draft.threadID)
                        }
                    } else {
                        Button(WallpaperRequestText.send) { Task { await draft.submit() } }
                            .disabled(draft.busy || loadingPhotos || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.text.utf8.count > 16000)
                        if draft.busy || loadingPhotos { ProgressView() }
                    }
                    if let error = draft.error { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }.mirsaListBackground()
            .navigationTitle(WallpaperRequestText.title)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(draft.busy || loadingPhotos)
            .onChange(of: selection) { _, items in
                guard draft.canEdit else { return }
                loadingPhotos = true
                Task { @MainActor in
                    defer { loadingPhotos = false }
                    var images: [Data] = []
                    for item in items {
                        guard let data = try? await item.loadTransferable(type: Data.self),
                              let jpeg = WallpaperRequestDraft.photo(data) else {
                            draft.error = ChatAttachmentText.imageFailed
                            return
                        }
                        images.append(jpeg)
                    }
                    draft.photos = images
                }
            }
        }
    }
}
