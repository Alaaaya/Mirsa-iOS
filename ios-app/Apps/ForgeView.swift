import SwiftUI
import UniformTypeIdentifiers

private let forgeCard = Color(red: 0.11, green: 0.12, blue: 0.16)
struct ShareItem: Identifiable { let url: URL; var id: String { url.path } }
struct ForgeShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}
private func forgeButton(_ icon: String, _ title: String, _ run: @escaping () -> Void) -> some View {
    Button(action: run) {
        VStack(spacing: 4) { Image(systemName: icon); Text(title).font(.caption.bold()).lineLimit(1) }
            .frame(maxWidth: .infinity).padding(.vertical, 10).background(Color.white.opacity(0.12)).foregroundStyle(.white).cornerRadius(12)
    }.buttonStyle(.plain)
}

/// Tools > Tweaks. Solid cards, layout always starts from the left.
struct ForgeView: View {
    @ObservedObject private var store = ForgeStore.shared
    @State private var picking = false
    @State private var translateMode = false
    @State private var error: String?
    @State private var status: String?
    @State private var shareURL: URL?
    @State private var langs: Set<String> = ["ar", "ckb", "kmr"]
    @State private var gallery = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Tweaks", "التويكس", ckb: "تویکەکان", kmr: "Tweak")).font(.title2.bold()).foregroundStyle(.white)
                        Text(tr("Describe it, Mirsa writes and injects it.", "اوصفه وميرسا بتكتبه وبتحقنه.", ckb: "وەسفی بکە، میرسا دەینووسێت و دەیچەسپێنێت.", kmr: "Vebêje, Mirsa dinivîse û dixe.")).font(.footnote).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Button { translateMode = false; picking = true } label: { Image(systemName: "plus").font(.title3.bold()).foregroundStyle(.white).frame(width: 44, height: 44).background(Color.accentColor).cornerRadius(12) }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label(tr("Translate an app", "ترجم تطبيق", ckb: "ئەپێک وەربگێڕە", kmr: "Appekê wergerîne"), systemImage: "character.bubble.fill").font(.headline).foregroundStyle(.white)
                    HStack { ForEach(IPAStringsTranslator.targets, id: \.code) { t in
                        Button { if langs.contains(t.code) { langs.remove(t.code) } else { langs.insert(t.code) } } label: {
                            Text(t.label).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 6)
                                .background(langs.contains(t.code) ? Color.accentColor : Color.white.opacity(0.1)).foregroundStyle(.white).cornerRadius(8)
                        }.buttonStyle(.plain) } }
                    forgeButton("doc.badge.gearshape", tr("Choose IPA", "اختر IPA", ckb: "IPA هەڵبژێرە", kmr: "IPA hilbijêre")) { translateMode = true; picking = true }
                }.padding(14).background(forgeCard).cornerRadius(16)
                ForEach(store.projects) { p in
                    NavigationLink(destination: ForgeProjectView(id: p.id)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.appName).font(.headline).foregroundStyle(.white)
                            Text(p.bundleID + " · v" + p.appVersion).font(.caption).foregroundStyle(.white.opacity(0.55))
                            Text(String(p.versions.count) + " " + tr("versions", "نسخ", ckb: "وەشان", kmr: "guhertin")).font(.caption2).foregroundStyle(.white.opacity(0.5))
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(forgeCard).cornerRadius(16)
                    }.buttonStyle(.plain)
                }
                forgeButton("person.2.fill", tr("Community tweaks", "تويكس المجتمع", ckb: "تویکی کۆمەڵگا", kmr: "Tweakên civakê")) { gallery = true }
                if let status { Text(status).font(.footnote).foregroundStyle(.white.opacity(0.7)) }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay { if let b = store.busy { ProgressView(b).padding().background(forgeCard).cornerRadius(14) } }
        .fileImporter(isPresented: $picking, allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data]) { r in
            guard case .success(let url) = r else { return }
            Task { await handle(url) }
        }
        .sheet(isPresented: $gallery) { ForgeGalleryView() }
        .sheet(item: Binding(get: { shareURL.map { ShareItem(url: $0) } }, set: { _ in shareURL = nil })) { ForgeShareSheet(url: $0.url) }
    }
    private func handle(_ url: URL) async {
        error = nil; status = nil
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        do {
            try FileManager.default.copyItem(at: url, to: local); defer { try? FileManager.default.removeItem(at: local) }
            if !translateMode {
                let info = try await ForgeStore.inspect(ipa: local)
                _ = try store.create(ipa: local, info: info)
            } else {
                store.busy = tr("Translating…", "عم أترجم…", ckb: "وەردەگێڕرێت…", kmr: "Tê wergerandin…"); defer { store.busy = nil }
                let chosen = IPAStringsTranslator.targets.filter { langs.contains($0.code) }
                let r = try await IPAStringsTranslator.run(ipa: local, languages: chosen) { _ in }
                status = tr("Translated \(r.strings) strings in \(r.files) files.", "تمت ترجمة \(r.strings) نص بـ \(r.files) ملف.", ckb: "\(r.strings) دەق وەرگێڕدرا.", kmr: "\(r.strings) rêzik hatin wergerandin.")
                shareURL = r.output
            }
        } catch { self.error = error.localizedDescription }
    }
}

struct ForgeProjectView: View {
    let id: UUID
    @ObservedObject private var store = ForgeStore.shared
    @State private var prompt = ""
    @State private var error: String?
    @State private var note: String?
    @State private var shareURL: URL?
    @State private var editing = false
    @State private var draft = ""
    @State private var updating = false

    var body: some View { if let p = store.project(id) { content(p) } else { Text("") } }

    private func run(_ work: @escaping () async throws -> Void) { Task { error = nil; note = nil; do { try await work() } catch { self.error = error.localizedDescription } } }

    @ViewBuilder private func content(_ p: ForgeProject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(p.appName).font(.title2.bold()).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $prompt).frame(height: 90).scrollContentBackground(.hidden).padding(6).background(Color.black.opacity(0.3)).cornerRadius(10).foregroundStyle(.white)
                    HStack {
                        forgeButton("sparkles", tr("Create", "أنشئ", ckb: "دروست بکە", kmr: "Çêke")) { run { try await store.generate(id, prompt: prompt); prompt = "" } }
                        forgeButton("scope", tr("Inspector", "المفتش", ckb: "پشکنەر", kmr: "Lêkolîner")) { run { shareURL = try await store.injectInspector(id) } }
                    }
                }.padding(14).background(forgeCard).cornerRadius(16)
                if let pending = store.pendingGalleryCode {
                    forgeButton("square.and.arrow.down", tr("Use community tweak", "استخدم تويك المجتمع", ckb: "تویکی کۆمەڵگا بەکاربهێنە", kmr: "Tweaka civakê bi kar bîne")) { store.editCode(id, code: pending); store.pendingGalleryCode = nil }
                }
                if let v = p.currentVersion {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("Settings", "الإعدادات", ckb: "ڕێکخستنەکان", kmr: "Mîheng")).font(.headline).foregroundStyle(.white)
                        ForEach(v.settings) { s in
                            Toggle(s.title, isOn: Binding(get: { p.values[s.key] ?? s.default }, set: { store.setValue(id, key: s.key, $0) })).foregroundStyle(.white)
                        }
                        if store.needsRebuild(p) { Text(tr("Toggles apply on the next build.", "الخيارات بتنطبق بالبناء الجاي.", ckb: "گۆڕانکاریەکان لە دروستکردنی داهاتوو جێبەجێ دەبن.", kmr: "Vebijark di çêkirina din de têne bicihanîn.")).font(.caption).foregroundStyle(.orange) }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(forgeCard).cornerRadius(16)
                    HStack {
                        forgeButton("syringe.fill", tr("Inject", "احقن", ckb: "بچەسپێنە", kmr: "Bixe")) { run { shareURL = try await store.inject(id) } }
                        forgeButton("square.and.arrow.up", ".deb") { run { shareURL = try await store.exportDeb(id) } }
                        forgeButton("books.vertical", tr("Library", "المكتبة", ckb: "کتێبخانە", kmr: "Pirtûkxane")) { run { try await store.addToLibrary(id); note = tr("Added.", "انضاف.", ckb: "زیادکرا.", kmr: "Hat zêdekirin.") } }
                    }
                    HStack {
                        forgeButton("chevron.left.forwardslash.chevron.right", tr("Edit code", "عدّل الكود", ckb: "کۆد", kmr: "Kod")) { draft = v.code; editing = true }
                        forgeButton("arrow.triangle.2.circlepath", tr("App updated", "التطبيق تحدّث", ckb: "ئەپ نوێبوو", kmr: "App nû bû")) { updating = true }
                        forgeButton("globe", tr("Publish", "انشر", ckb: "بڵاوکردنەوە", kmr: "Biweşîne")) { run { try await store.publish(id); note = tr("Published.", "انشر.", ckb: "بڵاوکرایەوە.", kmr: "Hat weşandin.") } }
                    }
                    if !v.explain.isEmpty { Text(v.explain).font(.footnote).foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, alignment: .leading).padding(14).background(forgeCard).cornerRadius(16) }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("Versions", "النسخ", ckb: "وەشانەکان", kmr: "Guhertin")).font(.headline).foregroundStyle(.white)
                        ForEach(Array(p.versions.enumerated().reversed()), id: \.element.id) { i, ver in
                            HStack {
                                Text("v\(i + 1) · " + ver.prompt).font(.footnote).foregroundStyle(.white).lineLimit(2)
                                Spacer()
                                if ver.id == p.currentVersion?.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                else { Button(tr("Revert", "ارجع", ckb: "بگەڕێوە", kmr: "Vegere")) { store.revert(id, to: ver.id) }.font(.caption.bold()) }
                            }
                        }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(forgeCard).cornerRadius(16)
                }
                if let note { Text(note).font(.footnote).foregroundStyle(.green) }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay { if let b = store.busy { ProgressView(b).padding().background(forgeCard).cornerRadius(14) } }
        .sheet(item: Binding(get: { shareURL.map { ShareItem(url: $0) } }, set: { _ in shareURL = nil })) { ForgeShareSheet(url: $0.url) }
        .sheet(isPresented: $editing) {
            NavigationView { TextEditor(text: $draft).font(.system(.footnote, design: .monospaced)).padding()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Save", "حفظ", ckb: "پاشەکەوت", kmr: "Tomar bike")) { store.editCode(id, code: draft); editing = false } } } }
        }
        .fileImporter(isPresented: $updating, allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data]) { r in
            guard case .success(let url) = r else { return }
            run { let c = try await store.updateTarget(id, ipa: url); note = c ? tr("New app version found, rebuilt.", "لقيت نسخة جديدة وعاد بنيت.", ckb: "وەشانی نوێ دۆزرایەوە.", kmr: "Guhertoya nû hat dîtin.") : tr("Rebuilt.", "عاد بنيت.", ckb: "دووبارە دروستکرا.", kmr: "Ji nû ve hat çêkirin.") }
        }
    }
}

struct ForgeGalleryView: View {
    @State private var items: [[String: Any]] = []
    @State private var error: String?
    @State private var note: String?
    var body: some View {
        NavigationView {
            List {
                ForEach(items.indices, id: \.self) { i in
                    let it = items[i]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(it["name"] as? String ?? "").font(.headline)
                        Text(it["target_bundle_id"] as? String ?? "").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(tr("Use", "استخدم", ckb: "بەکاربهێنە", kmr: "Bi kar bîne")) { Task { await use(it) } }.buttonStyle(.bordered)
                            Button(tr("Report", "بلّغ", ckb: "ڕاپۆرت", kmr: "Ragihîne")) { Task { _ = try? await ForgeClient.json(["action": "report", "id": it["id"] as? String ?? ""]) } }.buttonStyle(.bordered)
                        }
                    }
                }
                if let note { Text(note).foregroundStyle(.green) }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(tr("Community tweaks", "تويكس المجتمع", ckb: "تویکی کۆمەڵگا", kmr: "Tweakên civakê"))
        }
        .task { do { items = (try await ForgeClient.get(["action": "gallery"]))["items"] as? [[String: Any]] ?? [] } catch { self.error = error.localizedDescription } }
    }
    private func use(_ it: [String: Any]) async {
        guard let id = it["id"] as? String else { return }
        do {
            let d = try await ForgeClient.get(["action": "gallery-item", "id": id])
            ForgeStore.shared.pendingGalleryCode = d["code"] as? String
            note = tr("Open one of your tweak projects and tap Use community tweak.", "افتح مشروع تويك وكبس استخدم تويك المجتمع.", ckb: "پڕۆژەیەکی تویک بکەرەوە.", kmr: "Projeyekê veke.")
        } catch { self.error = error.localizedDescription }
    }
}
