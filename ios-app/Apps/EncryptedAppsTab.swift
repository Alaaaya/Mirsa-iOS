import SwiftUI
import UniformTypeIdentifiers

/// Fourth tab: App Store (FairPlay-encrypted) IPAs, installed unmodified.
struct EncryptedAppsTab: View {
    @Environment(\.mirsaDockBottomSafeArea) private var bottomSafeArea
    @EnvironmentObject var vm: AppViewModel
    @ObservedObject private var store = EncryptedAppsStore.shared
    @ObservedObject private var storeAccount = AppStoreSectionModel.shared
    @State private var picking = false
    @State private var storeLoginAvailable = false
    @State private var showingAppStore = false
    @State private var pendingDelete: EncryptedIPAEntry?
    @State private var section: StoreGalleryPage = StoreGalleryPage.initial
    /// Discover and Search are two faces of one App Store screen (one session, one download at a time).
    @State private var storeMode: StoreGalleryMode = StoreGalleryPage.initial == .search ? .search : .discover
    /// Tapping Discover or Search again closes an open app page.
    @State private var galleryReset = 0
    @ObservedObject private var transferControl = StoreTransferControl.shared
    @ObservedObject private var live = StoreGalleryLiveTransfer.shared
    /// Recreates the inline sign-in/search screen when the session changed elsewhere.
    @State private var storeViewID = UUID()
    @State private var libraryQuery = ""
    /// Follows `libraryQuery` after a short pause so typing does not re-filter the queue per keystroke.
    @State private var appliedLibraryQuery = ""
    @State private var showingAdd = false
    @State private var showingTools = false
    @State private var priorAccountID: String?
    /// Session-only: entries whose last install attempt ended with an error.
    @State private var failedInstalls: Set<UUID> = []
    @State private var storageSizes: [UUID: Int64] = [:]
    @State private var storageFree: Int64?

    private func t(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String { EncryptedText.t(en, ar, ckb, kmr) }

    var body: some View {
        // Every page stays alive while hidden, so switching pages never cancels a
        // running sign-in, search or download in the App Store screen.
        ZStack {
            StoreGalleryBackground()
            page(section == .discover || section == .search) { searchPage }
            page(section == .downloads) { downloadsPage }
            page(section == .purchases) {
                AppStorePurchasesPage(store: store, model: storeAccount, vm: vm, isActive: section == .purchases,
                                      onBack: { withAnimation(MirsaMotion.select) { section = .account } })
            }
            page(section == .account) {
                AppStoreAccountPage(model: storeAccount, library: store, storeAvailable: storeLoginAvailable,
                                    onAddAccount: { Task {
                                        priorAccountID = try? await MirsaStoreOnDeviceClient.shared.selectedAccountID()
                                        _ = try? await MirsaStoreOnDeviceClient.shared.beginAddAccount()
                                        storeAccount.updateAccount(nil); storeViewID = UUID()
                                        showingAppStore = true } },
                                    onOpen: { tab in withAnimation(MirsaMotion.select) { section = StoreGalleryPage(tab) } },
                                    onSignedOut: { storeViewID = UUID() },
                                    onAccountSwitched: { storeAccount.updateAccount(nil); storeViewID = UUID(); Task { await storeAccount.refresh() } },
                                    onOpenTools: { showingTools = true },
                                    onLeave: { tab in withAnimation(MirsaMotion.select) { vm.selectedTab = tab } })
            }
        }
        // Both glass bars overlay a full-height scroll surface. Reserve their
        // combined height in scroll content, never by shortening page viewports.
        .contentMargins(.bottom, StoreGallery.capsuleHeight + StoreGallery.capsuleTopGap + MirsaTabBarMetrics.scrollClearance(bottomSafeArea), for: .scrollContent)
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                StoreGalleryCapsuleBar(selection: $section, downloadsBadge: downloadsBadge,
                                       onReselect: { item in if item == .discover || item == .search { galleryReset += 1 } })
                    .padding(.top, StoreGallery.capsuleTopGap)
                Color.clear
                    .frame(height: MirsaTabBarMetrics.scrollClearance(bottomSafeArea))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            storeLoginAvailable = false
            storeLoginAvailable = true
            #if DEBUG
            if AppStoreSectionModel.fixtureAccount != nil { storeLoginAvailable = true }
            #endif
            await storeAccount.refresh()
        }
        .onChange(of: section) { _, value in
            if value == .discover { storeMode = .discover } else if value == .search { storeMode = .search }
            Task { await storeAccount.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: MirsaStoreIdentityLoader.readyNotification)) { _ in
            Task { storeLoginAvailable = true; await storeAccount.refresh() }
        }
        .sheet(isPresented: $showingAppStore, onDismiss: sessionMayHaveChanged) {
            AppStoreAccountView(onDownloaded: { url in
                let entry = try await EncryptedAppsStore.adopt(file: url, move: false)
                store.add(entry)
            })
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("mirsa.store.wishlist.open"))) { _ in
            section = .downloads; showingTools = true
        }
        .sheet(isPresented: $showingTools) {
            StoreLibraryToolsView(onAccountSwitched: { storeAccount.updateAccount(nil); storeViewID = UUID(); Task { await storeAccount.refresh() } },
                                  onAddAccount: { showingTools = false; Task {
                                      priorAccountID = try? await MirsaStoreOnDeviceClient.shared.selectedAccountID()
                                      _ = try? await MirsaStoreOnDeviceClient.shared.beginAddAccount()
                                      storeAccount.updateAccount(nil); storeViewID = UUID()
                                      showingAppStore = true } })
        }
        .preferredColorScheme(.dark)
        .environment(\.layoutDirection, .leftToRight)
        .sheet(isPresented: $picking) {
            DocumentPickerView(allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data]) { url in
                Task { await store.importIPA(from: url) }
            }
        }
        .confirmationDialog(t("Add a download", "إضافة تنزيل", "زیادکردنی داگرتن", "Daxistinekê zêde bike"),
                            isPresented: $showingAdd, titleVisibility: .visible) {
            Button(t("Import IPA from Files", "استيراد IPA من الملفات", "هاوردەکردنی IPA لە Files", "IPA ji Files bîne")) { picking = true }
            if storeLoginAvailable {
                Button(t("Search the App Store", "البحث بالـApp Store", "گەڕان لە App Store", "Li App Store bigere")) {
                    withAnimation(MirsaMotion.select) { section = .search }
                }
            }
            Button(tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal"), role: .cancel) {}
        }
        .alert(MirsaTr.lit("Notice"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button(MirsaTr.lit("OK")) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog(t("Delete this IPA?", "تحذف هالـIPA؟", "ئەم IPAیە بسڕیتەوە؟", "Vê IPA jê bibî?"),
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button(t("Delete", "حذف", "سڕینەوە", "Jê bibe"), role: .destructive) {
                if let e = pendingDelete { store.delete(e) }
                pendingDelete = nil
            }
            Button(tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(t("Only the file in Mirsa is removed. An installed app stays on your iPhone.",
                   "بينحذف الملف من مرسى بس. التطبيق المثبّت بيضل على الآيفون.",
                   "تەنها فایلەکە لە Mirsa دەسڕدرێتەوە. ئەپی دامەزراو لەسەر ئایفۆنەکەت دەمێنێتەوە.",
                   "Tenê pel ji Mirsa tê jêbirin. Sepana sazkirî li ser iPhone dimîne."))
        }
        .overlay(alignment: .top) {
            if let toast = store.toast {
                Text(toast).font(MirsaFont.button).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Color(red: 0.12, green: 0.11, blue: 0.19)))
                    .galleryGlassCapsule()
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation { store.toast = nil }
                    }
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.toast)
    }

    private func page<Content: View>(_ visible: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .storePageTransition(visible: visible)
            // One shared background is drawn by the tab; hidden pages rest their animations.
            .environment(\.storeBackdropProvided, true)
            .environment(\.storePageVisible, visible)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }

    /// Red count on the capsule's Downloads item: a running App Store download and a running import or install.
    private var downloadsBadge: Int {
        (transferControl.phase != .idle ? 1 : 0) + (store.busy != nil ? 1 : 0)
    }

    /// The sign-in sheet may have signed in or out. Reload the inline screen only then.
    private func sessionMayHaveChanged() {
        let prior = priorAccountID
        priorAccountID = nil
        Task {
            if let prior {
                let list = (try? await MirsaStoreOnDeviceClient.shared.listAccounts()) ?? []
                if let current = try? await MirsaStoreOnDeviceClient.shared.selectedAccountID(),
                   !list.contains(where: { $0.id == current }), list.contains(where: { $0.id == prior }) {
                    try? await MirsaStoreOnDeviceClient.shared.selectAccount(id: prior)
                }
            }
            storeAccount.updateAccount(nil)
            storeViewID = UUID()
            await storeAccount.refresh()
        }
    }

    // MARK: pages

    @ViewBuilder private var searchPage: some View {
        if storeLoginAvailable {
            // The existing sign-in, search, versions and download flow, unchanged; Discover and Search
            // are its two faces.
            AppStoreAccountView(onDownloaded: { url in
                let entry = try await EncryptedAppsStore.adopt(file: url, move: false)
                store.add(entry)
            }, searchOnly: true, onOpenAccount: {
                withAnimation(MirsaMotion.select) { section = .account }
            }, galleryMode: storeMode, galleryResetToken: galleryReset)
            .id(storeViewID)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: MirsaSpacing.m) {
                    StoreGalleryHeader(title: section == .discover ? StoreGalleryText.discover : AppStoreSectionTab.search.title) {
                        LanguageGlobeMenu(size: MirsaIconSize.button).galleryGlassCapsule()
                    }
                    StoreEmptyState(icon: "magnifyingglass",
                                    title: storeText("Search the App Store", "ابحث بمتجر أبل", de: "Im App Store suchen", ckb: "گەڕان لە App Store", kmr: "Li App Store bigere"),
                                    message: storeText("Find apps your Apple Account owns and keep them as untouched IPAs.",
                                                       "لاقي التطبيقات يلي بيملكها حساب Apple تبعك واحتفظ فيها كملفات IPA متل ما هي.",
                                                       de: "Finde Apps, die deinem Apple-Konto gehören, und behalte sie als unveränderte IPAs.",
                                                       ckb: "ئەو ئەپانە بدۆزەوە کە ئەکاونتی Appleـەکەت خاوەنیانە و وەک IPAی دەستکارینەکراو هەڵیانبگرە.",
                                                       kmr: "Sepanên ku hesabê te yê Apple xwedî ye bibîne û wekî IPAyên neguherî biparêze."))
                    appStoreButton
                    importButton
                }
                .environment(\.layoutDirection, StoreGallery.direction)
                .padding(.horizontal, MirsaSpacing.page)
                .padding(.bottom, MirsaSpacing.xl)
            }
        }
    }

    private var filteredEntries: [EncryptedIPAEntry] {
        let q = appliedLibraryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.version.localizedCaseInsensitiveContains(q)
                || $0.bundleID.localizedCaseInsensitiveContains(q)
        }
    }

    private var readyEntries: [EncryptedIPAEntry] { filteredEntries.filter { $0.installedAt == nil } }
    private var installedEntries: [EncryptedIPAEntry] { filteredEntries.filter { $0.installedAt != nil } }

    /// "Ready to install 3 · Installed 2" above the Downloads title.
    private var downloadsEyebrow: String? {
        guard !store.entries.isEmpty else { return nil }
        let ready = store.entries.filter { $0.installedAt == nil }.count
        return "\(StoreGalleryText.readyToInstall) \(ready) · \(StoreGalleryText.installed) \(store.entries.count - ready)"
    }

    private var downloadsPage: some View {
        List {
            Group {
                StoreGalleryHeader(eyebrow: downloadsEyebrow, title: AppStoreSectionTab.downloads.title) {
                    HStack(spacing: MirsaSpacing.xs) {
                        Button { showingAdd = true } label: { StoreGalleryRoundLabel(systemName: "plus", size: 40) }
                            .disabled(store.busy != nil)
                            .accessibilityLabel(t("Add a download", "إضافة تنزيل", "زیادکردنی داگرتن", "Daxistinekê zêde bike"))
                            .accessibilityIdentifier("store-add-download")
                        Button { showingTools = true } label: { StoreGalleryRoundLabel(systemName: "wrench.and.screwdriver", size: 40) }
                            .accessibilityLabel(StoreFeatureText.tools)
                        LanguageGlobeMenu(size: 40)
                            .galleryGlassCapsule()
                    }
                    .buttonStyle(.plain)
                }
                nowCard
                if store.busy != nil && store.installingID == nil {
                    importingRow
                }
                AppStoreSearchField(placeholder: storeText("Search by name, version or Bundle ID", "البحث بالاسم أو الإصدار أو Bundle ID",
                                                           de: "Nach Name, Version oder Bundle-ID suchen",
                                                           ckb: "گەڕان بە ناو، وەشان یان Bundle ID", kmr: "Bi nav, guherto an Bundle ID bigere"),
                                    text: $libraryQuery)
            }
            .modifier(StoreListRow())

            if store.entries.isEmpty {
                Group {
                    StoreEmptyState(icon: "arrow.down.app.fill",
                                    title: t("No encrypted IPAs yet", "لسّا ما في IPA مشفّرة", "هێشتا هیچ IPAیەکی شفرەکراو نییە", "Hêj IPA ya şîfrekirî tune"),
                                    message: storeText("Download an app you own from Search or Purchases, or import an App Store IPA from Files.",
                                                       "نزّل تطبيق بتملكه من البحث أو المشتريات، أو استورد IPA من App Store من الملفات.",
                                                       de: "Lade eine eigene App über Suche oder Käufe, oder importiere eine App-Store-IPA aus Dateien.",
                                                       ckb: "ئەپێک کە خاوەنیتی لە گەڕان یان کڕینەکان دابگرە، یان IPAیەک لە Files هاوردە بکە.",
                                                       kmr: "Sepanek ku ya te ye ji Lêgerîn an Kirînan daxe, an IPA yek ji Files bîne."),
                                    actionTitle: storeLoginAvailable ? AppStoreSectionTab.search.title : nil,
                                    action: openSearchAction)
                    importButton
                }
                .modifier(StoreListRow())
            } else {
                if filteredEntries.isEmpty {
                    Text(t("Nothing matches.", "ما في شي مطابق.", "هیچ شتێک ناگونجێت.", "Tiştek li hev nayê."))
                        .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                        .modifier(StoreListRow())
                }
                if !readyEntries.isEmpty {
                    Section {
                        ForEach(readyEntries) { entry in entryRow(entry) }
                    } header: {
                        StoreGallerySectionTitle(title: StoreGalleryText.readyToInstall, trailing: "\(readyEntries.count)")
                            .textCase(nil)
                            .padding(.vertical, 6)
                            .environment(\.layoutDirection, StoreGallery.direction)
                    }
                }
                if !installedEntries.isEmpty {
                    Section {
                        ForEach(installedEntries) { entry in entryRow(entry) }
                    } header: {
                        StoreGallerySectionTitle(title: StoreGalleryText.installed, trailing: "\(installedEntries.count)")
                            .textCase(nil)
                            .padding(.vertical, 6)
                            .environment(\.layoutDirection, StoreGallery.direction)
                    }
                }
                Group {
                    StoreStorageSummary(slices: storageSlices, total: storageTotal, free: storageFree)
                    importButton
                }
                .modifier(StoreListRow())
            }

            Group {
                StoreGallerySectionTitle(title: t("About App Store IPAs", "عن ملفات IPA من App Store", "دەربارەی IPAکانی App Store", "Derbarê IPAyên App Store"))
                    .padding(.top, MirsaSpacing.s)
                introCard
                benefitsCard
                Color.clear.frame(height: MirsaSpacing.xl)
            }
            .modifier(StoreListRow())
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .environment(\.layoutDirection, StoreGallery.direction)
        .scrollDismissesKeyboard(.interactively)
        .task(id: libraryQuery) {
            if libraryQuery.isEmpty { appliedLibraryQuery = ""; return }
            try? await Task.sleep(nanoseconds: 220_000_000)
            if !Task.isCancelled { appliedLibraryQuery = libraryQuery }
        }
        .refreshable { await refreshDownloads() }
        .task(id: store.entries.map(\.id)) { await refreshStorage() }
        .onChange(of: store.installingID) { old, new in
            // Session-only queue state: an install that ended with an error shows as failed with Retry.
            guard let old, new == nil else { return }
            let installed = store.entries.first(where: { $0.id == old })?.installedAt != nil
            if store.error != nil && !installed { failedInstalls.insert(old) } else { failedInstalls.remove(old) }
        }
    }

    /// One saved IPA with its existing swipe actions (install as-is, delete).
    private func entryRow(_ entry: EncryptedIPAEntry) -> some View {
        EncryptedEntryCard(entry: entry, store: store, vm: vm, failed: failedInstalls.contains(entry.id),
                           onInstall: { install(entry) }) { pendingDelete = entry }
            .modifier(StoreListRow())
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { install(entry) } label: {
                    Label(t("Install as-is", "ثبّت متل ما هو", "وەک خۆی دابمەزرێنە", "Wekî xwe saz bike"), systemImage: "arrow.down.app.fill")
                }
                .tint(StoreGallery.violet)
                .disabled(store.busy != nil)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button { StoreHaptics.delete(); pendingDelete = entry } label: {
                    Label(t("Delete", "حذف", "سڕینەوە", "Jê bibe"), systemImage: "trash.fill")
                }
                .tint(MirsaPalette.danger)
                .disabled(store.installingID == entry.id)
            }
    }

    /// The big "now" card: a running App Store download (with Pause/Resume and Cancel, the same
    /// transfer controls as the App Store screen) or a running install.
    @ViewBuilder private var nowCard: some View {
        if transferControl.phase != .idle {
            let progress = live.progress
            let expected = transferControl.expected > 0 ? transferControl.expected : (progress?.expected ?? 0)
            let received = max(transferControl.received, progress?.received ?? 0)
            let fraction: Double? = progress?.fraction ?? (expected > 0 ? min(1, Double(received) / Double(expected)) : nil)
            nowCardBody(title: StoreGalleryText.nowDownloading,
                        name: live.app?.name ?? StoreGalleryText.appStoreDownload,
                        fraction: fraction,
                        detail: bytesLine(received: received, expected: expected, fraction: fraction),
                        live: speedLine(progress: progress)) {
                StoreArtwork(url: live.app?.artworkURL ?? "", seed: live.app?.seed ?? "store", name: live.app?.name ?? "A", size: 58)
            } controls: {
                HStack(spacing: MirsaSpacing.xs) {
                    Button {
                        StoreHaptics.select()
                        if transferControl.phase == .paused { transferControl.resume() } else { transferControl.pause() }
                    } label: {
                        Label(transferControl.phase == .paused ? StorePauseText.resume : StorePauseText.pause,
                              systemImage: transferControl.phase == .paused ? "play.fill" : "pause.fill")
                            .galleryPill(.dark, height: 38)
                    }
                    .buttonStyle(.mirsaPress)
                    .accessibilityIdentifier("store-now-pause-resume")
                    Button { StoreHaptics.delete(); transferControl.discardCurrent() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.mirsaPress)
                    .accessibilityLabel(tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal"))
                    .accessibilityIdentifier("store-now-cancel")
                }
                if transferControl.phase == .paused || transferControl.phase == .waitingForNetwork {
                    Text(transferControl.phase == .paused ? StorePauseText.paused : StorePauseText.waiting)
                        .font(MirsaFont.caption).foregroundStyle(StoreGallery.secondary)
                }
            }
        } else if let id = store.installingID, let entry = store.entries.first(where: { $0.id == id }) {
            let fraction = min(max(store.progress, 0), 1)
            nowCardBody(title: StoreGalleryText.nowInstalling, name: entry.name, fraction: fraction,
                        detail: "\(Int((fraction * 100).rounded()))% · " + StoreBytes.text(entry.sizeBytes),
                        live: nil) {
                if let img = store.icon(entry) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                } else {
                    StoreArtwork(url: "", seed: entry.bundleID, name: entry.name, size: 58)
                }
            } controls: {
                EmptyView()
            }
        }
    }

    private func nowCardBody<Icon: View, Controls: View>(title: String, name: String, fraction: Double?, detail: String, live: String?,
                                                         @ViewBuilder icon: @escaping () -> Icon, @ViewBuilder controls: () -> Controls) -> some View {
        HStack(alignment: .center, spacing: MirsaSpacing.m) {
            StoreGalleryProgressRing(fraction: fraction, diameter: 112, lineWidth: 9) { icon() }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.white.opacity(0.7))
                Text(name).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.7)
                Text(detail).font(.system(size: 13).monospacedDigit()).foregroundStyle(StoreGallery.secondary).lineLimit(1).minimumScaleFactor(0.7)
                if let live {
                    Text(live).font(.system(size: 13).monospacedDigit()).foregroundStyle(StoreGallery.sky).lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 4) { controls() }.padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [StoreGallery.violet.opacity(0.35), Color(red: 0.08, green: 0.06, blue: 0.16).opacity(0.6)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .galleryGlass(radius: 28)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("store-now-card")
    }

    private func bytesLine(received: Int64, expected: Int64, fraction: Double?) -> String {
        let percent = fraction.map { "\(Int(($0 * 100).rounded()))% · " } ?? ""
        let total = expected > 0 ? " / " + StoreBytes.text(expected) : ""
        return percent + StoreBytes.text(received) + total
    }

    private func speedLine(progress: StoreDownloadProgress?) -> String? {
        guard let progress, progress.speed > 0 else { return live.phaseText.isEmpty ? nil : live.phaseText }
        let speed = StoreBytes.text(Int64(min(progress.speed, Double(Int64.max / 2)))) + "/s"
        return live.phaseText.isEmpty ? speed : speed + " · " + live.phaseText
    }

    private var openSearchAction: (() -> Void)? {
        guard storeLoginAvailable else { return nil }
        return { withAnimation(MirsaMotion.select) { section = .search } }
    }

    /// Same install call as the card's button; clears a previous failure first.
    private func install(_ entry: EncryptedIPAEntry) {
        guard store.busy == nil else { return }
        failedInstalls.remove(entry.id)
        StoreHaptics.install()
        Task { await store.install(entry, vm: vm) }
    }

    private func refreshDownloads() async {
        await refreshStorage()
        await storeAccount.refresh()
    }

    private func refreshStorage() async {
        let entries = store.entries
        let result = await StoreStorageReader.read(entries)
        storageSizes = result.sizes
        storageFree = result.free
    }

    private var storageTotal: Int64 { storageSlices.reduce(0) { $0 + $1.bytes } }
    private var storageSlices: [StoreStorageSummary.Slice] {
        store.entries
            .compactMap { e in storageSizes[e.id].map { StoreStorageSummary.Slice(id: e.id, name: e.name, bytes: $0, color: StoreLuxe.seedColor(e.bundleID)) } }
            .sorted { $0.bytes > $1.bytes }
    }

    /// Compact queued row with a thin bar while a file is imported.
    private var importingRow: some View {
        HStack(spacing: MirsaSpacing.s) {
            ProgressView().tint(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StoreGallery.violet.opacity(0.25)))
            VStack(alignment: .leading, spacing: 6) {
                Text(store.busy ?? "").font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                StoreGalleryThinBar(fraction: nil)
            }
            Text(storeText("Loading", "عم يحمّل", de: "Lädt", ckb: "بارکردن", kmr: "Tê barkirin"))
                .font(.system(size: 12)).foregroundStyle(StoreGallery.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .galleryGlass(radius: 18)
        .accessibilityElement(children: .combine)
    }

    private var introCard: some View {
        HStack(alignment: .top, spacing: MirsaSpacing.s) {
            Image(systemName: "lock.shield.fill").font(.system(size: MirsaIconSize.l))
                .foregroundStyle(StoreGallery.lilac).frame(width: MirsaIconSize.well)
            Text(t("Install App Store IPAs exactly as they are. Mirsa does not sign, change or decrypt them. They only open on an iPhone signed in to the Apple ID that bought them.",
                   "ثبّت ملفات IPA من App Store متل ما هي. مرسى ما بيوقّعها ولا بيعدّلها ولا بيفك تشفيرها. بتشتغل بس على آيفون مسجّل دخول بنفس حساب Apple يلي اشتراها.",
                   "IPAکانی App Store وەک خۆیان دابمەزرێنە. Mirsa واژۆیان ناکات، دەستکارییان ناکات و ڕەمزیان ناکاتەوە. تەنها لەسەر ئایفۆنێک دەکرێنەوە کە بە هەمان Apple ID کە کڕیویەتی چووبێتە ژوورەوە.",
                   "IPA yên App Store wekî xwe saz bike. Mirsa wan îmze nake, naguherîne û şîfreya wan venake. Tenê li ser iPhone ku bi heman Apple ID ya ku ew kirî ketiye vedibin."))
                .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MirsaSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .galleryGlass(radius: 22)
    }

    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            Text(t("What you get", "شو بتستفيد", "چی بەدەست دێنیت", "Tu çi werdigirî"))
                .font(MirsaFont.cardTitle).foregroundStyle(.white)
            benefitRow("clock.arrow.circlepath",
                       t("Keep a copy of an app you bought: an older version you like, or an app removed from the App Store.",
                         "احتفظ بنسخة من تطبيق اشتريته: نسخة قديمة بتحبها، أو تطبيق انشال من App Store.",
                         "کۆپییەک لە ئەپێک کە کڕیوتە هەڵبگرە: وەشانێکی کۆن کە حەزت لێیەتی، یان ئەپێک کە لە App Store لابراوە.",
                         "Kopiyek ji sepana ku te kirî biparêze: guhertoyek kevn ku tu jê hez dikî, an sepanek ku ji App Store hatiye rakirin."))
            benefitRow("checkmark.seal.fill",
                       t("Installs with Apple's original signature. No certificate needed.",
                         "بيتثبّت بتوقيع Apple الأصلي، بلا شهادة.",
                         "بە واژۆی ڕەسەنی Apple دادەمەزرێت. پێویستی بە بڕوانامە نییە.",
                         "Bi îmzeya resen a Apple tê sazkirin. Sertîfîka ne pêwîst e."))
            benefitRow("calendar.badge.checkmark",
                       t("No 7-day expiry and no re-signing.",
                         "ما بينتهي بعد 7 أيام، وما بدو إعادة توقيع.",
                         "دوای ٧ ڕۆژ بەسەرناچێت و پێویستی بە دووبارە واژۆکردن نییە.",
                         "Piştî 7 rojan naqede û ji nû ve îmzekirin ne pêwîst e."))
        }
        .padding(MirsaSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .galleryGlass(radius: 22)
    }

    private func benefitRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: MirsaSpacing.s) {
            Image(systemName: icon).foregroundStyle(StoreGallery.lilac).frame(width: MirsaIconSize.well)
            Text(text).font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var importButton: some View {
        Button { picking = true } label: {
            HStack(spacing: 8) {
                if store.busy != nil && store.installingID == nil { ProgressView().tint(.white) } else { Image(systemName: "square.and.arrow.down") }
                Text(t("Import encrypted IPA", "استيراد IPA مشفّر", "هاوردەکردنی IPAی شفرەکراو", "IPA ya şîfrekirî bîne"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.mirsaPrimary)
        .controlSize(.large)
        .disabled(store.busy != nil)
        .accessibilityIdentifier("encrypted-import")
    }

    private var appStoreButton: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.xs) {
            if storeLoginAvailable {
                Button { showingAppStore = true } label: {
                    Label(t("My App Store", "حسابي بالـApp Store", "ئەپستۆری من", "App Store ya min"),
                          systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.mirsaPrimary)
                .accessibilityIdentifier("encrypted-appstore-account")
            } else {
            Label(t("My App Store • Coming soon", "حسابي بالـApp Store • قريباً", "ئەپستۆری من • بەم زووانە", "App Store ya min • Nêzîk e"),
                  systemImage: "clock.badge")
                .font(MirsaFont.button).foregroundStyle(MirsaPalette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .galleryGlass(radius: 22)
                .accessibilityIdentifier("encrypted-appstore-coming-soon")
            Text(t("Signing in to Apple inside Mirsa is not available yet. You can still import App Store IPAs from Files.",
                   "تسجيل الدخول لحساب Apple جوا مرسى مو متاح لسا. لسا فيك تستورد IPA من الملفات.",
                   "چوونەژوورەوە بۆ Apple لەناو Mirsa هێشتا بەردەست نییە. هێشتا دەتوانیت IPA لە Files هاوردە بکەیت.",
                   "Têketina Apple di hundirê Mirsa de hêj ne amade ye. Hîn jî tu dikarî IPA ji Files têxî."))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: MirsaSpacing.s) {
            Image(systemName: "lock.doc").font(.largeTitle).foregroundStyle(MirsaPalette.textTertiary)
            Text(t("No encrypted IPAs yet", "لسّا ما في IPA مشفّرة", "هێشتا هیچ IPAیەکی شفرەکراو نییە", "Hêj IPA ya şîfrekirî tune"))
                .font(MirsaFont.cardTitle).foregroundStyle(.white)
            Text(t("Import an App Store IPA from Files.",
                   "استورد IPA من App Store من الملفات.",
                   "IPAیەکی App Store لە Files هاوردە بکە.",
                   "IPA yeke App Store ji Files bîne."))
                .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary).multilineTextAlignment(.center)
        }
        .padding(MirsaSpacing.xl)
        .frame(maxWidth: .infinity)
        .galleryGlass(radius: 22)
    }
}

private struct EncryptedEntryCard: View {
    let entry: EncryptedIPAEntry
    @ObservedObject var store: EncryptedAppsStore
    let vm: AppViewModel
    var failed = false
    /// The existing install call (store.install), wrapped by the page for haptics and queue state.
    let onInstall: () -> Void
    let onDelete: () -> Void

    @State private var installStart: Date?
    /// Icon average colour, computed once per entry off the main thread.
    @State private var iconTint: Color?
    private var tintKey: String { "store-ipa|" + entry.id.uuidString }
    @State private var showNotes = false

    private func t(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String { EncryptedText.t(en, ar, ckb, kmr) }

    private enum QueueState { case loading, failed, installed, ready }
    private var state: QueueState {
        if store.installingID == entry.id { return .loading }
        if failed { return .failed }
        if entry.installedAt != nil { return .installed }
        return .ready
    }

    var body: some View {
        let match = store.match(entry)
        let notes = warnings(match)
        let installing = store.installingID == entry.id
        let icon = store.icon(entry)
        let tint = iconTint ?? StoreIconTintCache.cached(tintKey) ?? StoreLuxe.seedColor(entry.bundleID)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: MirsaSpacing.s) {
                Group {
                    if let img = icon { Image(uiImage: img).resizable().scaledToFill() }
                    else {
                        ZStack {
                            LinearGradient(colors: [StoreLuxe.seedColor(entry.bundleID), StoreLuxe.seedColor(entry.bundleID + "~")],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            Text(String(entry.name.prefix(1)).uppercased())
                                .font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        }
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                    Text("\(entry.version) · \(ByteCountFormatter.string(fromByteCount: entry.sizeBytes, countStyle: .file))")
                        .font(.system(size: 13)).foregroundStyle(StoreGallery.secondary).lineLimit(1)
                    Text(entry.bundleID).font(.caption2.monospaced()).foregroundStyle(StoreGallery.tertiary).lineLimit(1)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
                // Install pill: the existing install call (store.install, wrapped by the page).
                Button { onInstall() } label: {
                    InstallKeyedLabel(key: "entry:" + entry.id.uuidString) {
                        Text(StoreGalleryText.install)
                    }
                    .galleryPill(installing ? .accent : .light, height: 34)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.mirsaPress)
                .disabled(store.busy != nil)
                .opacity(store.busy != nil && !installing ? 0.5 : 1)
                .accessibilityLabel(t("Install as-is", "ثبّت متل ما هو", "وەک خۆی دابمەزرێنە", "Wekî xwe saz bike"))
            }
            if installing { installProgress }
            HStack(spacing: MirsaSpacing.xs) {
                stateBadge
                purchaserRow
                Spacer(minLength: 0)
                // Share and Delete are icon-only so long labels never wrap mid-word; VoiceOver keeps the full label.
                StoreShareIPAButton(entry: entry).buttonStyle(.mirsaSecondary)
                    .labelStyle(.iconOnly).frame(width: 48)
                Button { StoreHaptics.delete(); onDelete() } label: {
                    Label(t("Delete", "حذف", "سڕینەوە", "Jê bibe"), systemImage: "trash")
                        .foregroundStyle(MirsaPalette.danger)
                }
                .buttonStyle(.mirsaSecondary)
                .labelStyle(.iconOnly).frame(width: 48)
                .disabled(installing)
            }
            if !notes.isEmpty {
                Button { withAnimation(.easeOut(duration: 0.2)) { showNotes.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(t("Notes: ", "ملاحظات: ", "تێبینی: ", "Not: ") + "\(notes.count)")
                        Spacer()
                        Image(systemName: showNotes ? "chevron.up" : "chevron.down")
                    }
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if showNotes {
                    ForEach(notes, id: \.self) { w in
                        Text(w).font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if state == .failed {
                HStack(spacing: MirsaSpacing.xs) {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(StoreLuxe.failed)
                    Text(storeText("The last install did not finish.", "آخر تثبيت ما كمل.", de: "Die letzte Installation wurde nicht abgeschlossen.",
                                   ckb: "دوایین دامەزراندن تەواو نەبوو.", kmr: "Sazkirina dawî neqediya."))
                        .font(MirsaFont.caption).foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Button { onInstall() } label: {
                        Label(storeText("Retry", "إعادة المحاولة", de: "Erneut", ckb: "دووبارە", kmr: "Dîsa"), systemImage: "arrow.clockwise")
                            .font(MirsaFont.button).foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(height: 32)
                            .background(StoreLuxe.failed.opacity(0.85), in: Capsule())
                    }
                    .buttonStyle(.mirsaPress)
                    .disabled(store.busy != nil)
                    .accessibilityIdentifier("store-queue-retry")
                }
                .padding(10)
                .background(StoreLuxe.failed.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(14)
        .galleryGlass(radius: 22, tint: tint.opacity(0.55))
        .contextMenu {
            Button { StoreLinks.copy(entry.bundleID) } label: {
                Label(storeText("Copy Bundle ID", "نسخ Bundle ID", de: "Bundle-ID kopieren", ckb: "کۆپی Bundle ID", kmr: "Bundle ID kopî bike"), systemImage: "doc.on.doc")
            }
            if let id = entry.metadata?.itemID, let link = StoreLinks.appPage(id: id, country: AppStoreSectionModel.shared.account?.country ?? "us") {
                ShareLink(item: link) {
                    Label(storeText("Share App Store link", "مشاركة رابط App Store", de: "App-Store-Link teilen", ckb: "هاوبەشکردنی بەستەری App Store", kmr: "Girêdana App Store parve bike"), systemImage: "square.and.arrow.up")
                }
            }
            Button { onInstall() } label: {
                Label(t("Install as-is", "ثبّت متل ما هو", "وەک خۆی دابمەزرێنە", "Wekî xwe saz bike"), systemImage: "arrow.down.app")
            }
            .disabled(store.busy != nil)
            Button(role: .destructive) { StoreHaptics.delete(); onDelete() } label: {
                Label(t("Delete", "حذف", "سڕینەوە", "Jê bibe"), systemImage: "trash")
            }
            .disabled(installing)
        }
        .onChange(of: store.installingID) { _, id in installStart = id == entry.id ? Date() : nil }
        .task(id: entry.id) {
            guard iconTint == nil else { return }
            if let c = await StoreIconTintCache.color(tintKey, image: store.icon(entry)) { iconTint = c }
        }
    }

    @ViewBuilder private var stateBadge: some View {
        switch state {
        case .loading:
            StoreStateBadge(title: storeText("Installing", "عم يثبّت", de: "Installiert", ckb: "دادەمەزرێت", kmr: "Tê sazkirin"), color: StoreLuxe.loading)
        case .failed:
            StoreStateBadge(title: storeText("Failed", "فشل", de: "Fehlgeschlagen", ckb: "سەرنەکەوت", kmr: "Têk çû"), color: StoreLuxe.failed, icon: "exclamationmark")
        case .installed:
            StoreStateBadge(title: t("Installed", "مثبّت", "دامەزراوە", "Sazkirî"), color: StoreLuxe.done, icon: "checkmark")
        case .ready:
            StoreStateBadge(title: storeText("Ready", "جاهز", de: "Bereit", ckb: "ئامادەیە", kmr: "Amade"), color: StoreLuxe.ready)
        }
    }

    /// Percentage from the existing install progress; speed estimated in the UI from
    /// that fraction, the file size and the elapsed time.
    private var installProgress: some View {
        VStack(alignment: .leading, spacing: 4) {
            StoreGalleryThinBar(fraction: min(max(store.progress, 0), 1))
            TimelineView(.periodic(from: installStart ?? Date(), by: 1)) { ctx in
                let fraction = min(max(store.progress, 0), 1)
                let elapsed = installStart.map { ctx.date.timeIntervalSince($0) } ?? 0
                let speed = elapsed > 1 && entry.sizeBytes > 0 ? Double(entry.sizeBytes) * fraction / elapsed : 0
                HStack {
                    Text("\(Int((fraction * 100).rounded()))%").monospacedDigit()
                    Spacer()
                    if speed > 0 {
                        Text("≈ " + ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s").monospacedDigit()
                    }
                }
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textSecondary)
            }
        }
    }

    @ViewBuilder private var purchaserRow: some View {
        let who = entry.metadata?.purchaserAppleID
        HStack(spacing: 6) {
            Image(systemName: "person.crop.circle").foregroundStyle(MirsaPalette.textSecondary)
            Text(t("Bought by: ", "اشتراه: ", "کڕیار: ", "Kirrîyar: ") + (who ?? t("unknown", "غير معروف", "نەزانراو", "nenas")))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textSecondary).lineLimit(1).truncationMode(.middle)
        }
    }

    private func warnings(_ match: EncryptedAccountMatch) -> [String] {
        var out: [String] = []
        if !entry.hasSinf {
            out.append(t("No purchase data (sinf) in this IPA. iOS will likely refuse to open it.",
                         "ما في بيانات شراء (sinf) بهالـIPA. غالباً iOS ما رح يفتحه.",
                         "هیچ داتای کڕین (sinf) لەم IPAیەدا نییە. لەوانەیە iOS نەیکاتەوە.",
                         "Di vê IPA de daneyên kirînê (sinf) tune. Dibe ku iOS wê venake."))
        }
        if entry.encryptedBinary == false {
            out.append(t("This IPA is not encrypted. You can also add it from the Apps tab.",
                         "هالـIPA مو مشفّر. فيك تضيفه كمان من تبويب التطبيقات.",
                         "ئەم IPAیە شفرەکراو نییە. دەتوانیت لە بەشی ئەپەکانیشەوە زیادی بکەیت.",
                         "Ev IPA ne şîfrekirî ye. Tu dikarî wê ji tabloya Sepanan jî zêde bikî."))
        }
        switch match {
        case .match: break
        case .mismatch(let mine):
            out.append(t("Bought with a different Apple ID than \(mine). It will only open on an iPhone signed in to the buyer's account.",
                         "انشرى بحساب Apple غير \(mine). بيشتغل بس على آيفون مسجّل دخول بحساب يلي اشتراه.",
                         "بە Apple IDیەکی جیاواز لە \(mine) کڕدراوە. تەنها لەسەر ئایفۆنێک دەکرێتەوە کە بە هەژماری کڕیار چووبێتە ژوورەوە.",
                         "Bi Apple ID ya ji \(mine) cuda hatiye kirîn. Tenê li ser iPhone ku bi hesabê kirrîyar ketiye vedibe."))
        case .noSignedInAccount:
            out.append(t("No Apple ID is signed in to Mirsa, so the buyer can't be checked. It will only open on an iPhone signed in to the buyer's account.",
                         "ما في حساب Apple مسجّل بمرسى، فما فينا نتأكد من المشتري. بيشتغل بس على آيفون مسجّل دخول بحساب يلي اشتراه.",
                         "هیچ Apple IDیەک لە Mirsa نەچووەتە ژوورەوە، بۆیە کڕیار پشکنین ناکرێت. تەنها لەسەر ئایفۆنێک دەکرێتەوە کە بە هەژماری کڕیار چووبێتە ژوورەوە.",
                         "Tu Apple ID di Mirsa de neketiye, ji ber vê kirrîyar nayê kontrolkirin. Tenê li ser iPhone ku bi hesabê kirrîyar ketiye vedibe."))
        case .unknownPurchaser:
            out.append(t("The buyer's Apple ID is not in this IPA. It will only open on an iPhone signed in to the account that bought it.",
                         "حساب المشتري مو موجود بهالـIPA. بيشتغل بس على آيفون مسجّل دخول بالحساب يلي اشتراه.",
                         "Apple IDی کڕیار لەم IPAیەدا نییە. تەنها لەسەر ئایفۆنێک دەکرێتەوە کە بە هەژمارێک چووبێتە ژوورەوە کە کڕیویەتی.",
                         "Apple ID ya kirrîyar di vê IPA de tune. Tenê li ser iPhone ku bi hesabê ku ew kirî ketiye vedibe."))
        }
        return out
    }
}
