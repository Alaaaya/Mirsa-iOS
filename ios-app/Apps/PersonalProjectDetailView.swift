import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import ImageIO

struct PersonalProjectDetailView: View {
    let app: PersonalLibraryApp
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var library = PersonalAppsLibrary.shared
    @StateObject private var tweaks = IPATweakLibrary.shared
    @State private var draft = PersonalProjectDraft()
    @State private var loaded = false
    @StateObject private var keyboard = MirsaKeyboardVisibility()
    @State private var identities: [PersonalIdentityVault.SavedIdentity] = []
    @State private var selectedID: String?
    @State private var showCertificates = false
    @State private var pickingTweak = false
    @State private var configBusy = false
    @ObservedObject var signing = PersonalSigningOperation.shared
    @State private var consumedResult: UUID?
    private var busy: Bool { configBusy || signing.running }
    @State private var message: String?
    @State private var resultAlert: String?
    @State private var output: URL?
    @State private var sharing = false
    @State private var icon: UIImage?
    @State private var iconPhoto: PhotosPickerItem?
    @State private var pickingIconPhoto = false
    @State private var pickingIcon = false
    @State private var extensionCount: Int?
    @State private var deps: [String]?
    @State private var existingLibraries: [ExistingProjectLibrary] = []
    @State private var showDeps = false
    @State private var pickingEntitlements = false
    @StateObject private var draftWriter = PersonalProjectDraftWriter()
    @State private var draftDestination: URL?
    @State private var scrolling = false
    @State private var workspace: ProjectFolderLocation?
    @State private var showProjectLogs = false
    @State private var showInstallLog = false
    @StateObject private var versionArchive = MirsaVersionArchive.shared

    private var configOnly: Bool { selected == nil }
    private var selected: PersonalIdentityVault.SavedIdentity? {
        identities.first { $0.id == selectedID } ?? identities.first
    }
    private func tweak(_ id: UUID) -> IPATweak? { tweaks.items.first { $0.id == id } }

    var body: some View {
        classicPage
        .preferredColorScheme(.dark)
        .environment(\.layoutDirection, .leftToRight)
        .sheet(isPresented: $showCertificates, onDismiss: reloadIdentities) { PersonalCertificateManagerView() }
        .sheet(isPresented: $pickingTweak) {
            DocumentPickerView(allowedContentTypes: ["zip", "dylib", "deb", "framework"].compactMap { UTType(filenameExtension: $0) } + [.data]) { url in
                Task {
                    do {
                        let imported = try await tweaks.addFile(url, allowSelection: true)
                        if !draft.tweakIDs.contains(imported.id) { draft.tweakIDs.append(imported.id) }
                    } catch { message = error.localizedDescription }
                }
            }
        }
        .sheet(item: $tweaks.pendingImport, onDismiss: { tweaks.finishImportSelection(nil) }) { choice in
            IPATweakImportSelectionView(choice: choice) { tweaks.finishImportSelection($0) }
        }
        .fileImporter(isPresented: $pickingIcon, allowedContentTypes: [.image]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard ((try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max) <= 16 * 1024 * 1024 else {
                    throw SideloadError.message("Choose an image smaller than 16 MB.")
                }
                try setProjectIcon(Data(contentsOf: url))
            } catch { message = error.localizedDescription }
        }
        // Keep the presenter on the editor, not inside the transient Menu.
        .photosPicker(isPresented: $pickingIconPhoto, selection: $iconPhoto, matching: .images)
        .onChange(of: iconPhoto) { _, selection in
            Task {
                do {
                    if let data = try await selection?.loadTransferable(type: Data.self) { try setProjectIcon(data) }
                } catch { message = error.localizedDescription }
                iconPhoto = nil
            }
        }
        .sheet(isPresented: $pickingEntitlements) {
            DocumentPickerView(allowedContentTypes: [.propertyList, .xml, .data]) { url in
                guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 64 * 1024,
                      let data = try? Data(contentsOf: url),
                      (try? PropertyListSerialization.propertyList(from: data, format: nil)) is [String: Any] else {
                    message = personalText("Invalid or too large entitlements file (max 64 KB plist).", "ملف Entitlements غير صالح أو كبير (الحد 64KB)."); return
                }
                draft.customEntitlements = data; draft.customEntitlementsName = url.lastPathComponent
            }
        }
        .sheet(isPresented: $sharing, onDismiss: cleanOutput) {
            if let output { PersonalSignedShare(url: output) }
        }
        .sheet(isPresented: Binding(get: { bundleManager != nil }, set: { if !$0 { bundleManager = nil } })) {
            if let manager = bundleManager {
                NavigationStack {
                    BundleFileBrowserView(manager: manager, onChange: { draft.bundleOverlay = manager.overlay.isEmpty ? nil : manager.overlay })
                }
            }
        }
        .sheet(item: $workspace) { location in
            PersonalProjectFolderBrowser(root: location.url, title: draft.name, sources: projectSources)
        }
        .sheet(isPresented: $showProjectLogs) {
            NavigationStack {
                ScrollView { MirsaTelemetryView(bundleID: app.bundleID).padding() }
                    .background(AuroraBackground()).navigationTitle(draft.name)
                    .toolbar { ToolbarItem(placement: .topBarLeading) {
                        Button(personalText("Close", "إغلاق")) { showProjectLogs = false }
                    } }
            }.preferredColorScheme(.dark).environment(\.layoutDirection, .leftToRight)
        }
        .alert(personalText("Result", "النتيجة"), isPresented: Binding(get: { resultAlert != nil }, set: { if !$0 { resultAlert = nil } })) {
            Button(personalText("OK", "تمام")) { resultAlert = nil }
        } message: { Text(resultAlert ?? "") }
        .task { await load(); await inspect(); consumeSigningResult() }
        .onReceive(NotificationCenter.default.publisher(for: .mirsaProjectAttached)) { note in
            guard note.object as? UUID == app.id else { return }
            do { draft = try ProjectAttachmentStore.draft(app) }
            catch { message = OpenInAttachmentText.failed }
        }
        .onChange(of: signing.state?.running) { _ in consumeSigningResult() }
        .onChange(of: draft) { _ in if loaded, let destination = draftDestination { draftWriter.schedule(draft, to: destination) } }
        .onChange(of: scenePhase) { phase in if phase != .active { draftWriter.flush() } }
        .onDisappear { draftWriter.flush(); if !sharing { cleanOutput() } }
    }

    // MARK: Classic (default, original design)

    private var classicPage: some View {
        ZStack {
            LCPalette.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    pageHeader
                    appCard
                    outputCard
                    tweaksCard
                    settingsCard
                    depsCard
                    certificateCard
                    MirsaVersionArchiveSection(bundleID: app.bundleID)
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled).accessibilityIdentifier("project-sign-result-notice") }
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 96)
                    .contentShape(Rectangle())
            }.scrollIndicators(.hidden)
                .clipped()
                .accessibilityIdentifier("mirsa.project.editor-scroll")
                .scrollDismissesKeyboard(.interactively)
                .onScrollPhaseChange { _, phase in scrolling = phase != .idle }
        }
        .safeAreaInset(edge: .bottom) {
            if !keyboard.isVisible { signButton }
        }
        .fullScreenCover(isPresented: $showInstallLog) {
            ProjectInstallLogView(signing: signing, projectID: app.id, appName: draft.name) { showInstallLog = false }
        }
    }

    private var rtlHeader: Bool {
        let language = AppLanguageStore.snapshot
        return language == .arabic || language == .sorani
    }
    private var pageHeader: some View {
        let back = Button { dismiss() } label: {
            Image(systemName: rtlHeader ? "chevron.right" : "chevron.left").font(.subheadline.weight(.semibold))
                .frame(width: 40, height: 40).background(LCPalette.pill, in: Circle())
        }.buttonStyle(.plain)
        let more = Menu {
            Button { openBundleFiles() } label: {
                Label(bundleLoading ? personalText("Reading app…", "عم أقرأ التطبيق…") : personalText("Bundle files", "ملفات التطبيق"), systemImage: "doc.on.doc")
            }.disabled(bundleLoading)
            Button { showProjectLogs = true } label: {
                Label(personalText("Launches & crash logs", "التشغيل وسجلات الأعطال"), systemImage: "waveform.path.ecg")
            }
            Button { openWorkspace() } label: {
                Label(personalText("Browse workspace folder", "تصفّح مجلد المشروع"), systemImage: "folder")
            }
        } label: {
            Image(systemName: "ellipsis").font(.subheadline.weight(.semibold)).foregroundStyle(LCPalette.green)
                .frame(width: 44, height: 34).background(LCPalette.updateBG, in: Capsule())
        }.accessibilityIdentifier("mirsa.project.more")
        return HStack {
            if rtlHeader { more; Spacer() } else { back; Spacer() }
            Text(personalText("Project details", "تفاصيل المشروع")).font(.headline)
            if rtlHeader { Spacer(); back } else { Spacer(); more }
        }
    }

    private var signButton: some View {
        Button {
            if signing.state?.projectID == app.id, signing.running { showInstallLog = true } else { sign() }
        } label: {
            HStack(spacing: 8) {
                if let state = signing.state, state.projectID == app.id, state.running {
                    ProgressView().tint(.white)
                    Text("\(Int(state.overallFraction * 100))% · " + personalText("Open log", "افتح السجل")).fontWeight(.semibold).monospacedDigit()
                } else {
                    if configBusy { ProgressView().tint(.white) } else { Image(systemName: "hammer.fill") }
                    Text(configOnly ? personalText("Export configuration only", "تصدير الإعدادات فقط") : personalText("Sign & Install", "توقيع وتثبيت")).fontWeight(.semibold)
                }
            }.foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 50)
                .background(LCPalette.signGreen, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mirsa.project.sign")
        .disabled(configBusy)
        .padding(.horizontal, 20).padding(.bottom, 8)
    }

    private var appCard: some View {
        HStack(alignment: .top, spacing: 14) {
            iconEditor(size: 72, radius: 16)
            appFields
        }.lcCard()
    }
    /// Project icon with the change menu (Photos / Files / use original).
    private func iconEditor(size: CGFloat, radius: CGFloat, border: Color? = nil, borderWidth: CGFloat = 1) -> some View {
        Group {
            if let preview = draft.iconPNG.flatMap({ UIImage(data: $0) }) ?? icon { Image(uiImage: preview).resizable().scaledToFill() }
            else { Image(systemName: "app.dashed").font(.title).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.08)) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(border, lineWidth: borderWidth)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Menu {
                    Button { pickingIconPhoto = true } label: {
                        Label(personalText("Photos", "الصور"), systemImage: "photo")
                    }
                    Button { pickingIcon = true } label: { Label(personalText("Files", "الملفات"), systemImage: "folder") }
                    if draft.iconPNG != nil {
                        Button(personalText("Use original icon", "رجّع الأيقونة الأصلية")) { draft.iconPNG = nil }
                    }
                } label: {
                    Image(systemName: "pencil").font(.caption.bold()).padding(7)
                        .background(.regularMaterial, in: Circle())
                }.accessibilityLabel(personalText("Change app icon", "تغيير أيقونة التطبيق"))
                    .disabled(busy)
            }
    }
    /// Name, bundle ID, version, workspace note and the extension info.
    private var appFields: AnyView {
        AnyView(
        VStack(alignment: .leading, spacing: 8) {
            field(personalText("Name", "الاسم"), $draft.name)
            field(personalText("Bundle ID", "معرّف التطبيق"), $draft.bundleID, mono: true)
            field(personalText("Version", "الإصدار"), $draft.version)
            field(personalText("Workspace note", "ملاحظة المشروع"), Binding(get: { draft.workspaceNote ?? "" }, set: { draft.workspaceNote = String($0.prefix(300)) }))
            HStack(spacing: 8) {
                chip("puzzlepiece.extension", extensionCountText)
                chip("arrow.triangle.branch", personalText("Main executable", "الملف الرئيسي"))
            }
            Text(tr("App extensions are parts already inside the app (widgets, share sheet…). They are not tweaks injected by Mirsa.", "إضافات التطبيق هي أجزاء موجودة أصلاً داخل التطبيق (ودجات، المشاركة…). مو إضافات حقنها Mirsa.", ckb: "پێوەکراوەکانی ئەپ ئەو بەشانەن کە پێشتر لەناو ئەپەکەدان (ویجێت، هاوبەشکردن…). ئەوە ئەو زیادکراوانە نین کە Mirsa تێیکردوون.", kmr: "Pêvekên sepanê beşên ku jixwe di nav sepanê de ne (widget, parvekirin…). Ew ne tweakên ku Mirsa danîne ne."))
                .font(.caption2).foregroundStyle(.secondary)
        }
            )
    }
    private var extensionCountText: String {
        extensionCount.map { "\($0) " + tr("app extensions", "إضافات تطبيق", ckb: "پێوەکراوەکانی ئەپ", kmr: "pêvekên sepanê") } ?? "…"
    }

    private func setProjectIcon(_ data: Data) throws {
        guard data.count <= 16 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= 16_777_216,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary),
              let png = UIImage(cgImage: thumbnail).pngData() else {
            throw SideloadError.message("Choose a valid image up to 4096 × 4096 pixels and 16 MB.")
        }
        draft.iconPNG = png
    }
    private func chip(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.caption2.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 4)
            .background(LCPalette.versionBG, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    private func field(_ title: String, _ binding: Binding<String>, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField(title, text: binding).font(mono ? .footnote.monospaced() : .subheadline)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(10).background(LCPalette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
    private var outputCard: some View {
        outputContent.lcCard()
    }
    /// Output file name + IPA/TIPA.
    private var outputContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(personalText("Output file name", "اسم ملف الإخراج"), systemImage: "doc.fill").font(.subheadline.weight(.semibold))
            HStack {
                TextField("Mirsa-Signed", text: $draft.outputFilename).autocorrectionDisabled().textInputAutocapitalization(.never)
            }.padding(12).background(LCPalette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Picker("", selection: Binding(get: { draft.exportExtension ?? "ipa" }, set: { draft.exportExtension = $0 })) {
                Text("IPA").tag("ipa"); Text("TIPA").tag("tipa")
            }.pickerStyle(.segmented)
        }
    }
    private var tweaksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(personalText("Injected tweaks", "الإضافات المحقونة"), systemImage: "puzzlepiece.extension.fill").font(.subheadline.weight(.semibold))
                Spacer()
                addTweakMenu { Label(personalText("Add", "إضافة"), systemImage: "plus") }
            }
            tweakNotices
            let comps = components()
            ForEach(Array(comps.enumerated()), id: \.element.id) { index, comp in
                HStack(spacing: 10) {
                    Button { removeComponent(comp) } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }.buttonStyle(.mirsaPress)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comp.title).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        if comp.subtitle != comp.title { Text(comp.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                        methodControls(comp)
                    }
                    Spacer()
                    ShareLink(item: comp.url) { Image(systemName: "square.and.arrow.up") }
                    Button { moveComponent(comp.id, -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                    Button { moveComponent(comp.id, 1) } label: { Image(systemName: "arrow.down") }.disabled(index == comps.count - 1)
                }.buttonStyle(.mirsaPress).padding(10).background(LCPalette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }.lcCard()
    }
    /// "Add" menu: import a file or pick one already in the tweak library.
    private func addTweakMenu<MenuLabel: View>(@ViewBuilder label: () -> MenuLabel) -> some View {
        Menu {
            Button { pickingTweak = true } label: { Label(personalText("Import file", "استيراد ملف"), systemImage: "folder") }
            let rest = tweaks.items.filter { !draft.tweakIDs.contains($0.id) }
            ForEach(rest) { item in
                Button(item.name) { draft.tweakIDs.append(item.id) }
            }
        } label: { label() }
    }
    /// Pending added/removed warning, already-present libraries and the empty hint.
    @ViewBuilder private var tweakNotices: some View {
        let ids = draft.tweakIDs.filter { tweak($0) != nil }
        let pending = pendingTweakChanges
        if pending.added + pending.removed > 0 {
            Label(MirsaTr.f("pending", pending.added, pending.removed), systemImage: "exclamationmark.circle.fill")
                .font(.caption).foregroundStyle(.yellow)
        }
        if !existingLibraries.isEmpty {
            ExistingLibrariesCard(libraries: existingLibraries, sourceIPA: library.url(app), edits: Binding(get: { draft.existingLibraryEdits ?? [] }, set: { draft.existingLibraryEdits = $0.isEmpty ? nil : $0 }))
                .padding(10).background(LCPalette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        if ids.isEmpty && existingLibraries.isEmpty {
            Text(tr("No additions. Import ZIP, .dylib, .deb or a .framework folder.", "ما في إضافات. ضيف ZIP أو dylib أو deb أو مجلد framework.", ckb: "زیادکراو نییە. ZIP، dylib، deb یان بوخچەی framework هاوردە بکە.", kmr: "Pêvek tune ne. ZIP, dylib, deb an peldanka framework bîne."))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    /// Selected packages not yet signed (added) and signed ones since removed.
    private var pendingTweakChanges: (added: Int, removed: Int) {
        let ids = draft.tweakIDs.filter { tweak($0) != nil }
        let applied = Set(draft.appliedTweakIDs ?? [])
        return (ids.filter { !applied.contains($0) }.count, applied.filter { !ids.contains($0) }.count)
    }
    struct TweakComponent { let id: String; let tweakID: UUID; let title: String; let subtitle: String; let url: URL }
    /// Every selected package expands to one component per dylib/framework root (stable id uuid:path).
    /// Order = persisted componentOrder (still valid) then new components in package order. Excluded ones are hidden.
    private func components() -> [TweakComponent] {
        let excluded = Set(draft.excludedRoots ?? [])
        var all: [TweakComponent] = []
        for id in draft.tweakIDs {
            guard let item = tweak(id) else { continue }
            for root in item.roots {
                let cid = IPATweakLibrary.componentID(item, root)
                if excluded.contains(cid) { continue }
                let url = IPATweakLibrary.root.appendingPathComponent(item.id.uuidString).appendingPathComponent(root)
                all.append(TweakComponent(id: cid, tweakID: id, title: (root as NSString).lastPathComponent, subtitle: item.name, url: url))
            }
        }
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let saved = (draft.componentOrder ?? []).compactMap { byID[$0] }
        let savedSet = Set(saved.map(\.id))
        var seen = Set<String>()
        return (saved + all.filter { !savedSet.contains($0.id) }).filter { seen.insert($0.id).inserted }
    }
    private func moveComponent(_ id: String, _ delta: Int) {
        var order = components().map(\.id)
        guard let i = order.firstIndex(of: id), order.indices.contains(i + delta) else { return }
        order.swapAt(i, i + delta)
        draft.componentOrder = order
    }
    private func removeComponent(_ comp: TweakComponent) {
        var list = draft.excludedRoots ?? []
        list.append(comp.id)
        draft.excludedRoots = list
        draft.componentOrder = (draft.componentOrder ?? []).filter { $0 != comp.id }
        if !components().contains(where: { $0.tweakID == comp.tweakID }) {
            draft.tweakIDs.removeAll { $0 == comp.tweakID }
            draft.excludedRoots = (draft.excludedRoots ?? []).filter { !$0.hasPrefix(comp.tweakID.uuidString + ":") }
        }
    }
    @State private var bundleManager: BundleFileManager?
    @State private var bundleLoading = false
    private var bundleDirs: (original: URL, staging: URL) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MirsaBundleFiles/\(app.id.uuidString)", isDirectory: true)
        return (base.appendingPathComponent("original", isDirectory: true), base.appendingPathComponent("staging", isDirectory: true))
    }
    /// Extracts the project's IPA once (original stays untouched) and opens the staged file manager.
    private func openBundleFiles() {
        guard !bundleLoading else { return }
        bundleLoading = true
        let input = library.url(app); let dirs = bundleDirs; let overlay = draft.bundleOverlay ?? BundleOverlay()
        Task {
            let result: BundleFileManager? = await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                do {
                    if !fm.fileExists(atPath: dirs.original.path) {
                        let tmp = dirs.original.deletingLastPathComponent().appendingPathComponent("extract-\(UUID().uuidString)", isDirectory: true)
                        try fm.createDirectory(at: tmp.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try IPAEditorService.run("extract", input: input, output: tmp)
                        try fm.moveItem(at: try IPAEditorService.app(in: tmp), to: dirs.original)
                        try? fm.removeItem(at: tmp)
                    }
                    try fm.createDirectory(at: dirs.staging, withIntermediateDirectories: true)
                    return try BundleFileManager(root: dirs.original, stagingDirectory: dirs.staging, overlay: overlay)
                } catch { return nil }
            }.value
            bundleLoading = false
            if let result { bundleManager = result } else { message = personalText("Could not read the app files.", "ما قدرت أقرأ ملفات التطبيق.") }
        }
    }
    private func reloadButton() -> some View {
        Button { loadTargets() } label: {
            Label(targetsLoading ? tr("Reading app…", "عم أقرأ التطبيق…", ckb: "ئەپەکە دەخوێنرێتەوە…", kmr: "Sepan tê xwendin…") : tr("Reload targets", "إعادة تحميل الأهداف", ckb: "دووبارە بارکردنی ئامانجەکان", kmr: "Armancan ji nû ve bar bike"), systemImage: "arrow.clockwise")
        }.disabled(targetsLoading)
    }
    @ViewBuilder private func methodControls(_ comp: TweakComponent) -> some View {
        let current = InjectionMethodStore.method(for: comp.id, methods: draft.injectionMethods, legacyDirect: draft.directInjection)
        let configured = InjectionMethodStore.isConfigured(comp.id, methods: draft.injectionMethods)
        let cc = injectionCaps.component(comp.id)
        Menu {
            // Reload is always available: it is the only way to clear stale capabilities.
            reloadButton()
            ForEach(InjectionMethod.allCases, id: \.self) { m in
                Button {
                    var d = draft.injectionMethods ?? [:]; d[comp.id] = m.rawValue; draft.injectionMethods = d
                } label: { Label(m.title, systemImage: m == current ? "checkmark" : "circle") }
                .disabled(!injectionCaps.isEnabled(m, component: comp.id))
            }
        } label: {
            Text((current?.title ?? tr("Invalid saved method. Pick again.", "طريقة محفوظة غير صالحة. اختار من جديد.", ckb: "ڕێگای پاشەکەوتکراو نادروستە. دووبارە هەڵبژێرە.", kmr: "Rêbaza tomarkirî nederbasdar e. Dîsa hilbijêre.")) + " ▾").font(.caption2).foregroundStyle(.secondary)
        }
        if let current {
            Text(configured ? current.explanation : tr("Default. Pick a method to configure this tweak.", "الافتراضي. اختار طريقة لتضبط هالإضافة.", ckb: "بنەڕەت. ڕێگایەک هەڵبژێرە بۆ ڕێکخستن.", kmr: "Bingeh. Rêbazekê hilbijêre da ku mîheng bike."))
                .font(.caption2).foregroundStyle(.secondary)
            // Show why a method is unavailable whether or not it was configured, once this component was inspected.
            if cc != nil || configured, let reason = injectionCaps.disabledReason(current, component: comp.id), configured || cc != nil {
                Text(reason).font(.caption2).foregroundStyle(.orange)
            }
            switch current {
            case .direct: targetMenu(comp)
            case .load_control: targetMenu(comp, method: .load_control)
            case .separate_extension: extensionPicker(comp)
            case .shared_library: sharedPicker(comp)
            }
        } else if let raw = draft.injectionMethods?[comp.id] {
            Text(tr("Unknown saved method \"", "طريقة محفوظة غير معروفة \"", ckb: "ڕێگای پاشەکەوتکراوی نەناسراو \"", kmr: "Rêbaza tomarkirî ya nenas \"") + raw + "\"")
                .font(.caption2).foregroundStyle(.orange)
        }
    }
    @ViewBuilder private func extensionPicker(_ comp: TweakComponent) -> some View {
        let picked = Set(draft.injectionProcessTargets?[comp.id] ?? [])
        let cc = injectionCaps.component(comp.id)
        let extensionIDs = cc?.eligible(.separate_extension) ?? []
        let optionalMain = injectionCaps.mainTarget.map { main in (cc?.eligible(.direct).contains(main.id) == true) ? [main.id] : [] } ?? []
        let eligible = optionalMain + extensionIDs
        Menu {
            ForEach(eligible, id: \.self) { id in
                Button {
                    var all = draft.injectionProcessTargets ?? [:]
                    var cur = all[comp.id] ?? []
                    if let i = cur.firstIndex(of: id) { cur.remove(at: i) } else { cur.append(id) }
                    all[comp.id] = cur.isEmpty ? nil : cur
                    draft.injectionProcessTargets = all.isEmpty ? nil : all
                } label: { Label(injectionCaps.label(id), systemImage: picked.contains(id) ? "checkmark.square" : "square") }
            }
        } label: {
            Text(tr("Extensions: ", "الامتدادات: ", ckb: "پێوەکراوەکان: ", kmr: "Pêvek: ") + (picked.isEmpty ? tr("none selected", "ما اخترت", ckb: "هیچ نەهەڵبژێردراوە", kmr: "tu nehatine hilbijartin") : "\(picked.count)") + " ▾").font(.caption2).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func sharedPicker(_ comp: TweakComponent) -> some View {
        let current = draft.injectionSharedTargets?[comp.id]
        let list = injectionCaps.component(comp.id)?.sharedCandidates ?? []
        let matches = list.filter { $0.selectionID == current || $0.id == current }
        let candidate = matches.count == 1 ? matches.first : nil
        Menu {
            ForEach(list, id: \.selectionID) { c in
                Button {
                    var all = draft.injectionSharedTargets ?? [:]; all[comp.id] = c.selectionID; draft.injectionSharedTargets = all
                } label: { Label(c.label + " (" + c.processes.map { injectionCaps.label($0) }.joined(separator: ", ") + ")", systemImage: c.selectionID == candidate?.selectionID ? "checkmark" : "circle") }
            }
        } label: {
            Text(tr("Shared library: ", "المكتبة المشتركة: ", ckb: "کتێبخانەی هاوبەش: ", kmr: "Pirtûkxaneya parvekirî: ") + (candidate?.label ?? tr("none selected", "ما اخترت", ckb: "هیچ نەهەڵبژێردراوە", kmr: "tu nehatine hilbijartin")) + " ▾").font(.caption2).foregroundStyle(.secondary)
        }
        if let candidate {
            Text(tr("Processes: ", "العمليات: ", ckb: "پرۆسەکان: ", kmr: "Pêvajo: ") + candidate.processes.map { injectionCaps.label($0) }.joined(separator: ", "))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func mainTarget() -> String? { targetList.first { $0.kind == "main" }?.id ?? injectionCaps.mainTarget?.id }
    @ViewBuilder private func targetMenu(_ comp: TweakComponent, method: InjectionMethod = .direct) -> some View {
        let current = draft.tweakTargets?[comp.id]
        let valid = Set(injectionCaps.component(comp.id)?.eligible(method) ?? [])
        let shown = targetList.first { $0.id == current }?.label ?? tr("Main app", "التطبيق الرئيسي", ckb: "ئەپی سەرەکی", kmr: "Sepana sereke")
        Menu {
            reloadButton()
            // Only targets the backend probed as valid for THIS component; stale or unknown ids never appear.
            ForEach(targetList.filter { valid.contains($0.id) }, id: \.id) { t in
                Button { setTarget(comp.id, t) } label: {
                    Label(t.label + " (" + t.kind + ")", systemImage: (current == t.id || (current == nil && t.kind == "main")) ? "checkmark" : "circle")
                }
            }
        } label: { Text(tr("Target: ", "الهدف: ", ckb: "ئامانج: ", kmr: "Armanc: ") + shown + " ▾").font(.caption2).foregroundStyle(.secondary) }
    }
    private func setTarget(_ cid: String, _ t: (id: String, kind: String, label: String)) {
        var m = draft.tweakTargets ?? [:]
        if t.kind == "main" { m.removeValue(forKey: cid) } else { m[cid] = t.id }
        draft.tweakTargets = m
    }
    private func loadTargets() {
        guard !targetsLoading else { return }
        targetsLoading = true
        // Drop old capabilities first so stale ones can never be used while re-inspecting.
        injectionCaps = InjectionCapabilities()
        let input = library.url(app)
        let comps = components()
        Task {
            let loaded: ([(id: String, kind: String, label: String)], InjectionCapabilities)? = await Task.detached(priority: .userInitiated) {
                let stage = FileManager.default.temporaryDirectory.appendingPathComponent("targets-\(UUID().uuidString)", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: stage) }
                do {
                    try IPAEditorService.run("extract", input: input, output: stage)
                    let app = try IPAEditorService.app(in: stage)
                    let list = try IPAEditorService.targets(app: app, scratch: stage)
                    guard let main = list.first(where: { $0.kind == "main" })?.id else { return nil }
                    // Backend probes each component with its own library; method here is only a placeholder it overrides.
                    let entries = comps.map { InjectionPlanEntry(id: $0.id, library: $0.url.path, target: main, method: .direct) }
                    let caps = try IPAEditorService.injectionCapabilities(app: app, scratch: stage, entries: entries)
                    return (list, caps)
                } catch { return nil }
            }.value
            targetsLoading = false
            if let loaded { targetList = loaded.0; injectionCaps = loaded.1 }
            else { message = tr("Could not read the app targets.", "ما قدرت أقرأ أهداف التطبيق.", ckb: "نەتوانرا ئامانجەکانی ئەپ بخوێندرێتەوە.", kmr: "Armancên sepanê nehatin xwendin.") }
        }
    }
    private var loaderOn: Bool { draft.directInjection == false }
    /// Backend-reported capabilities per component, from a clean extraction. Empty until loaded (fail closed).
    @State private var injectionCaps = InjectionCapabilities()
    @State private var targetList: [(id: String, kind: String, label: String)] = []
    @State private var targetsLoading = false
    private var settingsCard: some View {
        settingsContent.lcCard()
    }
    /// Every project setting toggle, game mode, minimum iOS and custom entitlements.
    private var settingsContent: AnyView {
        AnyView(
        VStack(alignment: .leading, spacing: 12) {
            Label(personalText("Project settings", "إعدادات المشروع"), systemImage: "gearshape.fill").font(.subheadline.weight(.semibold))
            toggle(personalText("Enable Files access", "تمكين الوصول إلى الملفات"), personalText("Shows app documents in Files.", "بيظهر ملفات التطبيق بتطبيق الملفات."), $draft.fileSharing)
            toggle(personalText("Remove URL schemes", "إزالة مخططات URL"), personalText("Deletes the app's custom URL schemes.", "بيحذف مخططات URL تبع التطبيق."), $draft.removeURLSchemes)
            toggle(PersonalProfileOmissionText.title(AppLanguageStore.snapshot), PersonalProfileOmissionText.subtitle(AppLanguageStore.snapshot), $draft.removeEmbeddedProfile)
            toggle(personalText("Remove extensions", "إزالة الإضافات المضمّنة"), personalText("Removes PlugIns before signing.", "بيحذف مجلد PlugIns قبل التوقيع."), Binding(get: { draft.removeExtensions ?? false }, set: { draft.removeExtensions = $0 }))
            toggle(personalText("Remove App Clips", "إزالة App Clips"), personalText("Removes AppClips before signing.", "بيحذف مجلد AppClips قبل التوقيع."), Binding(get: { draft.removeAppClips ?? false }, set: { draft.removeAppClips = $0 }))
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(get: { draft.translateArabic ?? false }, set: { draft.translateArabic = $0 })) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "globe").foregroundStyle(LCPalette.green)
                        Text(ArabicTranslateText.rowTitle).font(.subheadline)
                    }
                }.tint(LCPalette.green).accessibilityIdentifier("project-sign-translate-ar")
                VStack(alignment: .leading, spacing: 2) {
                    Text(personalText("Some texts need internet to translate", "بعض النصوص بتحتاج إنترنت لتترجم")).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("project-sign-translate-ar-hint")
                    Text(personalText("Encrypted apps, games and text inside images are not translated", "التطبيقات المشفّرة والألعاب والنصوص اللي بالصور ما بتتعرّب")).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("project-sign-translate-ar-hint2")
                    Text(personalText("If on, UI text missing a translation is sent for translation. The original stays unchanged; re-sign with it off to disable.", "إذا شغّلته، نص الواجهة يلي ما إلو ترجمة بينبعت للترجمة. الأصل بيضل متل ما هو، ووقّع من جديد وهو طافي لتعطّله.")).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("project-sign-translate-ar-consent")
                    RuntimeStagingImportRow()
                }.padding(.leading, 32).frame(maxWidth: .infinity, alignment: .leading)
            }
            toggle(personalText("Strict profile match", "مطابقة صارمة للبروفايل"), personalText("Off: the app keeps its own ID and is signed with your selected profile (compatibility, install not guaranteed). On: reject apps the profile does not cover.", "طافي: التطبيق بيحافظ على معرّفه وبينوقّع ببروفايلك المختار (توافق، التثبيت مو مضمون). شغّال: بيرفض التطبيقات يلي البروفايل ما بيغطيها."), Binding(get: { draft.strictProfile ?? false }, set: { draft.strictProfile = $0 }))
            toggle(personalText("Remove Watch app", "إزالة تطبيق الساعة"), personalText("Deletes the Watch folder before signing.", "بيحذف مجلد الساعة قبل التوقيع."), $draft.removeWatchApp)
            toggle(personalText("Fix white/blank icon", "إصلاح الأيقونة البيضاء"), personalText("Flattens transparent icon PNGs onto black.", "بيحوّل أيقونات PNG الشفافة لخلفية سودا."), Binding(get: { draft.fixWhiteIcon ?? false }, set: { draft.fixWhiteIcon = $0 }))
            toggle(personalText("Fix dark icon (iOS 18)", "إصلاح الأيقونة الداكنة (iOS 18)"), personalText("Removes primary dark icon renditions only when a matching default exists. Other assets stay intact.", "بيشيل نسخة الأيقونة الداكنة إذا إلها نسخة افتراضية مطابقة. باقي صور التطبيق بتضل."), Binding(get: { draft.fixDarkIcon ?? false }, set: { draft.fixDarkIcon = $0 }))
            toggle(personalText("Direct injection (main executable)", "حقن مباشر بالملف الرئيسي"), personalText("Off uses LoadControl (arm64 only).", "إذا طفيته بيستخدم LoadControl (arm64 بس)."), Binding(get: { !loaderOn }, set: { draft.directInjection = $0 }))
            toggle(personalText("New tweaks first", "الإضافات الجديدة أولاً"), personalText("Injected libraries load before the app's own.", "المكتبات المحقونة بتتحمّل قبل مكتبات التطبيق."), Binding(get: { draft.newTweaksFirst ?? false }, set: { draft.newTweaksFirst = $0 }))
            HStack {
                Text(personalText("Game Mode", "وضع الألعاب")).font(.subheadline)
                Spacer()
                Picker("", selection: Binding(get: { draft.gameMode ?? .keep }, set: { draft.gameMode = $0 })) {
                    Text(personalText("Keep", "إبقاء")).tag(PersonalGameMode.keep)
                    Text(personalText("On", "تشغيل")).tag(PersonalGameMode.on)
                    Text(personalText("Off", "إيقاف")).tag(PersonalGameMode.off)
                }.pickerStyle(.menu)
            }
            HStack {
                Text(personalText("Minimum iOS", "أدنى إصدار iOS")).font(.subheadline)
                Spacer()
                Picker("", selection: $draft.minimumOS) {
                    Text(personalText("Keep", "إبقاء")).tag("")
                    ForEach(["12.0", "13.0", "14.0", "15.0", "16.0", "17.0", "18.0"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(personalText("Custom entitlements", "Entitlements مخصّصة")).font(.subheadline)
                    Text(draft.customEntitlementsName ?? personalText("None. Still limited by the profile.", "ما في. وبتبقى محدودة بالبروفايل.")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if draft.customEntitlements != nil {
                    Button { draft.customEntitlements = nil; draft.customEntitlementsName = nil } label: { Image(systemName: "trash") }
                }
                Button { pickingEntitlements = true } label: { Image(systemName: "square.and.arrow.down") }
            }.buttonStyle(.mirsaPress)
        }
            )
    }
    private func toggle(_ title: String, _ sub: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
        }.tint(LCPalette.green)
    }
    private var depsCard: some View {
        depsContent.lcCard()
    }
    /// Main binary dependencies (collapsible).
    private var depsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.25)) { showDeps.toggle() } } label: {
                HStack {
                    Label(personalText("Main binary dependencies", "اعتماديات الملف الرئيسي"), systemImage: "link").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(deps.map { "\($0.count)" } ?? "…").foregroundStyle(.secondary)
                    Image(systemName: showDeps ? "chevron.up" : "chevron.down")
                }
            }.buttonStyle(.mirsaPress)
            if showDeps { LazyVStack(alignment: .leading, spacing: 8) { ForEach(deps ?? [], id: \.self) { Text($0).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2) } } }
        }
    }
    private var projectSources: [ProjectBrowserSource] {
        var result: [ProjectBrowserSource] = []
        func add(_ title: String, _ url: URL) {
            let root = url.deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: url.path),
                  (try? PersonalProjectFolder.validated(url, in: root)) != nil else { return }
            result.append(ProjectBrowserSource(title: title, url: url))
        }
        add(MirsaTr.lit("Original IPA"), library.url(app))
        add(MirsaTr.lit("Project configuration"), library.draftURL(app))
        add(MirsaTr.lit("Project icon"), library.iconURL(app))
        add(MirsaTr.lit("Extracted app"), bundleDirs.original)
        add(MirsaTr.lit("Staged changes"), bundleDirs.staging)
        for id in draft.tweakIDs {
            if let item = tweak(id) {
                add(item.name, IPATweakLibrary.root.appendingPathComponent(id.uuidString))
            }
        }
        let signedBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MirsaSignedExports")
        if let relative = UserDefaults.standard.string(forKey: "mirsa.project.signed." + app.id.uuidString),
           let signed = try? PersonalProjectFolder.validated(signedBase.appendingPathComponent(relative), in: signedBase) {
            add(MirsaTr.lit("Signed IPA"), signed)
        }
        if let output { add(MirsaTr.lit("Exported IPA"), output) }
        if let state = signing.state, state.projectID == app.id, let file = state.result?.url {
            add(MirsaTr.lit("Signed IPA"), file)
        }
        return result
    }
    private func openWorkspace() {
        draftWriter.flush()
        // Logical view of existing project files. Browsing never creates or migrates an empty UUID folder.
        workspace = ProjectFolderLocation(url: library.url(app).deletingLastPathComponent())
    }
    private func inspect() async {
        let input = library.url(app)
        let result = await PersonalProjectInspection.shared.inspect(input)
        guard !Task.isCancelled else { return }
        extensionCount = result?.extensions ?? 0
        deps = result?.dependencies ?? []
        existingLibraries = result?.existingLibraries ?? []
    }

    private var certificateCard: some View {
        certificateContent.lcCard()
    }
    /// Certificate selection, warnings, expiry, nested profiles, choose and manage.
    private var certificateContent: AnyView {
        AnyView(
        VStack(alignment: .leading, spacing: 10) {
            Label(personalText("Signing certificate", "شهادة التوقيع"), systemImage: "key.fill").font(.subheadline.weight(.semibold))
            if let selected {
                Text(selected.name).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                if !selected.verification.isVerified {
                    Label(selected.verification.warningText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Text("Team ID: " + selected.teamID).font(.caption).foregroundStyle(.secondary)
                if let expiry = selected.expiry {
                    Text(personalText("Local expiry date: ", "تاريخ الانتهاء المحلي: ") + expiry.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(personalText("No saved certificate yet.", "ما في شهادة محفوظة.")).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(identities.filter { $0.id != selected?.id }) { identity in
                Toggle(isOn: Binding(get: { (draft.additionalProfileIDs ?? []).contains(identity.id) }, set: { enabled in
                    var ids = draft.additionalProfileIDs ?? []
                    ids.removeAll { $0 == identity.id }
                    if enabled { ids.append(identity.id) }
                    draft.additionalProfileIDs = ids
                })) {
                    Text(personalText("Nested profile", "بروفايل للتطبيقات المضمّنة") + " · " + identity.name).font(.caption)
                }
            }
            if identities.count > 1 {
                Menu {
                    ForEach(identities) { i in Button(i.name + " · " + i.teamID) { try? PersonalIdentityVault.select(i.id); reloadIdentities() } }
                } label: { Label(personalText("Choose certificate", "اختيار الشهادة"), systemImage: "checkmark.seal") }
            }
            if selected == nil {
                Label(personalText("No certificate: export will apply the configuration only and the IPA stays UNSIGNED.", "بدون شهادة: التصدير بيطبّق الإعدادات بس والـ IPA بيضل غير موقّع."), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            Button { showCertificates = true } label: {
                Label(personalText("Manage certificates", "إدارة الشهادات"), systemImage: "slider.horizontal.3")
            }
        }
            )
    }

    private func load() async {
        reloadIdentities()
        icon = library.icon(for: app)
        if let refreshed = await library.ensureIcon(for: app) { icon = refreshed }
        var d = PersonalProjectDraft(name: app.name, bundleID: app.bundleID, version: app.version,
                                     outputFilename: app.name.replacingOccurrences(of: "/", with: "-") + "-signed")
        if let data = try? Data(contentsOf: library.draftURL(app)),
           let saved = try? JSONDecoder().decode(PersonalProjectDraft.self, from: data) { d = saved }
        #if DEBUG
        if MirsaUITestHarness.active && ProcessInfo.processInfo.arguments.contains("-MirsaProjectThemesFixture") {
            d.tweakIDs = [tweaks.projectThemesScreenshotFixture()]
            // Inert presentation-only identity: never stored in the vault or used to sign.
            let fixture = PersonalIdentityVault.SavedIdentity(
                id: "project-theme-ui", material: .init(p12: Data(), password: "", profile: Data()),
                name: "Mirsa UI Certificate", teamID: "UITESTONLY", bundleID: "*",
                expiry: Date().addingTimeInterval(30 * 86_400), profileType: "Development",
                verification: .unknown, entitlements: [:], devices: [])
            identities = [fixture]
            selectedID = fixture.id
        }
        #endif
        draftDestination = library.draftURL(app)
        draft = d; loaded = true
        #if DEBUG
        if MirsaUITestHarness.active && ProcessInfo.processInfo.arguments.contains("-MirsaRuntimeEncryptedFixture") {
            message = RuntimeArabicPipeline.encryptedFixtureNotice()
        }
        #endif
    }
    private func reloadIdentities() {
        do {
            identities = try PersonalIdentityVault.savedIdentities()
            selectedID = try PersonalIdentityVault.selectedID()
        } catch { message = error.localizedDescription }
    }
    private func cleanOutput() {
        if let output, output != signing.state?.result?.url { MirsaManagedTmp.end(output.deletingLastPathComponent()) }
        output = nil
    }

    private func sign() {
        draftWriter.flush()
        let material = selected?.material
        cleanOutput(); message = nil
        var options = PersonalProjectOptions()
        options.displayName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        options.bundleID = draft.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        options.version = draft.version.trimmingCharacters(in: .whitespacesAndNewlines)
        options.outputFilename = draft.outputFilename
        options.fileSharing = draft.fileSharing
        options.removeURLSchemes = draft.removeURLSchemes
        options.removeEmbeddedProfile = draft.removeEmbeddedProfile
        options.removeWatchApp = draft.removeWatchApp
        options.removeExtensions = draft.removeExtensions ?? false
        options.removeAppClips = draft.removeAppClips ?? false
        options.translateToArabic = draft.translateArabic ?? false
        options.strictProfile = draft.strictProfile ?? false
        options.gameMode = draft.gameMode ?? .keep
        options.fixDarkIcon = draft.fixDarkIcon ?? false
        options.fixWhiteIcon = draft.fixWhiteIcon ?? false
        options.newTweaksFirst = draft.newTweaksFirst ?? false
        options.useLoader = (draft.injectionMethods ?? [:]).isEmpty && draft.directInjection == false
        options.existingLibraryEdits = draft.existingLibraryEdits ?? []
        options.iconPNG = draft.iconPNG
        options.customEntitlements = draft.customEntitlements
        options.exportExtension = draft.exportExtension ?? "ipa"
        options.additionalProfiles = identities.filter { (draft.additionalProfileIDs ?? []).contains($0.id) }.map { $0.material.profile }
        let minimum = draft.minimumOS.trimmingCharacters(in: .whitespacesAndNewlines)
        options.minimumOS = minimum.isEmpty ? nil : minimum
        do {
            if let overlay = draft.bundleOverlay, !overlay.isEmpty {
                options.bundleOverlay = overlay; options.bundleBlobs = bundleDirs.staging; options.bundleOriginal = bundleDirs.original
            }
            let comps = components()
            options.libraries = comps.map(\.url)
            let targets = draft.tweakTargets ?? [:]
            let methods = draft.injectionMethods ?? [:]
            if comps.contains(where: { targets[$0.id] != nil || methods[$0.id] != nil }) {
                guard injectionCaps.mainTarget != nil else { message = personalText("Load targets first.", "حمّل الأهداف أولاً."); return }
                do {
                    options.injections = try comps.map { c in
                        try InjectionMethodStore.entry(id: c.id, library: c.url.path, tweakTarget: targets[c.id], methods: draft.injectionMethods, legacyDirect: draft.directInjection,
                                                       processTargets: draft.injectionProcessTargets, sharedTargets: draft.injectionSharedTargets, caps: injectionCaps)
                    }
                } catch {
                    message = tr("An injection choice is missing, unsupported or outdated. Reload targets and pick the method again.", "في اختيار حقن ناقص أو مو مدعوم أو قديم. أعد تحميل الأهداف واختار الطريقة مرة تانية.", ckb: "هەڵبژاردنێکی تێخستن کەمە، پشتگیری ناکرێت یان کۆنە. ئامانجەکان دووبارە بار بکە و ڕێگا هەڵبژێرە.", kmr: "Hilbijartineke derzîkirinê kêm e, nayê piştgirîkirin an kevn e. Armancan ji nû ve bar bike û rêbazê dîsa hilbijêre.")
                    return
                }
                options.injectionOrder = comps.map(\.id)
            }
        } catch { message = error.localizedDescription; return }
        let input = library.url(app)
        let signingOptions = options
        if let material {
            showInstallLog = true
            signing.start(projectID: app.id, title: app.name, input: input, material: material,
                          pairingPath: PairingController.pairingFilePath(), options: signingOptions)
            return
        }
        configBusy = true
        Task {
            do {
                output = try await Task.detached(priority: .userInitiated) {
                    try PersonalCertificateSigner.exportConfigurationOnly(ipa: input, options: signingOptions)
                }.value
                draft.appliedTweakIDs = draft.tweakIDs
                message = personalText("Configuration applied. This IPA is NOT signed.", "انطبقت الإعدادات. هاد الـ IPA غير موقّع.")
                if let notice = ArabicLocalizationPipeline.lastNotice { message = (message ?? "") + "\n" + notice }
                sharing = true
            } catch { message = error.localizedDescription }
            configBusy = false
        }
    }

    private func consumeSigningResult() {
        guard let state = signing.state, state.projectID == app.id, !state.running,
              consumedResult != state.id else { return }
        consumedResult = state.id
        guard state.shouldPresentResultAlert else {
            // Opening itms-services is a system handoff, never verified installation.
            // Keep this inline in the bottom bar instead of showing a success/failure modal.
            resultAlert = nil
            message = ArabicLocalizationPipeline.lastNotice
            return
        }
        guard let result = state.result else {
            let text = state.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            message = (text?.isEmpty == false) ? text : personalText("Signing stopped before it finished. Try again.", "توقف التوقيع قبل ما يكتمل. جرّب من جديد.")
            resultAlert = message; return
        }
        output = result.url
        draft.appliedTweakIDs = draft.tweakIDs
        if result.installed { message = personalText("Signed and installed.", "تم التوقيع والتثبيت.") }
        else {
            message = personalText("Signed locally but install failed: ", "تم التوقيع بس التثبيت فشل: ") + (result.installError ?? "")
                + "\n" + personalText("The signed IPA was kept for sharing.", "الـ IPA الموقّع انحفظ للمشاركة.")
        }
        if result.bundleIdentifierChanged { message = (message ?? "") + "\nتم تغيير المعرّف ليطابق البروفايل" }
        if !result.verification.isVerified { message = (message ?? "") + "\n" + result.verification.warningText }
        if let notice = ArabicLocalizationPipeline.lastNotice { message = (message ?? "") + "\n" + notice }
        sharing = !result.installed
        resultAlert = message
    }
}
