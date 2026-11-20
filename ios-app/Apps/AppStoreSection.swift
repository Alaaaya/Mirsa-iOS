import SwiftUI
import ApplePackage
import CryptoKit

// MARK: - App Store section shell (UI only)
//
// Bottom tab bar and the Account, Purchases and Settings pages of the App Store tab.
// Everything here reads state that already exists: the signed-in Store account from
// MirsaStoreOnDeviceClient.currentAccount(), the imported IPA library from
// EncryptedAppsStore, and the app-wide theme/language settings. Sign-in, verification,
// search and downloads stay in AppStoreAccountView, unchanged.

enum AppStoreSectionTab: String, CaseIterable, Identifiable {
    case search, downloads, purchases, account
    var id: String { rawValue }

    var title: String {
        switch self {
        case .search: return storeText("Search", "بحث", de: "Suche", ckb: "گەڕان", kmr: "Lêgerîn")
        case .downloads: return storeText("Downloads", "التنزيلات", de: "Downloads", ckb: "داگرتنەکان", kmr: "Daxistin")
        case .purchases: return storeText("Purchases", "المشتريات", de: "Käufe", ckb: "کڕینەکان", kmr: "Kirîn")
        case .account: return storeText("Account", "الحساب", de: "Konto", ckb: "ئەکاونت", kmr: "Hesab")
        }
    }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .downloads: return "arrow.down.circle.fill"
        case .purchases: return "bag.fill"
        case .account: return "person.crop.circle.fill"
        }
    }

    /// Opens on the library, like the tab did before. UI tests can pick a tab.
    static var initial: AppStoreSectionTab {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if MirsaUITestHarness.active, let i = args.firstIndex(of: "-MirsaStoreTab"), i + 1 < args.count,
           let tab = AppStoreSectionTab(rawValue: args[i + 1]) { return tab }
        #endif
        return .downloads
    }
}

/// Read-only view of the Store session for the shell pages.
@MainActor
final class AppStoreSectionModel: ObservableObject {
    static let shared = AppStoreSectionModel()
    @Published private(set) var account: MirsaStoreAccount?
    @Published private(set) var loaded = false

    #if DEBUG
    /// UI-test fixture only. No Apple request is made.
    static var fixtureAccount: MirsaStoreAccount? {
        guard MirsaUITestHarness.active, ProcessInfo.processInfo.arguments.contains("-MirsaStoreFixtureAccount") else { return nil }
        return MirsaStoreAccount(email: "sample.user@example.com", country: "tr", name: "Sample User")
    }
    #endif

    @Published private(set) var cachedPurchases: [MirsaStorePurchase] = []
    @Published private(set) var refreshingPurchases = false
    private var historyTask: Task<[MirsaStorePurchase], Error>?
    private var historyAccount: MirsaStoreAccount?
    private var historyGeneration = UUID()
    private var historyDate: Date?
    private func purchaseCacheURL(_ account: MirsaStoreAccount) -> URL {
        let identity = account.email.lowercased() + "|" + account.country.lowercased()
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MirsaPurchaseHistory", isDirectory: true).appendingPathComponent(hash + ".json")
    }
    func purchases(force: Bool = false) async throws -> [MirsaStorePurchase] {
        guard let account else { return [] }
        if let task = historyTask, historyAccount == account { return try await task.value }
        if !force, let historyDate, Date().timeIntervalSince(historyDate) < 60 { return cachedPurchases }
        let generation = UUID()
        historyGeneration = generation
        historyAccount = account
        refreshingPurchases = true
        let task = Task { try await MirsaStoreOnDeviceClient.shared.purchaseHistory() }
        historyTask = task
        defer {
            if historyGeneration == generation { historyTask = nil; refreshingPurchases = false }
        }
        let result = try await task.value
        guard self.account == account, historyGeneration == generation else { throw CancellationError() }
        if cachedPurchases != result { cachedPurchases = result }
        historyDate = Date()
        let url = purchaseCacheURL(account)
        // Atomic, private per-account cache. No credentials are persisted here.
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(result).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch { /* A cache failure must not hide a successful history response. */ }
        }
        return result
    }

    @Published private(set) var sessionRevision = 0

    func updateAccount(_ value: MirsaStoreAccount?) {
        let changed = account != value
        sessionRevision += 1
        account = value
        loaded = true
        if changed {
            let previousHistory = historyTask
            previousHistory?.cancel(); historyTask = nil; historyGeneration = UUID()
            refreshingPurchases = false; historyDate = nil; cachedPurchases = []
            if let value, let data = try? Data(contentsOf: purchaseCacheURL(value)),
               let items = try? JSONDecoder().decode([MirsaStorePurchase].self, from: data) {
                cachedPurchases = items
            }
            if value != nil { Task {
                _ = try? await previousHistory?.value
                guard self.account == value else { return }
                _ = try? await self.purchases()
            } }
        }
    }

    func refresh() async {
        #if DEBUG
        if let fixture = Self.fixtureAccount { account = fixture; loaded = true; return }
        if MirsaUITestHarness.active { account = nil; loaded = true; return }
        #endif
        let revision = sessionRevision
        do {
            let current = try await MirsaStoreOnDeviceClient.shared.currentAccount()
            guard revision == sessionRevision else { return }
            if account != current { updateAccount(current) }
        } catch {
            // A temporary capability/network error is not a logout.
        }
        loaded = true
    }

    /// Same call the sign-in screen uses for its own Sign out button.
    func signOut() async throws {
        #if DEBUG
        if MirsaUITestHarness.active { account = nil; return }
        #endif
        try await MirsaStoreOnDeviceClient.shared.signOut()
        updateAccount(nil)
    }
}

enum AppStoreCountry {
    /// "TR · Türkiye" in the app language, or just the code when the name is unknown.
    static func label(_ code: String) -> String {
        let upper = code.uppercased()
        guard !upper.isEmpty else { return "—" }
        if let name = AppLanguageStore.shared.current.locale.localizedString(forRegionCode: upper)
            ?? Locale(identifier: "en").localizedString(forRegionCode: upper), name != upper {
            return "\(upper) · \(name)"
        }
        return upper
    }
}

// MARK: - Bottom tab bar

/// Floating glass bar with an animated indicator that glides between the sections.
/// It is the only bottom bar while the App Store tab is open: its leading Mirsa button
/// opens a menu of the app's other tabs, so the main dock never stacks on top of it.
struct AppStoreSectionBar: View {
    @Binding var selection: AppStoreSectionTab
    /// Leaves the App Store tab for one of the app's main tabs.
    var onLeave: ((AppTab) -> Void)? = nil
    @Namespace private var ns
    @State private var bounce = 0

    private var mirsaTitle: String { storeText("Mirsa", "مرسى", de: "Mirsa", ckb: "مرسى", kmr: "Mirsa") }

    @ViewBuilder private var mirsaMenu: some View {
        if let onLeave {
            Menu {
                ForEach(LiquidTabItem.mainTabs.filter { $0.tab != .encrypted }) { item in
                    Button { StoreHaptics.select(); onLeave(item.tab) } label: { Label(item.title, systemImage: item.icon) }
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 18, weight: .regular)).frame(height: 21)
                    Text(mirsaTitle).font(MirsaFont.tabLabel).lineLimit(1)
                        .minimumScaleFactor(0.7).allowsTightening(true)
                }
                .foregroundStyle(MirsaPalette.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Capsule())
            }
            .menuIndicator(.hidden)
            .accessibilityIdentifier("store-tab-mirsa")
            .accessibilityLabel(mirsaTitle)
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            mirsaMenu
            ForEach(AppStoreSectionTab.allCases) { tab in
                let on = selection == tab
                Button {
                    guard selection != tab else { return }
                    StoreHaptics.select()
                    bounce += 1
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: on ? .bold : .regular))
                            .symbolEffect(.bounce, value: on ? bounce : 0)
                            .frame(height: 21)
                        Text(tab.title).font(MirsaFont.tabLabel).lineLimit(1)
                            .minimumScaleFactor(0.7).allowsTightening(true)
                    }
                    .foregroundStyle(on ? Color.white : MirsaPalette.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if on {
                            ZStack {
                                Capsule().fill(StoreLuxe.identity).opacity(0.85)
                                Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.30), .clear], startPoint: .top, endPoint: .center))
                                Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.8)
                            }
                            .matchedGeometryEffect(id: "store-tab", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.mirsaPress)
                .accessibilityIdentifier("store-tab-\(tab.rawValue)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(height: 62)
        .storeGlassBar()
        .padding(.horizontal, MirsaSpacing.page + MirsaSpacing.xs)
        .padding(.top, MirsaSpacing.xxs)
        .padding(.bottom, MirsaSpacing.xs)
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - Shared pieces

struct AppStoreSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: MirsaSpacing.xs) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.white.opacity(0.55))
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .foregroundStyle(.white)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(MirsaPalette.textTertiary)
                }
                .accessibilityLabel(tr("Clear", "مسح", ckb: "سڕینەوە", kmr: "Paqij bike"))
            }
        }
        .font(MirsaFont.body)
        .padding(.horizontal, 18)
        .frame(height: 50)
        .background(Capsule().fill(Color.white.opacity(0.10)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.7))
    }
}

/// A titled, rounded glass group of rows with an optional explanation under it (gallery look).
struct AppStoreGroup<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        StoreGalleryGroup(title: title, footer: footer, content: content)
    }
}

struct AppStoreRowDivider: View {
    var inset: CGFloat = 58
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.6).padding(.leading, inset)
    }
}

struct AppStoreRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var tint: Color = .white
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        // White means "no colour of its own": the gallery's lilac squares.
        StoreGalleryRow(icon: icon, title: title, subtitle: subtitle,
                        tint: tint == .white ? StoreGallery.lilac : tint,
                        titleColor: tint == .white ? .white : tint,
                        chevron: false, trailing: trailing)
    }
}

struct AppStoreAvatar: View {
    let text: String
    var size: CGFloat = 56
    var body: some View {
        let initial = text.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() }
        ZStack {
            Circle().fill(MirsaPalette.accentGradient)
            if let initial {
                Text(initial).font(.system(size: size * 0.42, weight: .bold, design: .rounded)).foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.42)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Account

enum AppStoreAccountRoute: Hashable {
    case settings

    static var initialPath: [AppStoreAccountRoute] {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if MirsaUITestHarness.active, let i = args.firstIndex(of: "-MirsaStoreRoute"), i + 1 < args.count, args[i + 1] == "settings" {
            return [.settings]
        }
        #endif
        return []
    }
}

struct AppStoreAccountPage: View {
    @ObservedObject var model: AppStoreSectionModel
    @ObservedObject var library: EncryptedAppsStore
    let storeAvailable: Bool
    let onAddAccount: () -> Void
    let onOpen: (AppStoreSectionTab) -> Void
    let onSignedOut: () -> Void
    /// Same refresh the library tools sheet runs after an account switch.
    var onAccountSwitched: () -> Void = {}
    /// Opens the existing library tools sheet (updates, wishlist, pins).
    var onOpenTools: (() -> Void)? = nil
    /// Leaves the App Store tab for one of Mirsa's main tabs (the former "Mirsa" bar menu).
    var onLeave: ((AppTab) -> Void)? = nil

    @ObservedObject private var wishes = StoreLibraryModel.shared
    @State private var path: [AppStoreAccountRoute] = AppStoreAccountRoute.initialPath
    @State private var confirmSignOut = false
    @State private var signingOut = false
    @State private var error: String?
    @State private var showSwitcher = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: MirsaSpacing.l) {
                    StoreGalleryHeader(title: storeText("Account", "الحساب", de: "Konto", ckb: "ئەکاونت", kmr: "Hesab")) {
                        if let onLeave { StoreGalleryMirsaMenu(onLeave: onLeave) }
                    }
                    profileCard
                    libraryGroup
                    storeGroup
                    if model.account != nil { signOutGroup }
                }
                .environment(\.layoutDirection, StoreGallery.direction)
                .padding(.horizontal, MirsaSpacing.page)
                .padding(.bottom, MirsaSpacing.xl)
            }
            .refreshable { await model.refresh() }
            .background(StoreGalleryBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppStoreAccountRoute.self) { route in
                switch route {
                case .settings: AppStoreDownloadSettingsPage(model: model, library: library)
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .sheet(isPresented: $showSwitcher) {
            StoreAccountSwitcherSheet(current: model.account, storeAvailable: storeAvailable,
                                      onSwitched: onAccountSwitched, onAddAccount: onAddAccount)
        }
        .confirmationDialog(tr("Sign out of this Apple Account?", "تطلع من حساب Apple؟", ckb: "لە ئەکاونتی Apple بچیتە دەرەوە؟", kmr: "Ji hesabê Apple derkevî?"),
                            isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(tr("Sign out", "تسجيل الخروج", ckb: "چوونە دەرەوە", kmr: "Derkeve"), role: .destructive) { signOut() }
            Button(tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal"), role: .cancel) {}
        } message: {
            Text(tr("Your local Apple session is deleted. Imported IPAs stay.",
                    "بتنمسح جلسة دخول Apple من آيفونك. ملفات IPA المستوردة بتضل.",
                    ckb: "دانیشتنی Apple لەسەر ئایفۆنەکەت دەسڕدرێتەوە. IPA هاوردەکراوەکان دەمێنن.",
                    kmr: "Danişîna Apple li ser iPhone tê jêbirin. IPAyên hatine anîn dimînin."))
        }
        .alert(tr("Notice", "تنبيه", ckb: "ئاگاداری", kmr: "Agahdarî"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(tr("OK", "تمام", ckb: "باشە", kmr: "Baş e")) { error = nil }
        } message: { Text(error ?? "") }
    }

    /// Gradient Apple ID card: initial, name, masked email, storefront and connected chips, switch account.
    @ViewBuilder private var profileCard: some View {
        if let a = model.account {
            StoreGalleryAccountCard(name: a.name, email: a.email, country: a.country,
                                    onSwitch: { StoreHaptics.select(); showSwitcher = true })
        } else {
            VStack(alignment: .leading, spacing: MirsaSpacing.s) {
                HStack(spacing: MirsaSpacing.s) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Circle().fill(Color.white.opacity(0.2)))
                        .accessibilityHidden(true)
                    Text(tr("Not signed in", "مو مسجّل دخول", ckb: "نەچوویتە ژوورەوە", kmr: "Te têneketiye"))
                        .font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                Text(storeAvailable
                     ? tr("Sign in with your Apple Account to search and download apps it owns.",
                          "سجّل دخول بحساب Apple تبعك لتدوّر وتنزّل التطبيقات يلي بيملكها.",
                          ckb: "بە ئەکاونتی Apple بچۆ ژوورەوە بۆ گەڕان و داگرتنی ئەو ئەپانەی خاوەنیانی.",
                          kmr: "Bi hesabê xwe yê Apple têkeve da ku li sepanên wî bigerî û daxî.")
                     : tr("Signing in to Apple inside Mirsa is not available yet. You can still import App Store IPAs from Files.",
                          "تسجيل الدخول لحساب Apple جوا مرسى مو متاح لسا. لسا فيك تستورد IPA من الملفات.",
                          ckb: "چوونەژوورەوە بۆ Apple لەناو Mirsa هێشتا بەردەست نییە. هێشتا دەتوانیت IPA لە Files هاوردە بکەیت.",
                          kmr: "Têketina Apple di hundirê Mirsa de hêj ne amade ye. Hîn jî tu dikarî IPA ji Files têxî."))
                    .font(MirsaFont.secondary).foregroundStyle(Color.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                if storeAvailable {
                    Button { onAddAccount() } label: {
                        Text(tr("Sign in", "تسجيل الدخول", ckb: "چوونەژوورەوە", kmr: "Têkeve")).galleryPill(.light, height: 40)
                    }
                    .buttonStyle(.mirsaPress)
                    .accessibilityIdentifier("store-account-sign-in")
                }
            }
            .padding(MirsaSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [StoreGallery.violet.opacity(0.42), StoreGallery.cyan.opacity(0.18)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 0.7))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("store-account-profile")
        }
    }

    /// Purchases, wishlist, downloads and installs.
    private var libraryGroup: some View {
        StoreGalleryGroup {
            Button { onOpen(.purchases) } label: {
                StoreGalleryRow(icon: "bag", title: storeText("Purchases", "المشتريات", de: "Käufe", ckb: "کڕینەکان", kmr: "Kirîn")) {
                    if !model.cachedPurchases.isEmpty {
                        Text("\(model.cachedPurchases.count)").font(.system(size: 14)).foregroundStyle(StoreGallery.tertiary).monospacedDigit()
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("store-open-purchases")
            if let onOpenTools {
                StoreGalleryRowDivider()
                Button { onOpenTools() } label: {
                    StoreGalleryRow(icon: "heart", title: StoreFeatureText.wishlist, subtitle: StoreFeatureText.tools) {
                        Text("\(wishes.wishlist.count)").font(.system(size: 14)).foregroundStyle(StoreGallery.tertiary).monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("store-open-wishlist")
            }
            StoreGalleryRowDivider()
            Button { onOpen(.downloads) } label: {
                StoreGalleryRow(icon: "clock.arrow.circlepath", title: storeText("Downloads and installs", "التنزيلات والتثبيت", de: "Downloads und Installationen", ckb: "داگرتن و دامەزراندن", kmr: "Daxistin û sazkirin")) {
                    Text("\(library.entries.count)").font(.system(size: 14)).foregroundStyle(StoreGallery.tertiary).monospacedDigit()
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("store-open-downloads")
        }
    }

    /// Store region, saved Apple Accounts (switch, add) and the download settings.
    private var storeGroup: some View {
        StoreGalleryGroup(footer: storeText("Switch between the Apple Accounts saved in Mirsa. Search and downloads use the selected account's storefront.",
                                            "بدّل بين حسابات Apple المحفوظة بمرسى. البحث والتنزيل بيستخدموا متجر الحساب المختار.",
                                            de: "Wechsle zwischen den in Mirsa gespeicherten Apple-Konten. Suche und Downloads nutzen den Store des gewählten Kontos.",
                                            ckb: "لە نێوان ئەکاونتە Apple ـە پاشەکەوتکراوەکانی Mirsa بگۆڕە. گەڕان و داگرتن ستۆری ئەکاونتی هەڵبژێردراو بەکاردەهێنن.",
                                            kmr: "Di navbera hesabên Apple yên di Mirsa de tomarkirî biguherîne. Lêgerîn û daxistin store ya hesabê hilbijartî bi kar tînin.")) {
            StoreGalleryRow(icon: "globe", title: StoreGalleryText.storeRegion, tint: StoreGallery.cyan, chevron: false) {
                Text(model.account.map { StoreIdentity.flag($0.country) + " " + AppStoreCountry.label($0.country) }
                     ?? tr("Not signed in", "مو مسجّل دخول", ckb: "نەچوویتە ژوورەوە", kmr: "Te têneketiye"))
                    .font(.system(size: 14)).foregroundStyle(StoreGallery.tertiary).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            if model.account != nil {
                StoreGalleryRowDivider()
                Button { StoreHaptics.select(); showSwitcher = true } label: {
                    StoreGalleryRow(icon: "person.2", title: storeText("Saved accounts", "الحسابات المحفوظة", de: "Gespeicherte Konten", ckb: "ئەکاونتە پاشەکەوتکراوەکان", kmr: "Hesabên tomarkirî"),
                                    tint: StoreGallery.cyan) { EmptyView() }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("store-saved-accounts")
            }
            StoreGalleryRowDivider()
            Button { onAddAccount() } label: {
                StoreGalleryRow(icon: "person.badge.plus", title: tr("Add account", "إضافة حساب", ckb: "زیادکردنی ئەکاونت", kmr: "Hesab zêde bike"),
                                subtitle: storeAvailable ? nil : tr("Coming soon", "قريباً", ckb: "بەم زووانە", kmr: "Nêzîk e"),
                                tint: StoreGallery.cyan) { EmptyView() }
            }
            .buttonStyle(.plain)
            .disabled(!storeAvailable)
            .opacity(storeAvailable ? 1 : 0.55)
            .accessibilityIdentifier("store-add-account")
            StoreGalleryRowDivider()
            Button { path.append(.settings) } label: {
                StoreGalleryRow(icon: "gearshape", title: storeText("Settings", "الإعدادات", de: "Einstellungen", ckb: "ڕێکخستنەکان", kmr: "Mîheng"),
                                tint: StoreGallery.cyan) { EmptyView() }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("store-open-settings")
        }
    }

    private var signOutGroup: some View {
        StoreGalleryGroup {
            Button { confirmSignOut = true } label: {
                StoreGalleryRow(icon: "rectangle.portrait.and.arrow.right", title: tr("Sign out", "تسجيل الخروج", ckb: "چوونە دەرەوە", kmr: "Derkeve"),
                                tint: StoreGallery.rose, titleColor: StoreGallery.rose, chevron: !signingOut) {
                    if signingOut { ProgressView().tint(StoreGallery.rose) }
                }
            }
            .buttonStyle(.plain)
            .disabled(signingOut)
            .accessibilityIdentifier("store-sign-out")
        }
    }

    private func signOut() {
        signingOut = true
        Task {
            defer { signingOut = false }
            do {
                try await model.signOut()
                onSignedOut()
            } catch {
                self.error = error.localizedDescription
                await model.refresh()
            }
        }
    }
}

// MARK: - Account switcher

/// Sheet over the existing saved-accounts registry: list, select, add. No sign-in here.
struct StoreAccountSwitcherSheet: View {
    let current: MirsaStoreAccount?
    let storeAvailable: Bool
    let onSwitched: () -> Void
    let onAddAccount: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var accounts: [MirsaStoreOnDeviceClient.SavedAccount] = []
    @State private var selectedID: String?
    @State private var loading = true
    @State private var switching: String?
    @State private var error: String?

    private struct Row: Identifiable { let id: String; let account: MirsaStoreAccount; let selected: Bool }
    private var rows: [Row] {
        if accounts.isEmpty, let current { return [Row(id: "current", account: current, selected: true)] }
        return accounts.map { Row(id: $0.id, account: $0.account, selected: $0.id == selectedID) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MirsaSpacing.s) {
                    if loading && rows.isEmpty {
                        StoreSkeletonCard(iconSize: 44)
                        StoreSkeletonCard(iconSize: 44)
                    }
                    ForEach(rows) { row in
                        Button { select(row) } label: {
                            HStack(spacing: MirsaSpacing.s) {
                                StoreMonogram(name: row.account.name, email: row.account.email, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.account.name.isEmpty ? row.account.email : row.account.name)
                                        .font(MirsaFont.cardTitle).foregroundStyle(.white).lineLimit(1)
                                    Text(row.account.email).font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                Spacer(minLength: MirsaSpacing.xs)
                                Text(StoreIdentity.flag(row.account.country) + " " + row.account.country.uppercased())
                                    .font(MirsaFont.caption.weight(.semibold)).foregroundStyle(MirsaPalette.textSecondary)
                                if switching == row.id { ProgressView().tint(.white) }
                                else if row.selected {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(StoreLuxe.identity)
                                        .accessibilityLabel(tr("Active", "الحالي", ckb: "چالاک", kmr: "Çalak"))
                                }
                            }
                            .padding(MirsaSpacing.s)
                            .storeGlass(radius: 20, tint: row.selected ? StoreLuxe.accent : nil, sheen: row.selected, elevation: 0.5)
                        }
                        .buttonStyle(.mirsaPress)
                        .disabled(switching != nil || row.selected)
                        .accessibilityElement(children: .combine)
                    }
                    Button {
                        dismiss()
                        // Let this sheet finish closing before the sign-in sheet opens.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onAddAccount() }
                    } label: {
                        Label(tr("Add account", "إضافة حساب", ckb: "زیادکردنی ئەکاونت", kmr: "Hesab zêde bike"), systemImage: "plus.circle.fill")
                            .font(MirsaFont.button).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(StoreLuxe.identity, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.mirsaPress)
                    .disabled(!storeAvailable || switching != nil)
                    .opacity(storeAvailable ? 1 : 0.55)
                    .padding(.top, MirsaSpacing.xs)
                    if let error {
                        Text(error).font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning)
                    }
                }
                .padding(MirsaSpacing.page)
            }
            .background(StoreGalleryBackground())
            .navigationTitle(storeText("Apple Accounts", "حسابات Apple", de: "Apple-Konten", ckb: "ئەکاونتەکانی Apple", kmr: "Hesabên Apple"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(storeText("Done", "تمام", de: "Fertig", ckb: "تەواو", kmr: "Temam")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
        .environment(\.layoutDirection, .leftToRight)
        .task { await load() }
    }

    private func load() async {
        #if DEBUG
        if MirsaUITestHarness.active { loading = false; return }
        #endif
        defer { loading = false }
        accounts = (try? await MirsaStoreOnDeviceClient.shared.listAccounts()) ?? []
        selectedID = try? await MirsaStoreOnDeviceClient.shared.selectedAccountID()
    }

    private func select(_ row: Row) {
        guard !row.selected, switching == nil, accounts.contains(where: { $0.id == row.id }) else { return }
        switching = row.id; error = nil
        Task {
            defer { switching = nil }
            do {
                try await MirsaStoreOnDeviceClient.shared.selectAccount(id: row.id)
                selectedID = row.id
                StoreHaptics.select()
                onSwitched()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Settings

struct AppStoreDownloadSettingsPage: View {
    @ObservedObject var model: AppStoreSectionModel
    @ObservedObject var library: EncryptedAppsStore
    @ObservedObject private var language = AppLanguageStore.shared
    @AppStorage(MirsaTheme.key) private var theme = MirsaTheme.liquid.rawValue
    @State private var tmpSize = "…"
    @State private var cleanupResult: String?
    @State private var cleaning = false
    @Environment(\.dismiss) private var dismiss

    private var librarySize: String {
        ByteCountFormatter.string(fromByteCount: library.entries.reduce(Int64(0)) { $0 + $1.sizeBytes }, countStyle: .file)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        if let build = info?["MirsaBuild"] as? String ?? info?["CFBundleVersion"] as? String { return "\(version) (\(build))" }
        return version
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MirsaSpacing.l) {
                AppStoreGroup(title: tr("Downloads", "التنزيل", ckb: "داگرتن", kmr: "Daxistin"),
                              footer: tr("Downloaded and imported IPAs are kept exactly as Apple sent them. They stay in Mirsa and are not backed up to iCloud.",
                                         "ملفات IPA يلي نزّلتها أو استوردتها بتنحفظ متل ما بعتتها Apple بالزبط. بتضل جوا مرسى وما بتنعمل إلها نسخة احتياطية على iCloud.",
                                         ckb: "IPA داگیراو و هاوردەکراوەکان وەک ئەوەی Apple ناردوویەتی دەپارێزرێن. لەناو Mirsa دەمێننەوە و باکئەپیان بۆ iCloud ناکرێت.",
                                         kmr: "IPAyên daxistî û anîn wekî ku Apple şandine têne parastin. Di Mirsa de dimînin û li iCloud nayên paşvekişandin.")) {
                    AppStoreRow(icon: "tray.full", title: tr("Saved IPAs", "ملفات IPA المحفوظة", ckb: "IPA هەڵگیراوەکان", kmr: "IPAyên tomarkirî")) {
                        Text("\(library.entries.count)").font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary).monospacedDigit()
                    }
                    AppStoreRowDivider()
                    AppStoreRow(icon: "internaldrive", title: tr("Space used", "المساحة المستخدمة", ckb: "شوێنی بەکارهاتوو", kmr: "Cihê bikaranî")) {
                        Text(librarySize).font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary).monospacedDigit()
                    }
                }

                AppStoreGroup(title: tr("Store", "المتجر", ckb: "ستۆر", kmr: "Store"),
                              footer: tr("Search and downloads use the storefront of the signed-in Apple Account. To use another country, sign in with an account from that country.",
                                         "البحث والتنزيل بيستخدموا واجهة المتجر تبع حساب Apple المسجّل. لتستخدم دولة تانية، سجّل دخول بحساب من هالدولة.",
                                         ckb: "گەڕان و داگرتن ستۆری ئەکاونتی Apple ی چووەژوورەوە بەکاردەهێنن. بۆ وڵاتێکی تر، بە ئەکاونتێکی ئەو وڵاتە بچۆ ژوورەوە.",
                                         kmr: "Lêgerîn û daxistin store ya hesabê Apple yê têketî bi kar tînin. Ji bo welatekî din, bi hesabekî wî welatî têkeve.")) {
                    AppStoreRow(icon: "globe", title: tr("Storefront", "واجهة المتجر", ckb: "ستۆر", kmr: "Store")) {
                        Text(model.account.map { AppStoreCountry.label($0.country) } ?? tr("Not signed in", "مو مسجّل دخول", ckb: "نەچوویتە ژوورەوە", kmr: "Te têneketiye"))
                            .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary).lineLimit(1)
                    }
                }

                AppStoreGroup(title: StoreStyle.settingTitle, footer: StoreStyle.explanation) {
                    StoreStyleSettingBlock()
                }

                AppStoreGroup(title: tr("Appearance", "المظهر", ckb: "ڕووکار", kmr: "Xuyang"),
                              footer: tr("Theme and language apply to all of Mirsa, the same as in the main settings.",
                                         "الثيم واللغة بيتطبقوا على كل مرسى، متل الإعدادات الرئيسية.",
                                         ckb: "ڕووکار و زمان بۆ هەموو Mirsa جێبەجێ دەبن، وەک ڕێکخستنە سەرەکییەکان.",
                                         kmr: "Tema û ziman li hemû Mirsa derbas dibin, wek mîhengên sereke.")) {
                    AppStoreRow(icon: "paintpalette", title: tr("Theme", "الثيم", ckb: "ڕووکار", kmr: "Tema")) {
                        Picker("", selection: $theme) {
                            ForEach(MirsaTheme.allCases) { item in Text(item.title).tag(item.rawValue) }
                        }
                        .pickerStyle(.menu).tint(MirsaPalette.accentSoft).labelsHidden()
                    }
                    AppStoreRowDivider()
                    AppStoreRow(icon: "character.bubble", title: tr("Language", "اللغة", ckb: "زمان", kmr: "Ziman")) {
                        Menu {
                            ForEach(AppLanguage.allCases) { l in
                                Button { language.set(l) } label: {
                                    if l == language.current { Label(l.nativeLabel, systemImage: "checkmark") } else { Text(l.nativeLabel) }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(language.current.nativeLabel)
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                            }
                            .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.accentSoft)
                        }
                    }
                }

                AppStoreGroup(title: tr("Maintenance", "الصيانة", ckb: "چاککردنەوە", kmr: "Lênêrîn"),
                              footer: tr("Only Mirsa's own working files that are not in use. Your apps, library and projects are never touched.",
                                         "بس ملفات الشغل المؤقتة تبع مرسى اللي مو مستخدمة. تطبيقاتك ومكتبتك ومشاريعك ما بتنلمس.",
                                         ckb: "تەنها فایلە کاتییەکانی خودی میرسا کە بەکارنایەن. ئەپ و کتێبخانە و پڕۆژەکانت دەست لێ نادرێت.",
                                         kmr: "Tenê pelên xebatê yên Mirsayê yên ku nayên bikaranîn. Sepan, pirtûkxane û projeyên te nayên destlêdan.")) {
                    Button { cleanTemp() } label: {
                        AppStoreRow(icon: "trash", title: tr("Clean temporary files", "تنظيف الملفات المؤقتة", ckb: "پاککردنەوەی فایلە کاتییەکان", kmr: "Pelên demkî paqij bike")) {
                            if cleaning { ProgressView().tint(.white) }
                            else { Text(tmpSize).font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary).monospacedDigit() }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(cleaning)
                    if let cleanupResult {
                        Text(cleanupResult).font(MirsaFont.secondary)
                            .foregroundStyle(MirsaPalette.textSecondary)
                            .padding(.horizontal, MirsaSpacing.m)
                            .padding(.bottom, MirsaSpacing.s)
                    }
                }

                AppStoreGroup {
                    AppStoreRow(icon: "info.circle", title: "Mirsa") {
                        Text(appVersion).font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary).monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, MirsaSpacing.page)
            .padding(.top, MirsaSpacing.s)
            .environment(\.layoutDirection, StoreGallery.direction)
            // A pushed page does not inherit the store's bottom inset; keep the last rows above the capsule and the dock.
            .padding(.bottom, MirsaSpacing.xl + StoreGallery.bottomClearance)
        }
        .background(StoreGalleryBackground())
        .navigationTitle(tr("Settings", "الإعدادات", ckb: "ڕێکخستنەکان", kmr: "Mîheng"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                }
                .accessibilityLabel(tr("Back", "رجوع", ckb: "گەڕانەوە", kmr: "Vegere"))
                .accessibilityIdentifier("store-settings-back")
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .environment(\.layoutDirection, .leftToRight)
        .onAppear { loadTempSize() }
    }

    private func loadTempSize() {
        DispatchQueue.global(qos: .utility).async {
            let text = MirsaManagedTmp.sizeText
            DispatchQueue.main.async { tmpSize = text }
        }
    }

    private func cleanTemp() {
        cleaning = true
        cleanupResult = nil
        DispatchQueue.global(qos: .utility).async {
            let before = MirsaManagedTmp.size()
            let removed = MirsaManagedTmp.cleanNow()
            let after = MirsaManagedTmp.size()
            let freed = ByteCountFormatter.string(fromByteCount: max(0, before - after), countStyle: .file)
            let text = ByteCountFormatter.string(fromByteCount: after, countStyle: .file)
            DispatchQueue.main.async {
                tmpSize = text
                cleaning = false
                if after > 0 {
                    cleanupResult = tr("Freed \(freed). Remaining files are protected, in use, or created during this session. Finish current work and relaunch Mirsa to retry.",
                        "تم تفريغ \(freed). الملفات الباقية محمية، قيد الاستخدام، أو انعملت بهالجلسة. خلّص الشغل وافتح مرسى من جديد لتجرّب.",
                        ckb: "\(freed) بەتاڵ کرا. فایلە ماوەکان پارێزراون یان بەکاردێن یان لەم دانیشتنە دروستکراون. دوای تەواوبوونی کار میرسا دووبارە بکەرەوە.",
                        kmr: "\(freed) hate valakirin. Pelên mayî parastî ne, di bikaranînê de ne an di vê danişînê de hatine çêkirin. Piştî xebatê Mirsa ji nû ve veke.")
                } else if removed > 0 {
                    cleanupResult = tr("Freed \(freed). Temporary files cleaned.", "تم تفريغ \(freed). نضّفنا الملفات المؤقتة.",
                        ckb: "\(freed) بەتاڵ کرا. فایلە کاتییەکان پاککرانەوە.", kmr: "\(freed) hate valakirin. Pelên demkî hatin paqijkirin.")
                } else {
                    cleanupResult = tr("No unused temporary files to remove.", "ما في ملفات مؤقتة غير مستخدمة للحذف.",
                        ckb: "هیچ فایلێکی کاتی بەکارنەهاتوو نییە بۆ سڕینەوە.", kmr: "Pelên demkî yên nayên bikaranîn ji bo jêbirinê tune ne.")
                }
            }
        }
    }
}

// MARK: - Purchases

/// Read-only signed Apple purchase history. Hidden tabs do not fetch account data.
struct AppStorePurchasesPage: View {
    @ObservedObject var store: EncryptedAppsStore
    @ObservedObject var model: AppStoreSectionModel
    let vm: AppViewModel
    let isActive: Bool
    /// Back to the Account page, which opens Purchases in the gallery style.
    var onBack: (() -> Void)? = nil
    @State private var query = ""
    /// The filter follows `query` after a short pause, so typing does not re-filter per keystroke.
    @State private var appliedQuery = ""
    @State private var months = 0
    @State private var purchases: [MirsaStorePurchase] = []
    @State private var artwork: [Int64: String] = [:]
    @State private var loading = false
    @State private var error: String?
    @State private var recovery: StoreFreeLicenseRecovery?
    @State private var downloading: Int64?
    @State private var openDetail: MirsaStorePurchase?
    @State private var reloadID = UUID()
    @State private var reloadTask: Task<Void, Never>?
    @ObservedObject private var tints = StoreArtworkTint.shared
    private var loadIdentity: String { "\(model.sessionRevision)|\(model.account?.email ?? "")|\(isActive)" }
    private var visible: [MirsaStorePurchase] {
        let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? .distantPast
        return purchases.filter {
            (months == 0 || ($0.date ?? .distantPast) >= cutoff) &&
            (appliedQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(appliedQuery) ||
             $0.bundleID.localizedCaseInsensitiveContains(appliedQuery) || String($0.id).contains(appliedQuery))
        }
    }
    var body: some View {
        let shown = visible
        return ScrollView {
            VStack(alignment: .leading, spacing: MirsaSpacing.m) {
                if let onBack {
                    Button { StoreHaptics.select(); onBack() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").flipsForRightToLeftLayoutDirection(true)
                            Text(AppStoreSectionTab.account.title)
                        }
                        .font(MirsaFont.button).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 36)
                        .galleryGlassCapsule()
                    }
                    .buttonStyle(.mirsaPress)
                    .padding(.top, MirsaSpacing.s)
                    .accessibilityIdentifier("store-purchases-back")
                }
                StoreGalleryHeader(title: storeText("Purchases", "المشتريات", de: "Käufe", ckb: "کڕینەکان", kmr: "Kirîn")) {
                    Button { Task { _ = try? await model.purchases(force: true); await reload() } } label: {
                        StoreGalleryRoundLabel(systemName: "arrow.clockwise", size: 40)
                    }
                    .buttonStyle(.plain)
                    .disabled(loading || !isActive)
                    .accessibilityLabel(tr("Refresh purchases", "تحديث المشتريات", ckb: "نوێکردنەوەی کڕینەکان", kmr: "Kirînan nû bike"))
                }
                if let account = model.account {
                    HStack(spacing: 8) {
                        Text(StoreIdentity.flag(account.country))
                        Text(account.email).lineLimit(1).truncationMode(.middle)
                    }
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textSecondary)
                    AppStoreSearchField(placeholder: storeText("Search purchases or App ID", "البحث بالمشتريات أو App ID", de: "Käufe oder App-ID suchen", ckb: "گەڕان لە کڕینەکان", kmr: "Li kirînan bigere"), text: $query)
                    purchaseFilters
                    HStack(spacing: MirsaSpacing.xs) {
                        Text((purchases.isEmpty && (loading || model.refreshingPurchases) ? "…" : String(shown.count)) + storeText(" items", " عنصراً", de: " Einträge", ckb: " بڕگە", kmr: " tişt"))
                            .font(MirsaFont.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(StoreGallery.accent))
                            .accessibilityIdentifier("store-purchases-count")
                        if loading || model.refreshingPurchases { ProgressView().controlSize(.small).tint(.white) }
                        Spacer()
                    }
                    if let error {
                        VStack(alignment: .leading, spacing: MirsaSpacing.xs) {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.warning)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(storeText("Try again", "جرّب مرة تانية", de: "Erneut versuchen", ckb: "دووبارە هەوڵ بدەرەوە", kmr: "Dîsa biceribîne")) {
                                Task { _ = try? await model.purchases(force: true); await reload() }
                            }
                            .font(MirsaFont.button).foregroundStyle(StoreGallery.lilac)
                            .disabled(loading || !isActive)
                        }
                        .padding(MirsaSpacing.card)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .galleryGlass(radius: 20, tint: MirsaPalette.warning)
                    } else if purchases.isEmpty && (loading || model.refreshingPurchases) {
                        ForEach(0..<4, id: \.self) { _ in StoreSkeletonCard(iconSize: 52) }
                    } else if !loading && !model.refreshingPurchases && shown.isEmpty {
                        StoreEmptyState(icon: query.isEmpty ? "bag" : "magnifyingglass",
                                        title: query.isEmpty
                                            ? storeText("No purchases here yet", "ما في مشتريات لسا", de: "Noch keine Käufe", ckb: "هێشتا هیچ کڕینێک نییە", kmr: "Hêj kirîn tune")
                                            : tr("No matching purchases.", "ما في مشتريات مطابقة.", ckb: "هیچ کڕینێک ناگونجێت.", kmr: "Kirînek li hev nayê."),
                                        message: storeText("Apps this Apple Account got or bought appear here, grouped by month.",
                                                           "التطبيقات يلي حصل عليها أو اشتراها حساب Apple بتظهر هون، مرتبة حسب الشهر.",
                                                           de: "Apps, die dieses Apple-Konto geladen oder gekauft hat, erscheinen hier nach Monat sortiert.",
                                                           ckb: "ئەو ئەپانەی ئەم ئەکاونتە وەریگرتوون یان کڕیونی لێرە بە پێی مانگ دەردەکەون.",
                                                           kmr: "Sepanên ku vî hesabî girtine an kirîne li vir li gorî mehê xuya dibin."))
                    }
                    LazyVStack(alignment: .leading, spacing: MirsaSpacing.m, pinnedViews: [.sectionHeaders]) {
                        ForEach(StorePurchaseGroups.make(shown)) { group in
                            purchaseGroup(group)
                        }
                    }
                    .accessibilityIdentifier("store-purchases-month-list")
                } else {
                    StoreEmptyState(icon: "person.crop.circle.badge.questionmark",
                                    title: tr("Not signed in", "مو مسجّل دخول", ckb: "نەچوویتە ژوورەوە", kmr: "Te têneketiye"),
                                    message: tr("Sign in from the Account tab to load your Apple purchases.", "سجّل دخول من تبويب الحساب لتشوف مشتريات Apple تبعك.", ckb: "بچۆ ژوورەوە بۆ بینینی کڕینەکان.", kmr: "Ji bo kirînan têkeve hesabê te."))
                }
            }
            .environment(\.layoutDirection, StoreGallery.direction)
            .padding(.horizontal, MirsaSpacing.page).padding(.bottom, MirsaSpacing.xl)
        }
        .refreshable { _ = try? await model.purchases(force: true); await reload() }
        .sheet(item: $openDetail) { item in
            NavigationStack {
                AppStoreAccountView(onDownloaded: { url in
                    let entry = try await EncryptedAppsStore.adopt(file: url, move: false)
                    store.add(entry)
                }, searchOnly: true, openAppID: item.id)
            }
            .preferredColorScheme(.dark)
        }
        .task(id: loadIdentity) {
            reloadID = UUID(); reloadTask?.cancel()
            recovery = nil; purchases = model.cachedPurchases; error = nil; loading = false
            #if DEBUG
            if AppStoreSectionModel.fixtureAccount != nil { purchases = StoreRedesignFixtures.purchases; return }
            #endif
            if isActive { await reload() }
        }
        .confirmationDialog(tr("Refresh free licence and retry?", "تحديث الترخيص المجاني وإعادة التنزيل؟", ckb: "مۆڵەتی بێبەرامبەر نوێ بکەوە؟", kmr: "Lîsansa belaş nû bike?"),
                            isPresented: Binding(get: { recovery != nil }, set: { if !$0 { recovery = nil } }), titleVisibility: .visible) {
            if let pending = recovery {
                Button(tr("Refresh free licence and retry once", "حدّث الترخيص المجاني وجرّب مرة", ckb: "نوێکردنەوە و هەوڵێکی تر", kmr: "Nû bike û carekê biceribîne")) {
                    recovery = nil
                    Task { await recoverDownload(pending) }
                }
            }
            Button(tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal"), role: .cancel) { recovery = nil }
        } message: {
            Text(tr("Apple rejected the download, not ownership. Only a verified free licence is refreshed after your confirmation, then the same download is retried once. No paid purchase.",
                    "Apple رفضت التنزيل، مو دليل إنك ما بتملك التطبيق. بموافقتك منحدّث الترخيص إذا مجاني بمتجر حسابك وبنعيد نفس التنزيل مرة وحدة. ما في شراء مدفوع.",
                    ckb: "تەنها مۆڵەتی بێبەرامبەر بە ڕەزامەندی تۆ نوێ دەکرێتەوە، پاشان جارێک هەوڵ دەدرێت.",
                    kmr: "Tenê bi razîbûna te lîsansa belaş nû dibe û carekê tê ceribandin."))
        }
        .onReceive(model.$cachedPurchases) { items in
            if purchases != items { purchases = items }
        }
        .onDisappear { reloadTask?.cancel() }
        .task(id: query) {
            if query.isEmpty { appliedQuery = ""; return }
            try? await Task.sleep(nanoseconds: 220_000_000)
            if !Task.isCancelled { appliedQuery = query }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(StoreGalleryPageBackdrop())
        .environment(\.layoutDirection, .leftToRight)
    }
    private var purchaseFilters: some View {
        HStack(spacing: 6) {
            purchaseFilter(0, title: storeText("All", "الكل", de: "Alle", ckb: "هەموو", kmr: "Hemû"))
            purchaseFilter(1, title: storeText("1 month", "شهر", de: "1 Monat", ckb: "مانگێک", kmr: "1 meh"))
            purchaseFilter(6, title: storeText("6 months", "٦ أشهر", de: "6 Monate", ckb: "٦ مانگ", kmr: "6 meh"))
            purchaseFilter(12, title: storeText("12 months", "سنة", de: "12 Monate", ckb: "ساڵێک", kmr: "12 meh"))
        }
    }

    private func purchaseFilter(_ value: Int, title: String) -> some View {
        Button { StoreHaptics.select(); withAnimation(MirsaMotion.select) { months = value } } label: {
            Text(title).font(MirsaFont.caption.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(months == value ? Color.white : MirsaPalette.textSecondary)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background {
                    if months == value {
                        Capsule().fill(StoreGallery.accent)
                    }
                }
                .galleryGlassCapsule()
        }
        .buttonStyle(.mirsaPress)
        .accessibilityAddTraits(months == value ? .isSelected : [])
        .accessibilityIdentifier("store-purchases-filter-\(value)")
    }

    /// One month of the timeline: a sticky glass header, then the rows along a glowing rail.
    private func purchaseGroup(_ group: StorePurchaseGroups.Group) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(group.items) { item in
                    HStack(alignment: .center, spacing: 10) {
                        ZStack {
                            Rectangle().fill(StoreGallery.ring).opacity(0.35).frame(width: 2)
                            Circle().fill(StoreGallery.violet.opacity(0.35)).frame(width: 14, height: 14)
                            Circle().fill(StoreGallery.lilac).frame(width: 8, height: 8)
                        }
                        .frame(width: 14)
                        purchaseRow(item)
                    }
                }
            }
        } header: {
            HStack(spacing: 8) {
                Image(systemName: "calendar").font(.system(size: 12, weight: .bold)).foregroundStyle(StoreGallery.lilac)
                Text(group.month.map { StorePurchaseGroups.title($0, locale: AppLanguageStore.shared.current.locale) }
                     ?? storeText("Date unavailable", "التاريخ مو متوفر", de: "Datum nicht verfügbar", ckb: "بەروار بەردەست نییە", kmr: "Dîrok ne berdest e"))
                    .font(MirsaFont.sectionTitle).foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text(String(group.items.count)).font(MirsaFont.caption.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(StoreGallery.violet.opacity(0.45), in: Capsule())
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            // Pinned while the month scrolls under it, so it keeps a dark base under the glass.
            .background(Capsule().fill(StoreGallery.ink.opacity(0.88)))
            .galleryGlassCapsule()
            .padding(.vertical, 4)
        }
    }

    private func purchaseRow(_ item: MirsaStorePurchase) -> some View {
        let art = artwork[item.id] ?? ""
        let tint = tints.tint(art, seed: item.bundleID)
        // Follows the page's reading direction (icon first, download action last).
        return HStack(spacing: MirsaSpacing.s) {
            StoreArtwork(url: art, seed: item.bundleID, name: item.name.isEmpty ? item.bundleID : item.name, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name.isEmpty ? item.bundleID : item.name)
                    .font(MirsaFont.cardTitle).foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let date = StorePurchaseGroups.validDate(item.date) {
                        Text(date.formatted(.dateTime.day().month(.abbreviated).year()
                            .locale(AppLanguageStore.shared.current.locale)))
                    }
                    if !item.version.isEmpty { Text("· " + item.version).lineLimit(1) }
                }
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textSecondary)
                // History has no reliable size field. Do not invent one or fetch a package here.
            }
            Spacer(minLength: 0)
            Group {
                if downloading == item.id { ProgressView().tint(.white) }
                else {
                    Button { StoreHaptics.get(); Task { await download(item) } } label: {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(StoreGallery.accent, in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
                    }
                    .buttonStyle(.mirsaPress)
                    .disabled(loading || downloading != nil || store.busy != nil)
                    .opacity(loading || downloading != nil || store.busy != nil ? 0.5 : 1)
                    .accessibilityLabel(tr("Download", "تنزيل", ckb: "داگرتن", kmr: "Daxe") + " " + item.name)
                    .accessibilityIdentifier("store-purchase-download-\(item.id)")
                }
            }.frame(width: 44, height: 44)
        }
        .padding(.horizontal, MirsaSpacing.s).padding(.vertical, 10)
        .galleryGlass(radius: 22, tint: tint.opacity(0.55))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { StoreHaptics.select(); openDetail = item }
        .contextMenu {
            Button { StoreLinks.copy(item.bundleID) } label: {
                Label(storeText("Copy Bundle ID", "نسخ Bundle ID", de: "Bundle-ID kopieren", ckb: "کۆپی Bundle ID", kmr: "Bundle ID kopî bike"), systemImage: "doc.on.doc")
            }
            if let link = StoreLinks.appPage(id: item.id, country: model.account?.country ?? "us") {
                ShareLink(item: link) {
                    Label(storeText("Share", "مشاركة", de: "Teilen", ckb: "هاوبەشکردن", kmr: "Parve bike"), systemImage: "square.and.arrow.up")
                }
            }
            Button { StoreHaptics.get(); Task { await download(item) } } label: {
                Label(tr("Download", "تنزيل", ckb: "داگرتن", kmr: "Daxe"), systemImage: "icloud.and.arrow.down")
            }
            .disabled(loading || downloading != nil || store.busy != nil)
        }
    }

    @MainActor private func reload() async {
        guard isActive, let account = model.account else { return }
        let revision = model.sessionRevision
        let previous = reloadTask
        previous?.cancel()
        let id = UUID()
        reloadID = id; loading = true; error = nil
        let task = Task { @MainActor in
            defer { if reloadID == id { loading = false } }
            // A cancelled account fetch must release its client reservation before a new one starts.
            await previous?.value
            guard !Task.isCancelled, reloadID == id, isActive,
                  model.sessionRevision == revision, model.account == account else { return }
            await loadHistory(account: account, revision: revision, id: id)
        }
        reloadTask = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
    }
    @MainActor private func loadHistory(account: MirsaStoreAccount, revision: Int, id: UUID) async {
        func isCurrent() -> Bool {
            !Task.isCancelled && reloadID == id && isActive &&
            model.sessionRevision == revision && model.account == account
        }
        do {
            let result = try await model.purchases()
            guard isCurrent() else { return }
            purchases = result
            // Public metadata lookup in bounded chunks, not authenticated history replay.
            for start in stride(from: 0, to: result.count, by: 100) {
                guard isCurrent() else { return }
                let ids = result[start..<min(start+100, result.count)].map { String($0.id) }.joined(separator: ",")
                var url = URLComponents(string: "https://itunes.apple.com/lookup")!
                url.queryItems = [URLQueryItem(name: "id", value: ids), URLQueryItem(name: "country", value: account.country)]
                var request = URLRequest(url: url.url!); request.timeoutInterval = 20
                guard let (data, _) = try? await URLSession.shared.data(for: request) else { continue }
                struct Icon: Decodable { let trackId: Int64; let artworkUrl100: String? }
                struct Reply: Decodable { let results: [Icon] }
                if let reply = try? JSONDecoder().decode(Reply.self, from: data) {
                    guard isCurrent() else { return }
                    for item in reply.results { artwork[item.trackId] = item.artworkUrl100 }
                }
            }
        } catch is CancellationError {}
        catch {
            guard isCurrent() else { return }
            if let diagnostic = error as? PurchaseHistoryDiagnostic {
                self.error = diagnostic.localizedDescription
            } else if let diagnostic = error as? StorefrontMetadataMissing {
                self.error = diagnostic.localizedDescription
            } else {
                // Known local states must not collapse into bridged enum error 0.
                // Never display arbitrary descriptions/userInfo containing session values.
                if let local = error as? MirsaStoreError {
                    self.error = "Apple history · local session · " + (local.errorDescription ?? "session unavailable")
                } else if error is DecodingError {
                    self.error = "Apple history · setup · invalid saved account record"
                } else {
                    self.error = "Apple history · setup · unexpected local session failure; no history result loaded"
                }
            }
        }
    }
    @MainActor private func download(_ item: MirsaStorePurchase) async {
        guard isActive, !loading, downloading == nil, let account = model.account else { return }
        let revision = model.sessionRevision
        downloading = item.id; error = nil
        defer { downloading = nil }
        do {
            let selectedID = try await MirsaStoreOnDeviceClient.shared.selectedAccountID()
            guard model.sessionRevision == revision, model.account == account else { return }
            let pin = StoreLibraryModel.shared.pin(bundleID: item.bundleID, country: account.country)
            let url = try await MirsaStoreOnDeviceClient.shared.downloadOwnedApp(item.app,
                externalVersionID: pin?.externalVersionID, expectedAccountID: selectedID)
            defer { MirsaManagedTmp.end(url.deletingLastPathComponent()) }
            try Task.checkCancellation()
            guard model.sessionRevision == revision, model.account == account else { return }
            let entry = try await EncryptedAppsStore.adopt(file: url, move: false)
            // adopt uses detached I/O. Discard its private copy if the account changed meanwhile.
            guard !Task.isCancelled, model.sessionRevision == revision, model.account == account else {
                try? FileManager.default.removeItem(at: EncryptedAppsStore.ipaURL(entry.id))
                try? FileManager.default.removeItem(at: EncryptedAppsStore.iconURL(entry.id))
                return
            }
            store.add(entry)
        } catch is CancellationError {}
        catch {
            guard model.sessionRevision == revision, model.account == account else { return }
            if let diagnostic = error as? StoreProductDiagnostic {
                if diagnostic.httpStatus == 403, !diagnostic.requiresReauthentication,
                   let fresh = try? await MirsaStoreOnDeviceClient.shared.freeAppForRecovery(item.app),
                   StoreFreeLicenseRecovery.canOffer(status: diagnostic.httpStatus, price: fresh.price),
                   model.sessionRevision == revision, model.account == account, !Task.isCancelled {
                    recovery = StoreFreeLicenseRecovery(app: fresh,
                        externalVersionID: StoreLibraryModel.shared.pin(bundleID: item.bundleID, country: account.country)?.externalVersionID,
                        revision: revision)
                    return
                }
                self.error = commerceError(diagnostic)
            } else {
                self.error = tr("Download failed. Try again.", "التنزيل ما كمل. جرّب مرة تانية.", ckb: "داگرتن سەرکەوتوو نەبوو.", kmr: "Daxistin bi ser neket.")
            }
        }
    }
    private func commerceError(_ diagnostic: StoreProductDiagnostic) -> String {
        guard diagnostic.requiresReauthentication else { return diagnostic.localizedDescription }
        return tr("Apple rejected this store session. Sign out, sign in again, then retry. Your saved apps stay here.",
                  "أبل رفضت جلسة المتجر. سجّل خروج وادخل من جديد، وبعدها جرّب. تطبيقاتك المحفوظة بتضل هون.",
                  ckb: "ئەپل دانیشتنی فرۆشگاکەی ڕەت کردەوە. بچۆ دەرەوە و دووبارە بچۆ ژوورەوە، پاشان هەوڵ بدەرەوە. ئەپە پاشەکەوتکراوەکانت دەمێننەوە.",
                  kmr: "Apple vê rûniştina firoşgehê red kir. Derkeve û dîsa têkeve, paşê dîsa biceribîne. Sepanên te yên tomarkirî dimînin.")
    }

    @MainActor private func recoverDownload(_ pending: StoreFreeLicenseRecovery) async {
        guard isActive, !loading, downloading == nil, pending.revision == model.sessionRevision,
              let account = model.account else { return }
        downloading = pending.app.id; error = nil
        defer { downloading = nil }
        do {
            let url = try await StoreFreeLicenseRecovery.retryOnce(consent: true, acquire: {
                guard pending.revision == model.sessionRevision, model.account == account else { throw CancellationError() }
                try await MirsaStoreOnDeviceClient.shared.acquireFreeApp(pending.app)
            }, download: {
                guard pending.revision == model.sessionRevision, model.account == account else { throw CancellationError() }
                return try await MirsaStoreOnDeviceClient.shared.downloadOwnedApp(pending.app, externalVersionID: pending.externalVersionID)
            })
            defer { MirsaManagedTmp.end(url.deletingLastPathComponent()) }
            try Task.checkCancellation()
            guard isActive, pending.revision == model.sessionRevision, model.account == account else { throw CancellationError() }
            let entry = try await EncryptedAppsStore.adopt(file: url, move: false)
            guard !Task.isCancelled, pending.revision == model.sessionRevision, model.account == account else {
                try? FileManager.default.removeItem(at: EncryptedAppsStore.ipaURL(entry.id))
                try? FileManager.default.removeItem(at: EncryptedAppsStore.iconURL(entry.id))
                return
            }
            store.add(entry)
        } catch is CancellationError {}
        catch {
            guard pending.revision == model.sessionRevision, model.account == account else { return }
            self.error = (error as? StoreProductDiagnostic).map { commerceError($0) }
                ?? tr("Free licence refresh or retry failed. No further retry was made.", "تحديث الترخيص أو إعادة التنزيل ما كملت، وما عدنا المحاولة.", ckb: "هەوڵەکە سەرکەوتوو نەبوو.", kmr: "Ceribandin bi ser neket.")
        }
    }

}
