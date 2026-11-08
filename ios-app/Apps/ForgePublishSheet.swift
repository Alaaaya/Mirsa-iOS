import SwiftUI
import UniformTypeIdentifiers

/// Pre-publication sheet: editable name, target app, short description; optional uploaded .dylib/.deb. Always LTR.
struct ForgePublishSheet: View {
    let id: UUID
    var onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ForgeStore.shared
    @ObservedObject private var library = PersonalAppsLibrary.shared
    @State private var name = ""
    @State private var what = ""
    @State private var targetBundleID = ""
    @State private var uploaded = false
    @State private var uploadURLText = ""
    @State private var importing = false
    @State private var uploadFile: URL?
    @State private var uploadInfo: ForgeDylibInfo?
    @State private var busy = false
    @State private var describing = false
    @State private var error: String?

    static var title: String { tr("Publish to community", "انشر للمجتمع", ckb: "بڵاوکردنەوە بۆ کۆمەڵگا", kmr: "Ji civakê re biweşîne") }
    private var project: ForgeProject? { store.project(id) }
    private var targetApp: PersonalLibraryApp? { library.apps.first { $0.bundleID == targetBundleID } }
    private var canPublish: Bool {
        !busy && !describing && !targetBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            && what.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 && (!uploaded || uploadFile != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        label(tr("Tweak name", "اسم التويك", ckb: "ناوی تویک", kmr: "Navê tweak"))
                        TextField("", text: $name).textFieldStyle(.plain).padding(10).background(Color.black.opacity(0.3)).cornerRadius(10)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        label(tr("Target app", "التطبيق المستهدف", ckb: "ئەپی ئامانج", kmr: "Sepana armanc"))
                        HStack(spacing: 10) {
                            Group {
                                if let app = targetApp, let icon = library.icon(for: app) { Image(uiImage: icon).resizable().scaledToFit() }
                                else { Image(systemName: "app.dashed") }
                            }.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading) {
                                Text(targetApp?.name ?? project?.appName ?? "")
                                Text(targetBundleID).font(.caption).foregroundStyle(.white.opacity(0.55))
                            }
                        }
                        if !library.apps.isEmpty {
                            Picker(tr("Choose target app", "اختار التطبيق المستهدف", ckb: "ئەپی ئامانج هەڵبژێرە", kmr: "Sepana armanc hilbijêre"), selection: $targetBundleID) {
                                if let project, !library.apps.contains(where: { $0.bundleID == project.bundleID }) { Text(project.appName).tag(project.bundleID) }
                                ForEach(library.apps) { app in Text(app.name).tag(app.bundleID) }
                            }.pickerStyle(.menu)
                        }
                        TextField("com.example.app", text: $targetBundleID).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(10).background(Color.black.opacity(0.3)).cornerRadius(10)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            label(tr("What it does", "شو بيعمل", ckb: "چی دەکات", kmr: "Çi dike"))
                            Spacer()
                            if describing { ProgressView() }
                        }
                        TextEditor(text: $what).frame(height: 90).scrollContentBackground(.hidden).padding(6).background(Color.black.opacity(0.3)).cornerRadius(10)
                            .onChange(of: what) { _, v in if v.count > 200 { what = String(v.prefix(200)) } }
                        Text(tr("Short and honest: only what this tweak really does.", "قصير وصادق: بس شو بيعمل التويك فعلاً.", ckb: "کورت و ڕاست: تەنها ئەوەی تویکەکە ڕاستەقینە دەیکات.", kmr: "Kurt û rast: tenê ya ku tweak bi rastî dike."))
                            .font(.caption).foregroundStyle(.white.opacity(0.55))
                    }
                    Divider()
                    Toggle(tr("Upload a .dylib or .deb instead", "ارفع ملف dylib أو deb بدل هالتويك", ckb: "فایلی dylib یان deb بار بکە", kmr: "Li şûna vê pelê dylib an deb bar bike"), isOn: $uploaded)
                    if uploaded { uploadSection }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Button { publish() } label: {
                        HStack { if busy { ProgressView() }; Text(Self.title).bold() }
                            .frame(maxWidth: .infinity).padding(12).background(MirsaPalette.accentGradient, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.mirsaPress).disabled(!canPublish).opacity(canPublish ? 1 : 0.4)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.9).ignoresSafeArea())
            .navigationTitle(Self.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal")) { dismiss() } } }
        }
        .foregroundStyle(.white).font(.subheadline)
        .environment(\.layoutDirection, .leftToRight)
        .onChange(of: uploaded) { _, _ in what = "" }
        .onDisappear { if let uploadFile { try? FileManager.default.removeItem(at: uploadFile) } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "dylib") ?? .data, UTType(filenameExtension: "deb") ?? .data, .data]) { result in
            guard case .success(let url) = result else { return }
            load { try await ForgeDylibImporter.fromFile(url) }
        }
        .task {
            guard let p = project, let v = p.currentVersion else { return }
            if name.isEmpty { name = p.name }
            if targetBundleID.isEmpty { targetBundleID = p.bundleID }
            if what.isEmpty {
                describing = true; defer { describing = false }
                let suggested = (try? await store.describeForPublish(id)) ?? String((v.title ?? v.prompt).prefix(120))
                if what.isEmpty && !uploaded { what = suggested }
            }
        }
    }

    private var uploadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Shown in the gallery as Uploaded, not server-built. The file is checked on-device and again on the server; nothing is executed.", "بتظهر بالمعرض كـ «مرفوع» مو مبني بالسيرفر. الملف بينفحص بالجهاز وبالسيرفر وما بينشغّل شي.", ckb: "لە گەلەری وەک «بارکراو» دەردەکەوێت، نەک دروستکراوی سێرڤەر. هیچ شتێک جێبەجێ ناکرێت.", kmr: "Di galeriyê de wekî «barkirî» tê nîşandan, ne çêkirina serverê. Tiştek nayê xebitandin."))
                .font(.caption).foregroundStyle(.white.opacity(0.6))
            Button { importing = true } label: { Label(tr("Choose from Files", "اختر من الملفات", ckb: "لە فایلەکان هەڵبژێرە", kmr: "Ji Pelan hilbijêre"), systemImage: "folder") }
            HStack {
                TextField("https://…", text: $uploadURLText).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .padding(10).background(Color.black.opacity(0.3)).cornerRadius(10)
                Button(tr("Fetch", "جلب", ckb: "هێنان", kmr: "Bîne")) { let t = uploadURLText; load { try await ForgeDylibImporter.fromURL(t) } }
                    .disabled(uploadURLText.isEmpty)
            }
            if let info = uploadInfo {
                Text("\(info.arch) · \(ByteCountFormatter.string(fromByteCount: Int64(info.size), countStyle: .file)) · \(info.classes.count) " + tr("classes", "كلاس", ckb: "کلاس", kmr: "class"))
                    .font(.caption).foregroundStyle(.green)
            }
        }
    }

    private func label(_ s: String) -> some View { Text(s).font(.caption.bold()).foregroundStyle(.white.opacity(0.7)) }

    private func load(_ work: @escaping () async throws -> (dylib: URL, info: ForgeDylibInfo)) {
        guard !busy else { return }; busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                if let old = uploadFile { try? FileManager.default.removeItem(at: old) }
                let r = try await work()
                guard r.info.size <= 4 * 1024 * 1024 else { try? FileManager.default.removeItem(at: r.dylib); throw ForgeDylibImportError.tooLarge }
                uploadFile = r.dylib; uploadInfo = r.info
            } catch { self.error = error.localizedDescription; uploadFile = nil; uploadInfo = nil }
        }
    }

    private func publish() {
        guard canPublish else { return }; busy = true; error = nil
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines), w = what.trimmingCharacters(in: .whitespacesAndNewlines)
        let file = uploaded ? uploadFile : nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try await store.publish(id, name: n, what: w, uploadedDylib: file, targetBundleID: targetBundleID.trimmingCharacters(in: .whitespacesAndNewlines))
                if let file { try? FileManager.default.removeItem(at: file) }
                onDone(tr("Published to the community.", "اننشر للمجتمع.", ckb: "بڵاوکرایەوە بۆ کۆمەڵگا.", kmr: "Ji civakê re hat weşandin."))
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

extension ForgeStore {
    /// AI-prefilled description grounded in the actual original request; nil on any failure so the caller falls back to the request text.
    func describeForPublish(_ id: UUID) async throws -> String? {
        guard let p = project(id), let v = p.currentVersion else { return nil }
        let out = try await ForgeClient.json(["action": "describe", "language": ForgeServerMessage.lang(), "name": p.name, "bundleID": p.bundleID, "prompt": String(v.prompt.prefix(1000)), "code": String(v.code.prefix(6000))])
        let d = (out["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return d.isEmpty ? nil : String(d.prefix(200))
    }
    func publish(_ id: UUID, name: String, what: String, uploadedDylib: URL?, targetBundleID: String? = nil) async throws {
        guard let p = project(id), let v = p.currentVersion else { return }
        var body: [String: Any] = ["action": "publish", "name": name, "bundleID": targetBundleID ?? p.bundleID, "description": what, "code": v.code,
            "settings": v.settings.map { ["key": $0.key, "title": $0.title, "default": $0.default] }]
        if let file = uploadedDylib {
            let data = try Data(contentsOf: file, options: [.mappedIfSafe])
            guard data.count <= 4 * 1024 * 1024 else { throw ForgeDylibImportError.tooLarge }
            body["upload"] = ["filename": "Community.dylib", "base64": data.base64EncodedString()]
            body["code"] = ""
        }
        _ = try await ForgeClient.json(body)
    }
}
