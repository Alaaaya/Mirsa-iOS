import SwiftUI

/// «Inject» on a Mirsa AI tweak file (.dylib/.deb/.zip). Client-only routing into
/// paths that already exist; nothing here talks to the server or loads the file.
enum ForgeChatInjectText {
    static var inject: String { tr("Inject", "حقن", ckb: "چەسپاندن", kmr: "Bixe") }
    static var title: String { tr("Inject tweak", "حقن التويك", ckb: "چەسپاندنی تویک", kmr: "Tweakê bixe") }
    static var container: String { tr("Inject into a container app", "حقن بتطبيق بالحاوية", ckb: "چەسپاندن لە ئەپێکی کۆنتەینەر", kmr: "Li sepaneke konteynerê bixe") }
    static var containerSub: String { tr("One app at a time. Mirsa opens that app's saved original IPA in the IPA editor with this tweak checked. Save the edits, then install to Container as usual.",
                                         "تطبيق واحد بكل مرة. مرسى بيفتح الـIPA الأصلي المحفوظ للتطبيق بمحرّر الـIPA والتويك محدّد. احفظ التعديلات وبعدين ثبّت بالحاوية متل العادة.",
                                         ckb: "هەر جارە یەک ئەپ. مرسا IPA ڕەسەنە پاشەکەوتکراوەکەی ئەو ئەپە لە دەستکاریکەری IPA دەکاتەوە و ئەم تویکە هەڵبژێردراوە. دەستکارییەکان پاشەکەوت بکە، پاشان وەک هەمیشە لە کۆنتەینەر دایبمەزرێنە.",
                                         kmr: "Her carê yek sepan. Mirsa IPAya orîjînal a tomarkirî ya wê sepanê di edîtora IPA de bi vê tweakê hilbijartî vedike. Guhertinan tomar bike, paşê wekî her car li Konteynerê saz bike.") }
    static var real: String { tr("Inject into a real app", "حقن بتطبيق حقيقي", ckb: "چەسپاندن لە ئەپێکی ڕاستەقینە", kmr: "Li sepaneke rastîn bixe") }
    static var realSub: String { tr("One app at a time. Mirsa opens that app's saved original IPA in the IPA editor with this tweak checked. Save the edits, then install as a real app as usual (Apple ID).",
                                    "تطبيق واحد بكل مرة. مرسى بيفتح الـIPA الأصلي المحفوظ للتطبيق بمحرّر الـIPA والتويك محدّد. احفظ التعديلات وبعدين ثبّت كتطبيق حقيقي متل العادة (Apple ID).",
                                    ckb: "هەر جارە یەک ئەپ. مرسا IPA ڕەسەنە پاشەکەوتکراوەکەی ئەو ئەپە لە دەستکاریکەری IPA دەکاتەوە و ئەم تویکە هەڵبژێردراوە. دەستکارییەکان پاشەکەوت بکە، پاشان وەک هەمیشە وەک ئەپی ڕاستەقینە دایبمەزرێنە (Apple ID).",
                                    kmr: "Her carê yek sepan. Mirsa IPAya orîjînal a tomarkirî ya wê sepanê di edîtora IPA de bi vê tweakê hilbijartî vedike. Guhertinan tomar bike, paşê wekî her car wekî sepaneke rastîn saz bike (Apple ID).") }
    static var certificate: String { tr("Inject into certificate apps", "حقن بتطبيقات الشهادة", ckb: "چەسپاندن لە ئەپەکانی بڕوانامە", kmr: "Li sepanên sertîfîkayê bixe") }
    static var certificateSub: String { tr("Pick one or more Certificate Library projects. The tweak is saved to each project only; sign and install from the project as usual.",
                                           "اختار مشروع أو أكتر من مكتبة الشهادة. التويك بينحفظ بكل مشروع بس، وبعدين وقّع وثبّت من المشروع متل العادة.",
                                           ckb: "یەک یان چەند پڕۆژەیەک لە کتێبخانەی بڕوانامە هەڵبژێرە. تویکەکە تەنیا لە هەر پڕۆژەیەک پاشەکەوت دەکرێت؛ پاشان وەک هەمیشە لە پڕۆژەکەوە واژۆ بکە و دایبمەزرێنە.",
                                           kmr: "Yek an çend projeyên Pirtûkxaneya sertîfîkayê hilbijêre. Tweak tenê di her projeyê de tê tomarkirin; paşê wekî her car ji projeyê îmze bike û saz bike.") }
    static var pickApp: String { tr("Choose one app", "اختار تطبيق واحد", ckb: "یەک ئەپ هەڵبژێرە", kmr: "Yek sepan hilbijêre") }
    static var noApps: String { tr("No apps of this type are installed yet.", "لسا ما في تطبيقات من هالنوع مثبّتة.", ckb: "هێشتا هیچ ئەپێکی ئەم جۆرە دانەمەزراوە.", kmr: "Hê sepaneke ji vî cureyî nehatiye sazkirin.") }
    static var noOriginal: String { tr("This app has no saved original IPA, so Mirsa can't inject into it. Import its IPA again, then try.",
                                       "هالتطبيق ما إلو IPA أصلي محفوظ، فمرسى ما بيقدر يحقن فيه. استورد الـIPA تبعو من جديد وبعدين جرّب.",
                                       ckb: "ئەم ئەپە IPAی ڕەسەنی پاشەکەوتکراوی نییە، بۆیە مرسا ناتوانێت تێیدا بچەسپێنێت. دووبارە IPAکەی هاوردە بکە، پاشان هەوڵ بدە.",
                                       kmr: "Ji vê sepanê re IPAya orîjînal a tomarkirî tune, ji ber vê Mirsa nikare tê de bixe. IPAya wê dîsa bîne, paşê biceribîne.") }
    static var busy: String { tr("Finish the current import first.", "خلّص الاستيراد الحالي أولاً.", ckb: "سەرەتا هاوردەکردنی ئێستا تەواو بکە.", kmr: "Pêşî importa niha biqedîne.") }
    static var noOriginalBadge: String { tr("No saved IPA", "ما في IPA محفوظ", ckb: "IPA پاشەکەوت نەکراوە", kmr: "IPA nehatiye tomarkirin") }
}

/// Artifacts with one of these extensions get «Inject» beside «Share».
enum ForgeChatTweakArtifact {
    static let extensions: Set<String> = ["dylib", "deb", "zip"]
    /// Prefer the artifact's own file name extension; fall back to its kind.
    static func fileExtension(_ a: ForgeChatArtifact) -> String? {
        if let n = a.name, let e = n.split(separator: ".").last.map({ String($0).lowercased() }), n.contains("."), extensions.contains(e) { return e }
        let k = a.kind.lowercased()
        return extensions.contains(k) ? k : nil
    }
}

enum ForgeChatInjectRoute: String, Identifiable { case container, real, certificate; var id: String { rawValue } }

struct ForgeChatInjectSheet: View {
    let file: URL
    /// Called once the sheet is gone. `keepFile` is true when another owner took the file.
    let close: (_ keepFile: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var route: ForgeChatInjectRoute?
    @State private var handedOff = false
    @State private var incomingIPA: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(file.lastPathComponent).font(.subheadline).textSelection(.enabled)
                    option(.container, "shippingbox.fill", ForgeChatInjectText.container, ForgeChatInjectText.containerSub)
                    option(.real, "app.badge.fill", ForgeChatInjectText.real, ForgeChatInjectText.realSub)
                    option(.certificate, "square.stack.3d.up.fill", ForgeChatInjectText.certificate, ForgeChatInjectText.certificateSub)
                }.padding(16)
            }
            .background(MirsaPalette.sheet)
            .navigationTitle(ForgeChatInjectText.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(OpenInAttachmentText.cancel) { dismiss() } } }
            .navigationDestination(item: Binding(get: { route == .certificate ? nil : route }, set: { route = $0 })) { r in
                ForgeChatInjectAppPicker(location: r == .container ? .container : .real, file: file) { ipa in
                    handedOff = false
                    incomingIPA = ipa
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark).environment(\.layoutDirection, .leftToRight)
        .onDisappear {
            close(handedOff)
            // The certificate path reuses the existing «Attach to project» sheet,
            // which snapshots the file itself and lists Certificate Library projects only.
            if handedOff { OpenInProjectCoordinator.shared.receive([file]) }
            // Posted only after this sheet is gone, so the root incoming-IPA sheet can present.
            // ContentView snapshots this URL before importing; the saved original stays untouched.
            if let ipa = incomingIPA { NotificationCenter.default.post(name: .mirsaIncomingIPA, object: ipa) }
        }
    }

    private func option(_ r: ForgeChatInjectRoute, _ icon: String, _ title: String, _ sub: String) -> some View {
        Button {
            if r == .certificate { handedOff = true; dismiss() } else { route = r }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.title3).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(sub).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).appsGlass(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mirsa.chat.inject." + r.rawValue)
    }
}

/// Single selection. The tweak goes into the tweak library, then the app's saved
/// original IPA goes through the normal incoming-IPA path (choice sheet → editor
/// with the tweak checked → normal install). The original file is never modified.
struct ForgeChatInjectAppPicker: View {
    let location: AppLocation
    let file: URL
    let done: (_ originalIPA: URL) -> Void
    @StateObject private var store = AppsStore.shared
    @StateObject private var tweaks = IPATweakLibrary.shared
    @State private var message: String?
    @State private var busy = false

    private var apps: [ManagedApp] { location == .container ? store.containerApps : store.realApps }
    private func hasOriginal(_ a: ManagedApp) -> Bool { FileManager.default.fileExists(atPath: AppsStore.originalIPA(a.id).path) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(location == .container ? ForgeChatInjectText.containerSub : ForgeChatInjectText.realSub)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let message { Text(message).foregroundStyle(.orange).accessibilityIdentifier("mirsa.chat.inject.error") }
                if apps.isEmpty { Text(ForgeChatInjectText.noApps) }
                ForEach(apps) { app in
                    Button { choose(app) } label: {
                        HStack(spacing: 12) {
                            Group {
                                if let icon = UIImage(contentsOfFile: AppsStore.iconURL(app.id).path) { Image(uiImage: icon).resizable().scaledToFill() }
                                else { Image(systemName: "app.dashed").resizable().scaledToFit().padding(10) }
                            }.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name).font(.headline)
                                Text(app.id).font(.caption).foregroundStyle(.secondary)
                                if !hasOriginal(app) { Text(ForgeChatInjectText.noOriginalBadge).font(.caption2).foregroundStyle(.orange) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).appsGlass(cornerRadius: 16)
                    }
                    .buttonStyle(.plain).disabled(busy)
                    .accessibilityIdentifier("mirsa.chat.inject.app." + app.id)
                }
                if busy { ProgressView() }
            }.padding(16)
        }
        .background(MirsaPalette.sheet)
        .navigationTitle(ForgeChatInjectText.pickApp).navigationBarTitleDisplayMode(.inline)
    }

    private func choose(_ app: ManagedApp) {
        message = nil
        // Clear message instead of a silent failure.
        guard hasOriginal(app) else { message = ForgeChatInjectText.noOriginal; return }
        guard store.busy == nil, store.pending == nil, !store.explicitIncomingInstall, !tweaks.importing else { message = ForgeChatInjectText.busy; return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let tweak = try await tweaks.addFile(file)
                store.injectTweakIDs = [tweak.id]
                done(AppsStore.originalIPA(app.id))
            } catch {
                store.injectTweakIDs = nil
                message = error.localizedDescription
            }
        }
    }
}
