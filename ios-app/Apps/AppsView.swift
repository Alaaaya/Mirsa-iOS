import SwiftUI
import UniformTypeIdentifiers

// MARK: - Card helpers (solid since the style unification; no blur or glass effect)

extension View {
    func appsGlassClassic(cornerRadius: CGFloat = 24, tint: Color? = nil, interactive: Bool = false) -> some View {
        appsGlass(cornerRadius: cornerRadius, tint: tint, interactive: interactive)
    }

    func appsGlassCapsuleClassic(tint: Color? = nil) -> some View {
        appsGlassCapsule(tint: tint)
    }

    func appsGlassFallback(cornerRadius: CGFloat, tint: Color?) -> some View {
        appsGlass(cornerRadius: cornerRadius, tint: tint)
    }
}

// MARK: - Aurora background

struct AuroraBackground: View {
    var paused = false
    @AppStorage(MirsaTheme.key) private var theme = MirsaTheme.liquid.rawValue
    @Environment(\.mirsaTabActive) private var tabActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// The classic mesh only ticks while it can actually be seen.
    private var meshPaused: Bool {
        paused || MirsaUITestHarness.active || !tabActive || reduceMotion || scenePhase != .active
    }
    var body: some View {
        // The UI-test harness freezes the drifting light so XCUITest can reach idle.
        if theme == MirsaTheme.liquid.rawValue { LiquidBackground(paused: paused || MirsaUITestHarness.active) } else { classic }
    }

    private var classic: some View {
        // Pinned to the screen like the Liquid backdrop, so every copy lines up seamlessly.
        MirsaScreenAnchored { _ in classicMesh }
    }

    private var classicMesh: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: meshPaused)) { ctx in
            let t = Float(ctx.date.timeIntervalSinceReferenceDate)
            let s = sin(t * 0.25) * 0.08
            let c = cos(t * 0.21) * 0.08
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + s, 0.45 + c], [1, 0.5],
                    [0, 1], [0.5 - c, 1], [1, 1],
                ],
                colors: [
                    Color(red: 0.06, green: 0.04, blue: 0.16), Color(red: 0.30, green: 0.14, blue: 0.62), Color(red: 0.05, green: 0.10, blue: 0.28),
                    Color(red: 0.10, green: 0.22, blue: 0.55), Color(red: 0.12, green: 0.45, blue: 0.62), Color(red: 0.36, green: 0.16, blue: 0.58),
                    Color(red: 0.02, green: 0.03, blue: 0.08), Color(red: 0.03, green: 0.20, blue: 0.24), Color(red: 0.03, green: 0.03, blue: 0.10),
                ]
            )
        }
        .overlay(Color.black.opacity(0.25))
    }
}

// MARK: - Icon colour

enum IconTint {
    private static var cache: [String: Color] = [:]

    static func color(for id: String, image: UIImage?) -> Color {
        if let c = cache[id] { return c }
        guard let image else { return Color(red: 0.45, green: 0.35, blue: 0.95) }
        let r = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let px = r.image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 1, height: 1)) }
        var c = Color(red: 0.45, green: 0.35, blue: 0.95)
        if let cg = px.cgImage, let data = cg.dataProvider?.data, let p = CFDataGetBytePtr(data) {
            c = Color(red: Double(p[0]) / 255, green: Double(p[1]) / 255, blue: Double(p[2]) / 255)
        }
        cache[id] = c
        return c
    }
}

// MARK: - Root

enum AppsSegment { case container, real, downloads }

struct AppsTab: View {
    @EnvironmentObject var vm: AppViewModel
    @StateObject private var store = AppsStore.shared
    @StateObject private var updater = MirsaUpdater.shared
    @Environment(\.scenePhase) private var scenePhaseForUpdates
    @State private var segment: AppsSegment = .container
    @State private var showPicker = false
    @State private var showURLImport = false
    @State private var showLogin = false
    @State private var showSettings = false
    @State private var infoApp: ManagedApp?
    @State private var backupApp: ManagedApp?
    @State private var shortcutError: String?
    @State private var showHidden = false
    @State private var pendingHideID: String?
    @ObservedObject private var progressState = MirsaOperationProgress.shared
    @ObservedObject private var hiddenStore = HiddenAppsStore.shared
    @ObservedObject private var downloads = DownloadsLibrary.shared
    @AppStorage("mirsa.apps.homeLayout") private var homeLayout = false
    @AppStorage("mirsa.home.style") private var homeStyle = "pages"
    @Namespace private var segNS

    @AppStorage(MirsaTheme.key) private var theme = MirsaTheme.liquid.rawValue
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: theme == MirsaTheme.liquid.rawValue ? 14 : 18), count: theme == MirsaTheme.liquid.rawValue ? 4 : 3) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AuroraBackground()

            if homeLayout {
                if homeStyle == "iphone" {
                    MirsaIPhoneHome(apps: hiddenStore.visible(store.containerApps + store.realApps, ns: .main, id: { $0.id }),
                                    allAppIDs: (store.containerApps + store.realApps).map(\.id),
                                    onLaunch: { launchIfIdle($0) },
                                    onSettings: { showSettings = true },
                                    onImport: { showPicker = true },
                                    onImportLink: { showURLImport = true },
                                    onDownloads: { segment = .downloads },
                                    // Same path as the context menu's Delete (store.delete); the «−» alert is the confirmation.
                                    onDelete: { app in Task { await store.delete(app, vm: vm) } },
                                    menu: { app in menu(for: app) })
                } else {
                    MirsaHomeScreen(apps: hiddenStore.visible(store.containerApps + store.realApps, ns: .main, id: { $0.id }),
                                    allAppIDs: (store.containerApps + store.realApps).map(\.id),
                                    onLaunch: { launchIfIdle($0) },
                                    onSettings: { showSettings = true },
                                    onImport: { showPicker = true },
                                    onImportLink: { showURLImport = true },
                                    onDownloads: { segment = .downloads },
                                    menu: { app in menu(for: app) })
                }
                if segment == .downloads {
                    VStack {
                        HStack {
                            Text(tr("Downloads", "التنزيلات")).font(.headline)
                            Spacer()
                            Button(L.t("settings.done")) { segment = .container }
                        }
                        ScrollView {
                            DownloadsList(store: store)
                        }
                        Spacer()
                    }
                    .padding(MirsaSpacing.page)
                    .background(MirsaPalette.sheet.ignoresSafeArea())
                }
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: MirsaSpacing.l) {
                    header
                    HeroCard(store: store, onSignIn: { showLogin = true }, onRefresh: refreshAll)
                        .mirsaAppear()
                    statusWarnings
                    segmentControl
                        .mirsaAppear(delay: 0.05)
                    grid
                        .mirsaAppear(delay: 0.1)
                }
                .padding(.horizontal, MirsaSpacing.page)
                .padding(.top, MirsaSpacing.xs)
                // Keeps the last row clear of the floating + button.
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
            .mirsaStatusBarScrim()

            fab
                .padding(.trailing, MirsaSpacing.page)
                // Clear gap above the floating dock (the tab already reserves the dock's own room).
                .padding(.bottom, MirsaSpacing.xl + MirsaTabBarMetrics.clearance)

            }

            if let busy = store.busy, !(store.isDownloading && operationOnTile) { BusyOverlay(text: busy, progress: store.progress, isDownloading: store.isDownloading, hasKnownSize: store.downloadHasKnownSize, onCancel: { store.cancelDownload() }) }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showURLImport) {
            // Same downloader as the personal library; importIPA copies the file into
            // its own work folder, then the Container/Real App choice sheet follows.
            PersonalURLImportSheet(disabled: store.busy != nil || store.pending != nil) { url in
                guard store.busy == nil, store.pending == nil else {
                    throw SideloadError.message(tr("Finish the current import first.", "خلّص الاستيراد الحالي أولاً."))
                }
                store.error = nil
                await store.importIPA(from: url)
                if let message = store.error { store.error = nil; throw SideloadError.message(message) }
            }
        }
        .sheet(isPresented: $showPicker) {
            DocumentPickerView(allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data, .zip]) { url in
                Task { await store.importIPA(from: url) }
            }
        }
        .sheet(item: Binding(get: { showURLImport || showPicker || store.explicitIncomingInstall ? nil : store.pending }, set: {
            if $0 == nil && !showURLImport && !showPicker && !store.explicitIncomingInstall { store.cancelPending() }
        })) { p in
            InstallChoiceSheet(pending: p, store: store, onPersonal: {
                Task {
                    do {
                        try await PersonalAppsLibrary.shared.add(p.originalIPA, signed: false)
                        store.cancelPending()
                        vm.selectedTab = .personalHub
                    } catch { store.error = error.localizedDescription }
                }
            }) { location in
                Task { await store.commitPending(to: location, vm: vm) }
            }
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
        .sheet(isPresented: $showSettings) {
            AppsSettingsSheet(store: store, onSignIn: { showSettings = false; showLogin = true })
                .environmentObject(vm)
        }
        .sheet(isPresented: $showHidden) {
            HiddenAppsView(store: hiddenStore) {
                HiddenAppsGrid(apps: store.apps, pendingHide: $pendingHideID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mirsaShowHidden)) { _ in showHidden = true }
        .onChange(of: scenePhaseForUpdates) { _, ph in
            if ph != .active { hiddenStore.lock() }
            if ph == .active { Task { await updater.check() } }
        }
        .sheet(item: $updater.available) { rel in
            MirsaUpdateSheet(release: rel, updater: updater) { Task { await updater.install(rel, vm: vm) } }
                .presentationDetents([.large])
                .mirsaSheetBackground()
        }
        .sheet(item: $backupApp) { a in BackupsSheet(app: a) }
        .alert(tr("Home Screen", "الشاشة الرئيسية"), isPresented: Binding(get: { shortcutError != nil }, set: { if !$0 { shortcutError = nil } })) {
            Button(MirsaTr.lit("OK")) { shortcutError = nil }
        } message: { Text(shortcutError ?? "") }
        .sheet(item: $infoApp) { a in
            AppInfoSheet(app: a, store: store)
                .presentationDetents([.medium])
                .mirsaSheetBackground()
        }
        .alert(L.t("tab"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            if store.errorOffersReimport {
                Button(tr("Import IPA again", "استيراد الـIPA من جديد")) { store.error = nil; showPicker = true }
                Button(tr("Download from link again", "تحميل من الرابط من جديد")) { store.error = nil; showURLImport = true }
            }
            if store.errorOffersLocalDevVPN {
                Button(tr5("Open LocalDevVPN", "فتح LocalDevVPN", de: "LocalDevVPN öffnen", ckb: "کردنەوەی LocalDevVPN", kmr: "LocalDevVPN veke")) {
                    AppsStore.openLocalDevVPN(); store.error = nil
                }
            }
            if store.errorOffersSettings {
                Button(tr("Open Settings", "فتح الإعدادات")) { AppsStore.openWiFiSettings(); store.error = nil }
            }
            Button(tr("Copy log", "نسخ السجل", ckb: "کۆپیکردنی تۆمار", kmr: "Tomarê kopî bike")) {
                // Public error summary only. Owner-only technical history must
                // still pass the separate live admin authorization boundary.
                let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
                MirsaDiagnosticPrivacy.copy(["Mirsa build " + build, store.error ?? ""]) {
                    UIPasteboard.general.string = $0
                }
            }
            Button(MirsaTr.lit("OK")) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .alert(L.f("launch.title", store.launchCandidate?.name ?? ""),
               isPresented: Binding(get: { store.launchCandidate != nil }, set: { if !$0 { store.launchCandidate = nil } })) {
            Button(L.t("choice.cancel"), role: .cancel) { store.launchCandidate = nil }
            Button(L.t("launch.go")) { if let a = store.launchCandidate { store.confirmLaunch(a) } }
        } message: { Text(L.f("launch.body", store.launchCandidate?.name ?? "")) }
        .alert(L.t("repair.title"), isPresented: Binding(get: { store.needsRepair && store.busy == nil && store.error == nil },
                                                         set: { if !$0 { store.needsRepair = false } })) {
            Button(L.t("choice.cancel"), role: .cancel) { store.needsRepair = false }
            Button(L.t("repair.go")) { Task { await store.installSelf(vm: vm) } }
        } message: { Text(L.t("repair.body")) }
        .overlay(alignment: .top) { toast }
        .task {
            // Screenshot fixture must never refresh credentials, install, or persist test data.
            if MirsaUITestHarness.active && MirsaStyleShots.page == "apps-design" { return }
            let launchErr = store.lastLaunchError
            if launchErr != nil {
                UserDefaults.standard.removeObject(forKey: "aircard.guest.lastError")
                store.forceResignContainer()
            }
            if store.account == nil && store.hasSavedLogin { await store.refreshAccount() }
            if let e = launchErr {
                let t = await store.signerSelfTest()
                store.error = store.signingDiagnostics + "\n" + t + "\n\n" + e
            }
            store.scheduleExpiryReminders()
            await updater.check()
            if GitHubWatcher.shared.autoInstall && !GitHubWatcher.shared.sources.isEmpty && store.networkReady(vm) {
                Task { await GitHubWatcher.shared.checkAll(install: true) }
            }
            vm.refreshNetworkStatus()
            store.scheduleBackgroundRefresh()
        }
    }

    // MARK: Pieces

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? L.t("greeting.morning") : (h < 18 ? L.t("greeting.afternoon") : L.t("greeting.evening"))
    }

    private var header: some View {
        MirsaPageHeader(title: L.t("title"), subtitle: greeting) {
            LanguageGlobeMenu()
                .appsGlassCapsule()
            Button { showSettings = true } label: {
                MirsaIconButtonLabel(systemName: "gearshape.fill")
            }
            .buttonStyle(.mirsaPress)
            .appsGlassCapsule()
            .accessibilityLabel(L.t("settings.title"))
        }
    }

    @ViewBuilder
    private var statusWarnings: some View {
        if segment == .real || store.pending != nil {
            if !vm.vpnUp {
                WarningPill(icon: "lock.shield", text: L.t("hero.vpnOff"))
            }
        }
    }

    private var segmentControl: some View {
        HStack(spacing: 4) {
            segButton(.container, title: L.t("seg.container"), trailing: "∞")
            segButton(.real, title: L.t("seg.real"), trailing: "\(store.slotsUsed)/\(store.realLimit)")
            segButton(.downloads, title: tr("Downloads", "التنزيلات"), trailing: "\(downloads.items.count)")
        }
        .frame(maxWidth: .infinity)
        .padding(4)
        .appsGlassCapsule()
        .environment(\.layoutDirection, .leftToRight)
    }

    private func segButton(_ s: AppsSegment, title: String, trailing: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { segment = s }
        } label: {
            VStack(spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.7).allowsTightening(true)
                Text(trailing)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white.opacity(segment == s ? 0.9 : 0.5))
            }
            .foregroundStyle(segment == s ? .white : .white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if segment == s {
                    Capsule()
                        .fill(MirsaPalette.accentGradient)
                        .opacity(0.9)
                        .matchedGeometryEffect(id: "seg", in: segNS)
                        .shadow(color: MirsaPalette.accent.opacity(0.45), radius: 8, y: 3)
                }
            }
        }
        .buttonStyle(.mirsaPress)
        .frame(minWidth: 0, maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Global overlay steps aside only when the cancellable tile is actually visible (list home, current segment).
    private var operationOnTile: Bool {
        guard !homeLayout, segment != .downloads else { return false }
        let ids = Set(currentApps.map(\.id))
        return progressState.entries.values.contains { $0.canCancel && $0.appID.map(ids.contains) == true }
    }
    private func launchIfIdle(_ app: ManagedApp) {
        if progressState.entry(for: app.id) == nil { store.launch(app) }
    }
    private var currentApps: [ManagedApp] {
        hiddenStore.visible(segment == .container ? store.containerApps : store.realApps, ns: .main, id: { $0.id })
    }

    @ViewBuilder
    private var grid: some View {
        if segment == .downloads {
            DownloadsList(store: store)
        } else if currentApps.isEmpty {
            ContentUnavailableView {
                Label(L.t("empty.title"), systemImage: segment == .container ? "shippingbox" : "app.badge")
                    .foregroundStyle(.white)
            } description: {
                Text(segment == .container ? L.t("empty.container") : L.t("empty.real"))
                    .foregroundStyle(.white.opacity(0.7))
            } actions: {
                Button { showPicker = true } label: {
                    Label(L.t("empty.import"), systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.mirsaPrimary)
            }
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
            .appsGlass(cornerRadius: 28)
        } else {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(currentApps) { app in
                    AppTile(app: app)
                        .onTapGesture { launchIfIdle(app) }
                        .contextMenu { menu(for: app) }
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for app: ManagedApp) -> some View {
        Button { launchIfIdle(app) } label: { Label(L.t("menu.open"), systemImage: "arrow.up.forward.app") }
        if app.location == .container {
            Button { Task { await store.move(app, to: .real, vm: vm) } } label: {
                Label(L.t("menu.toReal"), systemImage: "iphone.and.arrow.forward")
            }
            .disabled(store.slotsLeft == 0)
            Button { Task { await store.resign(app) } } label: { Label(L.t("menu.resign"), systemImage: "signature") }
            Button { backupApp = app } label: { Label(tr("Data backups", "نسخ البيانات"), systemImage: "externaldrive") }
            Button { shortcutError = HomeShortcut.add(app) } label: {
                Label(tr("Add to Home Screen", "إضافة للشاشة الرئيسية"), systemImage: "plus.app")
            }
        } else {
            Button { Task { await store.move(app, to: .container, vm: vm) } } label: {
                Label(L.t("menu.toContainer"), systemImage: "shippingbox")
            }
            Button { Task { await store.refresh(app, vm: vm) } } label: { Label(L.t("menu.refresh"), systemImage: "arrow.clockwise") }
        }
        Button { infoApp = app } label: { Label(L.t("menu.info"), systemImage: "info.circle") }
        Button {
            if !hiddenStore.hide(HiddenAppID(.main, app.id)) {
                if hiddenStore.health == .faulted { shortcutError = personalText("Hidden apps are unavailable right now. Nothing was hidden.", "التطبيقات المخفية مو متاحة هلأ. ما انخفى شي.") }
                else { pendingHideID = app.id; showHidden = true }
            }
        } label: { Label(tr("Hide", "إخفاء"), systemImage: "eye.slash") }
        Divider()
        Button(role: .destructive) { Task { await store.delete(app, vm: vm) } } label: {
            Label(L.t("menu.delete"), systemImage: "trash")
        }
    }

    private var fab: some View {
        Menu {
            Button { showPicker = true } label: { Label(tr("From Files", "من الملفات"), systemImage: "folder") }
            Button { showURLImport = true } label: { Label(tr("From link", "من رابط"), systemImage: "link") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(MirsaPalette.accentGradient))
                .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                .shadow(color: MirsaPalette.accent.opacity(0.5), radius: 14, y: 6)
        }
        .buttonStyle(.mirsaPress)
        .accessibilityLabel(L.t("empty.import"))
    }

    @ViewBuilder
    private var toast: some View {
        if let t = store.toast {
            Text(t)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .appsGlassCapsule(tint: .green)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    withAnimation { store.toast = nil }
                }
        }
    }

    private func refreshAll() {
        Task {
            await store.refreshAccount()
            await store.refreshAll(vm: vm)
        }
    }
}

// MARK: - Hero card

struct HeroCard: View {
    @ObservedObject var store: AppsStore
    let onSignIn: () -> Void
    let onRefresh: () -> Void

    private var days: Int? {
        guard let d = store.nextRenewal else { return nil }
        return max(0, Int(ceil(d.timeIntervalSinceNow / 86_400)))
    }

    private var canRenew: Bool { store.account != nil || store.hasSavedLogin }

    var body: some View {
        // Compact account card: the renewal ring leads, the account and its Renew action
        // share one row, and the two weekly quotas sit side by side with bars that fill
        // by what is still left.
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RenewalRing(days: days, size: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.account != nil ? L.t("hero.active") : (store.hasSavedLogin
                         ? tr("Apple ID · Sign-in needs checking", "Apple ID · بدو تحقق من تسجيل الدخول")
                         : L.t("hero.signedOut")))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let a = store.account {
                        Text(a.email)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: canRenew ? onRefresh : onSignIn) {
                    Label(canRenew ? L.t("hero.refresh") : L.t("hero.signIn"),
                          systemImage: canRenew ? "arrow.clockwise" : "person.crop.circle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
                .buttonStyle(.mirsaPress)
                .appsGlassCapsule(tint: Color(red: 0.45, green: 0.4, blue: 1))
            }

            HStack(spacing: 10) {
                if let a = store.account, let avail = a.appIDsAvailable, let max = a.appIDsMax {
                    HeroQuota(label: L.t("hero.appIDs.label"), left: avail, total: max,
                              spoken: L.f("hero.appIDs", avail, max))
                }
                HeroQuota(label: L.t("hero.slots.label"), left: store.slotsLeft, total: store.realLimit,
                          spoken: L.f("hero.slots", store.slotsLeft, store.realLimit))
            }
        }
        .padding(14)
        // The root dock stays fixed LTR; only the localized account card mirrors.
        .environment(\.layoutDirection, (L.lang == .arabic || L.lang == .sorani) ? .rightToLeft : .leftToRight)
        .appsGlass(cornerRadius: 26, tint: Color(red: 0.45, green: 0.35, blue: 1))
    }
}

/// One weekly quota on the account card: its name, "left of total", and a bar whose
/// filled part is the share still left (9 of 10 is nearly full; 1 of 3 is a third).
/// Turns amber when one or none is left.
struct HeroQuota: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let label: String
    let left: Int
    let total: Int
    let spoken: String

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(left) / Double(total)))
    }
    private var low: Bool { left <= 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(L.f("hero.count", left, total))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
            GeometryReader { geo in
                let fillWidth = geo.size.width * fraction
                let rtl = layoutDirection == .rightToLeft
                // Drawing isolated in forced LTR: physical left-to-right HStack, so no double mirroring.
                HStack(spacing: 0) {
                    if rtl { Spacer(minLength: 0) }
                    Capsule()
                        .fill(LinearGradient(colors: low
                                             ? [Color(red: 0.96, green: 0.62, blue: 0.04), Color(red: 0.98, green: 0.75, blue: 0.14)]
                                             : [MirsaPalette.accent, Color(red: 0.13, green: 0.83, blue: 0.93)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: fillWidth, height: geo.size.height)
                    if !rtl { Spacer(minLength: 0) }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .background(Capsule().fill(.white.opacity(0.10)))
                .environment(\.layoutDirection, .leftToRight)
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

struct RenewalRing: View {
    let days: Int?
    var size: CGFloat = 64
    var body: some View {
        let fraction = days.map { min(1, Double($0) / 7.0) } ?? 0
        let color: Color = (days ?? 7) <= 1 ? .red : ((days ?? 7) <= 3 ? .orange : Color(red: 0.4, green: 0.9, blue: 0.7))
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: size < 60 ? 5 : 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(AngularGradient(colors: [color.opacity(0.6), color], center: .center),
                        style: StrokeStyle(lineWidth: size < 60 ? 5 : 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.6), radius: 6)
            VStack(spacing: -2) {
                Text(days.map(String.init) ?? "–")
                    .font(.system(size: size < 60 ? 18 : 20, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text(L.t("hero.days"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(days ?? 0) \(L.t("hero.days")) \(L.t("hero.renews"))")
    }
}

// MARK: - Tile

struct AppTile: View {
    let app: ManagedApp
    @AppStorage(MirsaTheme.key) private var theme = MirsaTheme.liquid.rawValue
    private var liquid: Bool { theme == MirsaTheme.liquid.rawValue }
    // Cached decode (revalidated by file date): the grid re-renders on every progress tick,
    // and reading + decoding the PNG from disk in body made scrolling stutter.
    private var icon: UIImage? { MirsaIconCache.image(id: app.id, path: AppsStore.iconURL(app.id).path) }
    @ObservedObject private var progress = MirsaOperationProgress.shared
    private var iconSize: CGFloat { liquid ? 60 : 68 }
    private var iconRadius: CGFloat { iconSize * 0.225 }

    var body: some View {
        let img = icon
        let tint = IconTint.color(for: app.id, image: img)
        VStack(spacing: 8) {
            ZStack {
                Group {
                    if let img {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(colors: [tint, tint.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                            Text(String(app.name.prefix(1)))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: iconRadius, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 5)
            }
            // The icon stands on its own, like on the Home Screen; no glass tile around it.
            // The outer frame keeps the grid rhythm and the badge position unchanged.
            .frame(width: liquid ? 68 : 78, height: liquid ? 68 : 78)
            .overlay(alignment: .topTrailing) { badges }
            .overlay { operationOverlay }

            Text(app.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: liquid ? 82 : 96)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var operationOverlay: some View {
        if let e = progress.entry(for: app.id) {
            ZStack {
                RoundedRectangle(cornerRadius: iconRadius, style: .continuous).fill(.black.opacity(0.92)).frame(width: iconSize, height: iconSize)
                MirsaLiquidProgress(value: e.fraction, diameter: 48)
                if e.canCancel {
                    Button { progress.cancel(e.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).contentShape(Rectangle()).offset(x: 19, y: 19)
                    }.buttonStyle(.mirsaPress).accessibilityLabel(tr("Cancel download", "إلغاء التنزيل")).accessibilityAddTraits(.isButton)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(progressLabel(e))
        }
    }

    private func progressLabel(_ e: MirsaOperationProgress.Entry) -> String {
        if let stageLabel = e.stageLabel {
            return stageLabel + (e.fraction.map { " \(Int($0 * 100))%" } ?? "")
        }
        let phase: String
        switch e.phase {
        case .downloading: phase = tr("Downloading", "جاري التنزيل")
        case .preparing: phase = tr("Preparing", "جاري التحضير")
        case .signing: phase = tr("Signing", "جاري التوقيع")
        case .installing: phase = tr("Installing", "جاري التثبيت")
        case .updating: phase = tr("Updating", "جاري التحديث")
        }
        let pct = e.fraction.map { " \(Int($0 * 100))%" } ?? ""
        return app.name + ", " + phase + pct + (e.canCancel ? "" : ", " + tr("cannot be cancelled", "ما بيتلغى"))
    }

    @ViewBuilder
    private var badges: some View {
        if app.location == .real {
            HStack(spacing: 3) {
                if app.wantsNotifications {
                    Image(systemName: "bell.fill").font(.system(size: 9, weight: .bold))
                }
                if let d = app.daysLeft {
                    Text(L.f("badge.days", d)).font(.system(size: 10, weight: .bold).monospacedDigit())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill((app.daysLeft ?? 7) <= 2 ? Color.red : Color(red: 0.3, green: 0.45, blue: 1)))
            .offset(x: 6, y: -6)
        }
    }
}

// MARK: - Small views

struct WarningPill: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.orange)
            Text(text).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .appsGlass(cornerRadius: 16, tint: .orange)
    }
}

struct BusyOverlay: View {
    let text: String
    let progress: Double
    var isDownloading = false
    var hasKnownSize = false
    var onCancel: (() -> Void)? = nil
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                MirsaLiquidProgress(value: isDownloading && !hasKnownSize ? nil : (progress > 0 ? progress : nil), diameter: 112)
                Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                if isDownloading, let onCancel {
                    Button(action: onCancel) {
                        Text(tr("Cancel", "إلغاء"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 160).padding(.vertical, 10)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.mirsaPress)
                }
            }
            .padding(28)
            .appsGlass(cornerRadius: 26)
        }
        .transition(.opacity)
    }
}

// MARK: - Install choice

struct InstallChoiceSheet: View {
    let pending: PendingImport
    @ObservedObject var store: AppsStore
    var onPersonal: (() -> Void)? = nil
    let onChoose: (AppLocation) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false
    private var current: PendingImport { store.pending ?? pending }
    @State private var showLogin = false
    @State private var afterLogin: AppLocation?
    @State private var showCertificate = false
    @State private var savingPersonal = false

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Capsule().fill(.white.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 8)
                    appHeader
                    Button { showEditor = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3").font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tr("Edit IPA & inject tweaks", "تعديل التطبيق والتويكس")).font(.headline)
                                Text(tr("Name, icon, version and your own code", "الاسم، الأيقونة، الإصدار وملفاتك الخاصة"))
                                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.white).padding(16).appsGlass(cornerRadius: 22, tint: .purple)
                    }
                    .buttonStyle(.mirsaPress)
                    .disabled(store.busy != nil)


                    optionCard(selected: true,
                               icon: "shippingbox.fill", iconTint: Color(red: 0.5, green: 0.4, blue: 1),
                               title: L.t("choice.container"), sub: L.t("choice.containerSub"),
                               trailing: "∞", disabled: false) {
                        dismissThen(.container)
                    }

                    optionCard(selected: false,
                               icon: "app.badge.fill", iconTint: Color(red: 0.2, green: 0.65, blue: 0.95),
                               title: L.t("choice.real"), sub: L.f("choice.realSub", store.realLimit),
                               trailing: "\(store.slotsLeft)/\(store.realLimit)", disabled: store.slotsLeft == 0) {
                        dismissThen(.real)
                    }

                    optionCard(selected: false,
                               icon: "key.fill", iconTint: Color(red: 0.95, green: 0.7, blue: 0.2),
                               title: personalText("Install with certificate", "تثبيت عبر الشهادة"),
                               sub: personalText("Saved P12, no Apple ID. ∞ does not bypass certificate, profile or device limits.", "شهادتك المحفوظة، بدون Apple ID. علامة ∞ ما بتتجاوز حدود الشهادة أو البروفايل أو الجهاز."),
                               trailing: "∞", disabled: store.busy != nil) {
                        showCertificate = true
                    }
                    .sheet(isPresented: $showCertificate) {
                        CertificateInstallSheet(pending: current, store: store) { store.cancelPending(); dismiss() }
                    }
                    if let onPersonal {
                        optionCard(selected: false, icon: "square.stack.3d.up.fill", iconTint: .teal,
                                   title: tr("Certificate Library", "مكتبة الشهادة", ckb: "کتێبخانەی بڕوانامە", kmr: "Pirtûkxaneya sertîfîkayê"),
                                   sub: tr("Save only. No Apple ID or installation.", "حفظ فقط، بدون Apple ID أو تثبيت."),
                                   trailing: "+", disabled: store.busy != nil || savingPersonal) {
                            store.error = nil
                            savingPersonal = true
                            onPersonal()
                        }
                    }
                    if savingPersonal { ProgressView() }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "bell.badge.fill").foregroundStyle(.yellow)
                            Text(L.t("choice.note")).font(.footnote).foregroundStyle(.white.opacity(0.85))
                        }
                        Divider().overlay(.white.opacity(0.15))
                        Label(L.f("choice.slots", store.slotsLeft, store.realLimit), systemImage: "square.grid.3x3.fill")
                            .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.75))
                        if let a = store.account, let avail = a.appIDsAvailable, let max = a.appIDsMax {
                            Label(L.f("choice.appIDs", avail, max), systemImage: "number.circle.fill")
                                .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.75))
                        }
                        if store.slotsLeft == 0 {
                            Label(L.t("choice.full"), systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appsGlass(cornerRadius: 22)

                    Button(L.t("choice.cancel")) { store.cancelPending(); dismiss() }
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.vertical, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.layoutDirection, .leftToRight)
        .interactiveDismissDisabled(savingPersonal)
        .disabled(savingPersonal)
        .onChange(of: store.error) { _, error in
            if error != nil { savingPersonal = false }
        }
        .sheet(isPresented: $showEditor) {
            IPAEditorView(pending: current, store: store)
        }
        .task {
            // A Mirsa AI «Inject» choice opens the editor with its tweak already checked.
            if store.injectTweakIDs != nil { showEditor = true }
        }
        .sheet(isPresented: $showLogin, onDismiss: {
            if let l = afterLogin, store.account != nil {
                afterLogin = nil
                onChoose(l)
            }
        }) {
            LoginSheet(store: store)
                .mirsaSheetBackground()
        }
    }

    private func dismissThen(_ l: AppLocation) {
        if store.account == nil && !store.hasSavedLogin {
            afterLogin = l
            showLogin = true
        } else {
            onChoose(l)
        }
    }

    private var appHeader: some View {
        HStack(spacing: 14) {
            Group {
                if let i = current.icon { Image(uiImage: i).resizable().scaledToFill() }
                else { Color.purple.overlay(Text(String(current.name.prefix(1))).font(MirsaFont.sheetTitle).foregroundStyle(.white)) }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(L.f("choice.title", current.name)).font(.title3.bold()).foregroundStyle(.white)
                Text("\(current.version) · \(ByteCountFormatter.string(fromByteCount: current.sizeBytes, countStyle: .file))")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                Text(current.bundleID).font(.caption2).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
            Spacer()
        }
        .padding(16)
        .appsGlass(cornerRadius: 24)
    }

    private func optionCard(selected: Bool, icon: String, iconTint: Color, title: String, sub: String,
                            trailing: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(iconTint.gradient))
                    .shadow(color: iconTint.opacity(0.6), radius: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(sub).font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Text(trailing)
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(16)
            .appsGlass(cornerRadius: 22, tint: selected ? iconTint : nil)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(selected ? iconTint.opacity(0.8) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.mirsaPress)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

// MARK: - Login

struct LoginSheet: View {
    @ObservedObject var store: AppsStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = Keychain.get("appleid.email") ?? ""
    @State private var password = ""

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 18) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                    .padding(.top, 30)
                Text(L.t("login.title")).font(MirsaFont.sheetTitle).foregroundStyle(.white)
                Text(L.t("login.sub"))
                    .font(.subheadline).multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))

                VStack(spacing: 0) {
                    TextField(L.t("login.email"), text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                    Divider().overlay(.white.opacity(0.15))
                    SecureField(L.t("login.password"), text: $password)
                        .textContentType(.password)
                        .padding(14)
                }
                .foregroundStyle(.white)
                .appsGlass(cornerRadius: 18)

                Button {
                    Task {
                        await store.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
                        if store.account != nil { dismiss() }
                    }
                } label: {
                    Text(L.t("login.button")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.mirsaPrimary)
                .disabled(email.isEmpty || password.isEmpty || store.busy != nil)

                if store.busy != nil { ProgressView().tint(.white) }

                Text(L.t("login.privacy"))
                    .font(.caption2).multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $store.prompt) { p in
            PromptSheet(prompt: p) { store.prompt = nil }
                .presentationDetents([.medium, .large])
                .mirsaSheetBackground()
                .interactiveDismissDisabled()
        }
    }
}

// MARK: - 2FA / certificate prompt

struct PromptSheet: View {
    let prompt: SideloadPrompt
    let close: () -> Void
    @State private var code = ""
    @State private var answered = false

    private func answer(_ v: String?) {
        guard !answered else { return }
        answered = true
        PromptBridge.shared.respond(v)
        close()
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 16) {
                switch prompt.kind {
                case .twoFactor: twoFactor
                case .maxCerts: certs
                }
                Button(L.t("choice.cancel")) { answer("abort") }
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .onDisappear { answer("abort") }
    }

    private var twoFactor: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill").font(.system(size: 40)).foregroundStyle(.white).padding(.top, 20)
            Text(L.t("twofa.title")).font(MirsaFont.sheetTitle).foregroundStyle(.white)
            Text(prompt.sms ? L.t("twofa.subSMS") : L.t("twofa.sub"))
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.7))
            if let e = prompt.lastError, !e.isEmpty {
                Text(e).font(.caption).foregroundStyle(.orange)
            }
            TextField("000000", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .padding(14)
                .appsGlass(cornerRadius: 18)
            Button { answer("code:" + code) } label: {
                Text(L.t("twofa.submit")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.mirsaPrimary)
            .disabled(code.count < 6)

            HStack(spacing: 10) {
                if !prompt.sms {
                    ForEach(prompt.phones) { p in
                        Button(L.t("twofa.sms") + " " + p.number) { answer("sms:\(p.id)") }
                            .font(.caption.weight(.semibold))
                    }
                } else {
                    Button(L.t("twofa.devices")) { answer("devices") }.font(.caption.weight(.semibold))
                }
                Button(L.t("twofa.resend")) { answer("resend") }.font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var certs: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.t("certs.title")).font(.title3.bold()).foregroundStyle(.white).padding(.top, 20)
            Text(L.t("certs.sub")).font(.footnote).foregroundStyle(.white.opacity(0.7))
            ForEach(prompt.certs) { c in
                HStack {
                    VStack(alignment: .leading) {
                        Text(c.machine.isEmpty ? c.name : c.machine).font(.headline).foregroundStyle(.white)
                        Text(c.serial).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Button(L.t("certs.revoke"), role: .destructive) { answer(c.serial) }
                        .buttonStyle(.mirsaSecondary)
                }
                .padding(14)
                .appsGlass(cornerRadius: 18)
            }
        }
    }
}

// MARK: - Settings

struct AppsSettingsSheet: View {
    @AppStorage(MirsaInstallMode.key) private var installMode = "appleID"
    @AppStorage("mirsa.apps.homeLayout") private var homeLayout = false
    @AppStorage("mirsa.home.style") private var homeStyle = "pages"
    @AppStorage(MirsaCompletionFeedback.enabledKey) private var completionFeedback = true
    @AppStorage("mirsa.home.wallpaper") private var wallpaper = "ocean"
    @EnvironmentObject var vm: AppViewModel
    @AppStorage(MirsaTheme.key) private var theme = MirsaTheme.liquid.rawValue
    @ObservedObject var store: AppsStore
    let onSignIn: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var adminCode = ""
    @State private var adminNote: String?
    @State private var showCertificates = false
    private func claim() async {
        do { _ = try await ForgeClient.json(["action": "admin-claim", "code": adminCode]); NotificationCenter.default.post(name: .mirsaDiagnosticIdentityChanged, object: nil); adminCode = ""; adminNote = tr("Admin access enabled on this device.", "تفعّلت صلاحية المشرف.", ckb: "چالاک کرا.", kmr: "Çalak bû.") }
        catch { adminNote = tr("Invalid or expired code.", "الكود غلط أو منتهي.", ckb: "کۆدەکە هەڵەیە یان بەسەرچووە.", kmr: "Kod çewt an qediyaye.") }
    }

    var body: some View {
        NavigationStack {
            Form { Group {
                Section(tr("Admin access", "صلاحية المشرف", ckb: "دەسەڵاتی بەڕێوەبەر", kmr: "Gihîştina rêveber")) {
                    SecureField(tr("One-time code", "كود لمرة وحدة", ckb: "کۆدی یەکجار", kmr: "Koda carekê"), text: $adminCode).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button(tr("Claim", "تفعيل", ckb: "چالاک بکە", kmr: "Çalak bike")) { Task { await claim() } }.disabled(adminCode.count < 19)
                    if let adminNote { Text(adminNote).font(.footnote) }
                }
                Section(L.t("settings.account")) {
                    if let a = store.account {
                        LabeledContent("Apple ID", value: a.email)
                        LabeledContent("Team", value: a.teamName.isEmpty ? a.teamID : "\(a.teamName) (\(a.teamID))")
                        if let avail = a.appIDsAvailable, let max = a.appIDsMax {
                            LabeledContent("App IDs", value: "\(avail) / \(max)")
                        }
                        Button(L.t("settings.signOut"), role: .destructive) { store.signOut() }
                    } else {
                        Button(L.t("hero.signIn"), action: onSignIn)
                    }
                }
                Section(tr("Install mode", "طريقة التثبيت")) {
                    Picker(tr("Install mode", "طريقة التثبيت"), selection: $installMode) {
                        Text("Apple ID").tag("appleID")
                        Text(tr("My certificate", "شهادتي")).tag("certificate")
                    }
                    if installMode == "certificate" {
                        OwnCertificateDeviceSetup()
                        // The manager owns a NavigationStack (it is also a sheet elsewhere); pushing it
                        // nested a second stack with a duplicate bar and back button.
                        Button { showCertificates = true } label: {
                            HStack {
                                Label(tr("Certificates", "الشهادات"), systemImage: "signature").foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }.contentShape(Rectangle())
                        }
                        Text(tr("Self-install and updates use your certificate and a private HTTPS link valid for 15 minutes, OTA installation does not use VPN, after a one-time real device read in Settings. Signing and installation use only the device-bound secure cache. Only the signed IPA and public profile are uploaded, never your P12, password or private key. The profile must cover Mirsa and this device. Keychain data may reset; certificate revocation stops the app. Other Apple ID operations still require VPN.", "تثبيت مرسى وتحديثاته بشهادتك ورابط HTTPS خاص لمدة 15 دقيقة، التثبيت OTA ما بيحتاج VPN، بعد قراءة الجهاز مرة واحدة بالإعدادات. التوقيع والتثبيت بيستخدموا النسخة الآمنة المرتبطة بهالجهاز بدون VPN. بينرفع ملف IPA الموقّع والبروفايل العام فقط، مو ملف P12 ولا كلمة السر ولا المفتاح الخاص. لازم البروفايل يدعم مرسى وجهازك. ممكن بيانات سلسلة المفاتيح تنمسح، وإلغاء الشهادة بيوقف التطبيق. عمليات Apple ID التانية بعدها بحاجة VPN."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(tr("Apps layout", "واجهة التطبيقات")) {
                    Toggle(tr("Home Screen", "الشاشة الرئيسية"), isOn: $homeLayout)
                    Text(tr("Off keeps your current apps view unchanged. Home Screen uses pages and a glass dock.", "لما تطفّي الخيار بتضل الواجهة الحالية نفسها. الشاشة الرئيسية فيها صفحات ودوك زجاجي."))
                        .font(.caption).foregroundStyle(.secondary)
                    if homeLayout {
                        Picker(tr("Style", "الشكل", ckb: "شێواز", kmr: "Şêwaz"), selection: $homeStyle) {
                            Text(tr("Pages", "صفحات", ckb: "پەڕەکان", kmr: "Rûpel")).tag("pages")
                            Text(tr("iPhone", "متل الآيفون", ckb: "وەک ئایفۆن", kmr: "Wek iPhone")).tag("iphone")
                        }
                    }
                    if homeLayout && homeStyle != "iphone" {
                        Picker(tr("Wallpaper", "الخلفية"), selection: $wallpaper) {
                            Text(tr("Ocean", "بحر")).tag("ocean")
                            Text(tr("Sunset", "غروب")).tag("sunset")
                            Text(tr("Graphite", "داكن")).tag("graphite")
                        }
                    }
                }
                Section {
                    Toggle(tr("Completion sound & haptic", "صوت واهتزاز عند الانتهاء"), isOn: $completionFeedback)
                }
                Section {
                    Button { dismiss(); NotificationCenter.default.post(name: .mirsaShowHidden, object: nil) } label: {
                        Label(tr("Privacy", "الخصوصية"), systemImage: "lock")
                    }
                }
                MirsaTempCleanRow()
                Section(tr("Theme", "الثيم")) {
                    Picker(tr("Theme", "الثيم"), selection: $theme) {
                        ForEach(MirsaTheme.allCases) { t in Text(t.title).tag(t.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    StoreStylePicker()
                } header: { Text(StoreStyle.settingTitle) } footer: { Text(StoreStyle.explanation) }
                Section {
                    Stepper(value: $store.realLimit, in: 1...100) {
                        LabeledContent(L.t("settings.limit"), value: "\(store.realLimit)")
                    }
                    Toggle(L.t("settings.autoRefresh"), isOn: $store.autoRefresh)
                } footer: { Text(L.t("settings.limitFoot")) }

                Section {
                    Button {
                        Task { await MirsaUpdater.shared.updateNow(vm: vm) }
                    } label: {
                        InstallKeyedLabel(key: "mirsa-update") {
                            Label(tr("Update Mirsa", "حدّث مرسى"), systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(installMode != "certificate" && store.account == nil && !store.hasSavedLogin)
                } footer: {
                    Text(MirsaTr.f("checks", "\(MirsaUpdater.currentBuild)"))
                }
                Section {
                    Button {
                        Task { await store.installSelf(vm: vm) }
                    } label: {
                        InstallKeyedLabel(key: "self") {
                            Label(L.t("settings.selfInstall"), systemImage: "arrow.down.app")
                        }
                    }
                    .disabled(installMode != "certificate" && store.account == nil && !store.hasSavedLogin)
                } footer: { Text(L.t("settings.selfInstallFoot")) }

                MirsaNotificationSettings()

                Section(L.t("settings.anisette")) {
                    TextField("https://ani.sidestore.io", text: $store.anisetteURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section(tr("Days left", "الأيام الباقية")) {
                    ExpiryListView(store: store)
                }

                Section(tr("Get apps", "جيب تطبيقات")) {
                    NavigationLink { GitHubSourcesView() } label: {
                        Label(tr("GitHub Updates", "تحديثات GitHub"), systemImage: "shippingbox.and.arrow.backward")
                    }
                    NavigationLink { WebUploadView() } label: {
                        Label(tr("Upload from Computer", "رفع من الكمبيوتر"), systemImage: "laptopcomputer.and.arrow.down")
                    }
                }

                Section {
                    NavigationLink(L.t("settings.licenses")) { LicensesView() }
                }
            }.listRowBackground(MirsaPalette.row) }
            .mirsaScreen()
            .onChange(of: store.pending?.id) { _, new in if new != nil { dismiss() } }
            .navigationTitle(L.t("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L.t("settings.done")) { dismiss() } }
            }
            .sheet(isPresented: $showCertificates) { PersonalCertificateManagerView() }
        }
    }
}

// MARK: - App info

struct AppInfoSheet: View {
    let app: ManagedApp
    @ObservedObject var store: AppsStore

    var body: some View {
        NavigationStack {
            List { Group {
                LabeledContent(L.t("info.version"), value: app.version)
                LabeledContent(L.t("info.bundle"), value: app.installedBundleID ?? app.id)
                LabeledContent(L.t("info.location"), value: app.location == .container ? L.t("seg.container") : L.t("seg.real"))
                LabeledContent(L.t("info.size"), value: ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file))
                if let e = app.expires {
                    LabeledContent(L.t("info.expires"), value: e.formatted(date: .abbreviated, time: .shortened))
                }
                if let s = app.signedSerial {
                    LabeledContent(L.t("info.signedWith"), value: s)
                }
            }.listRowBackground(MirsaPalette.row) }
            .mirsaScreen()
            .navigationTitle(app.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Licenses

struct LicensesView: View {
    private struct Item: Identifiable {
        var id: String { name }
        let name: String; let license: String; let url: String; let note: String
        var fullNotice: String? = nil
    }
    private var items: [Item] { [
        Item(name: "Mirsa", license: "Mirsa License",
             url: "https://github.com/Alaaaya/Mirsa-iOS/blob/main/LICENSE",
             note: storeText(
                "Credit \"Based on Mirsa\" and share the full corresponding source under the same license.",
                "اذكر \"Based on Mirsa\" وانشر الكود المصدري الكامل بنفس الترخيص.",
                de: "Nenne \"Based on Mirsa\" und veröffentliche den vollständigen zugehörigen Quellcode unter derselben Lizenz.",
                ckb: "\"Based on Mirsa\" بنووسە و تەواوی کۆدی سەرچاوەی پەیوەندیدار بە هەمان مۆڵەتنامە بڵاو بکەرەوە.",
                kmr: "Navê \"Based on Mirsa\" bi bîr bîne û hemû koda çavkaniyê ya têkildar bi heman lîsansê belav bike.")),
        Item(name: "isideload", license: "MIT", url: "https://github.com/nab138/isideload",
             note: "Apple ID sign-in, anisette, development certificates, App IDs, provisioning profiles and app signing."),
        Item(name: "idevice", license: "MIT", url: "https://github.com/jkcoxson/idevice",
             note: "AFC and installation_proxy over the on-device loopback tunnel; pairing and RSD."),
        Item(name: "apple-codesign-quick", license: "LGPL-2.1-or-later", url: "https://github.com/Dadoum/apple-codesign-quick",
             note: "Code signing (used by isideload). Statically linked: Mirsa's full source and build scripts are public so you can relink with a modified version, as the LGPL requires."),
        Item(name: "Original base code", license: "MIT",
             url: "https://github.com/Alaaaya/Mirsa-iOS/blob/848bf273a2f2e85ac76004544e89b2108cb2a635/LICENSE",
             note: "Copyright (c) 2026 Johnny Franks",
             fullNotice: Self.upstreamMITNotice),
    ] }

    // Verbatim upstream notice, kept inside the binary as well as the source.
    // Provenance: Mak5er/AirCard-iOS, initial commit 848bf273.
    static let upstreamMITNotice = """
    MIT License
    
    Copyright (c) 2026 Johnny Franks
    
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """ + "\n"

    @State private var showLicenses = false
    private var licensesTitle: String {
        storeText("Licenses", "التراخيص", de: "Lizenzen", ckb: "مۆڵەتنامەکان", kmr: "Lîsans")
    }

    private var version: String {
        let i = Bundle.main.infoDictionary
        let v = i?["CFBundleShortVersionString"] as? String ?? "?"
        let b = i?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
    private var appIcon: UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let p = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let f = (p["CFBundleIconFiles"] as? [String])?.last else { return nil }
        return UIImage(named: f)
    }

    var body: some View {
        List { Group {
            Section {
                VStack(spacing: 10) {
                    if let img = appIcon {
                        Image(uiImage: img).resizable().frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    }
                    Text("Mirsa").font(MirsaFont.sheetTitle)
                    Text(tr("Version ", "الإصدار ") + version).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                LabeledContent(tr("Developer", "المطوّر"), value: "Alaa")
                Link(destination: URL(string: "https://x.com/rasmtk30")!) {
                    LabeledContent("X", value: "@rasmtk30")
                }
            }
            Section {
                Button { showLicenses = true } label: {
                    HStack {
                        Label(licensesTitle, systemImage: "doc.text").foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(licensesTitle)
                .accessibilityIdentifier("licenses-open")
            }
        }.listRowBackground(MirsaPalette.row) }
        .mirsaScreen()
        .navigationTitle(tr("About", "حول التطبيق"))
        .sheet(isPresented: $showLicenses) {
            NavigationStack {
                List { Group { ForEach(items) { i in licenseRow(i) } }.listRowBackground(MirsaPalette.row) }
                    .mirsaScreen()
                    .navigationTitle(licensesTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(storeText("Done", "تم", de: "Fertig", ckb: "تەواو", kmr: "Temam")) { showLicenses = false }
                        }
                    }
            }
        }
    }

    private func licenseRow(_ i: Item) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(i.name).font(.headline).accessibilityIdentifier("license-name-" + i.name)
                    Spacer()
                    Text(i.license).font(.caption.weight(.semibold))
                        .accessibilityIdentifier("license-badge-" + i.name)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                }
                Text(i.note).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("license-note-" + i.name)
                if let u = URL(string: i.url) {
                    Link(i.url, destination: u).font(.caption)
                        .accessibilityIdentifier("license-link-" + i.name)
                }
                if let notice = i.fullNotice {
                    DisclosureGroup {
                        Text(notice).font(.footnote).textSelection(.enabled)
                            .environment(\.layoutDirection, .leftToRight)
                            .accessibilityIdentifier("license-full-notice-" + i.name)
                    } label: {
                        Text(storeText("Full license", "نص الترخيص الكامل", de: "Vollständige Lizenz",
                                       ckb: "دەقی تەواوی مۆڵەتنامە", kmr: "Nivîsa tevahî ya lîsansê"))
                    }
                    .accessibilityIdentifier("license-disclosure-" + i.name)
                }
            }
            .padding(.vertical, 4)
    }
}
