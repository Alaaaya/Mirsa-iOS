import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Mirsa 2.1 attachment chips. Only used when ChatAttachmentConfig.uiEnabled (feature flag ON) or for
/// messages whose server row carries message.attachments.

/// A composer chip: uploading / ready / failed / unavailable (410) with Upload again, always removable.
struct ChatDraftAttachmentChip: View {
    let item: ChatDraftAttachment
    let onRemove: () -> Void
    let onUploadAgain: () -> Void

    private var icon: String {
        switch item.payload { case .image: return "photo"; case .text: return "doc.text"; case .binary: return "doc.zipper"; case .link: return "link" }
    }
    private var sizeText: String? {
        guard case .binary = item.payload, let n = item.payload.byteCount else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
    private var problem: String? {
        switch item.state { case .failed(let m), .unavailable(let m): return m; default: return nil }
    }

    var body: some View {
        HStack(spacing: 6) {
            if case .image(let jpeg, _) = item.payload, let img = UIImage(data: jpeg) {
                Image(uiImage: img).resizable().scaledToFill().frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            }
            Text(item.payload.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle).frame(maxWidth: 140, alignment: .leading)
            if let sizeText { Text(sizeText).font(.system(size: 11)).foregroundStyle(MirsaChatTheme.muted).lineLimit(1) }
            switch item.state {
            case .uploading: ProgressView().controlSize(.mini).tint(.white)
            case .ready: Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.green)
            case .failed, .unavailable:
                Button(action: onUploadAgain) { Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold)) }
                    .buttonStyle(.plain).accessibilityLabel(ChatAttachmentText.uploadAgain).accessibilityIdentifier("chat-attachment-reupload")
            }
            Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.75)) }
                .buttonStyle(.plain).accessibilityLabel(ChatAttachmentText.removeAttachment).accessibilityIdentifier("chat-attachment-remove")
        }
        .foregroundStyle(problem == nil ? Color.white : Color.white.opacity(0.6))
        .padding(.horizontal, 10).frame(height: 32)
        .background(Capsule().fill(.white.opacity(problem == nil ? 0.10 : 0.05)))
        .overlay(Capsule().stroke(problem == nil ? Color.white.opacity(0.12) : Color.orange.opacity(0.6), lineWidth: 0.6))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-attachment-chip")
    }
}

/// Attachments of a sent or received message (public metadata only).
struct ChatAttachmentStrip: View {
    let metas: [ChatAttachmentMeta]
    let threadID: UUID
    var alignment: HorizontalAlignment = .trailing
    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            ForEach(metas) { m in ChatAttachmentMetaChip(meta: m, threadID: threadID) }
        }
    }
}

struct ChatAttachmentMetaChip: View {
    let meta: ChatAttachmentMeta
    let threadID: UUID
    @State private var image: UIImage?
    @State private var text: String?
    @State private var showText = false
    @State private var shareURL: URL?
    @State private var downloading = false
    @State private var downloadProblem: String?
    private var isBinary: Bool { AttachmentUploader.isBinaryMime(meta.mime) }

    private var unavailable: Bool { meta.isExpired() }
    private var sizeText: String? { meta.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } }

    var body: some View {
        Group {
            if meta.kind == "image", !unavailable, let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 220, maxHeight: 200).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                chip
            }
        }
        .task(id: meta.id) { await loadImage() }
        .sheet(item: Binding(get: { shareURL.map(ChatShareFile.init) }, set: { if $0 == nil { shareURL = nil } })) { f in
            ChatActivityView(items: [f.url]).ignoresSafeArea()
        }
        .sheet(isPresented: $showText) {
            NavigationStack {
                ScrollView { Text(text ?? "").font(.system(.footnote, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                    .background(MirsaChatTheme.bg.ignoresSafeArea())
                    .navigationTitle(meta.name ?? "").navigationBarTitleDisplayMode(.inline)
            }
            .preferredColorScheme(.dark)
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    private var chip: some View {
        HStack(spacing: 8) {
            Image(systemName: unavailable ? "clock.badge.xmark" : meta.kind == "link" ? "link" : meta.kind == "image" ? "photo" : isBinary ? "doc.zipper" : "doc.text")
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(meta.kind == "link" ? (meta.url.flatMap { URL(string: $0)?.host } ?? meta.name ?? "") : (meta.name ?? "")).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(unavailable ? ChatAttachmentText.unavailable : meta.kind == "link" ? ChatAttachmentText.contextOnly
                     : downloading ? ChatAttachmentText.downloading : (downloadProblem ?? sizeText ?? ""))
                    .font(.system(size: 11)).foregroundStyle(MirsaChatTheme.muted)
            }
        }
        .foregroundStyle(.white.opacity(unavailable ? 0.55 : 0.95))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture {
            guard meta.kind == "file", !unavailable else { return }
            if isBinary { if MirsaFeatures.binaryAttachmentsEnabled, !downloading { Task { await download() } } }
            else { Task { await loadText() } }
        }
        .contextMenu {
            if meta.kind == "link", let u = meta.url { Button { UIPasteboard.general.string = u } label: { Label(ChatAttachmentText.copyLink, systemImage: "doc.on.doc") } }
        }
        .accessibilityIdentifier("chat-message-attachment")
    }

    /// Never fetches a link. Images/files are read through chat-attachment-read only when the feature is on.
    private func loadImage() async {
        guard meta.kind == "image", !unavailable, image == nil else { return }
        guard AttachmentUploader.shared.isEnabled || ChatAttachmentConfig.fixtureUI else { return }
        if case .bytes(let d, _)? = try? await AttachmentUploader.shared.read(meta.id, threadID: threadID) { image = UIImage(data: d) }
    }
    /// .zip / .deb / .dylib: downloaded through chat-attachment-read into a private temp file and handed to the share sheet.
    /// Never opened, extracted or loaded here.
    private func download() async {
        guard AttachmentUploader.shared.isEnabled || ChatAttachmentConfig.fixtureUI else { return }
        downloading = true; downloadProblem = nil
        defer { downloading = false }
        let result: ChatAttachmentReadResult
        do { result = try await AttachmentUploader.shared.read(meta.id, threadID: threadID, expected: meta) }
        catch let e as ChatAttachmentError where e.code == "attachment_integrity" { downloadProblem = e.message; return }
        catch { downloadProblem = ChatAttachmentText.downloadFailed; return }
        guard case .bytes(let d, let mime) = result, AttachmentUploader.isBinaryMime(mime) else { downloadProblem = ChatAttachmentText.downloadFailed; return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mirsa-attachments/\(meta.id.uuidString)", isDirectory: true)
        let name = ChatAttachmentRules.safeName(meta.name ?? "attachment")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            try d.write(to: url, options: [.atomic, .completeFileProtection])
            shareURL = url
        } catch { downloadProblem = ChatAttachmentText.downloadFailed }
    }
    private func loadText() async {
        guard AttachmentUploader.shared.isEnabled || ChatAttachmentConfig.fixtureUI else { return }
        if case .bytes(let d, _)? = try? await AttachmentUploader.shared.read(meta.id, threadID: threadID) {
            text = String(data: d, encoding: .utf8); showText = text != nil
        }
    }
}

/// «من رابط»: https only, no IPA/APK/ZIP/DEB/executable/archive paths. Context only, never fetched or previewed.
struct ChatLinkAttachmentSheet: View {
    let onAdd: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var raw = ""
    @State private var problem: ChatAttachmentRules.LinkProblem?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("https://", text: $raw)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(12).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.08)))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("chat-link-field")
                    .onChange(of: raw) { _, _ in problem = nil }
                    .onSubmit(add)
                if let problem {
                    Label(ChatAttachmentText.link(problem), systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("chat-link-error")
                }
                Text(ChatAttachmentText.linkHelp).font(.footnote).foregroundStyle(MirsaChatTheme.muted).fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(18)
            .background(MirsaChatTheme.bg.ignoresSafeArea())
            .navigationTitle(ChatAttachmentText.linkTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(ForgeChatText.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(ChatAttachmentText.add, action: add).disabled(raw.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("chat-link-add") }
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.layoutDirection, .leftToRight)
        .presentationDetents([.medium])
    }

    private func add() {
        switch ChatAttachmentRules.validateLink(raw) {
        case .success(let url): onAdd(url); dismiss()
        case .failure(let p): problem = p
        }
    }
}

/// Photos / Files / From link presenters. Attached only while the feature is on, so with the flag OFF
/// the conversation's modifier chain is exactly the 2.0 one.
struct ChatAttachmentPickers: ViewModifier {
    let enabled: Bool
    let threadID: UUID
    @Binding var showPhotos: Bool
    @Binding var showFiles: Bool
    @Binding var showLink: Bool
    @Binding var attachPhoto: PhotosPickerItem?
    @Binding var note: String?

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content
                .photosPicker(isPresented: $showPhotos, selection: $attachPhoto, matching: .images)
                .fileImporter(isPresented: $showFiles, allowedContentTypes: Self.fileTypes, allowsMultipleSelection: false) { handleFile($0) }
                .sheet(isPresented: $showLink) {
                    ChatLinkAttachmentSheet { url in add(.link(url: url, name: ChatAttachmentRules.linkName(url))) }
                }
                .onChange(of: attachPhoto) { _, item in
                    guard let item else { return }
                    Task {
                        let raw = try? await item.loadTransferable(type: Data.self)
                        attachPhoto = nil
                        guard let raw, let jpeg = ChatAttachmentImage.normalize(raw) else { note = ChatAttachmentText.imageFailed; return }
                        add(.image(jpeg: jpeg, name: "photo.jpg"))
                    }
                }
        } else {
            content
        }
    }

    private func add(_ payload: ChatAttachmentPayload) {
        let drafts = ChatAttachmentDrafts.shared
        guard drafts.canAdd(threadID) else { return }
        note = nil
        drafts.add(payload, thread: threadID)
    }

    /// .txt / .json always; .zip / .deb / .dylib only with MirsaFeatures.binaryAttachmentsEnabled.
    /// No new exported UTIs: dynamic types by extension, and .data as a fallback when iOS knows none
    /// (the extension and size are still checked below, so .data does not mean any file).
    static var fileTypes: [UTType] {
        var types: [UTType] = [.plainText, .json]
        guard MirsaFeatures.binaryAttachmentsEnabled else { return types }
        types.append(.zip)
        let extra = ["deb", "dylib"].map { UTType(filenameExtension: $0) }
        types.append(contentsOf: extra.compactMap { $0 })
        if extra.contains(where: { $0 == nil }) { types.append(.data) }
        return types
    }

    /// Only .txt / .json, at most 256 KiB, strict UTF-8 without control bytes, JSON must parse.
    private func handleFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if MirsaFeatures.binaryAttachmentsEnabled, ChatAttachmentRules.binaryMime(forName: url.lastPathComponent) != nil {
            handleBinary(url); return
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= ChatAttachmentRules.textMaxBytes else { note = ChatAttachmentText.file(.size); return }
        guard let data = try? Data(contentsOf: url) else { note = ChatAttachmentText.file(.type); return }
        switch ChatAttachmentRules.validateTextFile(name: url.lastPathComponent, data: data) {
        case .success(let ok): add(.text(data: data, name: ok.name, mime: ok.mime))
        case .failure(let problem): note = ChatAttachmentText.file(problem)
        }
    }
}

extension ChatAttachmentPickers {
    /// Size is checked before reading; at most 5 MiB + 1 byte is ever read, then extension and container family.
    fileprivate func handleBinary(_ url: URL) {
        let name = url.lastPathComponent
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > ChatAttachmentRules.binaryMaxBytes {
            note = ChatAttachmentText.file(.binarySize); return
        }
        guard let h = try? FileHandle(forReadingFrom: url) else { note = ChatAttachmentText.file(.type); return }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: ChatAttachmentRules.binaryMaxBytes + 1) else { note = ChatAttachmentText.file(.type); return }
        switch ChatAttachmentRules.validateBinaryFile(name: name, data: data) {
        case .success(let ok): addBinary(.binary(data: data, name: ok.name, mime: ok.mime))
        case .failure(let p): note = ChatAttachmentText.file(p)
        }
    }

    fileprivate func addBinary(_ payload: ChatAttachmentPayload) {
        let drafts = ChatAttachmentDrafts.shared
        guard drafts.canAdd(threadID) else { return }
        note = nil
        drafts.add(payload, thread: threadID)
    }
}

struct ChatShareFile: Identifiable { let url: URL; var id: String { url.path } }

struct ChatActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#if DEBUG
/// DEBUG UI-test harness (-MirsaAttachmentRulesSelfTest): runs the attachment rules on device/simulator
/// so CI verifies URL validation and image normalisation. Mirrors tests/ChatAttachmentRulesTests.swift.
enum ChatAttachmentSelfTest {
    static func run() -> [String] {
        var failures: [String] = []
        func expect(_ ok: Bool, _ what: String) { if !ok { failures.append(what) } }
        func link(_ s: String) -> ChatAttachmentRules.LinkProblem? {
            if case .failure(let p) = ChatAttachmentRules.validateLink(s) { return p }; return nil
        }
        expect(link("https://example.com/docs/page") == nil, "valid https")
        expect(link("https://github.com/Alaaaya/Mirsa-iOS/issues/1?x=1#y") == nil, "valid with query")
        expect(link("http://example.com") == .notHTTPS, "http")
        expect(link("ftp://example.com/a") == .notHTTPS, "ftp")
        expect(link("https://example.com/app.ipa") == .blockedFile, "ipa")
        expect(link("https://example.com/App.IPA") == .blockedFile, "IPA upper")
        expect(link("https://example.com/app%2Eipa") == .blockedFile, "ipa percent")
        expect(link("https://example.com/app%252Eipa") == .blockedFile, "ipa double percent")
        expect(link("https://example.com/a.apk") == .blockedFile, "apk")
        expect(link("https://example.com/a.zip") == .blockedFile, "zip")
        expect(link("https://example.com/a.deb") == .blockedFile, "deb")
        expect(link("https://example.com/setup.exe") == .blockedFile, "exe")
        expect(link("https://example.com/x.tar.gz") == .blockedFile, "tar.gz")
        expect(link("https://example.com/app.ipa.") == .blockedFile, "trailing dot")
        expect(link("https://example.com/app.ipa;v=1") == .blockedFile, "path param")
        expect(link("https://user:pw@example.com/") == .credentials, "credentials")
        expect(link("https://127.0.0.1/") == .host, "ipv4")
        expect(link("https://[::1]/") == .host, "ipv6")
        expect(link("https://localhost/") == .host, "localhost")
        expect(link("https://printer.local/") == .host, "local")
        expect(link("https://intranet/") == .host, "single label")
        expect(link("https://example.com:8443/") == .port, "port")
        expect(link("https://example.com:443/ok") == nil, "port 443")
        expect(link("") == .empty, "empty")
        expect(link("https://example.com/" + String(repeating: "a", count: 2100)) == .tooLong, "too long")
        let t = ChatAttachmentRules.imageTargetSize(width: 4032, height: 3024)
        expect(t.width <= 1600 && t.height <= 1600 && t.width * t.height <= 2_560_000, "target size 12MP")
        let small = ChatAttachmentRules.imageTargetSize(width: 800, height: 600)
        expect(small.width == 800 && small.height == 600, "no upscale")
        let square = ChatAttachmentRules.imageTargetSize(width: 1600, height: 1600)
        expect(square.width * square.height <= 2_560_000, "square MP cap")
        // Real JPEG normalisation of a large noisy image.
        let size = CGSize(width: 3000, height: 2400)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            for i in 0..<300 {
                UIColor(hue: CGFloat(i % 100) / 100, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                ctx.fill(CGRect(x: (i * 37) % 3000, y: (i * 53) % 2400, width: 160, height: 120))
            }
        }
        if let png = img.pngData(), let out = ChatAttachmentImage.normalize(png), let back = UIImage(data: out) {
            let w = Int(back.size.width * back.scale), h = Int(back.size.height * back.scale)
            expect(out.count <= 1_048_576, "jpeg <= 1 MiB")
            expect(w <= 1600 && h <= 1600 && w * h <= 2_560_000, "jpeg dimensions")
            expect(out.starts(with: [0xFF, 0xD8]), "is jpeg")
        } else { failures.append("normalize failed") }
        let goodJSON = Data("{\"a\":1}".utf8)
        expect(ChatAttachmentRules.textFileProblem(name: "a.json", data: goodJSON) == nil, "json ok")
        expect(ChatAttachmentRules.textFileProblem(name: "notes.TXT", data: Data("hello\nworld\t!".utf8)) == nil, "txt ok")
        expect(ChatAttachmentRules.textFileProblem(name: "a.json", data: Data("{".utf8)) == .json, "bad json")
        expect(ChatAttachmentRules.textFileProblem(name: "a.md", data: Data("x".utf8)) == .type, "md type")
        expect(ChatAttachmentRules.textFileProblem(name: "a.txt", data: Data([0x41, 0x01])) == .control, "control")
        expect(ChatAttachmentRules.textFileProblem(name: "a.txt", data: Data([0xFF, 0xFE, 0x41])) == .utf8, "utf8")
        expect(ChatAttachmentRules.textFileProblem(name: "a.txt", data: Data(repeating: 0x41, count: 262_145)) == .size, "size")
        let ids = (0..<5).map { _ in UUID() }
        expect(ChatAttachmentRules.sendIDs(ids + ids).count == 3, "max 3 unique")
        // Binary files (flag-independent rules).
        let zip = Data([0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0])
        let deb = Data("!<arch>\ndebian-binary".utf8)
        let dylib = Data([0xCF, 0xFA, 0xED, 0xFE, 7, 0, 0, 1])
        expect(ChatAttachmentRules.binaryFileProblem(name: "a.zip", data: zip) == nil, "zip ok")
        expect(ChatAttachmentRules.binaryFileProblem(name: "a.DEB", data: deb) == nil, "deb ok")
        expect(ChatAttachmentRules.binaryFileProblem(name: "libx.dylib", data: dylib) == nil, "dylib ok")
        expect(ChatAttachmentRules.binaryFileProblem(name: "a.zip", data: deb) == .signature, "zip signature")
        expect(ChatAttachmentRules.binaryFileProblem(name: "a.dylib", data: zip) == .signature, "dylib signature")
        expect(ChatAttachmentRules.binaryFileProblem(name: "a.ipa", data: zip) == .type, "ipa type")
        expect(ChatAttachmentRules.binaryFileProblem(name: "a.zip", data: Data()) == .binarySize, "empty")
        var big = zip; big.append(Data(count: 5_242_880 - zip.count))
        expect(ChatAttachmentRules.binaryFileProblem(name: "a.zip", data: big) == nil, "5 MiB exact")
        big.append(0)
        expect(ChatAttachmentRules.binaryFileProblem(name: "a.zip", data: big) == .binarySize, "5 MiB + 1")
        expect(ChatAttachmentRules.binaryMime(forName: "x.deb") == "application/vnd.debian.binary-package", "deb mime")
        expect(ChatAttachmentRules.binaryMime(forName: "x.dylib") == "application/x-mach-binary", "dylib mime")
        expect(ChatAttachmentRules.binaryMime(forName: "x.zip") == "application/zip", "zip mime")
        expect(!MirsaFeatures.binaryAttachmentsEnabled, "binary flag off")
        return failures
    }
}

struct ChatAttachmentSelfTestBadge: View {
    @State private var result = "RUNNING"
    var body: some View {
        Text(result).font(.caption2).foregroundStyle(.white).padding(6).background(Color.black.opacity(0.6))
            .accessibilityIdentifier("attachment-rules-selftest")
            .onAppear { let f = ChatAttachmentSelfTest.run(); result = f.isEmpty ? "PASS" : "FAIL: " + f.joined(separator: ", ") }
    }
}
#endif
