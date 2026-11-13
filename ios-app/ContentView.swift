import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Shared helpers

func logLineColor(_ line: String) -> Color {
    if line.contains("✅") || line.contains("🎉") { return .green }
    if line.contains("❌") { return .red }
    if line.contains("⚠️") { return .orange }
    return .secondary
}

// MARK: - Share Sheet for Exporting .passthm

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Crypto Donation Row

struct CryptoDonationRow: View {
    let title: String
    let address: String
    let icon: String
    let iconColor: Color

    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.subheadline.bold())
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                Button {
                    UIPasteboard.general.string = address
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation {
                            isCopied = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc.fill")
                        Text(isCopied ? "Copied!" : "Copy")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(isCopied ? .green : .blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isCopied ? Color.green.opacity(0.12) : Color.blue.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            Text(address)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(12)
        .mirsaCard(radius: MirsaRadius.snap(12))
    }
}

// MARK: - Donate View

struct DonateView: View {
    var isPopup: Bool = false
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            // Creator Card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.pink)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Maksym Reva")
                                .font(.headline.bold())
                            Text("🇺🇦")
                                .font(.subheadline)
                        }
                        Text(tr("@mak5er • Lead & Core Developer","@mak5er • المطوّر الرئيسي",ckb:"@mak5er • گەشەپێدەری سەرەکی",kmr:"@mak5er • Pêşdebirê sereke"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // Social Links (Twitter & GitHub)
                HStack(spacing: 10) {
                    Link(destination: URL(string: "https://x.com/mak5er")!) {
                        HStack(spacing: 5) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                            Text("Twitter / X")
                        }
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Link(destination: URL(string: "https://github.com/mak5er")!) {
                        HStack(spacing: 5) {
                            Image(systemName: "link")
                            Text("GitHub")
                        }
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.08))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(14)
            .mirsaCard(radius: MirsaRadius.snap(14))

            // Payment Methods
            VStack(alignment: .leading, spacing: 10) {
                Text(MirsaTr.lit("Donate & Support"))
                    .font(.caption.bold().uppercaseSmallCaps())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                // PayPal Button
                Link(destination: URL(string: "https://www.paypal.com/donate/?hosted_button_id=98QRTC2HFRA4Y")!) {
                    HStack(spacing: 10) {
                        Image(systemName: "creditcard.fill")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(MirsaTr.lit("Donate with PayPal"))
                                .font(.subheadline.bold())
                            Text(MirsaTr.lit("Recipient: Maksym Reva"))
                                .font(.caption2)
                                .opacity(0.85)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.subheadline)
                    }
                    .padding(MirsaSpacing.card)
                    .foregroundStyle(.white)
                    .background(MirsaPalette.accentGradient, in: RoundedRectangle(cornerRadius: MirsaRadius.m, style: .continuous))
                }

                // TON
                CryptoDonationRow(
                    title: "💎 TON (The Open Network)",
                    address: "UQBm9KPhtMw-XVVjirUoa09wzrlyWsbeZhKfefl1Uw-qNZ-r",
                    icon: "diamond.fill",
                    iconColor: .cyan
                )

                // USDT TRC20
                CryptoDonationRow(
                    title: "💵 USDT (TRC20)",
                    address: "TDkDMCyjYxgvkWUnQiF5Erk2RyPQMT6G1n",
                    icon: "dollarsign.circle.fill",
                    iconColor: .green
                )

                // BEP20
                CryptoDonationRow(
                    title: "🪙 BEP20 (BNB / USDT)",
                    address: "0x0954dc491c502849d04956ef74634aa5931a08e8",
                    icon: "bitcoinsign.circle.fill",
                    iconColor: .orange
                )
            }

            Text(MirsaTr.lit("Thank you so much for supporting Mirsa development! ❤️"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(.horizontal)
    }
}

// MARK: - Support Popup Sheet (Startup Welcome)

struct SupportPopupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var dontShowOnLaunch: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // Header Brand
                    VStack(spacing: 8) {
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.pink)

                        Text(MirsaTr.lit("Welcome to Mirsa!"))
                            .font(MirsaFont.sheetTitle)

                        Text(MirsaTr.lit("Free & Open Source • Developed by @mak5er"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    DonateView(isPopup: true, onDismiss: { dismiss() })

                    VStack(spacing: 12) {
                        Button {
                            dismiss()
                        } label: {
                            Text(MirsaTr.lit("Continue to Mirsa"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.mirsaPrimary)
                        .controlSize(.large)

                        Toggle(isOn: $dontShowOnLaunch) {
                            Text(MirsaTr.lit("Don't show this popup on startup"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)

                        Text(MirsaTr.lit("You can reopen donation options anytime in Credits › Donate ❤️"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .padding(.vertical)
            }
            .navigationTitle(MirsaTr.lit("Support Creator"))
            .navigationBarTitleDisplayMode(.inline)
            .mirsaScreen()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(MirsaTr.lit("Close")) {
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}

// MARK: - Credits Sheet

struct CreditsSheet: View {
    @Environment(\.dismiss) private var dismiss
    init(initialTab: Int = 0) {}
    var body: some View {
        NavigationStack {
            LicensesView()
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(MirsaTr.lit("Done")) { dismiss() }.bold() } }
        }
    }

}

// MARK: - Pairing File Guide Sheet

struct PairingGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onImportTapped: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text(MirsaTr.lit("Where to find your pairing file"))
                            .font(MirsaFont.sheetTitle)
                        Text(MirsaTr.lit("Mirsa can import pairing files exported by SideStore, LiveContainer, iLoader, or your computer."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // SideStore Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "app.badge.checkmark.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                            Text("SideStore")
                                .font(.headline.bold())
                            Spacer()
                            Text(MirsaTr.lit("Recommended"))
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }

                        Text(MirsaTr.lit("SideStore automatically creates a pairing file during setup. You can pick it directly in the Files app:"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(MirsaTr.lit("Path in Files app:"))
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Text(MirsaTr.lit("On My iPhone › SideStore › ALTPairingFile.mobiledevicepairing"))
                                .font(.caption.monospaced())
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(MirsaPalette.sheet, in: RoundedRectangle(cornerRadius: MirsaRadius.xs, style: .continuous))
                        }
                    }
                    .padding(14)
                    .mirsaCard(radius: MirsaRadius.snap(14))

                    // LiveContainer Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox.fill")
                                .font(.title3)
                                .foregroundStyle(.purple)
                            Text(MirsaTr.lit("LiveContainer (SideStore inside)"))
                                .font(.headline.bold())
                        }

                        Text(MirsaTr.lit("If you run SideStore inside LiveContainer, the pairing file is stored inside LiveContainer's app storage:"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(MirsaTr.lit("Path in Files app:"))
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Text(MirsaTr.lit("On My iPhone › LiveContainer › SideStore › Documents › ALTPairingFile.mobiledevicepairing"))
                                .font(.caption.monospaced())
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(MirsaPalette.sheet, in: RoundedRectangle(cornerRadius: MirsaRadius.xs, style: .continuous))
                        }
                    }
                    .padding(14)
                    .mirsaCard(radius: MirsaRadius.snap(14))

                    // iLoader / Jitterbug / AltStore Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                            Text("iLoader / Jitterbug / AltStore")
                                .font(.headline.bold())
                        }

                        Text(MirsaTr.lit("• In iLoader: Settings › Export Pairing File › save to Files.\n• In Jitterbug: Export your <UDID>.mobiledevicepairing.\n• On PC/Mac: Run jitterbugpair or export from SideServer / AltServer, then AirDrop to your iPhone."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .mirsaCard(radius: MirsaRadius.snap(14))

                    // Direct Placement Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                            Text(MirsaTr.lit("Manual Drop in Files App"))
                                .font(.headline.bold())
                        }

                        Text(MirsaTr.lit("You can also copy any .mobiledevicepairing or .plist file directly into:"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(MirsaTr.lit("Files app › On My iPhone › Mirsa"))
                            .font(.caption.monospaced())
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(MirsaPalette.sheet, in: RoundedRectangle(cornerRadius: MirsaRadius.xs, style: .continuous))

                        Text(MirsaTr.lit("It will immediately appear under 'Discovered in Documents' in Mirsa."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .mirsaCard(radius: MirsaRadius.snap(14))

                    // Action Button
                    Button {
                        dismiss()
                        onImportTapped()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "square.and.arrow.down.fill")
                            Text(MirsaTr.lit("Import Pairing File Now"))
                            Spacer()
                        }
                    }
                    .buttonStyle(.mirsaPrimary)
                    .controlSize(.large)
                    .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle(MirsaTr.lit("Pairing Guide"))
            .navigationBarTitleDisplayMode(.inline)
            .mirsaScreen()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(MirsaTr.lit("Done")) { dismiss() }.bold()
                }
            }
        }
    }
}

// MARK: - Compact Scrollable Log View with 1-Click Copy

struct CompactLogView: View {
    let title: String
    let lines: [String]
    var onClear: (() -> Void)? = nil
    @State private var copied: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if let onClear = onClear, !lines.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .padding(.trailing, 6)
                }
                Button {
                    UIPasteboard.general.string = lines.joined(separator: "\n")
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        copied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        var t2 = Transaction()
                        t2.disablesAnimations = true
                        withTransaction(t2) {
                            copied = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .bold))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(copied ? .green : .blue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(Capsule())
                }
                .buttonStyle(.borderless)
                .transaction { $0.animation = nil }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(logLineColor(line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 180)
                .background(MirsaPalette.sheet)
                .clipShape(RoundedRectangle(cornerRadius: MirsaRadius.s, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
                )
                .onChange(of: lines.count) { _, _ in
                    if !lines.isEmpty {
                        proxy.scrollTo(lines.count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Native Document Picker

struct DocumentPickerView: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView

        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let shouldStop = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStop { url.stopAccessingSecurityScopedResource() }
            }
            parent.onPick(url)
            parent.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

// MARK: - Root Tab View

struct ContentView: View {
    @EnvironmentObject var vm: AppViewModel
    @AppStorage("aircard.dont_show_support_on_launch") private var dontShowSupportOnLaunch: Bool = false
    @State private var showSupportPopup: Bool = false
    @State private var incoming: IncomingItem?
    @State private var incomingQueue: [IncomingItem] = []
    @State private var presentedURL: URL?
    @State private var incomingHandoff: (() -> Void)?
    @State private var incomingProject: PersonalLibraryApp?
    @State private var incomingProcessing = false
    @State private var incomingSources = Set<URL>()
    @State private var presentedSource: URL?
    private struct IncomingItem: Identifiable { let url: URL; let filename: String; let source: URL; var id: URL { url } }
    private func presentNextIncoming() {
        guard incoming == nil, !incomingProcessing, incomingProject == nil, !incomingQueue.isEmpty else { return }
        let next = incomingQueue.removeFirst()
        presentedSource = next.source
        presentedURL = next.url
        incoming = next
    }
    /// Transfer ownership before dismissal. The snapshot survives nested sheets,
    /// and work starts only once the confirmation sheet has actually dismissed.
    private func consumeIncoming(_ source: URL, operation: @escaping @MainActor () async throws -> Void) {
        guard incomingHandoff == nil, !incomingProcessing else { return }
        incomingProcessing = true
        presentedURL = nil
        incomingHandoff = {
            Task { @MainActor in
                defer {
                    OpenInIPA.remove(source)
                    if let original = presentedSource { incomingSources.remove(original) }
                    presentedSource = nil
                    incomingProcessing = false
                    presentNextIncoming()
                }
                do { try await operation() }
                catch { vm.errorMessage = error.localizedDescription }
            }
        }
        incoming = nil
    }
    @AppStorage(MirsaTheme.key) private var theme = MirsaTheme.liquid.rawValue
    private var liquidTheme: Bool { theme == MirsaTheme.liquid.rawValue }
    @State private var chatComposerFocused = false

    var body: some View {
        TabView(selection: $vm.selectedTab) {
            AppsTab()
                .modifier(LiquidTabChrome(liquid: liquidTheme))
                .tabItem { Label(L.t("tab"), systemImage: "square.grid.3x3.fill") }
                .tag(AppTab.apps)

            SourcesTab()
                .modifier(LiquidTabChrome(liquid: liquidTheme))
                .tabItem { Label(tr("Sources", "السورسات"), systemImage: "shippingbox.fill") }
                .tag(AppTab.sources)

            ToolsTab()
                .modifier(LiquidTabChrome(liquid: liquidTheme, chatEditing: chatComposerFocused, nestedNavigation: true))
                .tabItem { Label(L.t("tools.tab"), systemImage: "wand.and.stars") }
                .modifier(ForgeChatUnreadTabBadge())
                .tag(AppTab.pairing)

            EncryptedAppsTab()
                .modifier(LiquidTabChrome(liquid: liquidTheme))
                .tabItem { Label(EncryptedText.tabTitle, systemImage: "lock.shield") }
                .tag(AppTab.encrypted)

            PersonalAppsHub()
                .modifier(LiquidTabChrome(liquid: liquidTheme))
                .tabItem { Label(tr("Certificate", "الشهادة", ckb: "بڕوانامە", kmr: "Sertîfîka"), systemImage: "checkmark.seal") }
                .tag(AppTab.personalHub)
        }
        .environment(\.layoutDirection, .leftToRight)
        .overlay(alignment: .bottom) {
            if liquidTheme && !chatComposerFocused {
                LiquidTabBar(selection: $vm.selectedTab, items: [
                    LiquidTabItem(tab: .apps, title: L.t("tab"), icon: "square.grid.2x2"),
                    LiquidTabItem(tab: .sources, title: tr("Sources", "السورسات"), icon: "shippingbox"),
                    LiquidTabItem(tab: .pairing, title: L.t("tools.tab"), icon: "wand.and.stars"),
                    LiquidTabItem(tab: .encrypted, title: EncryptedText.tabTitle, icon: "lock.shield"),
                    LiquidTabItem(tab: .personalHub, title: tr("Certificate", "الشهادة", ckb: "بڕوانامە", kmr: "Sertîfîka"), icon: "checkmark.seal"),
                ])
                .ignoresSafeArea(.keyboard)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("mirsa.store.wishlist.open"))) { _ in vm.selectedTab = .encrypted }
        .onPreferenceChange(ForgeChatComposerFocusKey.self) { chatComposerFocused = $0 }
        .onOpenURL { url in
            if url.scheme == "mirsa", url.host == "wishlist" {
                vm.selectedTab = .encrypted
                NotificationCenter.default.post(name: Notification.Name("mirsa.store.wishlist.open"), object: nil)
                return
            }
            if OpenInTweak.accepts(url) { OpenInProjectCoordinator.shared.receive([url]); return }
            // mirsa://launch?bundle=… from a Home Screen shortcut.
            if HomeShortcut.handle(url) { vm.selectedTab = .apps; return }
            // Document handoff uses a private snapshot before the provider relinquishes access.
            guard url.isFileURL, url.pathExtension.lowercased() == "ipa" else { return }
            vm.selectedTab = .apps
            guard incomingSources.insert(url.standardizedFileURL).inserted else { return }
            let scope = url.startAccessingSecurityScopedResource()
            Task {
                defer { if scope { url.stopAccessingSecurityScopedResource() } }
                do {
                    let snapshot = try await Task.detached(priority: .userInitiated) {
                        try OpenInIPA.snapshot(url)
                    }.value
                    incomingQueue.append(IncomingItem(url: snapshot, filename: url.lastPathComponent, source: url.standardizedFileURL))
                    presentNextIncoming()
                } catch {
                    incomingSources.remove(url.standardizedFileURL)
                    vm.errorMessage = error.localizedDescription
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mirsaIncomingIPA)) { note in
            guard let file = note.object as? URL,
                  incomingSources.insert(file.standardizedFileURL).inserted else { return }
            Task {
                do {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    let snapshot = try await Task.detached(priority: .userInitiated) { try OpenInIPA.snapshot(file) }.value
                    incomingQueue.append(IncomingItem(url: snapshot, filename: file.lastPathComponent, source: file.standardizedFileURL))
                    presentNextIncoming()
                } catch {
                    incomingSources.remove(file.standardizedFileURL)
                    vm.errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(item: $incoming, onDismiss: {
            AppsStore.shared.cancelPending()
            AppsStore.shared.explicitIncomingInstall = false
            if let leftover = presentedURL { OpenInIPA.remove(leftover); presentedURL = nil }
            if let handoff = incomingHandoff {
                incomingHandoff = nil
                handoff()
            } else {
                if let source = presentedSource { incomingSources.remove(source); presentedSource = nil }
                presentNextIncoming()
            }
        }) { item in
            IncomingIPAChoiceSheet(url: item.url, store: AppsStore.shared, vm: vm) {
                incoming = nil
            }
            .presentationDetents([.large])
            .mirsaSheetBackground()
        }
        .sheet(item: $incomingProject, onDismiss: { presentNextIncoming() }) { app in
            PersonalProjectDetailView(app: app)
        }
        .alert(MirsaTr.lit("Notice"), isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button(MirsaTr.lit("OK")) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .alert(MirsaTr.lit("Success! 🎉"), isPresented: $vm.showSuccessAlert) {
            Button(MirsaTr.lit("OK")) {}
        } message: {
            Text(vm.successAlertMessage)
        }
        .sheet(isPresented: $vm.showShareSheet) {
            if let url = vm.exportedThemeURL {
                ShareSheet(items: [url])
            }
        }
        .onAppear {
            vm.showSuccessAlert = false
            vm.successAlertMessage = ""

        }
    }
}

// MARK: - Pairing Tab

struct PairingTab: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showDeleteConfirm = false
    @State private var showCredits = false
    @State private var showFilePicker = false
    @State private var showPairingGuide = false

    private var isIOS27OrNewer: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    private var isPotentiallyPatchedOS: Bool {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        if os.majorVersion > 27 { return true }
        if os.majorVersion == 27 && os.minorVersion >= 3 { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form { Group {
                // Header
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "creditcard.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                            Text("Mirsa")
                                .font(MirsaFont.sheetTitle)
                            Spacer()
                            Text("iOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion) · v1.3.2")
                                .font(.caption.monospaced().bold())
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.blue.opacity(0.12))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                        Text(MirsaTr.lit("Apply custom wallet card skins and passcode themes on-device. Supports iOS 18.0 – 27.2 beta 2 (iOS 27.2 beta 3+ patched)."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if isPotentiallyPatchedOS {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(MirsaTr.lit("iOS 27.2 beta 3 or newer detected: Apple patched the AirTraffic exploit on this version. Operations will likely fail."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Network / VPN Status
                Section(MirsaTr.lit("Network")) {
                    VPNStatusRow(vm: vm)
                }

                // Pairing Status
                Section(MirsaTr.lit("Active Pairing")) {
                    HStack(spacing: 10) {
                        if vm.hasPairingFile {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(MirsaTr.lit("Ready to exploit ✅"))
                                    .font(.subheadline.bold())
                                Text("\(vm.pairingFileName) (\(vm.pairingFileSizeString))")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(MirsaTr.lit("Not Paired"))
                                    .font(.subheadline.bold())
                                Text(isIOS27OrNewer
                                     ? "Pair on this iPhone below or import a pairing file."
                                     : "Import a pairing file from SideStore, iLoader, or PC below.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if vm.hasPairingFile {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    if vm.hasPairingFile {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "trash.fill")
                                Text(MirsaTr.lit("Delete Pairing File"))
                                Spacer()
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.red)
                        }
                    }
                }
                .confirmationDialog(
                    "Delete pairing session?",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button(MirsaTr.lit("Delete Pairing"), role: .destructive) { vm.deletePairingFile() }
                    Button(MirsaTr.lit("Cancel"), role: .cancel) {}
                } message: {
                    Text(MirsaTr.lit("The active pairing credentials will be removed so you can re-pair or import another file."))
                }

                // Pairing File Import (SideStore / iLoader / PC)
                Section(MirsaTr.lit("Pairing File")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            showFilePicker = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .foregroundStyle(.blue)
                                Text(MirsaTr.lit("Import Pairing File…"))
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }

                        Button {
                            showPairingGuide = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.circle")
                                Text(MirsaTr.lit("Where to find SideStore / LiveContainer pairing file?"))
                            }
                            .font(.footnote)
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.mirsaPress)

                        Text(MirsaTr.lit("Supports .mobiledevicepairing, .plist, or .mobilepair exported from SideStore, iLoader, AltStore, Jitterbug, or Mac/PC."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !vm.documentsPlistFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(MirsaTr.lit("Discovered in Documents:"))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            ForEach(vm.documentsPlistFiles, id: \.self) { filename in
                                HStack {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundStyle(.blue)
                                    Text(filename)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button(MirsaTr.lit("Use")) {
                                        vm.selectPairingFile(filename: filename)
                                    }
                                    .buttonStyle(.mirsaSecondary)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // On-Device Pairing Section (shown ONLY on iOS 27+)
                if isIOS27OrNewer {
                    Section(MirsaTr.lit("Pair on This iPhone")) {
                        if vm.pairingPhase == .pairing {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.85)
                                    Text(vm.pairingStatus.isEmpty ? "Starting local pairing host…" : vm.pairingStatus)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                if let pin = vm.pairingPIN {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(MirsaTr.lit("ENTER THIS PIN ON THIS IPHONE:"))
                                            .font(.caption2.bold().uppercaseSmallCaps())
                                            .foregroundStyle(.secondary)

                                        HStack(alignment: .center, spacing: 0) {
                                            Text(pin)
                                                .font(.system(size: 40, weight: .black, design: .monospaced))
                                                .foregroundStyle(.orange)
                                            Spacer()
                                            Button {
                                                UIPasteboard.general.string = pin
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            } label: {
                                                Label(MirsaTr.lit("Copy"), systemImage: "doc.on.doc")
                                                    .font(.caption.bold())
                                            }
                                            .buttonStyle(.mirsaSecondary)
                                        }

                                        Text(MirsaTr.lit("Settings › Privacy & Security › Developer Mode › Pair with Mirsa"))
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.primary)

                                        Button {
                                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                                UIApplication.shared.open(url)
                                            }
                                        } label: {
                                            Label(MirsaTr.lit("Open Settings App Now"), systemImage: "arrow.up.forward.app")
                                                .bold()
                                                .frame(maxWidth: .infinity, alignment: .center)
                                        }
                                        .buttonStyle(.mirsaPrimary)
                                    }
                                    .padding(14)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }

                                Button(role: .cancel) {
                                    vm.cancelPairing()
                                } label: {
                                    HStack(spacing: 8) {
                                        Spacer()
                                        Image(systemName: "xmark")
                                        Text(MirsaTr.lit("Cancel Pairing"))
                                        Spacer()
                                    }
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                }
                                .buttonStyle(.mirsaSecondary)
                            }
                        } else {
                            VStack(spacing: 12) {
                                if !vm.pairingStatus.isEmpty && vm.pairingStatus != "idle" {
                                    Text(vm.pairingStatus)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(
                                            vm.pairingStatus.contains("✅") ? .green :
                                            vm.pairingStatus.contains("❌") || vm.pairingStatus.contains("failed") ? .red :
                                            .secondary
                                        )
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }

                                Button {
                                    vm.startPairing()
                                } label: {
                                    HStack(spacing: 8) {
                                        Spacer()
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                            .font(.body.weight(.semibold))
                                        Text(vm.hasPairingFile ? "Re-Pair This iPhone" : "Pair This iPhone")
                                            .font(.headline)
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                }
                                .buttonStyle(.mirsaPrimary)
                            }
                            .listRowInsets(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                        }
                    }
                }

                if !vm.log.isEmpty {
                    Section {
                        CompactLogView(
                            title: "Activity Log (\(vm.log.count) lines)",
                            lines: vm.log,
                            onClear: { vm.log.removeAll() }
                        )
                    }
                }
            }.listRowBackground(MirsaPalette.row) }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 60)
            }
            .navigationTitle("Mirsa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCredits = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                            Text(tr("About Mirsa", "حول مرسى"))
                                .font(.caption.bold())
                        }
                        .foregroundStyle(.pink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.pink.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            }
            .sheet(isPresented: $showCredits) {
                CreditsSheet()
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPickerView(allowedContentTypes: [
                    UTType(filenameExtension: "mobiledevicepairing") ?? .data,
                    UTType(filenameExtension: "plist") ?? .propertyList,
                    UTType(filenameExtension: "mobilepair") ?? .data,
                    .propertyList,
                    .data,
                    .item
                ]) { url in
                    _ = vm.importPairingFile(from: url, originalName: url.lastPathComponent)
                }
            }
            .sheet(isPresented: $showPairingGuide) {
                PairingGuideSheet {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showFilePicker = true
                    }
                }
            }
            .onAppear {
                vm.refreshNetworkStatus()
                vm.refreshPairingFile()
            }
            .refreshable {
                vm.refreshNetworkStatus()
                vm.refreshPairingFile()
            }
        }
    }
}

// MARK: - VPN Status Row

struct VPNStatusRow: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: vm.vpnUp
                      ? "checkmark.shield.fill"
                      : "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(vm.vpnUp ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.vpnUp ? "Loopback VPN Active" : "Loopback VPN Not Detected")
                        .font(.subheadline.bold())
                    Text(vm.vpnUp
                         ? "RSD tunnel ready — exploit will connect."
                         : "Connect LocalDevVPN before running flashes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !vm.vpnUp {
                VStack(alignment: .leading, spacing: 6) {
                    Text(MirsaTr.lit("Setup LocalDevVPN:"))
                        .font(.caption.bold())
                    ForEach([
                        "1. Open LocalDevVPN app and tap Connect.",
                        "2. Return to Mirsa — status indicator turns green."
                    ], id: \.self) { step in
                        Text(step)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Link("Launch LocalDevVPN",
                         destination: URL(string: "localdevvpn://")!)
                        .font(.caption.bold())
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 8) {
                Text(MirsaTr.lit("Device IP:"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("10.7.0.1", text: $vm.deviceIP)
                    .font(.caption.monospaced())
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 120)
                Spacer()
                Button {
                    vm.refreshNetworkStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.bold())
                }
                .buttonStyle(.mirsaSecondary)
                .controlSize(.mini)
            }

            if !vm.networkDetail.isEmpty {
                Text(vm.networkDetail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Liquid Glass theme: hide the system tab bar (a floating glass bar replaces it)
/// and keep content clear of it.
struct LiquidTabChrome: ViewModifier {
    let liquid: Bool
    var chatEditing: Bool = false
    var nestedNavigation: Bool = false
    @ViewBuilder
    func body(content: Content) -> some View {
        if liquid {
            if nestedNavigation {
                // A pushed chat destination can lose an ancestor safe-area inset.
                // Bound the tools NavigationStack itself above the floating dock.
                content
                    .toolbar(.hidden, for: .tabBar)
                    .padding(.bottom, chatEditing ? 0 : MirsaTabBarMetrics.clearance)
                    // Fill the strip below the padded content with the page background (no black strip behind the dock).
                    .background(AuroraBackground().ignoresSafeArea())
            } else {
                content
                    .toolbar(.hidden, for: .tabBar)
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: chatEditing ? 0 : MirsaTabBarMetrics.clearance) }
            }
        } else {
            content.toolbar(chatEditing ? .hidden : .visible, for: .tabBar)
        }
    }
}
