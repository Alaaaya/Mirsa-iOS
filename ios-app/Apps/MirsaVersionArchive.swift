import SwiftUI

struct ForgeArchivedIPA: Codable, Identifiable, Equatable {
    var id = UUID()
    var bundleID: String
    var name: String
    var version: String
    var signed: Bool
    var date: Date
    var bytes: Int64
    var file: String { id.uuidString + ".ipa" }
}

/// Keeps older IPA versions per bundle ID so an app can be reinstalled or rolled back. Own folder, excluded from backup.
@MainActor final class MirsaVersionArchive: ObservableObject {
    static let shared = MirsaVersionArchive()
    static let limitKey = "mirsa.archive.keepPerApp"
    @Published private(set) var items: [ForgeArchivedIPA] = []
    let root: URL
    private var index: URL { root.appendingPathComponent("index.json") }

    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MirsaVersionArchive", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var u = root; var v = URLResourceValues(); v.isExcludedFromBackup = true; try? u.setResourceValues(v)
        if let d = try? Data(contentsOf: index), let list = try? JSONDecoder().decode([ForgeArchivedIPA].self, from: d) { items = list }
    }
    var keep: Int {
        get { let v = UserDefaults.standard.integer(forKey: Self.limitKey); return v == 0 ? 3 : min(max(v, 1), 20) }
        set { UserDefaults.standard.set(min(max(newValue, 1), 20), forKey: Self.limitKey); objectWillChange.send(); for b in Set(items.map(\.bundleID)) { prune(b) } }
    }
    func url(_ i: ForgeArchivedIPA) -> URL { root.appendingPathComponent(i.file) }
    func versions(of bundleID: String) -> [ForgeArchivedIPA] { items.filter { $0.bundleID == bundleID }.sorted { $0.date > $1.date } }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    func bytes(of bundleID: String) -> Int64 { versions(of: bundleID).reduce(0) { $0 + $1.bytes } }

    /// Copies the IPA; the same bundle ID, version, kind and size is not stored twice.
    func archive(_ ipa: URL, bundleID: String, name: String, version: String, signed: Bool) {
        let fm = FileManager.default
        guard let size = (try? ipa.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0 else { return }
        if items.contains(where: { $0.bundleID == bundleID && $0.version == version && $0.signed == signed && $0.bytes == Int64(size) }) { return }
        let item = ForgeArchivedIPA(bundleID: bundleID, name: name, version: version, signed: signed, date: Date(), bytes: Int64(size))
        do { try fm.copyItem(at: ipa, to: url(item)) } catch { return }
        items.insert(item, at: 0); save(); prune(bundleID)
    }
    func delete(_ i: ForgeArchivedIPA) { try? FileManager.default.removeItem(at: url(i)); items.removeAll { $0.id == i.id }; save() }
    func deleteOld(_ bundleID: String) { for i in versions(of: bundleID).dropFirst() { delete(i) } }
    private func prune(_ bundleID: String) { for i in versions(of: bundleID).dropFirst(keep) { delete(i) } }
    private func save() { try? JSONEncoder().encode(items).write(to: index, options: .atomic) }
}

/// Always left-to-right. Shown inside the project detail of one app.
struct MirsaVersionArchiveSection: View {
    let bundleID: String
    @ObservedObject private var archive = MirsaVersionArchive.shared
    @State private var confirmOld = false
    @State private var note: String?

    var body: some View {
        let list = archive.versions(of: bundleID)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("Saved versions", "النسخ المحفوظة", ckb: "وەشانە پاشەکەوتکراوەکان", kmr: "Guhertinên tomarkirî")).font(.headline)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: archive.bytes(of: bundleID), countStyle: .file)).font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Stepper(value: Binding(get: { archive.keep }, set: { archive.keep = $0 }), in: 1...20) {
                Text(tr("Keep", "احتفظ بـ", ckb: "هەڵبگرە", kmr: "Bihêle") + " \(archive.keep) " + tr("per app", "لكل تطبيق", ckb: "بۆ هەر ئەپێک", kmr: "ji bo her appê")).font(.subheadline)
            }
            if list.isEmpty {
                Text(tr("No saved versions yet. Each IPA you add or sign is kept here.", "ما في نسخ محفوظة لسا. كل IPA بتضيفه أو بتوقّعه بينحفظ هون.", ckb: "هێشتا وەشانی پاشەکەوتکراو نییە.", kmr: "Hê guhertinên tomarkirî tune ne.")).font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            ForEach(list) { i in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("v" + i.version + " · " + (i.signed ? tr("Signed", "موقّع", ckb: "واژۆکراو", kmr: "Îmzekirî") : tr("Original", "أصلي", ckb: "ڕەسەن", kmr: "Resen"))).font(.subheadline.bold())
                        Text(i.date.formatted(date: .abbreviated, time: .shortened) + " · " + ByteCountFormatter.string(fromByteCount: i.bytes, countStyle: .file)).font(.caption).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Button { reinstall(i) } label: { Image(systemName: "arrow.down.app").frame(width: 36, height: 36) }
                        .accessibilityLabel(tr("Reinstall", "أعد التثبيت", ckb: "دووبارە دایبمەزرێنە", kmr: "Ji nû ve saz bike"))
                    Button(role: .destructive) { archive.delete(i) } label: { Image(systemName: "trash").frame(width: 36, height: 36) }
                        .accessibilityLabel(tr("Delete", "احذف", ckb: "بیسڕەوە", kmr: "Jê bibe"))
                }.buttonStyle(.mirsaPress)
            }
            if list.count > 1 {
                Button(tr("Delete older versions", "احذف النسخ الأقدم", ckb: "وەشانە کۆنەکان بسڕەوە", kmr: "Guhertinên kevn jê bibe")) { confirmOld = true }.buttonStyle(.mirsaSecondary)
            }
            if let note { Text(note).font(.caption).foregroundStyle(.green) }
        }
        .padding(MirsaSpacing.card).frame(maxWidth: .infinity, alignment: .leading).appsGlass(cornerRadius: MirsaRadius.l)
        .environment(\.layoutDirection, .leftToRight)
        .confirmationDialog(tr("Delete all but the newest version?", "تحذف كل النسخ ما عدا الأحدث؟", ckb: "هەموو وەشانەکان جگە لە نوێترین بسڕدرێنەوە؟", kmr: "Hemû guhertin ji bilî ya herî nû jê bibim?"), isPresented: $confirmOld, titleVisibility: .visible) {
            Button(tr("Delete", "احذف", ckb: "بیسڕەوە", kmr: "Jê bibe"), role: .destructive) { archive.deleteOld(bundleID) }
            Button(tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal"), role: .cancel) {}
        }
    }
    private func reinstall(_ i: ForgeArchivedIPA) {
        // Hand a temporary copy to the normal incoming-IPA flow so the archive file stays intact.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("Mirsa-" + i.version + "-" + UUID().uuidString.prefix(6) + ".ipa")
        do { try FileManager.default.copyItem(at: archive.url(i), to: tmp); NotificationCenter.default.post(name: .mirsaIncomingIPA, object: tmp)
            note = tr("Sent to install.", "انبعت للتثبيت.", ckb: "نێردرا بۆ دامەزراندن.", kmr: "Ji bo sazkirinê hat şandin.") } catch { note = error.localizedDescription }
    }
}
