import SwiftUI

/// Mirsa Setup: a small installer (meant to be signed with ESign/Feather) that
/// installs the real Mirsa with the user's Apple ID and hands over the login,
/// signing key and pairing so Mirsa works on first launch.
struct SetupView: View {
    @EnvironmentObject var vm: AppViewModel
    @StateObject private var store = AppsStore.shared
    @State private var showPairing = false
    @State private var showLogin = false

    private var networkOK: Bool { vm.vpnUp }
    private var pairingOK: Bool { vm.hasPairingFile }
    private var accountOK: Bool { store.account != nil }
    private var ready: Bool { networkOK && pairingOK && accountOK }

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: MirsaSpacing.m) {
                    header
                    step(1, icon: "lock.shield.fill", title: L.t("setup.network"),
                         status: networkOK ? L.t("setup.networkOK") : L.t("setup.networkOff"),
                         ok: networkOK, action: L.t("setup.check")) {
                        vm.refreshNetworkStatus()
                    }
                    step(2, icon: "link", title: L.t("setup.pairing"),
                         status: pairingOK ? L.t("setup.pairingOK") : L.t("setup.pairingOff"),
                         ok: pairingOK, action: L.t("setup.pairingOpen")) {
                        showPairing = true
                    }
                    step(3, icon: "apple.logo", title: L.t("setup.account"),
                         status: store.account?.email ?? L.t("setup.accountOff"),
                         ok: accountOK, action: accountOK ? nil : L.t("setup.signIn")) {
                        showLogin = true
                    }
                    installButton
                    if store.installedSelfBundleID != nil { doneCard }
                    Text(L.t("setup.note"))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(MirsaPalette.textTertiary)
                        .padding(.horizontal, 10)
                }
                .padding(.horizontal, MirsaSpacing.page)
                .padding(.top, MirsaSpacing.xxl)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
            .mirsaStatusBarScrim()

            if let busy = store.busy { BusyOverlay(text: busy, progress: store.progress, isDownloading: store.isDownloading, hasKnownSize: store.downloadHasKnownSize, onCancel: { store.cancelDownload() }) }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPairing, onDismiss: {
            vm.refreshPairingFile(); vm.refreshNetworkStatus()
        }) {
            SetupPairingSheet().environmentObject(vm)
                .presentationDetents([.large])
                .mirsaSheetBackground()
        }
        .sheet(isPresented: $showLogin) {
            LoginSheet(store: store)
                .presentationDetents([.large])
                .mirsaSheetBackground()
        }
        .sheet(item: $store.prompt) { p in
            PromptSheet(prompt: p) { store.prompt = nil }
                .presentationDetents([.medium, .large])
                .mirsaSheetBackground()
                .interactiveDismissDisabled()
        }
        .alert(L.t("setup.title"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            if store.errorOffersSettings {
                Button(tr("Open Settings", "فتح الإعدادات")) { AppsStore.openWiFiSettings(); store.error = nil }
            }
            Button(MirsaTr.lit("OK")) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .task {
            vm.refreshNetworkStatus()
            vm.refreshPairingFile()
            if store.account == nil && store.hasSavedLogin { await store.refreshAccount() }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Group {
                if let icon = UIImage(named: "AppIcon") {
                    Image(uiImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: "sailboat.fill").font(.system(size: 40)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(red: 0.45, green: 0.38, blue: 1.0))
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: MirsaRadius.l, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
            Text(L.t("setup.title")).font(MirsaFont.pageTitle).foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(L.t("setup.sub"))
                .font(MirsaFont.secondary).multilineTextAlignment(.center)
                .foregroundStyle(MirsaPalette.textSecondary)
        }
        .padding(.bottom, 6)
    }

    private func step(_ n: Int, icon: String, title: String, status: String, ok: Bool,
                      action: String?, perform: @escaping () -> Void) -> some View {
        let badge = ZStack {
            Circle().fill(ok ? AnyShapeStyle(MirsaPalette.success) : AnyShapeStyle(MirsaPalette.cardRaised))
                .frame(width: MirsaIconSize.button, height: MirsaIconSize.button)
            Image(systemName: ok ? "checkmark" : icon)
                .font(.system(size: MirsaIconSize.m, weight: .bold))
                .foregroundStyle(.white)
        }
        let texts = VStack(alignment: .leading, spacing: 3) {
            Text("\(n). \(title)").font(MirsaFont.cardTitle).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(status).font(MirsaFont.secondary)
                .foregroundStyle(ok ? MirsaPalette.success : MirsaPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        let button = action.map { a in
            Button(action: perform) { Text(a).lineLimit(1).fixedSize() }
                .buttonStyle(.mirsaSecondary)
                .controlSize(.small)
        }
        // One row when everything fits; otherwise the action moves under the text
        // instead of squeezing the title into a narrow, truncated column.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                badge
                texts.fixedSize()
                Spacer(minLength: MirsaSpacing.xs)
                button
            }
            HStack(alignment: .top, spacing: 14) {
                badge
                VStack(alignment: .leading, spacing: MirsaSpacing.s) {
                    texts
                    button
                }
                Spacer(minLength: 0)
            }
        }
        .padding(MirsaSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appsGlass(cornerRadius: MirsaRadius.l)
        .mirsaAppear(delay: Double(n) * 0.05)
    }

    private var installButton: some View {
        Button {
            Task { await store.installSelf(vm: vm) }
        } label: {
            Label(L.t("setup.install"), systemImage: "arrow.down.app.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.mirsaPrimary)
        .controlSize(.large)
        .disabled(!ready || store.busy != nil)
        .padding(.top, 6)
    }

    private var doneCard: some View {
        VStack(spacing: 12) {
            Text(L.t("setup.installed"))
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            if let bid = store.installedSelfBundleID {
                Button(L.t("setup.open")) { _ = AppsStore.openInstalledApp(bundleID: bid) }
                    .buttonStyle(.mirsaSecondary)
            }
        }
        .padding(MirsaSpacing.card)
        .frame(maxWidth: .infinity)
        .appsGlass(cornerRadius: MirsaRadius.l, tint: MirsaPalette.success)
    }
}
