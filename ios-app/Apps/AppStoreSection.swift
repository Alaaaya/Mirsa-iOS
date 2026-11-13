import SwiftUI
import ApplePackage

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
        case .search: return tr("Search", "بحث", ckb: "گەڕان", kmr: "Lêgerîn")
        case .downloads: return tr("Downloads", "التنزيلات", ckb: "داگرتنەکان", kmr: "Daxistin")
        case .purchases: return tr("Purchases", "المشتريات", ckb: "کڕینەکان", kmr: "Kirîn")
        case .account: return tr("Account", "الحساب", ckb: "ئەکاونت", kmr: "Hesab")
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

    @Published private(set) var sessionRevision = 0

    func updateAccount(_ value: MirsaStoreAccount?) {
        sessionRevision += 1
        account = value
        loaded = true
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

struct AppStoreSectionBar: View {
    @Binding var selection: AppStoreSectionTab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: MirsaSpacing.xxs) {
            ForEach(AppStoreSectionTab.allCases) { tab in
                let on = selection == tab
                Button {
                    withAnimation(MirsaMotion.select) { selection = tab }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: on ? .semibold : .regular))
                            .frame(height: 20)
                        Text(tab.title).font(MirsaFont.tabLabel).lineLimit(1)
                            .minimumScaleFactor(0.7).allowsTightening(true)
                    }
                    .foregroundStyle(on ? Color.white : MirsaPalette.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if on {
                            Capsule().fill(Color.white.opacity(0.14))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
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
        .padding(5)
        .frame(height: 56)
        .modifier(MirsaSolidCard(shape: Capsule(), tint: nil, elevation: 1))
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
            Image(systemName: "magnifyingglass").foregroundStyle(MirsaPalette.textTertiary)
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
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(MirsaPalette.cardRaised.opacity(0.85), in: Capsule())
        .overlay(Capsule().strokeBorder(MirsaPalette.stroke, lineWidth: 1))
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
                Text(title).font(MirsaFont.sectionTitle).foregroundStyle(.white)
                    .padding(.horizontal, MirsaSpacing.xxs)
            }
            VStack(spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .mirsaCard()
            if let footer {
                Text(footer).font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MirsaSpacing.xxs)
            }
        }
    }
}

struct AppStoreRowDivider: View {
    var inset: CGFloat = 52
    var body: some View {
        Rectangle().fill(MirsaPalette.stroke).frame(height: 1).padding(.leading, inset)
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
                .font(.system(size: MirsaIconSize.m, weight: .semibold))
                .foregroundStyle(tint == .white ? MirsaPalette.accentSoft : tint)
                .frame(width: 28)
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

    @State private var path: [AppStoreAccountRoute] = AppStoreAccountRoute.initialPath
    @State private var confirmSignOut = false
    @State private var signingOut = false
    @State private var error: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: MirsaSpacing.l) {
                    MirsaPageHeader(title: tr("Account", "الحساب", ckb: "ئەکاونت", kmr: "Hesab")) { EmptyView() }
                    profileCard
                    accountsGroup
                    linksGroup
                    if model.account != nil { signOutButton }
                }
                .padding(.horizontal, MirsaSpacing.page)
                .padding(.bottom, MirsaSpacing.xl)
            }
            .background(AuroraBackground().ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppStoreAccountRoute.self) { route in
                switch route {
                case .settings: AppStoreDownloadSettingsPage(model: model, library: library)
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
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

    @ViewBuilder private var profileCard: some View {
        if let a = model.account {
            HStack(spacing: MirsaSpacing.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(a.name.isEmpty ? a.email : a.name)
                        .font(.title3.weight(.bold)).foregroundStyle(.white).lineLimit(1)
                    Text(a.email).font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                    Label(tr("Storefront: ", "واجهة المتجر: ", ckb: "ستۆر: ", kmr: "Store: ") + AppStoreCountry.label(a.country),
                          systemImage: "globe")
                        .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                }
                Spacer(minLength: 0)
                AppStoreAvatar(text: a.name.isEmpty ? a.email : a.name)
            }
            .padding(MirsaSpacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mirsaCard()
            .accessibilityElement(children: .combine)
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
                AppStoreAvatar(text: "")
            }
            .padding(MirsaSpacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mirsaCard()
            .accessibilityIdentifier("store-account-profile")
        }
    }

    private var accountsGroup: some View {
        AppStoreGroup(title: tr("Accounts", "الحسابات", ckb: "ئەکاونتەکان", kmr: "Hesab"),
                      footer: tr("Mirsa keeps one Apple Account signed in at a time. To use another one, sign out, then add it.",
                                 "مرسى بيخلّي حساب Apple واحد مسجّل بنفس الوقت. لتستخدم حساب تاني، اطلع من الحالي وبعدين ضيفو.",
                                 ckb: "Mirsa لە یەک کاتدا تەنها یەک ئەکاونتی Apple دەهێڵێتەوە. بۆ بەکارهێنانی یەکێکی تر، بچۆ دەرەوە و پاشان زیادی بکە.",
                                 kmr: "Mirsa di carekê de tenê hesabekî Apple têketî dihêle. Ji bo yekî din, derkeve û paşê wî zêde bike.")) {
            if let a = model.account {
                HStack(spacing: MirsaSpacing.s) {
                    AppStoreAvatar(text: a.name.isEmpty ? a.email : a.name, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.name.isEmpty ? a.email : a.name).font(MirsaFont.body).foregroundStyle(.white).lineLimit(1)
                        Text(a.email).font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: MirsaSpacing.xs)
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(MirsaPalette.accentSoft)
                        .accessibilityLabel(tr("Active", "الحالي", ckb: "چالاک", kmr: "Çalak"))
                }
                .padding(.horizontal, MirsaSpacing.card).padding(.vertical, 11)
                .accessibilityElement(children: .combine)
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
        AppStoreGroup {
            Button { onOpen(.purchases) } label: {
                AppStoreRow(icon: "bag", title: tr("Purchases", "المشتريات", ckb: "کڕینەکان", kmr: "Kirîn")) { AppStoreChevron() }
            }
            .buttonStyle(.plain)
            AppStoreRowDivider()
            Button { onOpen(.downloads) } label: {
                AppStoreRow(icon: "arrow.down.circle", title: tr("Downloads and installs", "التنزيلات والتثبيت", ckb: "داگرتن و دامەزراندن", kmr: "Daxistin û sazkirin")) {
                    Text("\(library.entries.count)").font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textTertiary).monospacedDigit()
                    AppStoreChevron()
                }
            }
            .buttonStyle(.plain)
            AppStoreRowDivider()
            Button { path.append(.settings) } label: {
                AppStoreRow(icon: "gearshape", title: tr("Settings", "الإعدادات", ckb: "ڕێکخستنەکان", kmr: "Mîheng")) { AppStoreChevron() }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("store-open-settings")
        }
    }

    private var signOutButton: some View {
        Button { confirmSignOut = true } label: {
            HStack {
                if signingOut { ProgressView().tint(MirsaPalette.danger) }
                Text(tr("Sign out", "تسجيل الخروج", ckb: "چوونە دەرەوە", kmr: "Derkeve"))
            }
            .font(MirsaFont.button)
            .foregroundStyle(MirsaPalette.danger)
            .frame(maxWidth: .infinity, minHeight: 50)
            .mirsaCard()
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

// MARK: - Settings

struct AppStoreDownloadSettingsPage: View {
    @ObservedObject var model: AppStoreSectionModel
    @ObservedObject var library: EncryptedAppsStore
    @ObservedObject private var language = AppLanguageStore.shared
    @AppStorage(MirsaTheme.key) private var theme = MirsaTheme.liquid.rawValue
    @State private var tmpSize = "…"
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
        .background(AuroraBackground().ignoresSafeArea())
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
        DispatchQueue.global(qos: .utility).async {
            _ = MirsaManagedTmp.cleanNow()
            let text = MirsaManagedTmp.sizeText
            DispatchQueue.main.async { tmpSize = text; cleaning = false }
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
                MirsaPageHeader(title: tr("Purchases", "المشتريات", ckb: "کڕینەکان", kmr: "Kirîn")) {
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.disabled(loading || !isActive)
                        .accessibilityLabel(tr("Refresh purchases", "تحديث المشتريات", ckb: "نوێکردنەوەی کڕینەکان", kmr: "Kirînan nû bike"))
                }
                if let account = model.account {
                    Text(account.email).font(MirsaFont.caption).foregroundStyle(MirsaPalette.textSecondary)
                    AppStoreSearchField(placeholder: tr("Search purchases or App ID", "البحث بالمشتريات أو App ID", ckb: "گەڕان لە کڕینەکان", kmr: "Li kirînan bigere"), text: $query)
                    purchaseFilters
                    HStack {
                        Text(String(visible.count) + tr(" items", " عنصراً", ckb: " بڕگە", kmr: " tişt"))
                            .font(MirsaFont.caption.weight(.semibold))
                            .foregroundStyle(MirsaPalette.accentSoft)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(MirsaPalette.accentSoft.opacity(0.10), in: Capsule())
                            .overlay(Capsule().strokeBorder(MirsaPalette.accentSoft.opacity(0.18), lineWidth: 1))
                            .accessibilityIdentifier("store-purchases-count")
                        Spacer()
                    }
                    if loading { ProgressView() }
                    if let error {
                        Text(error).font(MirsaFont.secondary).foregroundStyle(MirsaPalette.warning)
                    } else if !loading && visible.isEmpty {
                        Text(tr("No matching purchases.", "ما في مشتريات مطابقة.", ckb: "هیچ کڕینێک ناگونجێت.", kmr: "Kirînek li hev nayê.")).foregroundStyle(MirsaPalette.textSecondary)
                    }
                    LazyVStack(alignment: .leading, spacing: MirsaSpacing.l) {
                        ForEach(StorePurchaseGroups.make(visible)) { group in
                            purchaseGroup(group)
                        }
                    }
                    .accessibilityIdentifier("store-purchases-month-list")
                } else {
                    Text(tr("Sign in from the Account tab to load your Apple purchases.", "سجّل دخول من تبويب الحساب لتشوف مشتريات Apple تبعك.", ckb: "بچۆ ژوورەوە بۆ بینینی کڕینەکان.", kmr: "Ji bo kirînan têkeve hesabê te.")).foregroundStyle(MirsaPalette.textSecondary)
                }
            }.padding(.horizontal, MirsaSpacing.page).padding(.bottom, MirsaSpacing.xl)
        }
        .refreshable { await reload() }
        .task(id: loadIdentity) {
            reloadID = UUID(); reloadTask?.cancel()
            recovery = nil; purchases = []; artwork = [:]; error = nil; loading = false
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
        .onDisappear { reloadTask?.cancel() }
        .scrollDismissesKeyboard(.interactively)
        .background(AuroraBackground().ignoresSafeArea())
        .environment(\.layoutDirection, .leftToRight)
    }
    private var purchaseFilters: some View {
        HStack(spacing: 6) {
            purchaseFilter(0, title: tr("All", "الكل", ckb: "هەموو", kmr: "Hemû"))
            purchaseFilter(1, title: tr("1 month", "شهر", ckb: "مانگێک", kmr: "1 meh"))
            purchaseFilter(6, title: tr("6 months", "٦ أشهر", ckb: "٦ مانگ", kmr: "6 meh"))
            purchaseFilter(12, title: tr("12 months", "سنة", ckb: "ساڵێک", kmr: "12 meh"))
        }
    }

    private func purchaseFilter(_ value: Int, title: String) -> some View {
        Button { withAnimation(MirsaMotion.select) { months = value } } label: {
            Text(title).font(MirsaFont.caption.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(months == value ? Color.white : MirsaPalette.textSecondary)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(months == value ? Color.white.opacity(0.14) : Color.white.opacity(0.035), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(months == value ? 0.22 : 0.07), lineWidth: 1))
        }
        .buttonStyle(.mirsaPress)
        .accessibilityAddTraits(months == value ? .isSelected : [])
        .accessibilityIdentifier("store-purchases-filter-\(value)")
    }

    private func purchaseGroup(_ group: StorePurchaseGroups.Group) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
            Spacer(minLength: 0)
            Text(String(group.items.count)).font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
            Text(group.month.map { StorePurchaseGroups.title($0, locale: AppLanguageStore.shared.current.locale) }
                 ?? tr("Date unavailable", "التاريخ مو متوفر", ckb: "بەروار بەردەست نییە", kmr: "Dîrok ne berdest e"))
                .font(MirsaFont.sectionTitle).foregroundStyle(MirsaPalette.textSecondary)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            }
            LazyVStack(spacing: 0) {
                ForEach(group.items) { item in
                    purchaseRow(item)
                    if item.id != group.items.last?.id {
                        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)
                            .padding(.horizontal, MirsaSpacing.card)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .background(MirsaPalette.accentSoft.opacity(0.035), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func purchaseRow(_ item: MirsaStorePurchase) -> some View {
        HStack(spacing: MirsaSpacing.s) {
            // Physical LTR is app-wide. Put the real download action on the left.
            Group {
                if downloading == item.id { ProgressView() }
                else {
                    Button { Task { await download(item) } } label: {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(MirsaPalette.accentSoft)
                            .frame(width: 44, height: 44)
                            .background(MirsaPalette.accentSoft.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.mirsaPress)
                    .disabled(loading || downloading != nil || store.busy != nil)
                    .accessibilityLabel(tr("Download", "تنزيل", ckb: "داگرتن", kmr: "Daxe") + " " + item.name)
                    .accessibilityIdentifier("store-purchase-download-\(item.id)")
                }
            }.frame(width: 44, height: 44)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Text(item.name.isEmpty ? item.bundleID : item.name)
                    .font(MirsaFont.cardTitle).foregroundStyle(.white)
                    .lineLimit(2).multilineTextAlignment(.trailing)
                if let date = StorePurchaseGroups.validDate(item.date) {
                    Text(date.formatted(.dateTime.day().month(.abbreviated).year()
                        .locale(AppLanguageStore.shared.current.locale)))
                        .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textSecondary)
                }
                // History has no reliable size field. Do not invent one or fetch a package here.
            }
            AsyncImage(url: artwork[item.id].flatMap { URL(string: $0) }) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "app.dashed").font(.title2).foregroundStyle(MirsaPalette.textTertiary)
            }
            .frame(width: 52, height: 52).background(MirsaPalette.cardRaised)
            .clipShape(RoundedRectangle(cornerRadius: MirsaRadius.icon, style: .continuous))
            .accessibilityHidden(true)
        }
        .padding(.horizontal, MirsaSpacing.card).padding(.vertical, 14)
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
            let result = try await MirsaStoreOnDeviceClient.shared.purchaseHistory()
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
