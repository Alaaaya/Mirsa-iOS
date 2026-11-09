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
    static var share: String { tr("Share", "شارك", ckb: "هاوبەشکردن", kmr: "Parve bike") }
    static var cancel: String { tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal bike") }
    static var expired: String { tr("This file expired. Ask Mirsa again.", "انتهت صلاحية الملف. اطلب من مرسى مرة تانية.", ckb: "فایلەکە بەسەرچووە. دووبارە لە مرسا بپرسە.", kmr: "Dema pelê qediya. Dîsa ji Mirsayê bipirse.") }
    static var dlFailed: String { tr("Download failed or the file did not match. Try again.", "فشل التحميل أو الملف مو مطابق. جرّب مرة تانية.", ckb: "داگرتن شکستی هێنا یان فایلەکە نەگونجا. دووبارە هەوڵ بدە.", kmr: "Daxistin têk çû an pel li hev nehat. Dîsa biceribîne.") }
    static var ipaNote: String { tr("Goes through the normal import, sign and install steps.", "بيمشي بخطوات الاستيراد والتوقيع والتثبيت العادية.", ckb: "بە هەنگاوە ئاساییەکانی هێنان و واژۆ و دامەزراندن دەڕوات.", kmr: "Bi gavên asayî yên import, îmze û sazkirinê diçe.") }
}

extension ForgeChatStore {
    struct Issued: Decodable { let url: URL }
    /// Signed Oracle URL only; no Forge headers are sent to it. Streams to disk, verifies size and sha256.
    func downloadArtifact(threadID: UUID, artifact a: ForgeChatArtifact, progress: @escaping (Double) -> Void) async throws -> URL {
        let d = try await callPublic(["action": "chat-artifact-download", "threadID": threadID.uuidString.lowercased(), "id": a.id.uuidString.lowercased()])
        guard let issued = try? JSONDecoder().decode(Issued.self, from: d), issued.url.scheme == "https" else { throw ForgeClient.Failure.message(ForgeChatText.dlFailed) }
        let ext = ["ipa": "ipa", "apk": "apk", "zip": "zip"][a.kind] ?? "bin"
        let dir = try MirsaManagedTmp.begin("chat-artifact")
        var handedOff = false
        defer { if !handedOff { MirsaManagedTmp.end(dir) } }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(a.id.uuidString + "." + ext)
        try? FileManager.default.removeItem(at: dest)
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let out = try FileHandle(forWritingTo: dest)
        defer { try? out.close() }
        var req = URLRequest(url: issued.url); req.timeoutInterval = 60
        let (bytes, resp) = try await URLSession(configuration: .ephemeral).bytes(for: req)
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
}

struct ForgeChatArtifactCard: View {
    let threadID: UUID
    let artifact: ForgeChatArtifact
    @State private var task: Task<Void, Never>?
    @State private var progress: Double?
    @State private var error: String?
    @State private var shareURL: URL?
    private var isIPA: Bool { artifact.kind == "ipa" }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(artifact.name ?? artifact.kind.uppercased(), systemImage: isIPA ? "app.badge" : "doc.zipper").font(.caption.bold())
            if let s = artifact.size { Text(ByteCountFormatter.string(fromByteCount: s, countStyle: .file) + " · " + artifact.kind.uppercased()).font(.caption2).foregroundStyle(.secondary) }
            if isIPA { Text(ForgeChatText.ipaNote).font(.caption2).foregroundStyle(.secondary) }
            if let p = progress {
                ProgressView(value: min(max(p, 0), 1))
                Button(ForgeChatText.cancel) { task?.cancel(); progress = nil }.font(.caption)
            } else {
                Button(isIPA ? ForgeChatText.install : (artifact.kind == "apk" ? ForgeChatText.download : ForgeChatText.share)) { start() }.buttonStyle(.borderedProminent)
            }
            if let error { Text(error).font(.caption2).foregroundStyle(.red) }
        }
        .sheet(item: Binding(get: { shareURL.map { ForgeShareItem(url: $0) } }, set: { value in
            if value == nil { if let shareURL { MirsaManagedTmp.end(shareURL.deletingLastPathComponent()) }; shareURL = nil }
        })) { ForgeChatShare(url: $0.url) }
    }
    private func start() {
        error = nil; progress = 0
        task = Task {
            do {
                let f = try await ForgeChatStore.shared.downloadArtifact(threadID: threadID, artifact: artifact) { p in Task { @MainActor in progress = p } }
                progress = nil
                if Task.isCancelled { MirsaManagedTmp.end(f.deletingLastPathComponent()); return }
                if isIPA {
                    defer { MirsaManagedTmp.end(f.deletingLastPathComponent()) }
                    await AppsStore.shared.importIPA(from: f)
                } else { shareURL = f }
            } catch {
                progress = nil
                if Task.isCancelled || error is CancellationError { return }
                if let e = error as? ForgeClient.Failure, case .message(let m) = e { self.error = m } else { self.error = ForgeChatText.dlFailed }
            }
        }
    }
}
