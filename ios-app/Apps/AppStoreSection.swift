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
struct AppStoreSectionBar: View {
    @Binding var selection: AppStoreSectionTab
    @Namespace private var ns
    @State private var bounce = 0

    var body: some View {
        HStack(spacing: 2) {
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
                            .shadow(color: StoreLuxe.accent.opacity(0.55), radius: 12, y: 4)
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
        .storeGlassCapsule(elevation: 1.2)
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
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(StoreLuxe.accentSoft)
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
        .padding(.horizontal, 16)
        .frame(height: 48)
        .storeGlassCapsule(elevation: 0.5)
    }
}

/// A titled, rounded group of rows with an optional explanation under it.
struct AppStoreGroup<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.xs) {
            if let title {
                StoreSectionTitle(title: title)
                    .padding(.horizontal, MirsaSpacing.xxs)
            }
            VStack(spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .storeGlass(radius: 22, sheen: false, elevation: 0.6)
            if let footer {
                Text(footer).font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MirsaSpacing.xxs)
            }
        }
    }
}

struct AppStoreRowDivider: View {
    var inset: CGFloat = 58
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.7).padding(.leading, inset)
    }
}

struct AppStoreRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var tint: Color = .white
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: MirsaSpacing.s) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint == .white ? Color.white : tint)
                .frame(width: 30, height: 30)
                .background((tint == .white ? StoreLuxe.identitySoft : LinearGradient(colors: [tint.opacity(0.22)], startPoint: .top, endPoint: .bottom)),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(MirsaFont.body).foregroundStyle(tint).lineLimit(2)
                if let subtitle {
                    Text(subtitle).font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary).lineLimit(2)
                }
            }
            Spacer(minLength: MirsaSpacing.xs)
            trailing()
        }
        .padding(.horizontal, MirsaSpacing.card)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
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

private struct AppStoreChevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(MirsaPalette.textTertiary)
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
                    StorePageHeader(title: storeText("Account", "الحساب", de: "Konto", ckb: "ئەکاونت", kmr: "Hesab"),
                                    subtitle: EncryptedText.tabTitle) { EmptyView() }
                    profileCard
                    accountsGroup
                    linksGroup
                    if model.account != nil { signOutButton }
                }
                .padding(.horizontal, MirsaSpacing.page)
                .padding(.bottom, MirsaSpacing.xl)
            }
            .refreshable { await model.refresh() }
            .background(StoreLuxeBackground())
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

    /// Premium identity card: monogram, name, email and storefront flag.
    @ViewBuilder private var profileCard: some View {
        if let a = model.account {
            VStack(alignment: .leading, spacing: MirsaSpacing.m) {
                HStack(alignment: .top) {
                    StoreMonogram(name: a.name, email: a.email, size: 64)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Text(StoreIdentity.flag(a.country)).font(.system(size: 18))
                        Text(a.country.uppercased()).font(MirsaFont.caption.weight(.bold)).foregroundStyle(.white).monospaced()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .storeGlassCapsule(elevation: 0.3)
                    .accessibilityLabel(storeText("Storefront ", "واجهة المتجر ", de: "Store ", ckb: "ستۆر ", kmr: "Store ") + AppStoreCountry.label(a.country))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(a.name.isEmpty ? a.email : a.name)
                        .font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                    Text(a.email).font(MirsaFont.secondary).foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(1).truncationMode(.middle)
                    Label(storeText("Storefront: ", "واجهة المتجر: ", de: "Store: ", ckb: "ستۆر: ", kmr: "Store: ") + AppStoreCountry.label(a.country),
                          systemImage: "globe")
                        .font(MirsaFont.caption).foregroundStyle(Color.white.opacity(0.62))
                }
                HStack(spacing: MirsaSpacing.xs) {
                    Button { StoreHaptics.select(); showSwitcher = true } label: {
                        Label(storeText("Switch account", "تبديل الحساب", de: "Konto wechseln", ckb: "گۆڕینی ئەکاونت", kmr: "Hesab biguherîne"),
                              systemImage: "arrow.left.arrow.right.circle.fill")
                            .font(MirsaFont.button).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 38)
                            .storeGlassCapsule(elevation: 0.4)
                    }
                    .buttonStyle(.mirsaPress)
                    .accessibilityIdentifier("store-switch-account")
                    Spacer(minLength: 0)
                    Label("Apple Account", systemImage: "apple.logo")
                        .font(MirsaFont.badge).foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .padding(MirsaSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous).fill(StoreLuxe.identity).opacity(0.62)
                    Circle().fill(StoreLuxe.cyan.opacity(0.35)).frame(width: 220).blur(radius: 40).offset(x: 140, y: -70)
                    Circle().fill(StoreLuxe.accent.opacity(0.45)).frame(width: 180).blur(radius: 46).offset(x: -120, y: 80)
                }
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            .storeGlass(radius: 30, tint: StoreLuxe.accent, elevation: 1.3)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("store-account-profile")
        } else {
            HStack(spacing: MirsaSpacing.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Not signed in", "مو مسجّل دخول", ckb: "نەچوویتە ژوورەوە", kmr: "Te têneketiye"))
                        .font(.title3.weight(.bold)).foregroundStyle(.white)
                    Text(storeAvailable
                         ? tr("Sign in with your Apple Account to search and download apps it owns.",
                              "سجّل دخول بحساب Apple تبعك لتدوّر وتنزّل التطبيقات يلي بيملكها.",
                              ckb: "بە ئەکاونتی Apple بچۆ ژوورەوە بۆ گەڕان و داگرتنی ئەو ئەپانەی خاوەنیانی.",
                              kmr: "Bi hesabê xwe yê Apple têkeve da ku li sepanên wî bigerî û daxî.")
                         : tr("Signing in to Apple inside Mirsa is not available yet. You can still import App Store IPAs from Files.",
                              "تسجيل الدخول لحساب Apple جوا مرسى مو متاح لسا. لسا فيك تستورد IPA من الملفات.",
                              ckb: "چوونەژوورەوە بۆ Apple لەناو Mirsa هێشتا بەردەست نییە. هێشتا دەتوانیت IPA لە Files هاوردە بکەیت.",
                              kmr: "Têketina Apple di hundirê Mirsa de hêj ne amade ye. Hîn jî tu dikarî IPA ji Files têxî."))
                        .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                StoreMonogram(name: "", email: "", size: 56)
            }
            .padding(MirsaSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .storeGlass(radius: 30)
            .accessibilityIdentifier("store-account-profile")
        }
    }

    private var accountsGroup: some View {
        AppStoreGroup(title: storeText("Accounts", "الحسابات", de: "Konten", ckb: "ئەکاونتەکان", kmr: "Hesab"),
                      footer: storeText("Switch between the Apple Accounts saved in Mirsa. Search and downloads use the selected account's storefront.",
                                        "بدّل بين حسابات Apple المحفوظة بمرسى. البحث والتنزيل بيستخدموا متجر الحساب المختار.",
                                        de: "Wechsle zwischen den in Mirsa gespeicherten Apple-Konten. Suche und Downloads nutzen den Store des gewählten Kontos.",
                                        ckb: "لە نێوان ئەکاونتە Apple ـە پاشەکەوتکراوەکانی Mirsa بگۆڕە. گەڕان و داگرتن ستۆری ئەکاونتی هەڵبژێردراو بەکاردەهێنن.",
                                        kmr: "Di navbera hesabên Apple yên di Mirsa de tomarkirî biguherîne. Lêgerîn û daxistin store ya hesabê hilbijartî bi kar tînin.")) {
            if model.account != nil {
                Button { StoreHaptics.select(); showSwitcher = true } label: {
                    AppStoreRow(icon: "person.2.fill", title: storeText("Saved accounts", "الحسابات المحفوظة", de: "Gespeicherte Konten", ckb: "ئەکاونتە پاشەکەوتکراوەکان", kmr: "Hesabên tomarkirî")) {
                        AppStoreChevron()
                    }
                }
                .buttonStyle(.plain)
                AppStoreRowDivider()
            }
            Button { onAddAccount() } label: {
                AppStoreRow(icon: "plus", title: tr("Add account", "إضافة حساب", ckb: "زیادکردنی ئەکاونت", kmr: "Hesab zêde bike"),
                            subtitle: storeAvailable ? nil : tr("Coming soon", "قريباً", ckb: "بەم زووانە", kmr: "Nêzîk e")) {
                    AppStoreChevron()
                }
            }
            .buttonStyle(.plain)
            .disabled(!storeAvailable)
            .opacity(storeAvailable ? 1 : 0.55)
            .accessibilityIdentifier("store-add-account")
        }
    }

    private var linksGroup: some View {
        AppStoreGroup(title: storeText("Library", "المكتبة", de: "Bibliothek", ckb: "کتێبخانە", kmr: "Pirtûkxane")) {
            Button { onOpen(.purchases) } label: {
                AppStoreRow(icon: "bag.fill", title: storeText("Purchases", "المشتريات", de: "Käufe", ckb: "کڕینەکان", kmr: "Kirîn")) { AppStoreChevron() }
            }
            .buttonStyle(.plain)
            AppStoreRowDivider()
            Button { onOpen(.downloads) } label: {
                AppStoreRow(icon: "arrow.down.circle.fill", title: storeText("Downloads and installs", "التنزيلات والتثبيت", de: "Downloads und Installationen", ckb: "داگرتن و دامەزراندن", kmr: "Daxistin û sazkirin")) {
                    Text("\(library.entries.count)").font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textTertiary).monospacedDigit()
                    AppStoreChevron()
                }
            }
            .buttonStyle(.plain)
            if let onOpenTools {
                AppStoreRowDivider()
                Button { onOpenTools() } label: {
                    AppStoreRow(icon: "star.fill", title: StoreFeatureText.wishlist,
                                subtitle: StoreFeatureText.tools) {
                        Text("\(wishes.wishlist.count)").font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textTertiary).monospacedDigit()
                        AppStoreChevron()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("store-open-wishlist")
            }
            AppStoreRowDivider()
            Button { path.append(.settings) } label: {
                AppStoreRow(icon: "gearshape.fill", title: storeText("Settings", "الإعدادات", de: "Einstellungen", ckb: "ڕێکخستنەکان", kmr: "Mîheng")) { AppStoreChevron() }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("store-open-settings")
        }
    }

    private var signOutButton: some View {
        Button { confirmSignOut = true } label: {
            HStack(spacing: 8) {
                if signingOut { ProgressView().tint(MirsaPalette.danger) }
                else { Image(systemName: "rectangle.portrait.and.arrow.right") }
                Text(tr("Sign out", "تسجيل الخروج", ckb: "چوونە دەرەوە", kmr: "Derkeve"))
            }
            .font(MirsaFont.button)
            .foregroundStyle(MirsaPalette.danger)
            .frame(maxWidth: .infinity, minHeight: 50)
            .storeGlass(radius: 22, tint: MirsaPalette.danger, sheen: false, elevation: 0.4)
        }
        .buttonStyle(.plain)
        .disabled(signingOut)
        .accessibilityIdentifier("store-sign-out")
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
            .background(StoreLuxeBackground())
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
            // A pushed page does not inherit the section bar's inset; keep the last rows above both bars.
            .padding(.bottom, MirsaSpacing.xl + 140)
        }
        .background(StoreLuxeBackground())
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
    @State private var query = ""
    @State private var months = 0
    @State private var purchases: [MirsaStorePurchase] = []
    @State private var artwork: [Int64: String] = [:]
    @State private var loading = false
    @State private var error: String?
    @State private var recovery: StoreFreeLicenseRecovery?
    @State private var downloading: Int64?
    @State private var reloadID = UUID()
    @State private var reloadTask: Task<Void, Never>?
    @ObservedObject private var tints = StoreArtworkTint.shared
    private var loadIdentity: String { "\(model.sessionRevision)|\(model.account?.email ?? "")|\(isActive)" }
    private var visible: [MirsaStorePurchase] {
        let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? .distantPast
        return purchases.filter {
            (months == 0 || ($0.date ?? .distantPast) >= cutoff) &&
            (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) ||
             $0.bundleID.localizedCaseInsensitiveContains(query) || String($0.id).contains(query))
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MirsaSpacing.m) {
                StorePageHeader(title: storeText("Purchases", "المشتريات", de: "Käufe", ckb: "کڕینەکان", kmr: "Kirîn"),
                                subtitle: EncryptedText.tabTitle) {
                    Button { Task { _ = try? await model.purchases(force: true); await reload() } } label: {
                        MirsaIconButtonLabel(systemName: "arrow.clockwise")
                    }
                    .storeGlassCapsule()
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
                        Text((purchases.isEmpty && (loading || model.refreshingPurchases) ? "…" : String(visible.count)) + storeText(" items", " عنصراً", de: " Einträge", ckb: " بڕگە", kmr: " tişt"))
                            .font(MirsaFont.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(StoreLuxe.identity).opacity(0.55))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
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
                            .font(MirsaFont.button).foregroundStyle(StoreLuxe.accentSoft)
                            .disabled(loading || !isActive)
                        }
                        .padding(MirsaSpacing.card)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .storeGlass(radius: 20, tint: MirsaPalette.warning, sheen: false, elevation: 0.4)
                    } else if purchases.isEmpty && (loading || model.refreshingPurchases) {
                        ForEach(0..<4, id: \.self) { _ in StoreSkeletonCard(iconSize: 52) }
                    } else if !loading && !model.refreshingPurchases && visible.isEmpty {
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
                        ForEach(StorePurchaseGroups.make(visible)) { group in
                            purchaseGroup(group)
                        }
                    }
                    .accessibilityIdentifier("store-purchases-month-list")
                } else {
                    StoreEmptyState(icon: "person.crop.circle.badge.questionmark",
                                    title: tr("Not signed in", "مو مسجّل دخول", ckb: "نەچوویتە ژوورەوە", kmr: "Te têneketiye"),
                                    message: tr("Sign in from the Account tab to load your Apple purchases.", "سجّل دخول من تبويب الحساب لتشوف مشتريات Apple تبعك.", ckb: "بچۆ ژوورەوە بۆ بینینی کڕینەکان.", kmr: "Ji bo kirînan têkeve hesabê te."))
                }
            }.padding(.horizontal, MirsaSpacing.page).padding(.bottom, MirsaSpacing.xl)
        }
        .refreshable { _ = try? await model.purchases(force: true); await reload() }
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
        .scrollDismissesKeyboard(.interactively)
        .background(StoreLuxeBackground())
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
                        Capsule().fill(StoreLuxe.identity).opacity(0.8)
                            .shadow(color: StoreLuxe.accent.opacity(0.45), radius: 8, y: 3)
                    }
                }
                .storeGlassCapsule(elevation: 0.2)
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
                            Rectangle().fill(StoreLuxe.identity).opacity(0.35).frame(width: 2)
                            Circle().fill(StoreLuxe.accentSoft).frame(width: 8, height: 8)
                                .shadow(color: StoreLuxe.accent, radius: 4)
                        }
                        .frame(width: 14)
                        purchaseRow(item)
                    }
                }
            }
        } header: {
            HStack(spacing: 8) {
                Image(systemName: "calendar").font(.system(size: 12, weight: .bold)).foregroundStyle(StoreLuxe.accentSoft)
                Text(group.month.map { StorePurchaseGroups.title($0, locale: AppLanguageStore.shared.current.locale) }
                     ?? storeText("Date unavailable", "التاريخ مو متوفر", de: "Datum nicht verfügbar", ckb: "بەروار بەردەست نییە", kmr: "Dîrok ne berdest e"))
                    .font(MirsaFont.sectionTitle).foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text(String(group.items.count)).font(MirsaFont.caption.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(StoreLuxe.accent.opacity(0.45), in: Capsule())
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .storeGlassCapsule(elevation: 0.5)
            .padding(.vertical, 4)
        }
    }

    private func purchaseRow(_ item: MirsaStorePurchase) -> some View {
        let art = artwork[item.id] ?? ""
        let tint = tints.tint(art, seed: item.bundleID)
        // Arabic and Sorani keep the mirrored look of the existing rows (icon on the right).
        let mirrored = AppLanguageStore.shared.current == .arabic || AppLanguageStore.shared.current == .sorani
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
                            .background(StoreLuxe.identity, in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
                            .shadow(color: StoreLuxe.accent.opacity(0.5), radius: 8, y: 3)
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
        .environment(\.layoutDirection, mirrored ? .rightToLeft : .leftToRight)
        .storeGlass(radius: 22, tint: tint, sheen: true, elevation: 0.5)
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
