import SwiftUI
import UniformTypeIdentifiers

/// Sequential multi-app signing queue. Real progress from the signer, real per-item cancel.
@MainActor
final class SigningQueue: ObservableObject {
    static let shared = SigningQueue()
    enum State: Equatable { case waiting, signing, done, failed, cancelled }
    final class Item: ObservableObject, Identifiable, @unchecked Sendable {
        let id = UUID()
        let ipa: URL
        let title: String
        let options: PersonalProjectOptions
        let control = PersonalSigningControl()
        @Published var state: State = .waiting
        @Published var fraction: Double?
        @Published var output: URL?
        @Published var message: String?
        var cancelRequested = false
        init(ipa: URL, title: String, options: PersonalProjectOptions) { self.ipa = ipa; self.title = title; self.options = options }
    }
    @Published private(set) var items: [Item] = []
    @Published private(set) var running = false
    private var identity: PersonalIdentityVault.SavedIdentity?

    var activeCount: Int { items.filter { $0.state == .waiting || $0.state == .signing }.count }

    func enqueue(_ files: [URL], identity: PersonalIdentityVault.SavedIdentity, options: PersonalProjectOptions = .init(), cloneEach: Bool = false) throws {
        if let blocker = CertificateRevocationMonitor.shared.signingBlocker(identity) { throw SideloadError.message(blocker) }
        self.identity = identity
        for url in files {
            var o = options
            if cloneEach {
                let info = try? Self.appInfo(of: url)
                let original = info?.id ?? ""
                o = try AppClone.options(base: options, originalID: original, originalName: info?.name ?? url.deletingPathExtension().lastPathComponent,
                                         newID: AppClone.cloneID(from: original, index: 1 + items.count), newName: nil, identity: identity)
            }
            o.outputFilename = url.deletingPathExtension().lastPathComponent + "-signed"
            items.append(Item(ipa: url, title: url.deletingPathExtension().lastPathComponent, options: o))
        }
        startIfNeeded()
    }
    /// Reads bundle id and name from a copy of the IPA (read-only inspection in a temp folder).
    static func appInfo(of ipa: URL) throws -> (id: String, name: String) {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("queue-info-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let root = tmp.appendingPathComponent("x", isDirectory: true)
        try IPAEditorService.run("extract", input: ipa, output: root)
        let info = try IPAEditorService.info(in: try IPAEditorService.app(in: root))
        return (info["CFBundleIdentifier"] as? String ?? "", (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? "")
    }

    func cancel(_ item: Item) {
        item.cancelRequested = true
        item.control.cancel()
        if item.state == .waiting { item.state = .cancelled }
    }
    func cancelAll() { items.forEach { if $0.state == .waiting || $0.state == .signing { cancel($0) } } }
    func clearFinished() { items.removeAll { $0.state == .done || $0.state == .failed || $0.state == .cancelled } }

    private func startIfNeeded() {
        guard !running else { return }
        running = true
        Task { await drain() }
    }
    private func drain() async {
        while let item = items.first(where: { $0.state == .waiting }), let identity {
            item.state = .signing; item.fraction = nil
            let device = (try? OwnCertificateDevice.require()) ?? ""
            let material = identity.material
            let options = item.options, input = item.ipa, control = item.control
            do {
                let result = try await PersonalEncryptionWarning.signWithConsent { consent in
                    try PersonalCertificateSigner.sign(ipa: input, material: material, pairingPath: "", options: options,
                                                       cachedUDID: device, control: control, allowEncryptedSigning: consent) { event in
                        guard event.stage == .signing, let f = event.fraction else { return }
                        Task { @MainActor in item.fraction = max(item.fraction ?? 0, f) }
                    }
                }
                if item.cancelRequested { try? FileManager.default.removeItem(at: result.url.deletingLastPathComponent()); item.state = .cancelled }
                else {
                    item.output = try CertificateInstall.retain(result.url)
                    item.fraction = 1; item.state = .done
                    if !result.verification.isVerified { item.message = result.verification.warningText }
                }
            } catch {
                if item.cancelRequested { item.state = .cancelled }
                else { item.state = .failed; item.message = error.localizedDescription }
            }
        }
        running = false
    }
}

private struct MultiIPAPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: [UTType(filenameExtension: "ipa") ?? .data], asCopy: true)
        p.allowsMultipleSelection = true; p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ c: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(_ f: @escaping ([URL]) -> Void) { onPick = f }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls) }
    }
}

struct SigningQueueView: View {
    @ObservedObject private var queue = SigningQueue.shared
    @State private var identities: [PersonalIdentityVault.SavedIdentity] = []
    @State private var picking = false
    @State private var clone = false
    @State private var stripRestrictions = false
    @State private var message: String?
    @State private var pending: [PendingClone] = []
    @State private var sharing: SharedFile?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(sgText("Signing queue", "طابور التوقيع", "ڕیزی واژووکردن", "Rêzika îmzekirinê")).font(MirsaFont.sheetTitle)
                Toggle(sgText("Clone with a new bundle ID", "نسخة بمعرّف جديد", "کلۆن بە ناسنامەی نوێ", "Klon bi nasnameya nû"), isOn: $clone)
                Toggle(sgText("Remove device restrictions (copy only)", "إزالة قيود الجهاز (على النسخة فقط)", "لابردنی سنووردارییەکانی ئامێر (تەنها کۆپی)", "Sînorên cîhazê rake (tenê kopî)"), isOn: $stripRestrictions)
                Button(sgText("Add IPAs", "إضافة IPA", "زیادکردنی IPA", "IPA lê zêde bike")) { picking = true }
                    .buttonStyle(.mirsaPrimary).disabled(identities.isEmpty)
                if identities.isEmpty {
                    Text(sgText("Import a certificate first.", "استورد شهادة بالأول.", "سەرەتا شەهادەیەک هاوردە بکە.", "Pêşî sertîfîkayekê têxe.")).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach($pending) { $p in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(p.file.lastPathComponent).font(.caption.bold()).lineLimit(1)
                        TextField(sgText("New bundle ID", "المعرّف الجديد", "ناسنامەی نوێ", "Nasnameya nû"), text: $p.bundleID)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                        TextField(sgText("New app name", "الاسم الجديد", "ناوی نوێ", "Navê nû"), text: $p.name).textFieldStyle(.roundedBorder)
                        if !IPAEditorService.validBundleID(p.bundleID) || p.bundleID == p.originalID {
                            Text(sgText("Enter a valid bundle ID different from the original.", "اكتب معرّف صالح ومختلف عن الأصلي.", "ناسنامەیەکی دروست و جیاواز بنووسە.", "Nasnameyeke derbasdar û cuda binivîse.")).font(.caption2).foregroundStyle(.orange)
                        }
                    }.padding(MirsaSpacing.s).appsGlass(cornerRadius: MirsaRadius.m)
                }
                if !pending.isEmpty {
                    Button(sgText("Start cloning", "ابدأ النسخ", "دەستپێکردنی کلۆن", "Klonê dest pê bike")) { startPending() }
                        .buttonStyle(.mirsaPrimary)
                        .disabled(pending.contains { !IPAEditorService.validBundleID($0.bundleID) || $0.bundleID == $0.originalID })
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.orange) }
                ForEach(queue.items) { row($0) }
                if queue.activeCount > 0 {
                    Button(sgText("Cancel all", "إلغاء الكل", "هەموو هەڵبوەشێنەوە", "Hemûyan betal bike"), role: .destructive) { queue.cancelAll() }
                } else if !queue.items.isEmpty {
                    Button(sgText("Clear", "مسح", "پاککردنەوە", "Paqij bike")) { queue.clearFinished() }
                }
            }.padding(MirsaSpacing.page)
        }
        .mirsaScreen()
        .environment(\.layoutDirection, .leftToRight)
        .task { identities = (try? PersonalIdentityVault.savedIdentities()) ?? []; await CertificateRevocationMonitor.shared.checkAll() }
        .sheet(isPresented: $picking) { MultiIPAPicker { urls in picking = false; add(urls) } }
        .sheet(item: $sharing) { PersonalSignedShare(url: $0.url) }
    }
    private var chosenIdentity: PersonalIdentityVault.SavedIdentity? {
        (try? PersonalIdentityVault.selectedID()).flatMap({ id in identities.first { $0.id == id } }) ?? identities.first
    }
    private func startPending() {
        guard let identity = chosenIdentity else { return }
        var o = PersonalProjectOptions(); o.removeDeviceRestrictions = stripRestrictions
        do {
            for p in pending {
                let opts = try AppClone.options(base: o, originalID: p.originalID, originalName: p.originalName,
                                                newID: p.bundleID, newName: p.name, identity: identity)
                try queue.enqueue([p.file], identity: identity, options: opts, cloneEach: false)
            }
            pending = []; message = nil
        } catch { message = error.localizedDescription }
    }
    private func add(_ urls: [URL]) {
        guard let identity = chosenIdentity else { return }
        if clone {
            pending = urls.map { u in
                let info = try? SigningQueue.appInfo(of: u)
                let id = info?.id ?? ""
                return PendingClone(file: u, originalID: id, originalName: info?.name ?? u.deletingPathExtension().lastPathComponent,
                                    bundleID: AppClone.cloneID(from: id), name: (info?.name ?? "") + " 2")
            }
            return
        }
        var o = PersonalProjectOptions(); o.removeDeviceRestrictions = stripRestrictions
        do { try queue.enqueue(urls, identity: identity, options: o, cloneEach: clone); message = nil }
        catch { message = error.localizedDescription }
    }
    private func row(_ item: SigningQueue.Item) -> some View { SigningQueueRow(item: item, queue: queue, share: { sharing = SharedFile(url: $0) }) }
}
private struct SharedFile: Identifiable { let url: URL; var id: String { url.absoluteString } }

private struct SigningQueueRow: View {
    @ObservedObject var item: SigningQueue.Item
    let queue: SigningQueue
    let share: (URL) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.title).font(.headline).lineLimit(1)
                Spacer()
                switch item.state {
                case .waiting: Text(sgText("Waiting", "بالانتظار", "چاوەڕوان", "Li bendê"))
                case .signing: if let f = item.fraction { Text("\(Int(f * 100))%").monospacedDigit() } else { ProgressView() }
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                case .cancelled: Text(sgText("Cancelled", "ملغى", "هەڵوەشێنرایەوە", "Hate betalkirin"))
                }
            }.font(.caption)
            if item.state == .signing, let f = item.fraction { ProgressView(value: f).tint(.green) }
            if let m = item.message { Text(m).font(.caption2).foregroundStyle(.orange) }
            HStack {
                if item.state == .waiting || item.state == .signing {
                    Button(sgText("Cancel", "إلغاء", "هەڵوەشاندنەوە", "Betal bike"), role: .destructive) { queue.cancel(item) }
                }
                if let out = item.output { Button(sgText("Share", "مشاركة", "هاوبەشکردن", "Parve bike")) { share(out) } }
            }.font(.caption.weight(.semibold))
        }.padding(14).appsGlass(cornerRadius: 18)
    }
}

struct PendingClone: Identifiable {
    let id = UUID()
    let file: URL
    let originalID: String
    let originalName: String
    var bundleID: String
    var name: String
}
