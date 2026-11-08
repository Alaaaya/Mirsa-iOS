import SwiftUI
import UniformTypeIdentifiers

let forgeCard = MirsaPalette.card
private let forgeBG = MirsaPalette.sheet
struct ForgeShareItem: Identifiable { let url: URL; var id: String { url.path } }
/// Secondary share action: the same tweak as a .deb. Only offered inside the share menu.
final class DebActivity: UIActivity {
    let onTap: () -> Void
    init(onTap: @escaping () -> Void) { self.onTap = onTap }
    override var activityType: UIActivity.ActivityType? { .init("com.alaa.mirsa.forge.deb") }
    override var activityTitle: String? { tr("Share as .deb", "مشاركة كـ .deb", ckb: "وەک .deb بڵاوبکەرەوە", kmr: "Wekî .deb parve bike") }
    override var activityImage: UIImage? { UIImage(systemName: "shippingbox") }
    override class var activityCategory: UIActivity.Category { .action }
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }
    override func perform() { onTap(); activityDidFinish(true) }
}
struct ForgeShareSheet: UIViewControllerRepresentable {
    let url: URL
    var onDeb: (() -> Void)? = nil
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: onDeb.map { [DebActivity(onTap: $0)] })
    }
    func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}
private func forgeLabel(_ icon: String, _ title: String) -> some View {
    VStack(spacing: 4) { Image(systemName: icon); Text(title).font(.caption.bold()).lineLimit(1) }
        .frame(maxWidth: .infinity).padding(.vertical, 10).background(Color.white.opacity(0.12)).foregroundStyle(.white).cornerRadius(12)
}
private func forgeButton(_ icon: String, _ title: String, _ run: @escaping () -> Void) -> some View {
    Button(action: run) {
        VStack(spacing: 4) { Image(systemName: icon).font(.system(size: MirsaIconSize.m, weight: .semibold)); Text(title).font(MirsaFont.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8) }
            .frame(maxWidth: .infinity).padding(.vertical, MirsaSpacing.s)
            .background(MirsaPalette.cardRaised, in: RoundedRectangle(cornerRadius: MirsaRadius.s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MirsaRadius.s, style: .continuous).strokeBorder(MirsaPalette.strokeStrong, lineWidth: 1))
            .foregroundStyle(.white)
    }.buttonStyle(.mirsaPress)
}

let forgeDeleteTitle = tr("Delete", "حذف", ckb: "سڕینەوە", kmr: "Jê bibe")
func forgeDeleteFailed(_ name: String) -> String {
    tr("Could not delete \(name). It was kept.", "ما قدرت احذف \(name). تم الإبقاء عليه.", ckb: "نەتوانرا \(name) بسڕدرێتەوە. هێڵرایەوە.", kmr: "\(name) nehat jêbirin. Hat hiştin.")
}
func forgeDeleteMessage(_ name: String) -> String {
    tr("Delete \(name) and all its versions and files? This cannot be undone.", "حذف \(name) مع كل نسخه وملفاته؟ ما فيك ترجع عنها.",
       ckb: "\(name) لەگەڵ هەموو وەشان و فایلەکانی بسڕدرێتەوە؟ ناتوانرێت پاشگەز ببیتەوە.", kmr: "\(name) bi hemû guhertin û pelên wê jê bibe? Vegerandin tune.")
}
/// Tools > Tweaks. Solid cards, layout always starts from the left.
struct ForgeView: View {
    @ObservedObject private var store = ForgeStore.shared
    @State private var picking = false
    @State private var error: String?
    @State private var status: String?
    @State private var shareURL: URL?
    @State private var debID: UUID?
    @State private var targetSource: String?
    @State private var targetLink = false
    @State private var targetSources = false
    @State private var gallery = false
    @State private var toDelete: ForgeProject?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Tweaks", "التويكس", ckb: "تویکەکان", kmr: "Tweak")).font(MirsaFont.sheetTitle).foregroundStyle(.white)
                        Text(tr("Describe it, Mirsa writes and injects it.", "اوصفه ومرسى بتكتبه وبتحقنه.", ckb: "وەسفی بکە، میرسا دەینووسێت و دەیچەسپێنێت.", kmr: "Vebêje, Mirsa dinivîse û dixe.")).font(.footnote).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Menu {
                        Button { picking = true } label: { Label(tr("From Files", "من الملفات"), systemImage: "folder") }
                        Button { targetSource = "library" } label: { Label(tr("My Library", "مكتبتي"), systemImage: "books.vertical") }
                        Button { targetSource = "projects" } label: { Label(tr("Projects", "المشاريع"), systemImage: "doc.badge.gearshape") }
                        Button { targetLink = true } label: { Label(tr("From link", "من رابط"), systemImage: "link") }
                        Button { targetSources = true } label: { Label(tr("From sources", "من السورسات"), systemImage: "shippingbox") }
                    } label: { MirsaIconButtonLabel(systemName: "plus").background(MirsaPalette.accentGradient, in: Circle()).shadow(color: MirsaPalette.accent.opacity(0.4), radius: 8, y: 3) }
                }
                ForgeCrashCard()
                ForEach(store.projects) { p in
                    NavigationLink(destination: ForgeProjectView(id: p.id)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.appName).font(.headline).foregroundStyle(.white)
                            Text(p.bundleID + " · v" + p.appVersion).font(.caption).foregroundStyle(.white.opacity(0.55))
                            Text(String(p.versions.count) + " " + tr("versions", "نسخ", ckb: "وەشان", kmr: "guhertin")).font(.caption2).foregroundStyle(.white.opacity(0.5))
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).appsGlass(cornerRadius: MirsaRadius.l)
                    }.buttonStyle(.mirsaPress)
                    .contextMenu { Button(role: .destructive) { toDelete = p } label: { Label(forgeDeleteTitle, systemImage: "trash") } }
                    .gesture(DragGesture(minimumDistance: 30).onEnded { g in if g.translation.width < -60 && abs(g.translation.height) < 40 { toDelete = p } })
                }
                forgeButton("person.2.fill", tr("Community tweaks", "تويكس المجتمع", ckb: "تویکی کۆمەڵگا", kmr: "Tweakên civakê")) { gallery = true }
                if let status { Text(status).font(.footnote).foregroundStyle(.white.opacity(0.7)) }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }.padding(MirsaSpacing.page).frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay { if let b = store.busy { ProgressView(b).padding().appsGlass(cornerRadius: MirsaRadius.m) } }
        .navigationBarTitleDisplayMode(.inline).mirsaScreen()
        .fileImporter(isPresented: $picking, allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data]) { r in
            guard case .success(let url) = r else { return }
            Task { await handle(url) }
        }
        .task { await store.refreshNames() }
        .confirmationDialog(forgeDeleteMessage(toDelete?.appName ?? ""), isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button(forgeDeleteTitle, role: .destructive) { if let p = toDelete { do { try store.delete(p.id); error = nil } catch { self.error = forgeDeleteFailed(p.appName) + " " + error.localizedDescription } }; toDelete = nil }
            Button(tr("Cancel", "إلغاء", ckb: "پاشگەزبوونەوە", kmr: "Betal"), role: .cancel) { toDelete = nil }
        }
        .sheet(isPresented: Binding(get: { targetSource != nil }, set: { if !$0 { targetSource = nil } })) {
            ForgeLibraryTargetPicker(projectsOnly: targetSource == "projects") { url in
                try await createTarget(url)
                targetSource = nil
            }
        }
        .sheet(isPresented: $targetLink) { PersonalURLImportSheet { try await createTarget($0) } }
        .sheet(isPresented: $targetSources) {
            SourcesTab(onSelectIPA: { url in
                try await createTarget(url)
                targetSources = false
            })
        }
        .sheet(isPresented: $gallery) { ForgeGalleryView() }
        .sheet(item: Binding(get: { shareURL.map { ForgeShareItem(url: $0) } }, set: { _ in shareURL = nil })) { ForgeShareSheet(url: $0.url) }
    }
    private func createTarget(_ url: URL) async throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        try FileManager.default.copyItem(at: url, to: local)
        defer { try? FileManager.default.removeItem(at: local) }
        let info = try await ForgeStore.inspect(ipa: local)
        _ = try store.create(ipa: local, info: info)
    }
    private func handle(_ url: URL) async {
        error = nil; status = nil
        do { try await createTarget(url) } catch { self.error = error.localizedDescription }
    }
}

struct ForgeProjectView: View {
    let id: UUID
    @ObservedObject private var store = ForgeStore.shared
    @State private var prompt = ""
    @State private var error: String?
    @State private var note: String?
    @State private var shareURL: URL?
    @State private var debID: UUID?
    @State private var editing = false
    @State private var draft = ""
    @State private var updating = false
    @State private var fullLog: String?
    @State private var failedVersionID: UUID?
    @State private var reportTarget: ForgeFixReportTarget?
    @State private var showInspector = false
    @State private var needsInspector = false
    @State private var actionVersion: ForgeVersion?
    @State private var renameDraft = ""
    @State private var versionMenu = false
    @State private var renaming = false
    @State private var codeEditing = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    @State private var importingDylib = false
    @State private var publishing = false
    var body: some View { if let p = store.project(id) { content(p) } else { Text("") } }

    private func run(_ work: @escaping () async throws -> Void) { let startedVersion = store.project(id)?.currentVersion?.id; Task { error = nil; needsInspector = false; note = nil; fullLog = nil; failedVersionID = nil; do { try await work() } catch let f as ForgeBuildFailure { self.error = f.summary; self.fullLog = f.log; self.failedVersionID = startedVersion } catch ForgeClient.Failure.inspectorNeeded(let m) { self.error = m; self.needsInspector = true } catch { self.error = error.localizedDescription } } }

    @ViewBuilder private func content(_ p: ForgeProject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left").font(.title3.weight(.semibold)).frame(width: 36, height: 36) }
                    Text(p.appName).font(MirsaFont.sheetTitle).lineLimit(1)
                    Spacer()
                }.foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $prompt).frame(height: 90).scrollContentBackground(.hidden).padding(6).background(Color.black.opacity(0.3)).cornerRadius(10).foregroundStyle(.white)
                        .overlay(alignment: .topLeading) { if prompt.isEmpty { Text(tr("Describe the tweak you want…", "اوصف التويك اللي بدك ياه…", ckb: "تویکەکە باس بکە…", kmr: "Tweaka xwe vebêje…")).foregroundStyle(.white.opacity(0.4)).padding(.horizontal, 12).padding(.vertical, 14).allowsHitTesting(false) } }
                    forgeButton("square.and.arrow.down.on.square", ForgeDylibText.importTitle) { importingDylib = true }
                    HStack {
                        forgeButton("sparkles", tr("Create", "أنشئ", ckb: "دروست بکە", kmr: "Çêke")) { run { try await store.generate(id, prompt: prompt); prompt = "" } }
                        Menu {
                            Button(tr("Inject inspector", "احقن المفتش", ckb: "پشکنەر بچەسپێنە", kmr: "Lêkolîner bixe")) { run { let ipa = try await store.injectInspector(id); NotificationCenter.default.post(name: .mirsaIncomingIPA, object: ipa) } }
                                .disabled(!store.builderReady)
                            Button(tr("Capture / import", "التقاط / استيراد", ckb: "وەرگرتن / هاوردە", kmr: "Girtin / import")) { showInspector = true }
                        } label: { forgeLabel("scope", tr("Inspector", "المفتش", ckb: "پشکنەر", kmr: "Lêkolîner")) }
                    }
                }.padding(14).appsGlass(cornerRadius: MirsaRadius.l)
                ForgeFeaturesView(id: id, prompt: $prompt, showInspector: $showInspector)
                if let notice = store.fixNotice {
                    HStack(alignment: .top) {
                        Image(systemName: "checkmark.shield")
                        Text(notice).font(.footnote)
                        Spacer()
                        Button { store.fixNotice = nil } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(tr("Done", "تم", ckb: "تەواو", kmr: "Temam"))
                    }.foregroundStyle(.green).padding(14).appsGlass(cornerRadius: MirsaRadius.l)
                }
                if let pending = store.pendingGalleryCode {
                    forgeButton("square.and.arrow.down", tr("Use community tweak", "استخدم تويك المجتمع", ckb: "تویکی کۆمەڵگا بەکاربهێنە", kmr: "Tweaka civakê bi kar bîne")) { store.editCode(id, code: pending); store.pendingGalleryCode = nil }
                }
                if let v = p.currentVersion {
                    Button { reportTarget = ForgeFixReportTarget(versionID: v.id, kind: "crash", diagnostic: "") } label: {
                        Label(ForgeFixText.report, systemImage: "wrench.and.screwdriver")
                    }
                    if !v.settings.isEmpty { VStack(alignment: .leading, spacing: 8) {
                        Text(tr("Settings", "الإعدادات", ckb: "ڕێکخستنەکان", kmr: "Mîheng")).font(.headline).foregroundStyle(.white)
                        ForEach(v.settings) { s in
                            Toggle(s.title, isOn: Binding(get: { p.values[s.key] ?? s.default }, set: { store.setValue(id, key: s.key, $0) })).foregroundStyle(.white)
                        }
                        if store.needsRebuild(p) { Text(tr("Toggles apply on the next build.", "الخيارات بتنطبق بالبناء الجاي.", ckb: "گۆڕانکاریەکان لە دروستکردنی داهاتوو جێبەجێ دەبن.", kmr: "Vebijark di çêkirina din de têne bicihanîn.")).font(.caption).foregroundStyle(.orange) }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).appsGlass(cornerRadius: MirsaRadius.l) }
                    if !store.builderReady { Text(tr("Building tweaks is not available yet (the build server is not set up). Injecting, exporting the dylib and the inspector are disabled.", "بناء التويكس مو متاح هلق (سيرفر البناء مو جاهز). الحقن وتصدير deb والمفتش معطّلة.", ckb: "دروستکردنی تویک هێشتا بەردەست نییە (سێرڤەری دروستکردن ئامادە نییە).", kmr: "Çêkirina tweak hê ne amade ye (serverê çêkirinê ne sazkirî ye).")).font(.footnote).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading).padding(14).appsGlass(cornerRadius: MirsaRadius.l) }
                    HStack {
                        forgeButton("syringe.fill", tr("Inject", "احقن", ckb: "بچەسپێنە", kmr: "Bixe")) { run { let ipa = try await store.inject(id); NotificationCenter.default.post(name: .mirsaIncomingIPA, object: ipa) } }
                            .disabled(!store.builderReady).opacity(store.builderReady ? 1 : 0.4)
                        forgeButton("square.and.arrow.up", ".dylib") { run { shareURL = try await store.exportDylib(id); debID = id } }
                            .disabled(!store.builderReady).opacity(store.builderReady ? 1 : 0.4)
                        forgeButton("books.vertical", tr("Library", "المكتبة", ckb: "کتێبخانە", kmr: "Pirtûkxane")) { run { try await store.addToLibrary(id); note = tr("Added.", "انضاف.", ckb: "زیادکرا.", kmr: "Hat zêdekirin.") } }
                            .disabled(!store.builderReady).opacity(store.builderReady ? 1 : 0.4)
                    }
                    HStack {
                        forgeButton("chevron.left.forwardslash.chevron.right", tr("Edit code", "عدّل الكود", ckb: "کۆد", kmr: "Kod")) { draft = v.code; editing = true }
                        forgeButton("arrow.triangle.2.circlepath", tr("App updated", "التطبيق تحدّث", ckb: "ئەپ نوێبوو", kmr: "App nû bû")) { updating = true }
                        forgeButton("globe", ForgePublishSheet.title) { publishing = true }
                    }
                    if !v.explain.isEmpty { Text(v.explain).font(.footnote).foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, alignment: .leading).padding(14).appsGlass(cornerRadius: MirsaRadius.l) }
                    if p.versions.contains(where: { $0.importedInfo != nil }) { ForgeImportedDylibsView(id: id, versions: p.versions.filter { $0.importedInfo != nil }, openInspector: { showInspector = true }).padding(14).appsGlass(cornerRadius: MirsaRadius.l) }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("Versions", "النسخ", ckb: "وەشانەکان", kmr: "Guhertin")).font(.headline).foregroundStyle(.white)
                        ForEach(Array(p.versions.enumerated().reversed()), id: \.element.id) { i, ver in
                            ForgeVersionRow(label: "v\(i + 1) · " + (ver.fixSourceSHA256 != nil ? ForgeFixText.label : (ver.title ?? ver.prompt)), active: ver.id == p.currentVersion?.id,
                                onRevert: { store.revert(id, to: ver.id) }, onEdit: { actionVersion = ver; renameDraft = ver.title ?? ""; versionMenu = true }, onDelete: { actionVersion = ver; confirmDelete = true })
                        }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).appsGlass(cornerRadius: MirsaRadius.l)
                }
                if let note { Text(note).font(.footnote).foregroundStyle(.green) }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                if needsInspector { Button(ForgeInspectorText.open) { showInspector = true } }
                if let fullLog {
                    if let failedVersionID {
                        Button(ForgeFixText.report) { reportTarget = ForgeFixReportTarget(versionID: failedVersionID, kind: "build", diagnostic: fullLog) }
                    }
                    DisclosureGroup(tr("Full log", "السجل الكامل", ckb: "تۆماری تەواو", kmr: "Têketina tev")) {
                        ScrollView(.horizontal) { Text(fullLog).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.8)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    }.foregroundStyle(.white).padding(14).appsGlass(cornerRadius: MirsaRadius.l)
                }
            }.padding(MirsaSpacing.page).padding(.bottom, 90).frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay { if let b = store.busy { ProgressView(b).padding().appsGlass(cornerRadius: MirsaRadius.m) } }
        .task { await store.refreshStatus(); await store.syncFixInbox() }
        .sheet(item: $reportTarget) { target in
            ForgeFixReportView(projectID: id, versionID: target.versionID, initialDiagnostic: target.diagnostic, kind: target.kind)
        }
        .navigationBarHidden(true)
        .mirsaScreen()
        .sheet(isPresented: $importingDylib) { ForgeDylibImportSheet(id: id) }
        .sheet(isPresented: $publishing) { ForgePublishSheet(id: id) { note = $0 } }
        .sheet(item: Binding(get: { shareURL.map { ForgeShareItem(url: $0) } }, set: { _ in shareURL = nil })) { ForgeShareSheet(url: $0.url, onDeb: debID.map { d in { Task { @MainActor in try? await Task.sleep(nanoseconds: 600_000_000); run { shareURL = try await store.exportDeb(d) } } } }) }
        .confirmationDialog(tr("Edit version", "تعديل النسخة", ckb: "دەستکاری وەشان", kmr: "Guhertoyê biguherîne"), isPresented: $versionMenu) {
            Button(tr("Rename", "تغيير الاسم", ckb: "ناو بگۆڕە", kmr: "Nav biguherîne")) { renaming = true }
            Button(tr("Edit code (new version)", "تعديل الكود (نسخة جديدة)", ckb: "کۆد (وەشانی نوێ)", kmr: "Kod (guhertoya nû)")) { draft = actionVersion?.code ?? ""; codeEditing = true }
            Button(tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal"), role: .cancel) {}
        }
        .alert(tr("Rename", "تغيير الاسم", ckb: "ناو بگۆڕە", kmr: "Nav biguherîne"), isPresented: $renaming) {
            TextField("", text: $renameDraft)
            Button(tr("Save", "حفظ", ckb: "پاشەکەوت", kmr: "Tomar bike")) { if let v = actionVersion { store.renameVersion(id, v.id, to: renameDraft) } }
            Button(tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal"), role: .cancel) {}
        }
        .alert(tr("Delete this version?", "حذف هالنسخة؟", ckb: "ئەم وەشانە بسڕدرێتەوە؟", kmr: "Ev guhertoyê jê bibe?"), isPresented: $confirmDelete) {
            Button(tr("Delete", "حذف", ckb: "سڕینەوە", kmr: "Jê bibe"), role: .destructive) { if let v = actionVersion { do { try store.deleteVersion(id, v.id) } catch { self.error = error.localizedDescription } } }
            Button(tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal"), role: .cancel) {}
        } message: { Text(tr("Only this version's files are deleted. The app and other versions stay.", "بتنحذف ملفات هالنسخة بس. التطبيق والنسخ التانية بتضل.", ckb: "تەنها فایلەکانی ئەم وەشانە دەسڕدرێنەوە.", kmr: "Tenê pelên vê guhertoyê tên jêbirin.")) }
        .sheet(isPresented: $codeEditing) {
            NavigationView { TextEditor(text: $draft).font(.system(.footnote, design: .monospaced)).padding()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Save", "حفظ", ckb: "پاشەکەوت", kmr: "Tomar bike")) { if let v = actionVersion { store.editVersionCode(id, v.id, code: draft) }; codeEditing = false } } } }
        }
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
    @State private var editing: [String: Any]?
    @State private var editName = ""
    @State private var editDesc = ""
    @State private var deleting: [String: Any]?
    @State private var versioning: [String: Any]?
    var body: some View {
        NavigationView {
            List {
                ForEach(items.indices, id: \.self) { i in
                    let it = items[i]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(it["name"] as? String ?? "").font(.headline)
                        Text(it["target_bundle_id"] as? String ?? "").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(tr("Use", "استخدم", ckb: "بەکاربهێنە", kmr: "Bi kar bîne")) { Task { await use(it) } }.buttonStyle(.mirsaSecondary)
                            if it["mine"] as? Bool == true {
                                Button(tr("Edit", "تعديل", ckb: "دەستکاری", kmr: "Biguherîne")) { editName = it["name"] as? String ?? ""; editDesc = it["description"] as? String ?? ""; editing = it }.buttonStyle(.mirsaSecondary)
                                Button(tr("New version", "نسخة جديدة", ckb: "وەشانی نوێ", kmr: "Guhertoya nû")) { versioning = it }.buttonStyle(.mirsaSecondary)
                                Button(tr("Delete", "حذف", ckb: "سڕینەوە", kmr: "Jê bibe"), role: .destructive) { deleting = it }.buttonStyle(.mirsaSecondary)
                            } else {
                                Button(tr("Report", "بلّغ", ckb: "ڕاپۆرت", kmr: "Ragihîne")) { Task { _ = try? await ForgeClient.json(["action": "report", "id": it["id"] as? String ?? ""]) } }.buttonStyle(.mirsaSecondary)
                            }
                        }
                    }
                }
                if let note { Text(note).foregroundStyle(.green) }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(tr("Community tweaks", "تويكس المجتمع", ckb: "تویکی کۆمەڵگا", kmr: "Tweakên civakê"))
        }
        .task { await reload() }
        .alert(tr("Edit tweak", "تعديل التويك", ckb: "دەستکاری تویک", kmr: "Tweakê biguherîne"), isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField(tr("Name", "الاسم", ckb: "ناو", kmr: "Nav"), text: $editName)
            TextField(tr("Description", "الوصف", ckb: "وەسف", kmr: "Danasîn"), text: $editDesc)
            Button(tr("Save", "حفظ", ckb: "پاشەکەوت", kmr: "Tomar bike")) { let id = editing?["id"] as? String ?? ""; Task { await mutate(["action": "gallery-update", "id": id, "name": editName, "description": editDesc]) } }
            Button(tr("Cancel", "إلغاء", ckb: "پاشگەزبوونەوە", kmr: "Betal"), role: .cancel) {}
        }
        .confirmationDialog(tr("Upload which project?", "أي مشروع ترفع؟", ckb: "کام پڕۆژە؟", kmr: "Kîjan proje?"), isPresented: Binding(get: { versioning != nil }, set: { if !$0 { versioning = nil } }), titleVisibility: .visible) {
            ForEach(ForgeStore.shared.projects.filter { $0.currentVersion != nil }) { p in
                Button(p.name) { let e = versioning?["id"] as? String ?? ""; Task { do { try await ForgeStore.shared.updateGallery(entry: e, from: p.id); error = nil; note = tr("New version uploaded.", "انرفعت النسخة.", ckb: "وەشان بارکرا.", kmr: "Guhertoya nû hat barkirin."); await reload() } catch { self.error = error.localizedDescription } } }
            }
        }
        .alert(tr("Delete this tweak?", "حذف هالتويك؟", ckb: "ئەم تویکە بسڕیتەوە؟", kmr: "Ev tweak jê bibe?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(tr("Delete", "حذف", ckb: "سڕینەوە", kmr: "Jê bibe"), role: .destructive) { let id = deleting?["id"] as? String ?? ""; Task { await mutate(["action": "gallery-delete", "id": id]) } }
            Button(tr("Cancel", "إلغاء", ckb: "پاشگەزبوونەوە", kmr: "Betal"), role: .cancel) {}
        } message: { Text(tr("It disappears for everyone.", "رح يختفي عند الجميع.", ckb: "بۆ هەموو دەبزر دەبێت.", kmr: "Ji bo herkesî winda dibe.")) }
    }
    private func reload() async {
        do { items = (try await ForgeClient.get(["action": "gallery"]))["items"] as? [[String: Any]] ?? [] } catch { self.error = error.localizedDescription }
    }
    private func mutate(_ body: [String: Any]) async {
        do { _ = try await ForgeClient.json(body); error = nil; await reload() } catch { self.error = error.localizedDescription }
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

/// Selects existing personal app archives without mutating the library or project.
private struct ForgeLibraryTargetPicker: View {
    let projectsOnly: Bool
    let onFile: (URL) async throws -> Void
    @ObservedObject private var library = PersonalAppsLibrary.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var working = false
    @State private var failure: String?
    private var apps: [PersonalLibraryApp] {
        library.apps.filter { app in
            (!projectsOnly || FileManager.default.fileExists(atPath: library.draftURL(app).path)) &&
            (query.isEmpty || app.name.localizedCaseInsensitiveContains(query) || app.bundleID.localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        NavigationStack {
            List {
                ForEach(apps) { app in
                    Button {
                        working = true; failure = nil
                        Task { @MainActor in
                            do { try await onFile(library.url(app)); dismiss() }
                            catch { failure = error.localizedDescription }
                            working = false
                        }
                    } label: {
                        HStack {
                            Group {
                                if let icon = library.icon(for: app) { Image(uiImage: icon).resizable().scaledToFit() }
                                else { Image(systemName: "app.dashed") }
                            }.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading) { Text(app.name); Text(app.bundleID).font(.caption).foregroundStyle(.secondary) }
                        }
                    }.disabled(working)
                }
                if apps.isEmpty { Text(tr("No apps found.", "ما في تطبيقات.")).foregroundStyle(.secondary) }
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            .searchable(text: $query)
            .navigationTitle(projectsOnly ? tr("Projects", "المشاريع") : tr("My Library", "مكتبتي"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Cancel", "إلغاء")) { dismiss() }.disabled(working) } }
            .overlay { if working { ProgressView() } }
            .mirsaScreen()
        }.environment(\.layoutDirection, .leftToRight).interactiveDismissDisabled(working)
    }
}


struct ForgeVersionRow: View {
    let label: String; let active: Bool
    let onRevert: () -> Void; let onEdit: () -> Void; let onDelete: () -> Void
    @State private var offset: CGFloat = 0
    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                Button(action: { offset = 0; onEdit() }) { Text(tr("Edit", "تعديل", ckb: "دەستکاری", kmr: "Biguherîne")).font(.caption.bold()).frame(width: 70, height: 44).background(Color.blue) }
                Button(action: { offset = 0; onDelete() }) { Text(tr("Delete", "حذف", ckb: "سڕینەوە", kmr: "Jê bibe")).font(.caption.bold()).frame(width: 70, height: 44).background(Color.red) }
            }.foregroundStyle(.white).cornerRadius(10)
            HStack {
                Text(label).font(.footnote).foregroundStyle(.white).lineLimit(2)
                Spacer()
                if active { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                else { Button(tr("Revert", "ارجع", ckb: "بگەڕێوە", kmr: "Vegere"), action: onRevert).font(.caption.bold()) }
            }
            .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 44).background(forgeCard)
            .offset(x: offset)
            .contextMenu {
                Button(tr("Edit", "تعديل", ckb: "دەستکاری", kmr: "Biguherîne"), action: onEdit)
                Button(tr("Delete", "حذف", ckb: "سڕینەوە", kmr: "Jê bibe"), role: .destructive, action: onDelete)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 20).onChanged { g in if abs(g.translation.width) > abs(g.translation.height) { offset = max(-140, min(0, g.translation.width)) } }
                .onEnded { g in withAnimation(.easeOut(duration: 0.15)) { offset = g.translation.width < -60 ? -140 : 0 } })
        }.clipped()
    }
}
