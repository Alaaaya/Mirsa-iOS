import SwiftUI
import UniformTypeIdentifiers

/// Fourth tab: App Store (FairPlay-encrypted) IPAs, installed unmodified.
struct EncryptedAppsTab: View {
    @EnvironmentObject var vm: AppViewModel
    @ObservedObject private var store = EncryptedAppsStore.shared
    @ObservedObject private var storeAccount = AppStoreSectionModel.shared
    @State private var picking = false
    @State private var storeLoginAvailable = false
    @State private var showingAppStore = false
    @State private var pendingDelete: EncryptedIPAEntry?
    @State private var section: AppStoreSectionTab = AppStoreSectionTab.initial
    /// Recreates the inline sign-in/search screen when the session changed elsewhere.
    @State private var storeViewID = UUID()
    @State private var libraryQuery = ""
    @State private var showingAdd = false
    @State private var showingTools = false
    @State private var priorAccountID: String?

    private func t(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String { EncryptedText.t(en, ar, ckb, kmr) }

    var body: some View {
        // Every page stays alive while hidden, so switching tabs never cancels a
        // running sign-in, search or download in the App Store screen.
        ZStack {
            AuroraBackground().ignoresSafeArea()
            page(.search) { searchPage }
            page(.downloads) { downloadsPage }
            page(.purchases) { AppStorePurchasesPage(store: store, model: storeAccount, vm: vm, isActive: section == .purchases) }
            page(.account) {
                AppStoreAccountPage(model: storeAccount, library: store, storeAvailable: storeLoginAvailable,
                                    onAddAccount: { Task {
                                        priorAccountID = try? await MirsaStoreOnDeviceClient.shared.selectedAccountID()
                                        _ = try? await MirsaStoreOnDeviceClient.shared.beginAddAccount()
                                        showingAppStore = true } },
                                    onOpen: { tab in withAnimation(MirsaMotion.select) { section = tab } },
                                    onSignedOut: { storeViewID = UUID() })
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { AppStoreSectionBar(selection: $section) }
        .task {
            storeLoginAvailable = false
            storeLoginAvailable = await MirsaStoreServerClient.shared.loginAvailable()
            #if DEBUG
            if AppStoreSectionModel.fixtureAccount != nil { storeLoginAvailable = true }
            #endif
            await storeAccount.refresh()
        }
        .onChange(of: section) { _, _ in Task { await storeAccount.refresh() } }
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
            StoreLibraryToolsView(country: storeAccount.account?.country ?? "US",
                                  onAccountSwitched: { storeViewID = UUID(); Task { await storeAccount.refresh() } },
                                  onAddAccount: { showingTools = false; Task {
                                      priorAccountID = try? await MirsaStoreOnDeviceClient.shared.selectedAccountID()
                                      _ = try? await MirsaStoreOnDeviceClient.shared.beginAddAccount()
                                      showingAppStore = true } }) { url in
                do {
                    let entry = try await EncryptedAppsStore.adopt(file: url, move: false)
                    store.add(entry)
                    await store.install(entry, vm: vm)
                } catch { store.error = error.localizedDescription }
            }
        }
        .mirsaStatusBarScrim()
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
                    .mirsaCard(radius: MirsaRadius.l)
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

    private func page<Content: View>(_ tab: AppStoreSectionTab, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .opacity(section == tab ? 1 : 0)
            .allowsHitTesting(section == tab)
            .accessibilityHidden(section != tab)
    }

    /// The sign-in sheet may have signed in or out. Reload the inline screen only then.
    private func sessionMayHaveChanged() {
        if let prior = priorAccountID {
            priorAccountID = nil
            Task {
                let list = (try? await MirsaStoreOnDeviceClient.shared.listAccounts()) ?? []
                // Cancelled add: the new context is not listed, so restore the previous one.
                if let current = try? await MirsaStoreOnDeviceClient.shared.selectedAccountID(), !list.contains(where: { $0.id == current }),
                   list.contains(where: { $0.id == prior }) {
                    try? await MirsaStoreOnDeviceClient.shared.selectAccount(id: prior)
                }
                await storeAccount.refresh()
            }
        }
        let before = storeAccount.account
        Task {
            await storeAccount.refresh()
            if storeAccount.account != before { storeViewID = UUID() }
        }
    }

    // MARK: pages

    @ViewBuilder private var searchPage: some View {
        if storeLoginAvailable {
            // The existing sign-in, search, versions and download flow, unchanged.
            AppStoreAccountView(onDownloaded: { url in
                let entry = try await EncryptedAppsStore.adopt(file: url, move: false)
                store.add(entry)
            }, searchOnly: true, onOpenAccount: {
                withAnimation(MirsaMotion.select) { section = .account }
            })
            .id(storeViewID)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: MirsaSpacing.m) {
                    MirsaPageHeader(title: AppStoreSectionTab.search.title, subtitle: EncryptedText.tabTitle) {
                        LanguageGlobeMenu(size: MirsaIconSize.button)
                    }
                    appStoreButton
                    importButton
                }
                .padding(.horizontal, MirsaSpacing.page)
                .padding(.bottom, MirsaSpacing.xl)
            }
        }
    }

    private var filteredEntries: [EncryptedIPAEntry] {
        let q = libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.version.localizedCaseInsensitiveContains(q)
                || $0.bundleID.localizedCaseInsensitiveContains(q)
        }
    }

    private var downloadsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MirsaSpacing.m) {
                MirsaPageHeader(title: AppStoreSectionTab.downloads.title, subtitle: EncryptedText.tabTitle) {
                    HStack(spacing: MirsaSpacing.xs) {
                        Button { showingAdd = true } label: { MirsaIconButtonLabel(systemName: "plus") }
                            .modifier(MirsaSolidCard(shape: Circle(), tint: nil, elevation: 1))
                            .disabled(store.busy != nil)
                            .accessibilityLabel(t("Add a download", "إضافة تنزيل", "زیادکردنی داگرتن", "Daxistinekê zêde bike"))
                            .accessibilityIdentifier("store-add-download")
                        Button { showingTools = true } label: { MirsaIconButtonLabel(systemName: "wrench.and.screwdriver") }
                            .modifier(MirsaSolidCard(shape: Circle(), tint: nil, elevation: 1))
                            .accessibilityLabel(StoreFeatureText.tools)
                        LanguageGlobeMenu(size: MirsaIconSize.button)
                    }
                }
                AppStoreSearchField(placeholder: t("Search by name, version or Bundle ID", "البحث بالاسم أو الإصدار أو Bundle ID",
                                                   "گەڕان بە ناو، وەشان یان Bundle ID", "Bi nav, guherto an Bundle ID bigere"),
                                    text: $libraryQuery)
                if store.entries.isEmpty {
                    emptyCard
                    importButton
                } else {
                    Text(t("Items: ", "العناصر: ", "بڕگەکان: ", "Tişt: ") + "\(filteredEntries.count)")
                        .font(MirsaFont.sectionTitle).foregroundStyle(.white)
                        .padding(.top, MirsaSpacing.xs)
                    if filteredEntries.isEmpty {
                        Text(t("Nothing matches.", "ما في شي مطابق.", "هیچ شتێک ناگونجێت.", "Tiştek li hev nayê."))
                            .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                    }
                    ForEach(filteredEntries) { entry in
                        EncryptedEntryCard(entry: entry, store: store, vm: vm) { pendingDelete = entry }
                    }
                    importButton
                }
                Text(t("About App Store IPAs", "عن ملفات IPA من App Store", "دەربارەی IPAکانی App Store", "Derbarê IPAyên App Store"))
                    .font(MirsaFont.sectionTitle).foregroundStyle(.white)
                    .padding(.top, MirsaSpacing.s)
                introCard
                benefitsCard
            }
            .padding(.horizontal, MirsaSpacing.page)
            .padding(.bottom, MirsaSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var introCard: some View {
        HStack(alignment: .top, spacing: MirsaSpacing.s) {
            Image(systemName: "lock.shield.fill").font(.system(size: MirsaIconSize.l))
                .foregroundStyle(MirsaPalette.accentSoft).frame(width: MirsaIconSize.well)
            Text(t("Install App Store IPAs exactly as they are. Mirsa does not sign, change or decrypt them. They only open on an iPhone signed in to the Apple ID that bought them.",
                   "ثبّت ملفات IPA من App Store متل ما هي. مرسى ما بيوقّعها ولا بيعدّلها ولا بيفك تشفيرها. بتشتغل بس على آيفون مسجّل دخول بنفس حساب Apple يلي اشتراها.",
                   "IPAکانی App Store وەک خۆیان دابمەزرێنە. Mirsa واژۆیان ناکات، دەستکارییان ناکات و ڕەمزیان ناکاتەوە. تەنها لەسەر ئایفۆنێک دەکرێنەوە کە بە هەمان Apple ID کە کڕیویەتی چووبێتە ژوورەوە.",
                   "IPA yên App Store wekî xwe saz bike. Mirsa wan îmze nake, naguherîne û şîfreya wan venake. Tenê li ser iPhone ku bi heman Apple ID ya ku ew kirî ketiye vedibin."))
                .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MirsaSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mirsaCard()
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
        .mirsaCard()
    }

    private func benefitRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: MirsaSpacing.s) {
            Image(systemName: icon).foregroundStyle(MirsaPalette.accentSoft).frame(width: MirsaIconSize.well)
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
                .mirsaCard()
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
        .mirsaCard()
    }
}

private struct EncryptedEntryCard: View {
    let entry: EncryptedIPAEntry
    @ObservedObject var store: EncryptedAppsStore
    let vm: AppViewModel
    let onDelete: () -> Void

    @State private var installStart: Date?
    @State private var showNotes = false

    private func t(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String { EncryptedText.t(en, ar, ckb, kmr) }

    var body: some View {
        let match = store.match(entry)
        let notes = warnings(match)
        let installing = store.installingID == entry.id
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            HStack(spacing: MirsaSpacing.s) {
                Group {
                    if let img = store.icon(entry) { Image(uiImage: img).resizable().scaledToFill() }
                    else { Image(systemName: "app.dashed").font(.title).foregroundStyle(MirsaPalette.textTertiary) }
                }
                .frame(width: 60, height: 60)
                .background(MirsaPalette.cardRaised)
                .clipShape(RoundedRectangle(cornerRadius: MirsaRadius.icon, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(MirsaFont.cardTitle).foregroundStyle(.white).lineLimit(2)
                    Text("\(entry.version) · \(ByteCountFormatter.string(fromByteCount: entry.sizeBytes, countStyle: .file))")
                        .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textSecondary)
                    Text(entry.bundleID).font(.caption2.monospaced()).foregroundStyle(MirsaPalette.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if entry.installedAt != nil {
                    Label(t("Installed", "مثبّت", "دامەزراوە", "Sazkirî"), systemImage: "checkmark.seal.fill")
                        .font(MirsaFont.badge).foregroundStyle(MirsaPalette.success)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(MirsaPalette.success.opacity(0.14), in: Capsule())
                }
            }
            purchaserRow
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
            if installing { installProgress }
            HStack(spacing: MirsaSpacing.xs) {
                Button { Task { await store.install(entry, vm: vm) } } label: {
                    Label(t("Install as-is", "ثبّت متل ما هو", "وەک خۆی دابمەزرێنە", "Wekî xwe saz bike"), systemImage: "arrow.down.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.mirsaPrimary)
                .disabled(store.busy != nil)
                StoreShareIPAButton(entry: entry).buttonStyle(.mirsaSecondary)
                Button(role: .destructive, action: onDelete) {
                    Label(t("Delete", "حذف", "سڕینەوە", "Jê bibe"), systemImage: "trash")
                        .foregroundStyle(MirsaPalette.danger)
                }
                .buttonStyle(.mirsaSecondary)
                .disabled(installing)
            }
        }
        .padding(MirsaSpacing.card)
        .mirsaCard()
        .onChange(of: store.installingID) { _, id in installStart = id == entry.id ? Date() : nil }
    }

    /// Percentage from the existing install progress; speed estimated in the UI from
    /// that fraction, the file size and the elapsed time.
    private var installProgress: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: min(max(store.progress, 0), 1)).tint(MirsaPalette.accentSoft)
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
