import SwiftUI
import CryptoKit

struct ForgeChatShare: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}

extension ForgeChatText {
    static var install: String { tr("Install", "ثبّت", ckb: "دایبمەزرێنە", kmr: "Saz bike") }
    static var download: String { tr("Download", "حمّل", ckb: "دابەزاندن", kmr: "Daxe") }
    static var addWallpaper: String { tr5("Add to wallpapers", "أضف للخلفيات", de: "Zu Hintergründen hinzufügen", ckb: "زیادکردن بۆ وەڵپەیپەرەکان", kmr: "Li wallpaperan zêde bike") }
    static var share: String { tr("Share", "شارك", ckb: "هاوبەشکردن", kmr: "Parve bike") }
    static var cancel: String { tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal bike") }
    static var expired: String { tr("This file expired. Ask Mirsa again.", "انتهت صلاحية الملف. اطلب من مرسى مرة تانية.", ckb: "فایلەکە بەسەرچووە. دووبارە لە مرسا بپرسە.", kmr: "Dema pelê qediya. Dîsa ji Mirsayê bipirse.") }
    static var dlFailed: String { tr("Download failed or the file did not match. Try again.", "فشل التحميل أو الملف مو مطابق. جرّب مرة تانية.", ckb: "داگرتن شکستی هێنا یان فایلەکە نەگونجا. دووبارە هەوڵ بدە.", kmr: "Daxistin têk çû an pel li hev nehat. Dîsa biceribîne.") }
    static var ipaNote: String { tr("Goes through the normal import, sign and install steps.", "بيمشي بخطوات الاستيراد والتوقيع والتثبيت العادية.", ckb: "بە هەنگاوە ئاساییەکانی هێنان و واژۆ و دامەزراندن دەڕوات.", kmr: "Bi gavên asayî yên import, îmze û sazkirinê diçe.") }
}

extension ForgeChatStore {
    struct Issued: Decodable { let url: URL }
    /// Keep the delivered wallpaper name (import uses lastPathComponent); strip path bits, force .tendies.
    static func safeTendiesName(_ a: ForgeChatArtifact) -> String {
        let raw = (a.name ?? "").replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
        var base = (raw as NSString).deletingPathExtension.filter { $0 != ":" }.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty || base.hasPrefix(".") { base = "Wallpaper-" + String(a.id.uuidString.prefix(8)) }
        return String(base.prefix(80)) + ".tendies"
    }
    /// Signed Oracle URL only; no Forge headers are sent to it. Streams to disk, verifies size and sha256.
    func downloadArtifact(threadID: UUID, artifact a: ForgeChatArtifact, progress: @escaping (Double) -> Void, configuration: URLSessionConfiguration = .ephemeral) async throws -> URL {
        if a.kind == "tendies" {
            guard let size = a.size, size > 0, let hash = a.sha256, hash.count == 64,
                  hash.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw ForgeClient.Failure.message(ForgeChatText.dlFailed) }
        }
        let d = try await callPublic(["action": "chat-artifact-download", "threadID": threadID.uuidString.lowercased(), "id": a.id.uuidString.lowercased()])
        guard let issued = try? JSONDecoder().decode(Issued.self, from: d), issued.url.scheme == "https" else { throw ForgeClient.Failure.message(ForgeChatText.dlFailed) }
        let ext = ["ipa": "ipa", "apk": "apk", "zip": "zip"][a.kind] ?? (a.kind == "tendies" ? "tendies" : nil) ?? ForgeChatTweakArtifact.fileExtension(a) ?? "bin"
        let dir = try MirsaManagedTmp.begin("chat-artifact")
        var handedOff = false
        defer { if !handedOff { MirsaManagedTmp.end(dir) } }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(ext == "tendies" ? Self.safeTendiesName(a) : (["dylib", "deb", "zip", "framework"].contains(ext) ? (IPATweakIdentity.cleanName(a.name) ?? a.id.uuidString) : a.id.uuidString) + "." + ext)
        try? FileManager.default.removeItem(at: dest)
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let out = try FileHandle(forWritingTo: dest)
        defer { try? out.close() }
        var req = URLRequest(url: issued.url); req.timeoutInterval = 60
        let (bytes, resp) = try await URLSession(configuration: configuration).bytes(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ForgeClient.Failure.message(code == 404 || code == 410 || code == 403 ? ForgeChatText.expired : ForgeChatText.dlFailed) }
        var hasher = SHA256(); var buf = Data(); var total: Int64 = 0
        let expected = a.size ?? resp.expectedContentLength
        for try await b in bytes {
            buf.append(b)
            if buf.count >= 1 << 18 {
                hasher.update(data: buf); try out.write(contentsOf: buf); total += Int64(buf.count); buf.removeAll(keepingCapacity: true)
                if expected > 0 { progress(Double(total) / Double(expected)) }
            }
        }
        if !buf.isEmpty { hasher.update(data: buf); try out.write(contentsOf: buf); total += Int64(buf.count) }
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        if let sz = a.size, sz != total { try? FileManager.default.removeItem(at: dest); throw ForgeClient.Failure.message(ForgeChatText.dlFailed) }
        if let h = a.sha256, h.lowercased() != hex { try? FileManager.default.removeItem(at: dest); throw ForgeClient.Failure.message(ForgeChatText.dlFailed) }
        try Task.checkCancellation()
        handedOff = true
        return dest
    }
    /// The same library import used by Files. Does not install or touch PosterBoard.
    static func importDownloadedTendies(_ file: URL, model: AppViewModel?) async throws {
        defer { MirsaManagedTmp.end(file.deletingLastPathComponent()) }
        guard let model else { throw ForgeClient.Failure.message(ForgeChatText.dlFailed) }
        let ids = await model.importTendieFiles(urls: [file])
        guard !ids.isEmpty else { throw ForgeClient.Failure.message(ForgeChatText.dlFailed) }
    }
}

struct ForgeChatArtifactCard: View {
    let threadID: UUID
    let artifact: ForgeChatArtifact
    @State private var task: Task<Void, Never>?
    @State private var progress: Double?
    @State private var error: String?
    @State private var shareURL: URL?
    @State private var injectURL: URL?
    private var isIPA: Bool { artifact.kind == "ipa" }
    private var isTendies: Bool { artifact.kind == "tendies" }
    private var isTweak: Bool { !isIPA && !isTendies && artifact.kind != "apk" && ForgeChatTweakArtifact.fileExtension(artifact) != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(artifact.name ?? artifact.kind.uppercased(), systemImage: isIPA ? "app.badge" : "doc.zipper").font(.caption.bold())
            if let s = artifact.size { Text(ByteCountFormatter.string(fromByteCount: s, countStyle: .file) + " · " + artifact.kind.uppercased()).font(.caption2).foregroundStyle(.secondary) }
            if isIPA { Text(ForgeChatText.ipaNote).font(.caption2).foregroundStyle(.secondary) }
            if let p = progress {
                MirsaLiquidProgress(value: p)
                Button(ForgeChatText.cancel) { task?.cancel(); progress = nil }.font(.caption)
            } else {
                HStack(spacing: 8) {
                    Button(isIPA ? ForgeChatText.install : isTendies ? ForgeChatText.addWallpaper : (artifact.kind == "apk" ? ForgeChatText.download : ForgeChatText.share)) { start() }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(isTendies ? "mirsa.chat.artifact.add-wallpaper" : "mirsa.chat.artifact.download")
                    if isTweak {
                        Button { start(inject: true) } label: { Label(ForgeChatInjectText.inject, systemImage: "syringe.fill") }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("mirsa.chat.artifact.inject")
                    }
                }
            }
            if let error { Text(error).font(.caption2).foregroundStyle(.red) }
        }
        .sheet(item: Binding(get: { shareURL.map { ForgeShareItem(url: $0) } }, set: { value in
            if value == nil { if let shareURL { MirsaManagedTmp.end(shareURL.deletingLastPathComponent()) }; shareURL = nil }
        })) { ForgeChatShare(url: $0.url) }
        .sheet(item: Binding(get: { injectURL.map { ForgeShareItem(url: $0) } }, set: { if $0 == nil { injectURL = nil } })) { item in
            ForgeChatInjectSheet(file: item.url) { keep in
                // The certificate path hands the file to the attach sheet, which snapshots it;
                // a leftover is removed by the managed-tmp sweep.
                if !keep { MirsaManagedTmp.end(item.url.deletingLastPathComponent()) }
            }
        }
    }
    private func start(inject: Bool = false) {
        error = nil; progress = 0
        task = Task {
            do {
                let f = try await ForgeChatStore.shared.downloadArtifact(threadID: threadID, artifact: artifact) { p in Task { @MainActor in progress = p } }
                progress = nil
                if Task.isCancelled { MirsaManagedTmp.end(f.deletingLastPathComponent()); return }
                if isTendies {
                    try await ForgeChatStore.importDownloadedTendies(f, model: AppViewModel.shared)
                } else if isIPA {
                    defer { MirsaManagedTmp.end(f.deletingLastPathComponent()) }
                    await AppsStore.shared.importIPA(from: f)
                } else if inject { injectURL = f } else { shareURL = f }
            } catch {
                progress = nil
                if Task.isCancelled || error is CancellationError { return }
                if let e = error as? ForgeClient.Failure, case .message(let m) = e { self.error = m } else { self.error = ForgeChatText.dlFailed }
            }
        }
    }
}
