import SwiftUI
import UniformTypeIdentifiers

extension ForgeStore {
    /// Saves an imported dylib as a NEW version (never activates a previous one silently: the new version becomes current but nothing is injected).
    func importDylib(_ id: UUID, dylib: URL, info: ForgeDylibInfo, name: String) throws {
        guard let p = project(id) else { return }
        var v = ForgeVersion(prompt: tr("Imported dylib", "dylib مستورد", ckb: "dylib هاوردەکراو", kmr: "dylib hatiye import kirin"), code: "", settings: [], explain: "")
        v.title = name
        v.builtWithValues = [:]
        v.importedInfo = info
        v.importEnabled = false // explicit opt-in: a fresh import is never injected silently
        try FileManager.default.createDirectory(at: dir(p), withIntermediateDirectories: true)
        let dest = dylibURL(p, v)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: dylib, to: dest)
        try? FileManager.default.removeItem(at: dylib)
        addVersion(id, v)
    }
    func setImportedEnabled(_ id: UUID, _ versionID: UUID, _ on: Bool) {
        update(id) { p in if let i = p.versions.firstIndex(where: { $0.id == versionID }) { p.versions[i].importEnabled = on } }
    }
    /// Moves an imported version among imported versions (load order).
    func moveImported(_ id: UUID, _ versionID: UUID, by delta: Int) {
        update(id) { p in
            let idx = p.versions.indices.filter { p.versions[$0].importedInfo != nil }
            guard let pos = idx.firstIndex(where: { p.versions[$0].id == versionID }), idx.indices.contains(pos + delta) else { return }
            p.versions.swapAt(idx[pos], idx[pos + delta])
        }
    }
    /// Companion tweak: a NEW tweak made by the AI from a bounded summary. The binary itself is never modified.
    func generateCompanion(_ id: UUID, from v: ForgeVersion, request: String) async throws {
        guard let info = v.importedInfo else { return }
        let prompt = tr("Create a NEW companion tweak (do not modify the binary). Request: ", "اعمل تويك مرافق جديد (بدون تعديل الباينري). الطلب: ", ckb: "تویکێکی هاوەڵی نوێ دروست بکە. داواکاری: ", kmr: "Tweakeke nû ya hevalbend çêke. Daxwaz: ") + request + "\n\nBinary summary (not guaranteed exact):\n" + ForgeDylibInspector.companionSummary(info)
        try await generate(id, prompt: prompt)
    }
}

enum ForgeDylibText {
    static let importTitle = tr("Import dylib / deb", "استيراد dylib / deb", ckb: "هاوردەکردنی dylib / deb", kmr: "Import dylib / deb")
    static let fromFiles = tr("From Files", "من الملفات", ckb: "لە فایلەکان", kmr: "Ji Pelan")
    static let fromLink = tr("From link (HTTPS)", "من رابط (HTTPS)", ckb: "لە لینک (HTTPS)", kmr: "Ji lînkê (HTTPS)")
    static let honest = tr("Info is read from symbols and strings. It does not guarantee which methods are really hooked.", "المعلومات مقروءة من الرموز والنصوص. ما بتضمن أي دوال معمول لها hook فعلاً.", ckb: "زانیاری لە هێما و دەقەکانەوە دەخوێنرێتەوە، گەرەنتی هووکی ڕاستەقینە نییە.", kmr: "Agahî ji sembol û rêzikan tê xwendin, garantiya hookên rastî nade.")
    static let jointNote = tr("Enabled imported dylibs are injected together as binaries, in this order (binary joint injection). This is NOT the source merge of AI tweaks, which combines code.", "الـ dylib المفعّلة بتنحقن مع بعض كملفات جاهزة بهالترتيب (حقن مشترك للباينري). هاد مو دمج الكود تبع تويكات الذكاء الاصطناعي.", ckb: "dylibە چالاککراوەکان پێکەوە وەک فایلی ئامادە دەچەسپێنرێن (چەسپاندنی هاوبەش). ئەمە تێکەڵکردنی کۆدی تویکەکان نییە.", kmr: "dylibên çalak bi hev re wek binary têne xistin (derzîkirina hevpar). Ev ne yekkirina koda tweakan e.")
    static let disabledNote = tr("New imports start disabled. Enable one to include it when you press Inject.", "الاستيراد الجديد بيبدأ معطّل. فعّله ليدخل عند الحقن.", ckb: "هاوردەی نوێ ناچالاکە. چالاکی بکە بۆ ئەوەی لەگەڵ چەسپاندن بێت.", kmr: "Importa nû ne çalak dest pê dike. Çalak bike da di derzîkirinê de be.")
    static let companion = tr("Edit on it", "عدّل عليه", ckb: "دەستکاری بکە لەسەری", kmr: "Li ser biguherîne")
    static let companionNote = tr("Creates a NEW companion tweak from a summary. The original binary is not changed.", "بيعمل تويك مرافق جديد من ملخص. الملف الأصلي ما بيتغير.", ckb: "تویکێکی هاوەڵی نوێ دروست دەکات. فایلە سەرەکییەکە ناگۆڕێت.", kmr: "Ji kurteyê tweakeke nû çêdike. Binaryê eslî nayê guhertin.")
}

struct ForgeDylibImportSheet: View {
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ForgeStore.shared
    @State private var picking = false
    @State private var link = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(ForgeDylibText.importTitle).font(MirsaFont.sheetTitle).foregroundStyle(.white)
            Button { picking = true } label: { Label(ForgeDylibText.fromFiles, systemImage: "folder") }.buttonStyle(.mirsaSecondary).disabled(busy)
            TextField("https://…", text: $link).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .padding(10).background(Color.black.opacity(0.3)).cornerRadius(10).foregroundStyle(.white)
            Button { run { try await ForgeDylibImporter.fromURL(link) } } label: { Label(ForgeDylibText.fromLink, systemImage: "link") }
                .buttonStyle(.mirsaSecondary).disabled(busy || link.isEmpty)
            Text(ForgeDylibText.honest).font(.footnote).foregroundStyle(.white.opacity(0.6))
            if busy { ProgressView() }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            Spacer()
        }
        .padding(MirsaSpacing.page).frame(maxWidth: .infinity, alignment: .leading).mirsaScreen()
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data]) { r in
            guard case .success(let u) = r else { return }
            run {
                let ok = u.startAccessingSecurityScopedResource(); defer { if ok { u.stopAccessingSecurityScopedResource() } }
                return try await ForgeDylibImporter.fromFile(u)
            }
        }
    }
    private func run(_ work: @escaping () async throws -> (dylib: URL, info: ForgeDylibInfo)) {
        Task { busy = true; error = nil; defer { busy = false }
            do { let r = try await work(); try store.importDylib(id, dylib: r.dylib, info: r.info, name: r.dylib.deletingPathExtension().lastPathComponent); dismiss() }
            catch { self.error = error.localizedDescription } }
    }
}

struct ForgeImportedDylibsView: View {
    let id: UUID
    let versions: [ForgeVersion]
    @ObservedObject private var store = ForgeStore.shared
    @State private var asking: ForgeVersion?
    @State private var request = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(versions) { v in
                if let info = v.importedInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(v.title ?? "dylib").font(.headline).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            Button { store.moveImported(id, v.id, by: -1) } label: { Image(systemName: "arrow.up").frame(width: 36, height: 36) }
                            Button { store.moveImported(id, v.id, by: 1) } label: { Image(systemName: "arrow.down").frame(width: 36, height: 36) }
                            Toggle("", isOn: Binding(get: { v.importEnabled ?? false }, set: { store.setImportedEnabled(id, v.id, $0) })).labelsHidden()
                        }
                        Text("\(info.arch) · \(ByteCountFormatter.string(fromByteCount: Int64(info.size), countStyle: .file)) · \(info.classes.count) classes · \(info.selectors.count) selectors")
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                        if !info.linked.isEmpty { Text(info.linked.prefix(8).joined(separator: ", ")).font(.caption2).foregroundStyle(.white.opacity(0.5)).lineLimit(2) }
                        if !info.classes.isEmpty { Text(info.classes.prefix(12).joined(separator: ", ")).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.5)).lineLimit(3) }
                        Button { request = ""; asking = v } label: { Label(ForgeDylibText.companion, systemImage: "sparkles") }.buttonStyle(.mirsaSecondary)
                    }.foregroundStyle(.white).padding(10).background(forgeCard)
                }
            }
            Text(ForgeDylibText.jointNote).font(.caption).foregroundStyle(.white.opacity(0.6))
            Text(ForgeDylibText.disabledNote).font(.caption).foregroundStyle(.white.opacity(0.6))
            Text(ForgeDylibText.companionNote).font(.caption).foregroundStyle(.white.opacity(0.5))
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .alert(ForgeDylibText.companion, isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })) {
            TextField(tr("What should it do?", "شو بدك يعمل؟", ckb: "چی بکات؟", kmr: "Çi bike?"), text: $request)
            Button(tr("Create", "أنشئ", ckb: "دروست بکە", kmr: "Çêke")) { if let v = asking { Task { do { try await store.generateCompanion(id, from: v, request: request); error = nil } catch { self.error = error.localizedDescription } } } }
            Button(tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal"), role: .cancel) {}
        }
    }
}
