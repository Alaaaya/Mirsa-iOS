import SwiftUI

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

    func refresh() async {
        #if DEBUG
        if let fixture = Self.fixtureAccount { account = fixture; loaded = true; return }
        if MirsaUITestHarness.active { account = nil; loaded = true; return }
        #endif
        let current = try? await MirsaStoreOnDeviceClient.shared.currentAccount()
        account = current
        loaded = true
    }

    /// Same call the sign-in screen uses for its own Sign out button.
    func signOut() async throws {
        #if DEBUG
        if MirsaUITestHarness.active { account = nil; return }
        #endif
        try await MirsaStoreOnDeviceClient.shared.signOut()
        account = nil
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

/// IPAs in the library, grouped by who bought them. Apple's own purchase history is
/// not requested here; only the purchaser recorded inside each IPA is shown.
struct AppStorePurchasesPage: View {
    @ObservedObject var store: EncryptedAppsStore
    @ObservedObject var model: AppStoreSectionModel
    let vm: AppViewModel

    enum Filter: String, CaseIterable, Identifiable {
        case all, mine, others
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return tr("All", "الكل", ckb: "هەموو", kmr: "Hemû")
            case .mine: return tr("This account", "هالحساب", ckb: "ئەم ئەکاونتە", kmr: "Ev hesab")
            case .others: return tr("Other accounts", "حسابات تانية", ckb: "ئەکاونتی تر", kmr: "Hesabên din")
            }
        }
    }

    @State private var query = ""
    @State private var filter: Filter = .all

    private func mine(_ e: EncryptedIPAEntry) -> Bool {
        guard let me = model.account?.email, let buyer = e.metadata?.purchaserAppleID else { return false }
        return me.caseInsensitiveCompare(buyer) == .orderedSame
    }

    private var visible: [EncryptedIPAEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.entries.filter { e in
            switch filter {
            case .all: break
            case .mine: if !mine(e) { return false }
            case .others: if mine(e) { return false }
            }
            guard !q.isEmpty else { return true }
            return e.name.localizedCaseInsensitiveContains(q) || e.bundleID.localizedCaseInsensitiveContains(q)
                || (e.metadata?.itemID.map { String($0).contains(q) } ?? false)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MirsaSpacing.m) {
                MirsaPageHeader(title: tr("Purchases", "المشتريات", ckb: "کڕینەکان", kmr: "Kirîn")) { EmptyView() }
                AppStoreSearchField(placeholder: tr("Search purchases or App ID", "البحث بالمشتريات أو App ID", ckb: "گەڕان لە کڕینەکان یان App ID", kmr: "Li kirînan an App ID bigere"),
                                    text: $query)
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { f in Text(f.title).tag(f) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("store-purchases-filter")
                if let email = model.account?.email {
                    Text(tr("Account: ", "الحساب: ", ckb: "ئەکاونت: ", kmr: "Hesab: ") + email)
                        .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary).lineLimit(1).truncationMode(.middle)
                }
                Text(tr("Items: ", "العناصر: ", ckb: "بڕگەکان: ", kmr: "Tişt: ") + "\(visible.count)")
                    .font(MirsaFont.sectionTitle).foregroundStyle(.white)
                if visible.isEmpty {
                    Text(store.entries.isEmpty
                         ? tr("No App Store IPAs in Mirsa yet.", "لسّا ما في IPA من App Store بمرسى.", ckb: "هێشتا هیچ IPAیەکی App Store لە Mirsa نییە.", kmr: "Hêj IPA ya App Store di Mirsa de tune.")
                         : tr("Nothing matches.", "ما في شي مطابق.", ckb: "هیچ شتێک ناگونجێت.", kmr: "Tiştek li hev nayê."))
                        .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                        .padding(MirsaSpacing.card).frame(maxWidth: .infinity).mirsaCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { AppStoreRowDivider(inset: 84) }
                            row(entry)
                        }
                    }
                    .mirsaCard()
                }
                Text(tr("Apple's purchase history is not loaded here. This list shows the App Store IPAs saved in Mirsa and the Apple Account that bought each one.",
                        "سجل مشتريات Apple ما بينجاب هون. هالقائمة بتعرض ملفات IPA من App Store المحفوظة بمرسى وحساب Apple يلي اشترى كل واحد.",
                        ckb: "مێژووی کڕینی Apple لێرە بار ناکرێت. ئەم لیستە IPAکانی App Store لە Mirsa و ئەو ئەکاونتەی کڕیویەتی نیشان دەدات.",
                        kmr: "Dîroka kirînê ya Apple li vir nayê barkirin. Ev lîste IPAyên App Store yên di Mirsa de û hesabê ku her yek kirî nîşan dide."))
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, MirsaSpacing.page)
            .padding(.bottom, MirsaSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AuroraBackground().ignoresSafeArea())
        .environment(\.layoutDirection, .leftToRight)
    }

    private func row(_ entry: EncryptedIPAEntry) -> some View {
        HStack(spacing: MirsaSpacing.s) {
            Group {
                if let img = store.icon(entry) { Image(uiImage: img).resizable().scaledToFill() }
                else { Image(systemName: "app.dashed").font(.title2).foregroundStyle(MirsaPalette.textTertiary) }
            }
            .frame(width: 56, height: 56)
            .background(MirsaPalette.cardRaised)
            .clipShape(RoundedRectangle(cornerRadius: MirsaRadius.icon, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(MirsaFont.cardTitle).foregroundStyle(.white).lineLimit(2)
                Text(tr("Bought by: ", "اشتراه: ", ckb: "کڕیار: ", kmr: "Kirrîyar: ")
                     + (entry.metadata?.purchaserAppleID ?? tr("unknown", "غير معروف", ckb: "نەزانراو", kmr: "nenas")))
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textSecondary).lineLimit(1).truncationMode(.middle)
                Text(tr("Added ", "انضاف ", ckb: "زیادکرا ", kmr: "Hat zêdekirin ")
                     + entry.addedAt.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(AppLanguageStore.shared.current.locale)))
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
            }
            Spacer(minLength: MirsaSpacing.xs)
            if store.installingID == entry.id {
                ProgressView(value: store.progress).progressViewStyle(.circular).tint(.white)
            } else {
                Button { Task { await store.install(entry, vm: vm) } } label: {
                    Image(systemName: entry.installedAt != nil ? "checkmark.icloud" : "icloud.and.arrow.down")
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(MirsaPalette.accentSoft)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(store.busy != nil)
                .accessibilityLabel(tr("Install as-is", "ثبّت متل ما هو", ckb: "وەک خۆی دابمەزرێنە", kmr: "Wekî xwe saz bike"))
            }
        }
        .padding(.horizontal, MirsaSpacing.card)
        .padding(.vertical, MirsaSpacing.s)
    }
}
