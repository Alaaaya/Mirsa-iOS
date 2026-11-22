import SwiftUI
import ApplePackage

/// Own-account App Store downloads (no sharing, no decryption, no signing).
/// Self-contained: the host passes `onDownloaded` which must import the file into the
/// encrypted-IPA flow WITHOUT modifying it. After it returns normally this view removes
/// the file's private temp directory. Hook: AppStoreAccountView(onDownloaded: { url in ... }).
struct AppStoreAccountView: View {
    var onDownloaded: (URL) async throws -> Void
    var searchOnly = false
    /// Opens straight on this app detail (used from the purchases list).
    var openAppID: Int64? = nil
    var onOpenAccount: () -> Void = {}
    /// Gallery store style: the tab's one App Store screen shows Discover or Search.
    var galleryMode: StoreGalleryMode = .search
    /// Bumped by the tab when the user taps the Discover or Search item again: closes an open app page.
    var galleryResetToken = 0
    @AppStorage("mirsa.store.recentSearches.v1") private var recentSearchData = Data()

    private let client = MirsaStoreOnDeviceClient.shared
    @ObservedObject private var session = AppStoreSectionModel.shared
    private var account: MirsaStoreAccount? {
        get { session.account }
        nonmutating set { session.updateAccount(newValue) }
    }
    @State private var searchCountry: String?
    @State private var showCountries = false
    @State private var countryQuery = ""
    @State private var accountAvailable: Set<Int64> = []
    private enum Ownership { case owned, licenseRequired }
    // Session-local positive evidence only. No entry means unknown, not unowned.
    @State private var ownership: [Int64: Ownership] = [:]
    private var effectiveCountry: String { searchCountry ?? account?.country ?? "tr" }
    private var otherStore: Bool { effectiveCountry.lowercased() != account?.country.lowercased() }
    private func canDownload(_ app: MirsaStoreApp) -> Bool { (ownership[app.id] != .licenseRequired) && (!otherStore || accountAvailable.contains(app.id)) }

    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var needsCode = false
    @State private var versions: [String: [String]] = [:]
    @State private var metadata: [String: [String: MirsaStoreServerClient.VersionMetadata]] = [:]
    @State private var metadataTasks: [String: Task<Void, Never>] = [:]
    @State private var metadataLimit: [String: Int] = [:]
    @State private var metadataAttempts: [String: Int] = [:]
    @State private var chosen: [String: String] = [:]
    @State private var preflightTask: Task<Void, Never>?
    @State private var pendingOS: (app: MirsaStoreApp, acquire: Bool)?
    @State private var versionListAttempted: Set<Int64> = []
    @State private var term = ""
    @State private var results: [MirsaStoreApp] = []
    @State private var searched = false
    @State private var discoveryGenre: Int?
    @State private var chartApps: [StoreChartApp] = []
    @State private var chartLoadedKey = ""
    @State private var chartLoading = false
    @State private var chartFailed = false
    @State private var chartRetry = 0
    /// Includes whether an account is signed in, so Apple's chart loads right after sign-in.
    private var discoveryKey: String { "\(effectiveCountry.lowercased())|\(discoveryGenre ?? 0)|\(chartRetry)|\(account == nil ? 0 : 1)" }

    @State private var busy: String?
    @State private var work: Task<Void, Never>?
    @State private var recovery: StoreFreeLicenseRecovery?
    /// Get paused because Apple asked to confirm the password (session kept).
    @State private var authorizeApp: MirsaStoreApp?
    @State private var authorizeCodeApp: MirsaStoreApp?
    @State private var notice: String?
    @State private var showSteps = false
    @State private var confirmSignOut = false
    @State private var operationGeneration = UUID()
    /// UI only: the app whose detail page is open, and when the current task started.
    @State private var selected: MirsaStoreApp?
    @State private var busySince: Date?
    @State private var transfer: StoreDownloadProgress?
    @State private var inlineTransferAppID: Int64?
    @State private var inlineIsGet = false
    @State private var progressAttempt: UUID?
    @FocusState private var focus: Bool
    @ObservedObject private var library = StoreLibraryModel.shared
    @ObservedObject private var tints = StoreArtworkTint.shared

    private func t(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String { tr(en, ar, ckb: ckb, kmr: kmr) }

    // Separate opaque view boundaries keep SwiftUI type-checking bounded.
    private var accountScrollContent: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: MirsaSpacing.m) {
                Color.clear.frame(height: 0).id("store-top")
                if let account, let app = selected {
                    if busy != nil { busyCard }
                    detailView(app, account: account)
                } else {
                    if searchOnly { searchHeader }
                    if searchOnly && galleryMode == .search && StoreSearchNavigation(term: term, resultCount: results.count, searched: searched, genreActive: discoveryGenre != nil, detailOpen: false).showsBack {
                        HStack {
                            Button { StoreHaptics.select(); exitSearchToMain() } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left").flipsForRightToLeftLayoutDirection(true)
                                    Text(storeText("Back", "رجوع", de: "Zurück", ckb: "گەڕانەوە", kmr: "Vegere"))
                                }
                                    .font(MirsaFont.button).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 36).galleryGlassCapsule()
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("store-search-back")
                            Spacer()
                        }
                    }
                    if !searchOnly {
                        StoreGalleryHeader(title: t("My App Store", "حسابي بالـApp Store", "ئەپستۆری من", "App Store ya min")) { EmptyView() }
                        infoCard
                    }
                    if let account { signedInCards(account) }
                    else if !session.loaded { StoreSkeletonCard(); StoreSkeletonCard() }
                    else if searchOnly {
                        signedOutCard
                    } else if needsCode { verificationCard } else { signInCard }
                    if busy != nil { busyCard }
                }
            }
            .environment(\.layoutDirection, StoreGallery.direction)
            .padding(.horizontal, MirsaSpacing.page)
            .padding(.bottom, MirsaSpacing.tabBarClearance)
            .background(alignment: .top) {
                if account != nil, let app = selected { detailBackdrop(app) }
            }
        }
        .onChange(of: selected?.id) { _, _ in withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { proxy.scrollTo("store-top", anchor: .top) } }
        .refreshable { pullToRefresh() }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(StoreGalleryPageBackdrop())
        .preferredColorScheme(.dark)
        .environment(\.layoutDirection, .leftToRight)
    }

    private var accountLifecycleContent: some View {
        accountScrollContent
        .onChange(of: galleryMode) { _, _ in
            // Discover and Search share this screen: switching faces closes an open app page.
            if selected != nil { withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { selected = nil } }
        }
        .onChange(of: galleryResetToken) { _, _ in
            if selected != nil { withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { selected = nil } }
        }
        .onChange(of: liveTransferKey) { _, _ in publishLiveTransfer() }
        // Apple's chart feeds both faces (Discover and Search), so it loads here once per
        // storefront/category instead of every time a face appears.
        .task(id: discoveryKey) {
            guard searchOnly, openAppID == nil, account != nil else { return }
            await loadChart()
        }
        .task {
            #if DEBUG
            if let fixture = Self.uiTestFixture() { account = fixture.account; results = fixture.results; searched = true
                versions = fixture.versions; metadata = fixture.metadata; metadataLimit = fixture.limits; selected = fixture.selected; return }
            #endif
            await session.refresh()
        }
        .sheet(isPresented: $showCountries) {
            NavigationStack {
                List {
                    Button(t("Account storefront", "متجر حسابي", "ستۆری ئەکاونت", "Stoya hesabê min")) { selectCountry(nil) }
                    ForEach(Locale.isoRegionCodes.filter {
                        $0.count == 2 && (countryQuery.isEmpty || AppStoreCountry.label($0).localizedCaseInsensitiveContains(countryQuery))
                    }.sorted { AppStoreCountry.label($0) < AppStoreCountry.label($1) }, id: \.self) { country in
                        Button(AppStoreCountry.label(country)) { selectCountry(country.lowercased()) }
                    }
                }.mirsaListBackground()
                .searchable(text: $countryQuery)
                .navigationTitle(t("Search storefront", "متجر البحث", "ستۆری گەڕان", "Stoya lêgerînê"))
                .toolbar { Button(t("Done", "تمام", "تەواو", "Temam")) { showCountries = false } }
            }
            .preferredColorScheme(.dark)
        }
        .onChange(of: busy) { _, value in busySince = value == nil ? nil : (busySince ?? Date()) }
        .confirmationDialog(StoreFeatureText.osConfirmTitle, isPresented: Binding(get: { pendingOS != nil }, set: { if !$0 { pendingOS = nil } }), titleVisibility: .visible) {
            Button(StoreFeatureText.continueAnyway) {
                if let p = pendingOS { pendingOS = nil; if p.acquire { acquire(p.app) } else { download(p.app) } }
            }
            Button(StoreFeatureText.cancel, role: .cancel) { pendingOS = nil }
        } message: { Text(StoreFeatureText.minOSWarn) }
        .onChange(of: account) { _, value in
            #if DEBUG
            if Self.uiTestFixture() != nil { return }
            #endif
            // Account switched: drop in-flight work and every account-specific result immediately.
            operationGeneration = UUID(); preflightTask?.cancel(); preflightTask = nil; work?.cancel(); work = nil; busy = nil; transfer = nil; progressAttempt = nil
            results = []; accountAvailable = []; metadata = [:]; pendingOS = nil
            recovery = nil; ownership = [:]; versionListAttempted = []; versions = [:]; chosen = [:]
            if value == nil { selected = nil }
        }
        .task(id: busy == nil ? selected?.id : nil) {
            guard busy == nil, let app = selected, versions[app.bundleID] == nil,
                  !versionListAttempted.contains(app.id), ownership[app.id] != .licenseRequired else { return }
            versionListAttempted.insert(app.id)
            loadVersions(app)
        }
        .task { if let id = openAppID, account != nil, results.isEmpty, selected == nil { term = String(id); search() } }
        .onDisappear { preflightTask?.cancel(); password = ""; code = ""; work?.cancel(); cancelMetadata() }
    }

    private var accountAuthorizationContent: some View {
        accountLifecycleContent
        .alert(t("Notice", "تنبيه", "ئاگاداری", "Agahdarî"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(t("OK", "تمام", "باشە", "Baş e")) { notice = nil }
        } message: { Text(notice ?? "") }
        .alert(storeText("Confirm your Apple Account", "أكّد حساب Apple", de: "Apple Account bestätigen", ckb: "ئەکاونتی Apple پشتڕاست بکەرەوە", kmr: "Hesabê Apple piştrast bike"),
               isPresented: Binding(get: { authorizeApp != nil }, set: { if !$0 { authorizeApp = nil } }), presenting: authorizeApp) { app in
            SecureField(storeText("Password", "كلمة السر", de: "Passwort", ckb: "وشەی نهێنی", kmr: "Şîfre"), text: $password)
            Button(storeText("Confirm and Get", "أكّد وخدو", de: "Bestätigen und laden", ckb: "پشتڕاستکردنەوە و وەرگرتن", kmr: "Piştrast bike û bigire")) { confirmPurchase(app) }
            Button(t("Cancel", "إلغاء", "هەڵوەشاندنەوە", "Betal"), role: .cancel) { password = "" }
        } message: { _ in Text(MirsaStorePurchaseAuthorization().localizedDescription + (account.map { "\n" + $0.email } ?? "")) }
        .alert(storeText("Verification code", "رمز التحقق", de: "Bestätigungscode", ckb: "کۆدی پشتڕاستکردنەوە", kmr: "Koda piştrastkirinê"),
               isPresented: Binding(get: { authorizeCodeApp != nil }, set: { if !$0 { authorizeCodeApp = nil } }), presenting: authorizeCodeApp) { app in
            TextField("000000", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
            Button(storeText("Confirm and Get", "أكّد وخدو", de: "Bestätigen und laden", ckb: "پشتڕاستکردنەوە و وەرگرتن", kmr: "Piştrast bike û bigire")) { confirmPurchaseCode(app) }
            Button(t("Cancel", "إلغاء", "هەڵوەشاندنەوە", "Betal"), role: .cancel) { code = "" }
        } message: { _ in Text(t("Enter the 6-digit code from Apple.", "اكتب الرمز من 6 أرقام من Apple.", "کۆدی ٦ ژمارەیی Apple بنووسە.", "Koda 6 hejmarî ya Apple binivîse.")) }
    }

    var body: some View {
        accountAuthorizationContent
        .confirmationDialog(t("Refresh free licence and retry?", "تحديث الترخيص المجاني وإعادة التنزيل؟", "مۆڵەتی بێبەرامبەر نوێ بکەوە؟", "Lîsansa belaş nû bike?"),
                            isPresented: Binding(get: { recovery != nil }, set: { if !$0 { recovery = nil } }), titleVisibility: .visible) {
            if let pending = recovery {
                Button(t("Refresh free licence and retry once", "حدّث الترخيص المجاني وجرّب مرة", "نوێکردنەوە و هەوڵێکی تر", "Nû bike û carekê biceribîne")) { recoverDownload(pending) }
            }
            Button(t("Cancel", "إلغاء", "هەڵوەشاندنەوە", "Betal"), role: .cancel) { recovery = nil }
        } message: {
            Text(t("Apple rejected the download, not necessarily ownership. This checks the current account store, refreshes only a verified free licence, then retries your exact selected version once. No paid purchase.",
                   "Apple رفضت التنزيل، مو دليل إنك ما بتملك التطبيق. منتحقق من متجر حسابك، منحدّث الترخيص إذا مجاني، ومنعيد نفس النسخة المختارة مرة وحدة. ما في شراء مدفوع.",
                   "ڕەتکردنەوە بەڵگەی نەبوونی خاوەندارێتی نییە. تەنها مۆڵەتی بێبەرامبەر نوێ دەکرێتەوە و هەمان وەشان جارێک داگیرێت.",
                   "Redkirin nebûna xwedîtiyê îspat nake. Tenê lîsansa belaş nû dibe û heman guherto carekê tê ceribandin."))
        }
        .confirmationDialog(t("Sign out of this Apple Account?", "تطلع من حساب Apple؟", "لە ئەکاونتی Apple بچیتە دەرەوە؟", "Ji hesabê Apple derkevî?"),
                            isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(t("Sign out", "تسجيل الخروج", "چوونە دەرەوە", "Derkeve"), role: .destructive) { signOut() }
            Button(t("Cancel", "إلغاء", "هەڵوەشاندنەوە", "Betal"), role: .cancel) {}
        } message: {
            Text(t("Your local Apple session and verification challenge are deleted. Imported IPAs stay.",
                   "بتنمسح جلسة دخول Apple ورموز التحقق من آيفونك. ملفات IPA المستوردة بتضل.",
                   "دانیشتن و کۆدەکان و داگرتنەکانی سێرڤەر دەسڕدرێنەوە. IPA هاوردەکراوەکان دەمێنن.",
                   "Danişîn, kod û daxistinên serverê tên jêbirin. IPAyên hatine anîn dimînin."))
        }
    }

    // MARK: cards

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            Label(t("Download apps your own Apple Account owns. Mirsa does not decrypt, sign or share them.",
                    "نزّل تطبيقات حساب Apple تبعك بيملكها. مرسى ما بيفك تشفيرها ولا بيوقّعها ولا بيشاركها.",
                    "ئەو ئەپانە دابگرە کە ئەکاونتی Apple ی خۆت خاوەنیەتی. Mirsa ڕەمزیان ناکاتەوە، واژۆیان ناکات و بڵاویان ناکاتەوە.",
                    "Sepanên ku hesabê te yê Apple xwedî ye dakêşe. Mirsa şîfreya wan venake, îmze nake û parve nake."),
                  systemImage: "lock.shield.fill")
                .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
            if account == nil {
                Text(t("Sign-in goes directly to Apple; Mirsa doesn't store your password.",
                       "تسجيل الدخول مباشر مع Apple، ومرسى ما بيحفظ كلمة السر",
                       "چوونەژوورەوە ڕاستەوخۆ لەگەڵ Apple ـە، و Mirsa وشەی نهێنییەکەت هەڵناگرێت.",
                       "Têketin rasterast bi Apple re ye; Mirsa şîfreya te tomar nake."))
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { withAnimation(.easeOut(duration: 0.2)) { showSteps.toggle() } } label: {
                HStack {
                    Text(t("How it works and limits", "كيف بيشتغل والحدود", "چۆن کار دەکات و سنوورەکان", "Çawa dixebite û sînor"))
                    Spacer()
                    Image(systemName: showSteps ? "chevron.up" : "chevron.down")
                }
                .font(MirsaFont.button).foregroundStyle(MirsaPalette.accentSoft)
            }
            Text(t("Opens the guide below.", "بيفتح الشرح تحت.", "ڕاڤەکە لە خوارەوە دەکاتەوە.", "Rêbernameyê li jêr vedike."))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
            if showSteps {
                VStack(alignment: .leading, spacing: 8) {
                    step("1", t("Your iPhone signs in directly to Apple over HTTPS. Your password is not saved. Only the session is kept.",
                                "آيفونك بيسجّل دخول مباشرة عند Apple عبر HTTPS. كلمة السر ما بتنحفظ، بس جلسة الدخول.",
                                "Mirsa ئیمەیڵ و وشەی نهێنی بە HTTPS بۆ سێرڤەری خۆی دەنێرێت بۆ چوونەژوورەوەی Apple. وشەی نهێنی هەڵناگیرێت، تەنها دانیشتن.",
                                "Mirsa e-name û şîfreya te bi HTTPS ji servera xwe re dişîne ji bo têketina Apple. Şîfre nayê tomarkirin, tenê danişîn dimîne."))
                    step("2", t("If Apple asks, type the 6-digit code it sends to your devices.",
                                "إذا طلبت Apple، اكتب الرمز من 6 أرقام يلي بيوصلك.",
                                "ئەگەر Apple داوای کرد، کۆدی ٦ ژمارەیی بنووسە کە بۆت دێت.",
                                "Heke Apple bixwaze, koda 6 hejmarî ya ku jî re tê binivîse."))
                    step("3", t("Search the store linked to your Apple Account.",
                                "دوّر على تطبيق بمتجر حساب Apple تبعك.",
                                "لە ستۆری بەستراو بە ئەکاونتی Apple بگەڕێ.",
                                "Li stoya girêdayî hesabê Apple bigere."))
                    step("4", t("Free apps you never got: tap Get free license once. Paid apps are never bought here.",
                                "تطبيقات مجانية ما حصلت عليها: دوس احصل على ترخيص مجاني مرة وحدة. التطبيقات المدفوعة ما بتنشترى هون.",
                                "ئەپە بێبەرامبەرەکان کە نەتهێناون: جارێک مۆڵەتی بێبەرامبەر بهێنە. ئەپی پارەدار لێرە ناکڕدرێت.",
                                "Sepanên belaş ên te negirtine: carekê lîsansa belaş bigire. Sepanên bi pere li vir nayên kirîn."))
                    step("5", t("Open the app page and choose Latest or an older version from Apple's official list, then tap Download. Names are labels; downloads use the selected external version ID.",
                                "افتح صفحة التطبيق واختار الأحدث أو نسخة قديمة من قائمة Apple الرسمية، وبعدين دوس تنزيل. اسم النسخة للعرض، والتنزيل برقمها الرسمي.",
                                "پەڕەی ئەپەکە بکەرەوە، نوێترین یان وەشانێکی کۆن لە لیستی فەرمی Apple هەڵبژێرە، پاشان دایبگرە.",
                                "Rûpela sepanê veke, Ya herî nû an guhertoyeke kevn ji lîsteya fermî ya Apple hilbijêre, paşê Daxe bitikîne."))
                    step("6", t("Download. Mirsa keeps the original file and adds it to the App Store tab.",
                                "نزّل. مرسى بيحتفظ بالملف الأصلي وبيضيفو لتبويب متجر أبل.",
                                "دایبگرە. Mirsa فایلە ڕەسەنەکە دەپارێزێت و دەیخاتە بەشی فرۆشگای ئەپڵ.",
                                "Daxe. Mirsa pelê resen diparêze û li Firoşgeha Apple zêde dike."))
                    Text(t("Limits: a downloaded file does not mean it will install or open. The app must belong to this Apple Account. Do not share these files; they are tied to your account.",
                           "حدود: نزول الملف ما يعني إنه رح يتثبت أو يفتح. التطبيق لازم يكون على حسابك. لا تشارك هالملفات لأنها مربوطة بحسابك.",
                           "سنوور: داگرتنی فایل مانای ئەوە نییە دامەزرێت یان بکرێتەوە. ئەپەکە دەبێت هی ئەم ئەکاونتە بێت. ئەم فایلانە بڵاو مەکەرەوە، بە ئەکاونتەکەتەوە بەستراون.",
                           "Sînor: daketina pelê nayê wê wateyê ku dê saz bibe an vebe. Sepan divê yê vî hesabî be. Van pelan parve neke, bi hesabê te ve girêdayî ne."))
                        .font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(MirsaSpacing.card).frame(maxWidth: .infinity, alignment: .leading).galleryGlass(radius: 24)
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(MirsaFont.badge).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(MirsaPalette.accent, in: Circle())
            Text(text).font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var verificationCard: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            Label(t("Step 2: Apple verification code", "الخطوة 2: رمز تحقق Apple", "هەنگاوی ٢: کۆدی پشتڕاستکردنەوەی Apple", "Gava 2: Koda piştrastkirinê ya Apple"),
                  systemImage: "number.circle.fill")
                .font(MirsaFont.cardTitle).foregroundStyle(.white)
            Text(t("Apple is asking for a 6-digit code before it finishes signing you in. Open the code on another device already signed in to this Apple Account, then type it below.",
                   "Apple عم تطلب رمز من 6 أرقام قبل ما تكمّل الدخول. افتح الرمز عجهاز تاني مسجّل فيه نفس حساب Apple واكتبو تحت.",
                   "Apple پێش تەواوکردنی چوونەژوورەوە کۆدێکی ٦ ژمارەیی دەخوازێت. کۆدەکە لە ئامێرێکی تر بکەرەوە کە بەم ئەکاونتی Apple ەوە چووەتە ژوورەوە و لە خوارەوە بینووسە.",
                   "Apple berî ku têketinê biqedîne koda 6 hejmarî dixwaze. Koda li cihazeke din a bi vî hesabê Apple ve têketî veke û li jêr binivîse."))
                .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(t("Code shown on your iPhone", "الرمز يلي وصل عآيفونك", "کۆدی سەر ئایفۆنەکەت", "Koda li iPhone ya te"), text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode).disabled(busy != nil)
                .focused($focus).fieldStyle()
                .onChange(of: code) { _, v in code = MirsaStoreCode.normalize(v) }
            Button { submitCode() } label: { Text(t("Verify code", "تحقق من الرمز", "کۆدەکە پشتڕاست بکەرەوە", "Kodê piştrast bike")).frame(maxWidth: .infinity) }
                .buttonStyle(.mirsaPrimary).disabled(MirsaStoreCode.valid(code) == nil || busy != nil)
            Text(t("Enter only the code. The original password stays in memory for up to five minutes, never on disk. Three verification tries, then start again.",
                   "اكتب الرمز بس. كلمة السر الأصلية بتضل بالذاكرة لخمس دقايق كحد أقصى، مو محفوظة عالجهاز. عندك 3 محاولات وبعدين ابدأ من جديد.",
                   "تەنها کۆدەکە بنووسە. وشەی نهێنی تەنها تا پێنج خولەک لە بیرگەدا دەمێنێتەوە. سێ هەوڵ، پاشان دووبارە دەست پێبکە.",
                   "Tenê kodê binivîse. Şîfre tenê heta pênc deqeyan di bîrê de dimîne. Sê hewil, paşê ji nû ve dest pê bike."))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
            Button(t("Cancel and start over", "إلغاء والبدء من جديد", "هەڵوەشاندنەوە و دەستپێکردنەوە", "Betal bike û ji nû ve dest pê bike")) { cancelVerification() }
                .buttonStyle(.mirsaSecondary).disabled(busy != nil)
        }
        .padding(MirsaSpacing.card).frame(maxWidth: .infinity, alignment: .leading).galleryGlass(radius: 24)
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            Text(t("Apple Account", "حساب Apple", "ئەکاونتی Apple", "Hesabê Apple"))
                .font(MirsaFont.cardTitle).foregroundStyle(.white)
            TextField(t("Apple Account email", "إيميل حساب Apple", "ئیمەیڵی ئەکاونتی Apple", "E-nameya hesabê Apple"), text: $email)
                .keyboardType(.emailAddress).textContentType(.username).textInputAutocapitalization(.never)
                .autocorrectionDisabled().focused($focus).fieldStyle()
            SecureField(t("Password", "كلمة السر", "وشەی نهێنی", "Şîfre"), text: $password)
                .textContentType(.password).focused($focus).fieldStyle().disabled(busy != nil)
            Text(t("Sent directly from your iPhone to Apple over HTTPS. Your password is not saved. Apple may ask for a code.", "بتنبعت مباشرة من آيفونك لـApple عبر HTTPS. كلمة السر ما بتنحفظ. ممكن Apple تطلب رمز تحقق.",
                   "بە HTTPS بۆ Apple دەنێردرێت بۆ چوونەژوورەوەی Apple. وشەی نهێنی هەڵناگیرێت. Apple ڕەنگە کۆد بخوازێت.", "Bi HTTPS ji Apple re ji bo têketina Apple tê şandin. Şîfre nayê tomarkirin. Dibe ku Apple kodê bixwaze."))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
            Button { signIn() } label: { Text(t("Sign in", "تسجيل الدخول", "چوونەژوورەوە", "Têkeve")).frame(maxWidth: .infinity) }
                .buttonStyle(.mirsaPrimary)
                .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || busy != nil)
        }
        .padding(MirsaSpacing.card).frame(maxWidth: .infinity, alignment: .leading).galleryGlass(radius: 24)
    }

    @ViewBuilder private func signedInCards(_ a: MirsaStoreAccount) -> some View {
        if !searchOnly {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name.isEmpty ? a.email : a.name).font(MirsaFont.cardTitle).foregroundStyle(.white)
                    Text("\(a.email) · \(a.country.uppercased())").font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                }
                Spacer()
                VStack(spacing: 4) {
                    Button { confirmSignOut = true } label: { Image(systemName: "rectangle.portrait.and.arrow.right") }
                        .buttonStyle(.mirsaSecondary)
                    Text(t("Sign out", "خروج", "دەرچوون", "Derkeve")).font(MirsaFont.badge).foregroundStyle(MirsaPalette.textTertiary)
                }
            }
            .padding(MirsaSpacing.card).galleryGlass(radius: 24)

        }

        if searchOnly && galleryMode == .discover {
            discoverContent
        } else {
        searchControls(a)

        if !searchOnly || !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if searched && results.isEmpty && busy == nil {
            StoreEmptyState(icon: "magnifyingglass",
                            title: t("No results in this country.", "ما في نتائج بهالدولة.", "لەم وڵاتەدا هیچ ئەنجامێک نییە.", "Li vî welatî encam tune."),
                            message: storeText("Try another name, a numeric App ID or an App Store link.",
                                               "جرّب اسم تاني، أو App ID رقمي، أو رابط App Store.",
                                               de: "Versuche einen anderen Namen, eine App-ID oder einen App-Store-Link.",
                                               ckb: "ناوێکی تر، App IDی ژمارەیی یان بەستەری App Store تاقی بکەرەوە.",
                                               kmr: "Navekî din, App ID ya hejmarî an girêdana App Store biceribîne."))
        }
        if busy != nil && results.isEmpty {
            ForEach(0..<3, id: \.self) { _ in StoreSkeletonCard(iconSize: 76) }
        }
        if !results.isEmpty {
            StoreGallerySectionTitle(title: t("Results", "النتائج", "ئەنجامەکان", "Encam"), trailing: "\(results.count)")
                .padding(.top, MirsaSpacing.xs)
        }
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(results) { app in resultRow(app) }
        }
        }
        }
    }

    /// Transparent gallery header: Discover shows today's date above its title, Search its title only.
    private var searchHeader: some View {
        StoreGalleryHeader(eyebrow: galleryMode == .discover ? StoreGallery.todayEyebrow() : nil,
                           title: galleryMode == .discover ? StoreGalleryText.discover : t("Search", "بحث", "گەڕان", "Lêgerîn")) {
            Button(action: onOpenAccount) { headerAvatar }
                .buttonStyle(.mirsaPress)
                .accessibilityLabel(t("Account", "الحساب", "ئەکاونت", "Hesab"))
                .accessibilityIdentifier("store-search-account")
        }
    }

    private var headerAvatar: some View {
        let initials = StoreIdentity.initials(name: account?.name ?? "", email: account?.email ?? "")
        return ZStack {
            Circle().fill(StoreGallery.ring)
            if account == nil {
                Image(systemName: "person.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            } else {
                Text(String(initials.prefix(1))).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }

    /// Search and Discover before sign-in: the existing hint plus a way to the Account page.
    private var signedOutCard: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 30, weight: .semibold)).foregroundStyle(StoreGallery.lilac)
            Text(t("Sign in from the Account tab to search the App Store.", "سجّل دخول من تبويب الحساب لتبحث بمتجر Apple.", "لە بەشی ئەکاونت بچۆ ژوورەوە.", "Ji beşa Hesabê têkeve."))
                .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(StoreGalleryText.signInToBrowse)
                .font(MirsaFont.secondary).foregroundStyle(StoreGallery.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onOpenAccount) {
                Text(AppStoreSectionTab.account.title).galleryPill(.light, height: 40)
            }
            .buttonStyle(.mirsaPress)
            .padding(.top, 4)
            .accessibilityIdentifier("store-signed-out-account")
        }
        .padding(MirsaSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .galleryGlass(radius: 26)
    }

    private func exitSearchToMain() {
        var nav = StoreSearchNavigation(term: term, resultCount: results.count, searched: searched, genreActive: discoveryGenre != nil, detailOpen: false)
        nav.returnToMain()
        term = nav.term; results = []; searched = nav.searched; discoveryGenre = nil; focus = false
    }

    private func searchControls(_ a: MirsaStoreAccount) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 19, weight: .semibold)).foregroundStyle(Color.white.opacity(0.55))
                TextField(t("App name, App ID or link", "اسم التطبيق أو App ID أو الرابط", "ناوی ئەپ، App ID یان بەستەر", "Navê sepanê, App ID an girêdan"), text: $term)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search).onSubmit { search() }.focused($focus)
                    .disabled(busy != nil).foregroundStyle(.white)
                    .accessibilityIdentifier("store-search-input")
                if !term.isEmpty {
                    Button { exitSearchToMain() } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(MirsaPalette.textTertiary)
                        .accessibilityLabel(t("Clear", "مسح", "سڕینەوە", "Paqij bike"))
                }
            }
            .font(.system(size: 17)).padding(.horizontal, 18).frame(minHeight: 56)
            .background(Capsule().fill(Color.white.opacity(0.10)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.7))
            .padding(.top, 4)

            HStack(spacing: 8) {
                Button { showCountries = true } label: {
                    HStack(spacing: 6) {
                        Text(StoreIdentity.flag(effectiveCountry))
                        Text(AppStoreCountry.label(effectiveCountry)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                    .padding(.horizontal, 13).frame(minHeight: 34)
                    .galleryGlassCapsule()
                }.buttonStyle(.plain).disabled(busy != nil)
                Label("iOS", systemImage: "iphone")
                    .padding(.horizontal, 13).frame(minHeight: 34)
                    .galleryGlassCapsule()
                    .accessibilityLabel(t("Platform: iOS", "المنصة iOS", "پلاتفۆرم iOS", "Platform iOS"))
                Spacer(minLength: 0)
            }.font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.75))

            if otherStore {
                Text(t("Downloads use your account storefront (\(AppStoreCountry.label(a.country))).",
                       "التنزيل من متجر حسابك (\(AppStoreCountry.label(a.country))).",
                       "داگرتن لە ستۆری ئەکاونتەکەتە.", "Daxistin ji stoya hesabê te ye."))
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning)
            }
            if term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recentSearches
                if searchOnly { discoveryContent }
            }

        }
        .environment(\.layoutDirection, (AppLanguageStore.shared.current == .arabic || AppLanguageStore.shared.current == .sorani) ? .rightToLeft : .leftToRight)
    }


    private var recentSearches: some View {
        let recents = StoreRecentSearches.read(recentSearchData)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(t("Recent searches", "عمليات البحث الأخيرة", "گەڕانەکانی ئەم دواییە", "Lêgerînên dawî"))
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.white.opacity(0.5))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if !recents.isEmpty {
                    Button(t("Clear", "مسح", "سڕینەوە", "Paqij bike")) { StoreHaptics.select(); recentSearchData = Data() }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(StoreGallery.lilac)
                        .accessibilityIdentifier("store-clear-recent")
                }
            }
            if recents.isEmpty {
                Text(t("Your searches will appear here.", "عمليات بحثك بتظهر هون.", "گەڕانەکانت لێرە دەردەکەون.", "Lêgerînên te li vir xuya dibin."))
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            } else {
                StoreFlowLayout(spacing: 8) {
                    ForEach(recents, id: \.self) { recent in
                        HStack(spacing: 0) {
                            Button { StoreHaptics.select(); term = recent; search() } label: {
                                Text(recent).lineLimit(1).truncationMode(.tail).frame(maxWidth: 170, alignment: .leading)
                                    .padding(.leading, 14).padding(.vertical, 9)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).disabled(busy != nil)
                            Button { recentSearchData = StoreRecentSearches.removing(recent, from: recentSearchData) } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(MirsaPalette.textTertiary)
                                    .frame(width: 30, height: 36).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(t("Remove search \(recent)", "حذف البحث \(recent)", "سڕینەوەی \(recent)", "Lêgerîna \(recent) jê bibe"))
                            .accessibilityIdentifier("store-remove-recent")
                        }
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
                    }
                }
            }
        }.padding(.top, 12)
    }

    /// Search face: Apple's chart for a chosen category, then the category tiles.
    private var discoveryContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if discoveryGenre != nil {
                VStack(alignment: .leading, spacing: 14) {
                    chartHeading
                    if let state = chartStateText { chartStateView(state) } else { rankedRow(chartApps, startRank: 1) }
                }
                .accessibilityIdentifier("store-top-free")
            }
            VStack(alignment: .leading, spacing: 14) {
                StoreGallerySectionTitle(title: t("Browse by category", "تصفح حسب الفئة", "بەپێی پۆل بگەڕێ", "Li gorî kategoriyê bigere"))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(StoreGenreTile.all) { tile in categoryTile(tile, height: 84) }
                }
            }
        }
        .padding(.top, 14)
    }

    /// Discover face: the featured hero (Apple's No. 1), the ranked row and the collections.
    private var discoverContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 26) {
                if let state = chartStateText {
                    chartStateView(state).frame(minHeight: 320)
                } else if let first = chartApps.first {
                    StoreGalleryHeroCard(tag: discoveryGenre == nil ? StoreGalleryText.topFreeTag : genreName(discoveryGenre),
                                         headline: first.name,
                                         subtitle: AppStoreCountry.label(effectiveCountry) + " · " + t("Top free · Apple", "الأكثر تنزيلاً مجاناً · Apple", "بێبەرامبەر · Apple", "Belaş · Apple"),
                                         artworkURL: first.artworkURL?.absoluteString ?? "",
                                         seed: String(first.id),
                                         actionTitle: StoreGalleryText.view) { openChartApp(first) }
                        .disabled(busy != nil)
                        .accessibilityIdentifier("store-chart-app-\(first.id)")
                    if chartApps.count > 1 {
                        VStack(alignment: .leading, spacing: 14) {
                            chartHeading
                            rankedRow(Array(chartApps.dropFirst()), startRank: 2)
                        }
                    }
                }
            }
            .accessibilityIdentifier("store-top-free")
            VStack(alignment: .leading, spacing: 14) {
                StoreGallerySectionTitle(title: StoreGalleryText.collections)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(StoreGenreTile.all) { tile in categoryTile(tile, height: 130).frame(width: 220) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.top, 8)
    }

    /// Title of the ranked row, with "All" to leave a category.
    private var chartHeading: some View {
        let reset: (() -> Void)? = discoveryGenre == nil ? nil : { discoveryGenre = nil }
        return VStack(alignment: .leading, spacing: 4) {
            StoreGallerySectionTitle(title: discoveryGenre == nil ? StoreGalleryText.mostDownloaded : genreName(discoveryGenre),
                                     trailing: discoveryGenre == nil ? nil : t("All", "الكل", "هەموو", "Hemû"),
                                     action: reset)
            Text(AppStoreCountry.label(effectiveCountry) + " · " + t("Top free · Apple", "الأكثر تنزيلاً مجاناً · Apple", "بێبەرامبەر · Apple", "Belaş · Apple"))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
        }
    }

    private enum ChartState { case loading, failed, empty }
    /// nil when Apple's chart is loaded and has apps.
    private var chartStateText: ChartState? {
        if chartLoading || chartLoadedKey != discoveryKey { return .loading }
        if chartFailed { return .failed }
        if chartApps.isEmpty { return .empty }
        return nil
    }

    @ViewBuilder private func chartStateView(_ state: ChartState) -> some View {
        switch state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text(t("Loading Apple's charts…", "عم نحمّل ترتيب Apple…", "بارکردنی لیستی Apple…", "Lîsteya Apple tê barkirin…"))
                    .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .galleryGlass(radius: 26)
        case .failed:
            VStack(spacing: 10) {
                Text(t("Apple's chart couldn't load.", "ما قدرنا نحمّل ترتيب Apple.", "لیستی Apple بار نەبوو.", "Lîsteya Apple nehat barkirin."))
                    .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                Button(t("Try again", "جرّب مرة تانية", "دووبارە", "Dîsa biceribîne")) { chartRetry += 1 }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(StoreGallery.lilac)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .galleryGlass(radius: 26)
        case .empty:
            Text(t("No chart available for this selection.", "ما في ترتيب متاح لهالاختيار.", "لیست بەردەست نییە.", "Ji bo vê hilbijartinê lîste tune."))
                .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 120)
                .galleryGlass(radius: 26)
        }
    }

    /// Horizontal ranked row of Apple's chart: icon, name, rank. Opens the app page.
    private func rankedRow(_ apps: [StoreChartApp], startRank: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    Button { openChartApp(app) } label: {
                        StoreGalleryRankedItem(rank: index + startRank, name: app.name,
                                               artworkURL: app.artworkURL?.absoluteString ?? "", seed: String(app.id))
                    }
                    .buttonStyle(.plain).disabled(busy != nil)
                    .accessibilityIdentifier("store-chart-app-\(app.id)")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func genreName(_ genre: Int?) -> String {
        switch genre {
        case 6014: return t("Games", "الألعاب", "یاری", "Lîstik")
        case 6007: return t("Productivity", "الإنتاجية", "بەرهەمهێنان", "Berhemdarî")
        case 6017: return t("Education", "التعليم", "پەروەردە", "Perwerde")
        case 6011: return t("Music", "الموسيقى", "مۆسیقا", "Muzîk")
        case 6016: return t("Entertainment", "الترفيه", "کات بەسەربردن", "Şahî")
        case 6013: return t("Health & Fitness", "الصحة واللياقة", "تەندروستی", "Tenduristî")
        default: return t("Trending apps", "أكثر التطبيقات رواجاً", "ئەپی بەناوبانگ", "Sepanên populer")
        }
    }

    /// Category (Search) or collection (Discover) tile. Same action as before: show Apple's chart for that genre.
    private func categoryTile(_ tile: StoreGenreTile, height: CGFloat) -> some View {
        Button {
            chartApps = []; chartLoading = true; discoveryGenre = tile.id
        } label: {
            StoreGalleryTile(title: genreName(tile.id), icon: tile.icon, colors: tile.colors, height: height,
                             selected: discoveryGenre == tile.id)
        }.buttonStyle(.mirsaPress).disabled(busy != nil || discoveryGenre == tile.id)
        .accessibilityIdentifier("store-genre-\(tile.id)")
        .accessibilityAddTraits(discoveryGenre == tile.id ? .isSelected : [])
    }

    @MainActor private func loadChart() async {
        let key = discoveryKey, country = effectiveCountry.lowercased(), genre = discoveryGenre
        chartApps = []; chartFailed = false; chartLoading = true; chartLoadedKey = key
        do {
            let apps = try await StoreDiscovery.load(country: country, genre: genre)
            try Task.checkCancellation()
            guard key == discoveryKey else { return }
            chartApps = apps; chartLoading = false
        } catch {
            guard !Task.isCancelled, key == discoveryKey else { return }
            chartApps = []; chartLoading = false; chartFailed = true
        }
    }

    private func openChartApp(_ chart: StoreChartApp) {
        guard busy == nil else { return }
        run(t("Loading app…", "عم نحمّل التطبيق…", "بارکردنی ئەپ…", "Sepan tê barkirin…")) {
            let country = effectiveCountry
            let found = try await client.search(term: String(chart.id), country: country, limit: 1)
            guard let app = found.first(where: { $0.id == chart.id }) else {
                throw StoreDiscovery.Failure.invalidFeed
            }
            var available: Set<Int64> = []
            if otherStore, let accountCountry = account?.country {
                available = try await client.availableInStore([app], country: accountCountry)
            }
            try Task.checkCancellation()
            guard country == effectiveCountry else { return }
            accountAvailable.formUnion(available)
            selected = app
        }
    }

    // MARK: result row, detail page, progress (UI only; same actions as before)

    private func artwork(_ app: MirsaStoreApp, size: CGFloat) -> some View {
        MirsaRemoteImage(url: URL(string: app.artworkURL), maxPixel: size * 3) {
            ZStack { MirsaPalette.cardRaised; Image(systemName: "app.dashed").font(.system(size: size * 0.35)).foregroundStyle(MirsaPalette.textTertiary) }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(MirsaPalette.stroke, lineWidth: 1))
    }

    private func priceBadge(_ app: MirsaStoreApp) -> some View {
        let free = app.price == 0
        return Text(free ? t("Free", "مجاني", "بێبەرامبەر", "Belaş")
                         : t("Paid: cannot be bought here", "مدفوع: ما بينشترى هون", "پارەدار: لێرە ناکڕدرێت", "Bi pere: li vir nayê kirîn"))
            .font(MirsaFont.badge).foregroundStyle(free ? MirsaPalette.success : MirsaPalette.warning)
    }

    /// Gallery result row: icon, name and details open the app page; Download sits on the same line.
    private func resultRow(_ app: MirsaStoreApp) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: MirsaSpacing.s) {
                Button { openDetail(app) } label: {
                    HStack(alignment: .center, spacing: MirsaSpacing.s) {
                        StoreArtwork(url: app.artworkURL, seed: app.bundleID, name: app.name, size: 60)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                            Text(app.bundleID).font(.caption2.monospaced()).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
                                .environment(\.layoutDirection, .leftToRight)
                            HStack(spacing: 6) {
                                Text("v" + app.version).foregroundStyle(Color.white.opacity(0.62)).lineLimit(1)
                                if ownership[app.id] == .owned {
                                    Text(storeText("Owned", "مملوك", de: "Im Besitz", ckb: "خاوەندارە", kmr: "Xwedî"))
                                        .foregroundStyle(MirsaPalette.success)
                                } else {
                                    priceBadge(app).lineLimit(1).minimumScaleFactor(0.8)
                                }
                            }
                            .font(MirsaFont.caption)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(t("Opens the app page", "بيفتح صفحة التطبيق", "پەڕەی ئەپەکە دەکاتەوە", "Rûpela sepanê vedike"))
                Button {
                    if inlineTransferAppID == app.id && busy != nil && !inlineIsGet { cancelInlineTransfer() }
                    else { StoreHaptics.get(); guardedStart(app, acquire: false) }
                } label: {
                    Group {
                        if inlineTransferAppID == app.id && busy != nil && !inlineIsGet {
                            storeInlineIndicator
                        } else {
                            Label(canDownload(app) ? t("Download", "تنزيل", "داگرتن", "Daxe") : t("Not in account store", "مو بمتجر حسابك", "لە ستۆرەکەت نییە", "Ne li stoya te ye"),
                          systemImage: canDownload(app) ? "icloud.and.arrow.down" : "nosign")
                        }
                    }
                        .galleryPill(.accent, height: 34)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.mirsaPress)
                .disabled((busy != nil && inlineTransferAppID != app.id) || !canDownload(app))
                .opacity((busy != nil && inlineTransferAppID != app.id) || !canDownload(app) ? 0.5 : 1)
            }
            // Footer: wishlist and versions, aligned under the action.
            HStack(spacing: MirsaSpacing.xs) {
                Spacer(minLength: 0)
                if (app.price ?? 0) > 0 { wishButton(app, size: 36) }
                Button { openDetail(app) } label: {
                    HStack(spacing: 4) {
                        Text(storeText("Versions", "النسخ", de: "Versionen", ckb: "وەشانەکان", kmr: "Guherto"))
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                            .flipsForRightToLeftLayoutDirection(true)
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(StoreGallery.lilac)
                    .padding(.horizontal, 12).frame(height: 32)
                    .galleryGlassCapsule()
                }
                .buttonStyle(.mirsaPress)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(StoreGallery.hairline).frame(height: 0.6) }
        .contentShape(Rectangle())
        .contextMenu { appMenu(app) }
        .accessibilityIdentifier("store-result-\(app.id)")
    }

    /// Long-press menu: copy the Bundle ID, share the public App Store page, open the app page.
    @ViewBuilder private func appMenu(_ app: MirsaStoreApp) -> some View {
        Button { StoreLinks.copy(app.bundleID) } label: {
            Label(storeText("Copy Bundle ID", "نسخ Bundle ID", de: "Bundle-ID kopieren", ckb: "کۆپی Bundle ID", kmr: "Bundle ID kopî bike"), systemImage: "doc.on.doc")
        }
        if let link = StoreLinks.appPage(id: app.id, country: effectiveCountry) {
            ShareLink(item: link) {
                Label(storeText("Share", "مشاركة", de: "Teilen", ckb: "هاوبەشکردن", kmr: "Parve bike"), systemImage: "square.and.arrow.up")
            }
        }
        if selected?.id != app.id {
            Button { openDetail(app) } label: {
                Label(storeText("Open app page", "افتح صفحة التطبيق", de: "App-Seite öffnen", ckb: "کردنەوەی پەڕەی ئەپ", kmr: "Rûpela sepanê veke"), systemImage: "app.badge")
            }
        }
    }

    /// Heart bound to the existing wishlist (StoreLibraryModel). Paid apps only, like its own button.
    private func wishButton(_ app: MirsaStoreApp, size: CGFloat = 44) -> some View {
        let item = library.wishlist.first { $0.appID == app.id }
        return Button {
            StoreHaptics.select()
            if let item { library.removeWish(id: item.id) }
            else {
                let country = effectiveCountry
                Task { do { try await library.addWish(app: app, country: country) } catch { notice = error.localizedDescription } }
            }
        } label: {
            Image(systemName: item == nil ? "heart" : "heart.fill")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(item == nil ? Color.white.opacity(0.9) : StoreGallery.badge)
                .symbolEffect(.bounce, value: item != nil)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.mirsaPress)
        .accessibilityLabel(StoreFeatureText.wishlist)
        .accessibilityAddTraits(item != nil ? .isSelected : [])
        .accessibilityIdentifier("store-wish-\(app.id)")
    }

    private func openDetail(_ app: MirsaStoreApp) {
        StoreHaptics.select()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) { selected = app }
    }

    /// Pull to refresh: re-run the current search, or reload Apple's chart. Same calls as the buttons.
    private func pullToRefresh() {
        guard busy == nil, selected == nil else { return }
        if term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chartRetry += 1 } else { search() }
    }

    private static func newestFirst(_ ids: [String]) -> [String] {
        ids.sorted { (UInt64($0) ?? 0) > (UInt64($1) ?? 0) }
    }

    @ViewBuilder private func detailView(_ app: MirsaStoreApp, account a: MirsaStoreAccount) -> some View {
        let key = app.bundleID
        let transferring = inlineTransferAppID == app.id && busy != nil
        // Top row: round glass back and share buttons over the tinted backdrop.
        HStack {
            Button { StoreHaptics.select(); withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { selected = nil } } label: {
                Image(systemName: "chevron.left")
                    .flipsForRightToLeftLayoutDirection(true)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.28)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7))
                    .contentShape(Circle())
            }
            .buttonStyle(.mirsaPress)
            .accessibilityLabel(t("Results", "النتائج", "ئەنجامەکان", "Encam"))
            .accessibilityIdentifier("store-detail-back")
            Spacer()
            if let link = StoreLinks.appPage(id: app.id, country: effectiveCountry) {
                ShareLink(item: link) { StoreGalleryRoundLabel(systemName: "square.and.arrow.up") }
                    .accessibilityLabel(storeText("Share", "مشاركة", de: "Teilen", ckb: "هاوبەشکردن", kmr: "Parve bike"))
                    .accessibilityIdentifier("store-detail-share")
            }
        }
        .padding(.top, MirsaSpacing.s)

        // Hero: big centred icon, name, Bundle ID and price, then the main actions.
        VStack(spacing: MirsaSpacing.s) {
            StoreArtwork(url: app.artworkURL, seed: app.bundleID, name: app.name, size: 116)
                .padding(.bottom, 4)
            Text(app.name).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.75)
            HStack(spacing: 6) {
                Text(app.bundleID).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                    .environment(\.layoutDirection, .leftToRight)
                Text("·")
                priceBadge(app)
            }
            .font(MirsaFont.secondary).foregroundStyle(Color.white.opacity(0.7))
            .contextMenu { appMenu(app) }

            // Main actions on one line: wishlist (paid apps), Download, and Get beside it only when it applies.
            HStack(spacing: MirsaSpacing.s) {
                if (app.price ?? 0) > 0 { wishButton(app, size: 52) }
                Button {
                    if inlineTransferAppID == app.id && busy != nil && !inlineIsGet { cancelInlineTransfer() }
                    else { StoreHaptics.get(); guardedStart(app, acquire: false) }
                } label: {
                    Group {
                        if transferring && !inlineIsGet {
                            storeInlineIndicator
                        } else {
                            HStack(spacing: 8) { Image(systemName: "arrow.down.to.line"); Text(t("Download", "تنزيل", "داگرتن", "Daxe")) }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .galleryPill(transferring && !inlineIsGet ? .dark : .light, height: 52)
                }
                .buttonStyle(.mirsaPress).disabled((busy != nil && inlineTransferAppID != app.id) || !canDownload(app))
                .opacity((busy != nil && inlineTransferAppID != app.id) || !canDownload(app) ? 0.5 : 1)
                if app.price == 0 && ownership[app.id] != .owned {
                    Button {
                        if inlineTransferAppID == app.id && busy != nil && inlineIsGet { cancelInlineTransfer() }
                        else { StoreHaptics.get(); guardedStart(app, acquire: true) }
                    } label: {
                        Group {
                            if inlineTransferAppID == app.id && busy != nil && inlineIsGet { storeInlineIndicator }
                            else { Text(t("Get", "احصل عليه", "وەریبگرە", "Bigire")) }
                        }
                        .galleryPill(.dark, height: 52)
                    }
                    .buttonStyle(.mirsaPress)
                    .disabled(app.price != 0 || (busy != nil && !(inlineTransferAppID == app.id && inlineIsGet)) || (otherStore && !accountAvailable.contains(app.id)))
                    .accessibilityIdentifier("store-detail-get")
                }
            }
            .padding(.top, 6)
            if otherStore && !accountAvailable.contains(app.id) {
                Text(t("Not available in your account storefront. Download is disabled.", "مو متاح بمتجر حسابك، التنزيل موقف.", "لە ستۆری ئەکاونتەکەت بەردەست نییە.", "Li stoya hesabê te ne berdest e.")).font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning)
                    .multilineTextAlignment(.center)
            }
            Text(t("Version: ", "النسخة: ", "وەشان: ", "Guherto: ") + chosenLabel(app))
                .font(MirsaFont.caption).foregroundStyle(Color.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))

        // Stats strip, screenshots, what's new and version pins (same public catalogue lookup as before).
        StoreGalleryCatalogSection(app: app, country: effectiveCountry, externalVersionID: effectiveVersion(app),
                                   versionLabel: chosenLabel(app))

        VStack(alignment: .leading, spacing: MirsaSpacing.xs) {
            Text(t("Needs this account to own the app. Saved unchanged in the App Store tab.",
                   "لازم الحساب يملك التطبيق. بينحفظ متل ما هو بتبويب متجر أبل.",
                   "پێویستە ئەکاونتەکە خاوەنی ئەپەکە بێت. وەک خۆی لە بەشی فرۆشگای ئەپڵ هەڵدەگیرێت.",
                   "Divê hesab xwediyê sepanê be. Wekî xwe li Firoşgeha Apple tê tomarkirin."))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
            if ownership[app.id] == .owned {
                Text(t("Owned by this account. Tap Download separately for the selected version.", "هالحساب بيملك التطبيق. دوس تنزيل لحاله للنسخة المختارة.", "ئەم ئەکاونتە خاوەنی ئەپەکەیە. داگرتن جیا بکە.", "Ev hesab xwedî ye. Ji bo guhertoya hilbijartî Daxe bitikîne."))
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.success)
            }
            if app.price == 0 && ownership[app.id] != .owned {
            Text(t("Only if this account never got the app. Adds it to your Apple Account; costs nothing.",
                   "بس إذا حسابك ما حصل عالتطبيق قبل. بيضيفو لحساب Apple تبعك وبلا مصاري.",
                   "تەنها ئەگەر ئەم ئەکاونتە پێشتر ئەپەکەی نەهێنابێت. دەیخاتە ئەکاونتی Apple ت بێ پارە.",
                   "Tenê heke ev hesab berê sepan negirtibe. Li hesabê Apple zêde dike, bêpere."))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
            }
        }
        .padding(MirsaSpacing.card).frame(maxWidth: .infinity, alignment: .leading).galleryGlass(radius: 20)

        StoreGallerySectionTitle(title: t("Older versions", "نسخ أقدم", "وەشانە کۆنەکان", "Guhertoyên kevn"),
                                 trailing: versions[key].map { "\($0.count)" })
            .padding(.top, MirsaSpacing.xs)
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            versionRow(key: key, id: nil, title: t("Latest", "الأحدث", "نوێترین", "Ya herî nû"), subtitle: app.version)
            if let list = versions[key] {
                if list.isEmpty {
                    Text(t("Apple returned no versions.", "Apple ما رجّعت نسخ.", "Apple هیچ وەشانێکی نەگەڕاندەوە.", "Apple guhertoyek neda."))
                        .font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning)
                } else {
                    let sorted = Self.newestFirst(list)
                    let visible = Array(sorted.prefix(metadataLimit[key] ?? 20))
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 0).task(id: visible.count) { requestMetadata(app, ids: visible + Array(sorted.dropFirst(visible.count).prefix(20)), reset: true) }
                        ForEach(visible, id: \.self) { id in
                            Rectangle().fill(StoreGallery.hairline).frame(height: 0.6)
                            versionRow(key: key, id: id, title: versionName(app, id), subtitle: "ID \(id)")
                        }
                    }
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7))
                    if visible.count < sorted.count {
                        Button(t("Show 20 more versions", "عرض 20 نسخة كمان", "٢٠ وەشانی تریش نیشان بدە", "20 guhertoyên din nîşan bide")) {
                            let next = min(sorted.count, visible.count + 20)
                            metadataLimit[key] = next
                            // Ask for every visible version still without a name, not only the new ones,
                            // so a batch that was interrupted is picked up again.
                            requestMetadata(app, ids: Array(sorted.prefix(next)))
                        }.buttonStyle(.mirsaSecondary)
                    }
                    if visible.contains(where: { metadata[key]?[$0]?.status == "unavailable" }) {
                        Button(t("Retry version names", "إعادة محاولة أسماء النسخ", "دووبارە هەوڵدانەوەی ناوی وەشانەکان", "Navên guhertoyan dîsa biceribîne")) {
                            for id in visible where metadata[key]?[id]?.status == "unavailable" { metadata[key]?[id] = nil }
                            requestMetadata(app, ids: visible, reset: true)
                        }
                        .buttonStyle(.mirsaSecondary).disabled(busy != nil)
                    }
                    Text(t("Version names come from Apple's official metadata. While loading or unavailable, External ID is shown. Downloads do not wait for names.",
                           "أسماء النسخ من بيانات Apple الرسمية. إذا الاسم عم يتحمّل أو مو متاح بيظهر رقم النسخة الخارجي. التنزيل ما بينتظر الاسم.",
                           "ناوی وەشان لە زانیارییە فەرمییەکانی Apple دێت. لە بارکردن یان نەبووندا ناسنامەی دەرەکی نیشان دەدرێت. داگرتن چاوەڕێی ناو ناکات.",
                           "Navên guhertoyan ji metadata fermî ya Apple ne. Dema barkirinê an ne berdest be ID ya derveyî tê nîşandan. Daxistin li navan nasekine."))
                        .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                }
            } else {
                Button { loadVersions(app) } label: { Text(t("Older versions", "نسخ أقدم", "وەشانە کۆنەکان", "Guhertoyên kevn")).frame(maxWidth: .infinity) }
                    .buttonStyle(.mirsaSecondary).disabled(busy != nil || ownership[app.id] == .licenseRequired)
            }

        }
        .padding(MirsaSpacing.card).frame(maxWidth: .infinity, alignment: .leading).galleryGlass(radius: 22)
        Text(a.email).font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary).lineLimit(1).truncationMode(.middle)
    }

    /// Full-bleed tint from the app's artwork behind the top of its page, fading into the background.
    private func detailBackdrop(_ app: MirsaStoreApp) -> some View {
        let tint = tints.tint(app.artworkURL, seed: app.bundleID)
        return LinearGradient(stops: [
            .init(color: tint.opacity(0.95), location: 0),
            .init(color: tint.opacity(0.45), location: 0.45),
            .init(color: tint.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(height: 640)
        .offset(y: -180)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func versionRow(key: String, id: String?, title: String, subtitle: String) -> some View {
        let on = chosen[key] == id
        return Button {
            chosen[key] = id
        } label: {
            HStack(spacing: MirsaSpacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(MirsaFont.body).foregroundStyle(.white).lineLimit(1)
                    Text(subtitle).font(.caption2.monospaced()).foregroundStyle(MirsaPalette.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if on { Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(StoreLuxe.identity) }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background { if on { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StoreLuxe.accent.opacity(0.16)) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy != nil)
    }

    private func versionName(_ app: MirsaStoreApp, _ id: String) -> String {
        if let item = metadata[app.bundleID]?[id], item.status == "ready", let version = item.version { return version }
        if metadata[app.bundleID]?[id]?.status == "unavailable" {
            return t("Name unavailable", "الاسم مو متاح", "ناو بەردەست نییە", "Nav ne berdest e")
        }
        return t("Loading name…", "عم يتحمّل الاسم…", "ناو بار دەکرێت…", "Nav tê barkirin…")
    }

    /// Exact external version: explicit choice, else persisted pin (nil means latest).
    private func effectiveVersion(_ app: MirsaStoreApp) -> String? {
        chosen[app.bundleID] ?? StoreLibraryModel.shared.pin(bundleID: app.bundleID, country: effectiveCountry)?.externalVersionID
    }
    private func chosenLabel(_ app: MirsaStoreApp) -> String {
        guard let id = effectiveVersion(app) else { return t("Latest", "الأحدث", "نوێترین", "Ya herî nû") + " · " + app.version }
        if let item = metadata[app.bundleID]?[id], item.status == "ready", let version = item.version { return "\(version) · ID \(id)" }
        return "ID \(id)"
    }

    /// The app this screen is downloading or getting right now (display only).
    private var liveTransferApp: MirsaStoreApp? {
        guard busy != nil else { return nil }
        if let id = inlineTransferAppID {
            if selected?.id == id { return selected }
            return results.first { $0.id == id }
        }
        return selected
    }

    /// Changes whenever the live transfer shown on the Downloads page should update.
    private var liveTransferKey: String {
        let progress = transfer.map { "\($0.phase.rawValue)|\($0.received)|\($0.expected)" } ?? "-"
        return "\(busy ?? "")|\(progress)|\(inlineTransferAppID ?? 0)|\(selected?.id ?? 0)"
    }

    /// Mirrors the running transfer for the Downloads page (display only, the tab's own screen only).
    private func publishLiveTransfer() {
        guard searchOnly, openAppID == nil else { return }
        guard busy != nil, let transfer else { StoreGalleryLiveTransfer.shared.clear(); return }
        let app = liveTransferApp.map { StoreGalleryLiveTransfer.App(name: $0.name, artworkURL: $0.artworkURL, seed: $0.bundleID) }
        StoreGalleryLiveTransfer.shared.update(app: app, progress: transfer, phaseText: transferPhase(transfer.phase))
    }

    /// Running task: gradient ring around the app icon, phase, bytes and speed, Pause/Resume and Cancel.
    private var busyCard: some View {
        let fraction = transfer.flatMap { $0.fraction }
        return HStack(alignment: .center, spacing: MirsaSpacing.m) {
            StoreGalleryProgressRing(fraction: fraction, diameter: 88, lineWidth: 7) {
                if let app = liveTransferApp {
                    StoreArtwork(url: app.artworkURL, seed: app.bundleID, name: app.name, size: 50)
                } else {
                    Image(systemName: "arrow.down").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(busy ?? "").font(MirsaFont.secondary.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                    Spacer(minLength: 0)
                    if let since = busySince {
                        TimelineView(.periodic(from: since, by: 1)) { ctx in
                            let s = max(0, Int(ctx.date.timeIntervalSince(since)))
                            Text(String(format: "%d:%02d", s / 60, s % 60)).font(MirsaFont.caption.monospacedDigit()).foregroundStyle(MirsaPalette.textTertiary)
                        }
                    }
                }
                if let transfer {
                    Text(transferPhase(transfer.phase) + (fraction.map { " · \(Int($0 * 100))%" } ?? ""))
                        .font(MirsaFont.caption.monospacedDigit()).foregroundStyle(StoreGallery.secondary)
                    if transfer.received > 0 {
                        let received = ByteCountFormatter.string(fromByteCount: transfer.received, countStyle: .file)
                        let speed = ByteCountFormatter.string(fromByteCount: Int64(min(transfer.speed, Double(Int64.max / 2))), countStyle: .file) + "/s"
                        let total = transfer.expected > 0
                            ? " / " + ByteCountFormatter.string(fromByteCount: transfer.expected, countStyle: .file) : ""
                        Text(received + total + " · " + speed)
                            .font(MirsaFont.caption.monospacedDigit()).foregroundStyle(StoreGallery.sky)
                    }
                }
                HStack(spacing: MirsaSpacing.xs) {
                    StorePauseButton()
                    Button(t("Cancel", "إلغاء", "هەڵوەشاندنەوە", "Betal")) { StoreTransferControl.shared.discardCurrent(); work?.cancel() }
                        .buttonStyle(.mirsaSecondary)
                }
                .padding(.top, 2)
                StorePauseStatus()
            }
        }
        .padding(MirsaSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [StoreGallery.violet.opacity(0.30), Color(red: 0.08, green: 0.06, blue: 0.16).opacity(0.6)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .galleryGlass(radius: 26)
        .accessibilityElement(children: .combine)
    }

    private func transferPhase(_ phase: StoreDownloadProgress.Phase) -> String {
        switch phase {
        case .preparing: return t("Preparing licence and download link…", "عم جهّز الترخيص ورابط التنزيل…", "ئامادەکردنی مۆڵەت و بەستەر…", "Lîsans û girêdan amade dibin…")
        case .downloading: return t("Downloading…", "عم نزّل…", "داگرتن…", "Daxistin…")
        case .packaging: return t("Adding original Apple licence…", "عم ضيف ترخيص Apple الأصلي…", "زیادکردنی مۆڵەتی ئەسڵی Apple…", "Lîsansa resen a Apple tê zêdekirin…")
        case .validating: return t("Checking IPA…", "عم تحقق من ملف IPA…", "پشکنینی IPA…", "IPA tê kontrolkirin…")
        case .saving: return t("Saving to your library…", "عم احفظ بالمكتبة…", "هەڵگرتن لە کتێبخانە…", "Li pirtûkxaneyê tê tomarkirin…")
        case .saved: return t("Saved", "انحفظ", "هەڵگیرا", "Hat tomarkirin")
        case .failed: return t("Download stopped", "وقف التنزيل", "داگرتن وەستا", "Daxistin rawestiya")
        }
    }

    // MARK: actions

    private func run(_ message: String, _ op: @escaping () async throws -> Void) {
        guard busy == nil else { return }
        focus = false
        busy = message
        let generation = operationGeneration
        let attempt = UUID()
        progressAttempt = attempt
        transfer = nil
        let report: @Sendable (StoreDownloadProgress.Event) -> Void = { event in
            Task { @MainActor in
                guard progressAttempt == attempt, generation == operationGeneration else { return }
                if transfer == nil { transfer = StoreDownloadProgress() }
                transfer?.apply(event)
            }
        }
        work = Task {
            defer { password = ""; code = "" }
            do { try await StoreDownloadProgress.$report.withValue(report) { try await op() } }
            catch is CancellationError {}
            catch { if generation == operationGeneration { notice = describe(error) } }
            if generation == operationGeneration, progressAttempt == attempt {
                progressAttempt = nil; transfer = nil; inlineTransferAppID = nil; inlineIsGet = false; busy = nil; work = nil
            }
        }
    }

    private func signIn() {
        let mail = email.trimmingCharacters(in: .whitespaces)
        let secret = password
        password = ""
        run(t("Signing in…", "عم نسجّل الدخول…", "چوونەژوورەوە…", "Têketin…")) {
            switch try await client.signIn(email: mail, password: secret) {
            case .signedIn(let a): account = a; email = ""
            case .verificationRequired: needsCode = true
            }
        }
    }

    private func submitCode() {
        guard busy == nil else { return }
        let c = code
        password = ""; code = ""
        run(t("Verifying…", "عم نتحقق…", "پشتڕاستکردنەوە…", "Piştrastkirin…")) {
            switch try await client.verify(code: c) {
            case .signedIn(let a): account = a; needsCode = false; email = ""
            case .verificationRequired: notice = t("The code was not accepted. Try again.", "الرمز ما انقبل. جرّب مرة ثانية.", "کۆدەکە وەرنەگیرا. دووبارە هەوڵ بدەرەوە.", "Kod nehat pejirandin. Dîsa biceribîne.")
            }
        }
    }

    private func cancelVerification() {
        password = ""; code = ""; needsCode = false
        Task { try? await client.signOut() }
    }

    private func signOut() {
        operationGeneration = UUID()
        cancelMetadata()
        metadata = [:]
        work?.cancel()
        password = ""; code = ""; email = ""; needsCode = false
        Task {
            do {
                try await client.signOut()
                account = nil; results = []; versions = [:]; chosen = [:]; versionListAttempted = []; searched = false
            } catch { notice = describe(error); account = try? await client.currentAccount() }
        }
    }

    private func selectCountry(_ country: String?) {
        guard busy == nil else { return }
        searchCountry = country; showCountries = false
        results = []; selected = nil; searched = false; accountAvailable = []
        // Changing the catalogue filter does not submit a search.
    }

    private func search() {
        guard busy == nil else { return }
        let submittedTerm = term
        let generation = operationGeneration
        let q: String
        var urlAppID: Int64?
        do { let parsed = try StoreSearchQuery.parse(term); q = parsed.term; if case .appID(let s) = parsed, term.contains("/") { urlAppID = Int64(s) } }
        catch { notice = t("Enter an app name, numeric App ID or an Apple App Store link.", "اكتب اسم تطبيق أو App ID رقمي أو رابط من متجر Apple.", "ناو یان ناسنامە یان بەستەری Apple بنووسە.", "Nav, App ID an girêdana Apple binivîse."); return }
        run(t("Searching…", "عم نبحث…", "گەڕان…", "Lêgerîn…")) {
            let country = effectiveCountry
            let found = try await client.search(term: q, country: country, limit: 25)
            var available: Set<Int64> = []
            if otherStore, let accountCountry = account?.country {
                available = try await client.availableInStore(found, country: accountCountry)
            }
            try Task.checkCancellation()
            guard generation == operationGeneration, country == effectiveCountry, submittedTerm == term else { return }
            results = found; accountAvailable = available; searched = true
            if let wanted = urlAppID ?? openAppID, let hit = found.first(where: { $0.id == wanted }) { selected = hit }
            recentSearchData = StoreRecentSearches.adding(q, to: recentSearchData)
        }
    }

    /// Checks the exact chosen version's minimum iOS first; warns but never blocks.
    private func guardedStart(_ app: MirsaStoreApp, acquire isAcquire: Bool) {
        guard busy == nil else { return }
        let version = effectiveVersion(app)
        let country = effectiveCountry
        // Captured before the first await: an account switch must not start a download for the new account.
        let expectedAccount = account
        let generation = operationGeneration
        preflightTask?.cancel()
        preflightTask = Task {
            let item = try? await StoreCatalog.fetch(appID: app.id, bundleID: nil, country: country)
            guard !Task.isCancelled, generation == operationGeneration, account == expectedAccount,
                  country == effectiveCountry else { return }
            if StoreCatalogDetailCard.osWarning(item, externalVersionID: version) { pendingOS = (app, isAcquire) }
            else if isAcquire { acquire(app) } else { download(app) }
        }
    }

    private func acquire(_ app: MirsaStoreApp) {
        guard app.price == 0, (!otherStore || accountAvailable.contains(app.id)) else { return }
        let version = effectiveVersion(app)
        inlineTransferAppID = app.id; inlineIsGet = true
        run(t("Getting free license and downloading…", "عم نجيب الترخيص المجاني وننزّل…", "مۆڵەتی بێبەرامبەر وەردەگیرێت و دادەگیرێت…", "Lîsansa belaş tê girtin û tê daxistin…")) {
            try await getOperation(app, version: version)
        }
    }

    /// Get = free licence + download in one serial operation. Also resumed after Apple asks
    /// to confirm the account password for a first-time acquisition.
    private func getOperation(_ app: MirsaStoreApp, version: String?) async throws {
        inlineTransferAppID = app.id; inlineIsGet = true
        transfer = StoreDownloadProgress()
        let generation = operationGeneration
        let selectedID = try await client.selectedAccountID()
        try Task.checkCancellation()
        guard generation == operationGeneration else { throw CancellationError() }
        let url: URL
        do { url = try await client.acquireFreeAppAndDownload(app, externalVersionID: version, expectedAccountID: selectedID) }
        catch is MirsaStorePurchaseAuthorization {
            // Session kept: ask only for the password, then resume this same Get.
            authorizeApp = app
            throw CancellationError()
        }
        ownership[app.id] = .owned
        defer { MirsaManagedTmp.end(url.deletingLastPathComponent()) }
        try Task.checkCancellation()
        guard generation == operationGeneration else { throw CancellationError() }
        transfer?.apply(.init(phase: .saving))
        try await onDownloaded(url)
        try Task.checkCancellation()
        transfer?.apply(.init(phase: .saved))
        notice = t("Saved to your App Store tab, unchanged.", "انحفظ بتبويب متجر أبل متل ما هو.",
                   "وەک خۆی لە بەشی فرۆشگای ئەپڵ هەڵگیرا.", "Wekî xwe li Firoşgeha Apple hat tomarkirin.")
    }

    /// Re-authenticates the SAME selected account (fresh password token, same device GUID and
    /// account slot) and resumes the Get. A wrong password leaves the saved session untouched.
    private func confirmPurchase(_ app: MirsaStoreApp) {
        authorizeApp = nil
        let secret = password
        password = ""
        guard let mail = account?.email, !secret.isEmpty else { return }
        run(storeText("Confirming with Apple…", "عم نتأكد مع أبل…", de: "Bestätigung bei Apple…", ckb: "پشتڕاستکردنەوە لەگەڵ Apple…", kmr: "Bi Apple re tê piştrastkirin…")) {
            switch try await client.signIn(email: mail, password: secret) {
            case .signedIn(let a):
                if account != a { account = a }
                try await getOperation(app, version: effectiveVersion(app))
            case .verificationRequired:
                authorizeCodeApp = app
            }
        }
    }

    private func confirmPurchaseCode(_ app: MirsaStoreApp) {
        authorizeCodeApp = nil
        let c = code
        code = ""
        run(t("Verifying…", "عم نتحقق…", "پشتڕاستکردنەوە…", "Piştrastkirin…")) {
            switch try await client.verify(code: c) {
            case .signedIn(let a):
                if account != a { account = a }
                try await getOperation(app, version: effectiveVersion(app))
            case .verificationRequired:
                notice = t("The code was not accepted. Try again.", "الرمز ما انقبل. جرّب مرة ثانية.", "کۆدەکە وەرنەگیرا. دووبارە هەوڵ بدەرەوە.", "Kod nehat pejirandin. Dîsa biceribîne.")
            }
        }
    }

    private func loadVersions(_ app: MirsaStoreApp) {
        guard ownership[app.id] != .licenseRequired else { selected = app; return }
        run(t("Asking Apple for versions…", "عم نسأل Apple عن النسخ…", "پرسیار لە Apple دەکرێت…", "Ji Apple guhertoyan dipirsin…")) {
            let ids: [String]
            do { ids = try await client.availableVersions(app) }
            catch { recordOwnershipFailure(error, app: app); throw error }
            ownership[app.id] = .owned
            versions[app.bundleID] = ids
            metadataLimit[app.bundleID] = 20
            requestMetadata(app, ids: Array(Self.newestFirst(ids).prefix(20)), reset: true)
        }
    }

    private func download(_ app: MirsaStoreApp) {
        guard canDownload(app) else { selected = app; return }
        let version = effectiveVersion(app)
        inlineTransferAppID = app.id; inlineIsGet = false
        run(t("Preparing and downloading…", "عم جهّز ونزّل…", "لە Apple دادەگیرێت…", "Ji Apple tê daxistin…")) {
            transfer = StoreDownloadProgress()
            let generation = operationGeneration
            let selectedID = try await client.selectedAccountID()
            try Task.checkCancellation()
            guard generation == operationGeneration else { throw CancellationError() }
            let url: URL
            do { url = try await client.downloadOwnedApp(app, externalVersionID: version, expectedAccountID: selectedID) }
            catch {
                if await offerRecovery(error, app: app, version: version) { return }
                recordOwnershipFailure(error, app: app); throw error
            }
            ownership[app.id] = .owned
            defer { MirsaManagedTmp.end(url.deletingLastPathComponent()) }
            try Task.checkCancellation()
            guard generation == operationGeneration else { throw CancellationError() }
            transfer?.apply(.init(phase: .saving))
            try await onDownloaded(url)
            try Task.checkCancellation()
            transfer?.apply(.init(phase: .saved))
            notice = t("Saved to your App Store tab, unchanged.", "انحفظ بتبويب متجر أبل متل ما هو.",
                       "وەک خۆی لە بەشی فرۆشگای ئەپڵ هەڵگیرا.", "Wekî xwe li Firoşgeha Apple hat tomarkirin.")
        }
    }

    private func offerRecovery(_ error: Error, app: MirsaStoreApp, version: String?) async -> Bool {
        guard let diagnostic = error as? StoreProductDiagnostic, diagnostic.httpStatus == 403, !diagnostic.requiresReauthentication else { return false }
        let revision = session.sessionRevision
        guard let fresh = try? await client.freeAppForRecovery(app),
              StoreFreeLicenseRecovery.canOffer(status: diagnostic.httpStatus, price: fresh.price),
              revision == session.sessionRevision, !Task.isCancelled else { return false }
        recovery = StoreFreeLicenseRecovery(app: fresh, externalVersionID: version, revision: revision)
        return true
    }

    private var storeInlineIndicator: some View {
        let downloading = transfer?.phase == .downloading
        let known = downloading && (transfer?.expected ?? 0) > 0
        let fraction: Double? = known ? Double(transfer?.received ?? 0) / Double(transfer?.expected ?? 1) : nil
        return SourceDownloadIndicator(fraction: fraction, phase: downloading ? .downloading : .preparing, cancellable: downloading)
    }

    /// Only the network transfer can be cancelled; packaging, validating and saving finish on their own.
    private func cancelInlineTransfer() {
        guard transfer?.phase == .downloading else { return }
        StoreTransferControl.shared.discardCurrent(); work?.cancel()
    }

    private func recoverDownload(_ pending: StoreFreeLicenseRecovery) {
        recovery = nil
        inlineTransferAppID = pending.app.id; inlineIsGet = true
        guard pending.revision == session.sessionRevision else { return }
        run(t("Refreshing free licence and retrying…", "عم نحدّث الترخيص المجاني ونعيد المحاولة…", "نوێکردنەوەی مۆڵەت…", "Lîsans nû dibe…")) {
            transfer = StoreDownloadProgress()
            let url = try await StoreFreeLicenseRecovery.retryOnce(consent: true, acquire: {
                guard pending.revision == session.sessionRevision else { throw CancellationError() }
                do { try await client.acquireFreeApp(pending.app) }
                catch is MirsaStorePurchaseAuthorization {
                    // Apple wants the password for this licence: ask, keep the session, resume as Get.
                    authorizeApp = pending.app
                    throw CancellationError()
                }
            }, download: {
                guard pending.revision == session.sessionRevision else { throw CancellationError() }
                return try await client.downloadOwnedApp(pending.app, externalVersionID: pending.externalVersionID)
            })
            defer { MirsaManagedTmp.end(url.deletingLastPathComponent()) }
            guard pending.revision == session.sessionRevision else { throw CancellationError() }
            try Task.checkCancellation()
            transfer?.apply(.init(phase: .saving))
            try await onDownloaded(url)
            try Task.checkCancellation()
            transfer?.apply(.init(phase: .saved))
            ownership[pending.app.id] = .owned
            notice = t("Saved to your App Store tab, unchanged.", "انحفظ بتبويب متجر أبل متل ما هو.", "هەڵگیرا.", "Hat tomarkirin.")
            // Failure goes directly to run's diagnostics. Never offer/acquire in a loop.
        }
    }

    private func cancelMetadata() {
        for task in metadataTasks.values { task.cancel() }
        metadataTasks = [:]
    }

    private func versionLabel(_ app: MirsaStoreApp, _ id: String) -> String {
        if let item = metadata[app.bundleID]?[id], item.status == "ready", let version = item.version {
            return "\(version) · ID \(id)"
        }
        if metadata[app.bundleID]?[id]?.status == "unavailable" {
            return t("External ID \(id) · name unavailable", "رقم خارجي \(id) · الاسم مو متاح", "ناسنامەی دەرەکی \(id) · ناو بەردەست نییە", "ID ya derveyî \(id) · nav ne berdest e")
        }
        return t("External ID \(id) · loading name", "رقم خارجي \(id) · عم يتحمّل الاسم", "ناسنامەی دەرەکی \(id) · ناو بار دەکرێت", "ID ya derveyî \(id) · nav tê barkirin")
    }

    private func requestMetadata(_ app: MirsaStoreApp, ids: [String], reset: Bool = false) {
        let key = app.bundleID
        // A fresh visibility/reopen/manual cycle gives exhausted rows a new bounded attempt budget.
        // Internal retries pass reset:false, so there is no retry loop.
        if reset { StoreMetadataRetryPolicy.resetExhausted(key: key, ids: ids, attempts: &metadataAttempts, unavailable: { metadata[key]?[$0]?.status == "unavailable" }, clear: { metadata[key]?[$0] = nil }) }
        // Disk cache first: names never change for an external version ID.
        for id in ids where metadata[key]?[id] == nil {
            if let v = StoreVersionNameCache.get(key, id) { metadata[key, default: [:]][id] = .init(externalVersionID: id, status: "ready", version: v) }
        }
        // Visible rows first, then the next 20 rows prefetched quietly.
        let pending = Array(ids.filter { metadata[key]?[$0]?.status != "ready" && metadata[key]?[$0]?.status != "unavailable" })
        guard !pending.isEmpty else { return }
        metadataTasks[key]?.cancel()
        let generation = operationGeneration
        metadataTasks[key] = Task {
            // Apple answers through one serialized session, so small chunks publish each name as soon as it arrives.
            for start in stride(from: 0, to: pending.count, by: 2) {
                let chunk = Array(pending[start..<min(start + 2, pending.count)])
                guard !Task.isCancelled, generation == operationGeneration else { return }
                do {
                    let entries = try await withThrowingTaskGroup(of: [MirsaStoreServerClient.VersionMetadata].self) { group in
                        group.addTask { try await client.versionMetadata(app, externalVersionIDs: chunk) }
                        group.addTask { try await Task.sleep(nanoseconds: 90_000_000_000); throw MirsaStoreError.serviceUnavailable }
                        defer { group.cancelAll() }
                        return try await group.next() ?? []
                    }
                    guard !Task.isCancelled, generation == operationGeneration else { return }
                    for id in chunk {
                        let item = entries.first { $0.externalVersionID == id }
                        if item?.status == "ready", let v = item?.version { StoreVersionNameCache.set(key, id, v) }
                        metadata[key, default: [:]][id] = item?.status == "ready" ? item :
                            .init(externalVersionID: id, status: "unavailable", version: nil)
                    }
                } catch {
                    guard !Task.isCancelled, generation == operationGeneration else { return }
                    // Timeout / transport failure is NOT a terminal answer: keep the row loading and retry (bounded).
                    var retry: [String] = []
                    for id in chunk {
                        let n = (metadataAttempts[key + "|" + id] ?? 0) + 1
                        metadataAttempts[key + "|" + id] = n
                        if StoreMetadataRetryPolicy.shouldRetry(attempt: n) { retry.append(id) }
                        else { metadata[key, default: [:]][id] = .init(externalVersionID: id, status: "unavailable", version: nil) }
                    }
                    if !retry.isEmpty {
                        let wait = StoreMetadataRetryPolicy.delay(attempt: metadataAttempts[key + "|" + retry[0]] ?? 1)
                        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                        guard !Task.isCancelled, generation == operationGeneration else { return }
                        requestMetadata(app, ids: retry + Array(pending[min(start + 2, pending.count)...]))
                        return
                    }
                }
            }
        }
    }

    private func recordOwnershipFailure(_ error: Error, app: MirsaStoreApp) {
        let explicitLicense: Bool
        if let diagnostic = error as? StoreProductDiagnostic {
            explicitLicense = diagnostic.requiresLicense
        } else if let local = error as? MirsaStoreError, case .licenseRequired = local {
            explicitLicense = true
        } else { explicitLicense = false }
        if explicitLicense { ownership[app.id] = .licenseRequired }
        // Route a failed row action to details so Get is an explicit separate action.
        selected = app
    }

    private func codeReset() { code = "" }

    private func describe(_ error: Error) -> String {
        if let authorization = error as? MirsaStorePurchaseAuthorization { return authorization.localizedDescription }
        if let diagnostic = error as? StorefrontMetadataMissing { return diagnostic.localizedDescription }
        if let diagnostic = error as? StoreProductDiagnostic {
            if diagnostic.requiresReauthentication {
                // The client already removed the rejected session; reflect it so the sign-in card shows.
                account = nil; needsCode = false
                return storeText("Apple ended this store session (its sign-in token expired). Sign in again and retry. Your saved apps are unchanged.",
                                 "أبل أنهت جلسة المتجر (انتهت صلاحية الدخول). سجّل دخول من جديد وجرّب. تطبيقاتك المحفوظة ما تغيّرت.",
                                 de: "Apple hat diese Store-Sitzung beendet (die Anmeldung ist abgelaufen). Melde dich erneut an und versuche es noch einmal. Deine gespeicherten Apps bleiben unverändert.",
                                 ckb: "Apple ئەم دانیشتنەی ستۆری کۆتایی پێهێنا (چوونەژوورەوە بەسەرچوو). دووبارە بچۆ ژوورەوە و هەوڵ بدەرەوە. ئەپە هەڵگیراوەکانت نەگۆڕدراون.",
                                 kmr: "Apple ev danişîna firoşgehê qedand (têketin qediya). Dîsa têkeve û biceribîne. Sepanên te yên tomarkirî neguherîn.") + "\n\n" + diagnostic.localizedDescription
            }
            let explanation = diagnostic.requiresLicense
                ? t("Apple says this account needs the app's license. For a free app, tap Get to acquire its free license and download in one action.", "Apple بتقول الحساب بحاجة لترخيص التطبيق. إذا مجاني، دوس احصل عليه لنجيب الترخيص المجاني وننزّل بضغطة وحدة.", "مۆڵەتی ئەپ پێویستە. وەریبگرە پاشان دایبگرە.", "Lîsans pêwîst e. Bigire, paşê Daxe bitikîne.")
                : t("Apple rejected the request. This does not mean you do not own the app. If a free licence refresh is available, it requires your explicit confirmation and retries the selected download once.", "Apple رفضت الطلب، مو دليل إنك ما بتملك التطبيق. إذا تحديث الترخيص المجاني متاح، بدّه موافقتك وبنعيد نفس النسخة مرة وحدة.", "Apple داواکاری ڕەتکردەوە؛ ئەمە بەڵگەی نەبوونی مۆڵەت نییە.", "Apple daxwaz red kir; ev nebûna lîsansê îspat nake.")
            return explanation + "\n\n" + diagnostic.localizedDescription
        }
        if let diagnostic = error as? MirsaStoreAuthDiagnostic { return diagnostic.localizedDescription }
        if let server = error as? MirsaStoreServerError {
            switch server {
            case .code(let code):
                switch code {
                case "invalid_code": return t("Code not accepted. Re-enter your password and try once more.", "الرمز ما انقبل. اكتب كلمة السر من جديد وجرّب مرة ثانية.", "کۆدەکە وەرنەگیرا. وشەی نهێنی دووبارە بنووسە و هەوڵ بدە.", "Kod nehat pejirandin. Şîfreyê dîsa binivîse û biceribîne.")
                case "challenge_expired", "credentials_rejected":
                    needsCode = false; password = ""; codeReset()
                    return t("Sign-in expired or was rejected. Start again with your Apple Account.", "انتهت محاولة الدخول أو ما انقبلت. ابدأ من جديد بحساب Apple.", "چوونەژوورەوە بەسەرچوو یان ڕەتکرایەوە. دووبارە دەست پێبکە.", "Têketin qediya an hat redkirin. Ji nû ve dest pê bike.")
                case "unauthorized", "device_required", "session_expired", "not_authenticated":
                    account = nil; needsCode = false; results = []
                    return t("Your session is no longer available. Sign in again explicitly.", "جلستك ما عادت متاحة. سجّل دخول من جديد.", "دانیشتنەکەت بەردەست نییە. دووبارە بچۆ ژوورەوە.", "Danişîna te êdî ne berdest e. Dîsa têkeve.")
                case "staging_denied": return t("App Store testing is restricted to the owner's existing verified device. This installation has no approved device credential. Nothing was reset.", "تجربة متجر أبل حالياً بس لجهاز صاحب التطبيق المسجّل. هالتثبيت ما عنده هوية جهاز معتمدة، وما غيّرنا شي.", "تاقیکردنەوەی ستۆر تەنها بۆ ئامێری پشتڕاستکراوەی خاوەنەکەیە. ئەم دامەزراندنە ناسنامەی ڕێپێدراوی نییە. هیچ شتێک نەگۆڕدرا.", "Ceribandina Store tenê ji bo amûra pejirandî ya xwedî ye. Ev sazkirin nasnameya pejirandî tune ye. Tiştek nehat guherandin.")
                case "upstream_unavailable": return storeText("Could not confirm this device right now. Nothing was reset. Try again in a moment.", "ما قدرت أتأكد من الجهاز هلأ. ما انمسح شي. جرّب بعد شوي.", de: "Das Gerät konnte gerade nicht bestätigt werden. Es wurde nichts zurückgesetzt. Versuche es gleich noch einmal.", ckb: "ئێستا نەتوانرا ئامێرەکە پشتڕاست بکرێتەوە. هیچ ڕیسێت نەکرا. کەمێکی تر دووبارە هەوڵ بدە.", kmr: "Niha cîhaz nehat piştrastkirin. Tiştek nehat vesazkirin. Piştî demekê dîsa biceribîne.")
                case "device_limit": return t("This account reached its device limit. Use an already registered device.", "هالحساب وصل لحد الأجهزة. استخدم جهاز مسجّل من قبل.", "ئەم ئەکاونتە گەیشتووەتە سنووری ئامێرەکان. ئامێرێکی پێشتر تۆمارکراو بەکاربهێنە.", "Ev hesab gihîştiye sînorê amûran. Amûreke berê tomarkirî bi kar bîne.")
                case "invalid_version": return t("This version is not available for this app. Reload its official version list and choose again.", "هالنسخة مو متاحة لهالتطبيق. حدّث قائمة النسخ الرسمية واختار من جديد.", "ئەم وەشانە بۆ ئەم ئەپە بەردەست نییە. لیستی فەرمی نوێ بکەرەوە و دووبارە هەڵبژێرە.", "Ev guherto ji bo vê sepanê ne berdest e. Lîsteya fermî nû bike û dîsa hilbijêre.")
                case "license_required": return t("Your account must own this app before listing versions or downloading. For a free app, tap Get free license first. Paid apps cannot be purchased here.", "لازم حسابك يملك التطبيق لتشوف النسخ أو تنزّل. إذا مجاني دوس احصل على ترخيص مجاني أول. المدفوع ما بينشترى هون.", "بۆ وەشانەکان و داگرتن دەبێت خاوەنی ئەپەکە بیت. بۆ ئەپی بێبەرامبەر سەرەتا مۆڵەت وەربگرە. پارەدار لێرە ناکڕدرێت.", "Ji bo guhertoyan û daxistinê divê hesab xwedî be. Ji bo belaş pêşî lîsansê bigire. Bi pere li vir nayê kirîn.")
                case "paid_app_forbidden": return t("Paid apps cannot be purchased here.", "التطبيقات المدفوعة ما بتنشترى هون.", "ئەپە پارەدارەکان لێرە ناکڕدرێن.", "Sepanên bi pere li vir nayên kirîn.")
                case "artifact_expired", "not_found": return t("This session or download expired. Start the action again.", "انتهت هالجلسة أو هالتنزيل. ابدأ الطلب من جديد.", "دانیشتن یان داگرتن بەسەرچوو. دووبارە دەست پێبکە.", "Danişîn an daxistin qediya. Dîsa dest pê bike.")
                case "too_large": return t("This download exceeds the 2 GB limit.", "هالتنزيل أكبر من حد 2 غيغابايت.", "ئەم داگرتنە لە سنووری ٢ گیگابایت زیاترە.", "Ev daxistin ji sînorê 2 GB mezintir e.")
                case "rate_limited", "busy": return t("The service is busy. Wait a little before trying again.", "الخدمة مشغولة. استنى شوي قبل ما تعيد.", "خزمەتگوزاری سەرقاڵە. کەمێک چاوەڕێ بکە.", "Xizmet mijûl e. Hinekî bisekine û dîsa biceribîne.")
                default: return t("The App Store service could not finish this request. Try again later.", "خدمة متجر أبل ما قدرت تكمل الطلب. جرّب بعدين.", "خزمەتگوزاری App Store نەیتوانی داواکاری تەواو بکات. دواتر هەوڵ بدە.", "Xizmeta App Store nikarî daxwazê biqedîne. Paşê biceribîne.")
                }
            }
        }
        guard let e = error as? MirsaStoreError else {
            return t("Something went wrong. Check your connection and try again.", "صار خطأ. تأكد من الإنترنت وجرّب.",
                     "هەڵەیەک ڕوویدا. ئینتەرنێتەکەت بپشکنە و دووبارە هەوڵ بدە.", "Çewtiyek çêbû. Girêdana înternetê kontrol bike û dîsa biceribîne.")
        }
        switch e {
        case .busy: return t("Another App Store task is still running.", "في مهمة App Store ثانية لسا شغالة.", "کارێکی تری App Store هێشتا کار دەکات.", "Karekî din ê App Store hê dixebite.")
        case .signedOut: return t("Sign in first.", "سجّل دخول أول.", "سەرەتا بچۆ ژوورەوە.", "Pêşî têkeve.")
        case .verificationRequired: return t("Enter the 6-digit code from Apple.", "اكتب الرمز من 6 أرقام من Apple.", "کۆدی ٦ ژمارەیی Apple بنووسە.", "Koda 6 hejmarî ya Apple binivîse.")
        case .invalidVerificationCode: return t("Enter six digits. Nothing was sent to Apple.", "اكتب رمز من 6 أرقام. ما بعتنا طلب لـApple.", "کۆدی شەش ژمارەیی بنووسە. هیچ نەنیردرا بۆ Apple.", "Koda şeş hejmarî binivîse. Tiştek ji Apple re nehat şandin.")
        case .duplicateVerificationCode: return t("This code was already submitted. Use a new code or cancel and start over. Nothing was sent to Apple.", "هالرمز انبعت قبل. اكتب رمز جديد أو الغِ وابدأ من جديد. ما بعتنا طلب لـApple.", "ئەم کۆدە پێشتر نێردراوە. کۆدێکی نوێ بنووسە یان دووبارە دەست پێبکە.", "Ev kod berê hat şandin. Kodeke nû binivîse an ji nû ve dest pê bike.")
        case .verificationPasswordChanged: return t("The password changed. Cancel and sign in again. Nothing was sent to Apple.", "كلمة السر تغيّرت. الغِ وارجع سجّل دخول. ما بعتنا طلب لـApple.", "وشەی نهێنی گۆڕاوە. دووبارە بچۆ ژوورەوە.", "Şîfre guherî. Ji nû ve têkeve.")
        case .invalidInput: return t("Check your email, password and verification code.", "تأكد من الإيميل وكلمة السر ورمز التحقق.", "ئیمەیڵ و وشەی نهێنی و کۆدی پشتڕاستکردنەوە بپشکنە.", "E-name, şîfre û koda piştrastkirinê kontrol bike.")
        case .freeAppsOnly: return t("Only apps that are free in this account's store can be acquired.", "بس التطبيقات المجانية بمتجر هالحساب بتنجاب.", "تەنها ئەپە بێبەرامبەرەکانی ستۆری ئەم ئەکاونتە دەهێنرێن.", "Tenê sepanên belaş ên stoya vî hesabî dikarin bên girtin.")
        case .keychain: return t("The device Keychain is unavailable. Unlock the iPhone and try again.", "سلسلة المفاتيح مو متاحة. افتح قفل الآيفون وجرّب.", "Keychain بەردەست نییە. ئایفۆنەکە بکەرەوە و دووبارە هەوڵ بدە.", "Keychain ne berdest e. iPhone vekin û dîsa biceribînin.")
        case .invalidPackage: return t("Apple sent a file that does not match the requested app or version.", "Apple بعتت ملف ما بيطابق التطبيق أو النسخة.", "Apple فایلێکی ناردووە کە لەگەڵ ئەپ یان وەشانەکە ناگونجێت.", "Apple pelek şand ku bi sepan an guhertoyê re nagunce.")
        case .untrustedURL: return t("The download address was not a trusted Apple address, so it was stopped.", "عنوان التنزيل مو موثوق من Apple فانوقف.", "ناونیشانی داگرتن متمانەپێکراوی Apple نەبوو، بۆیە وەستێنرا.", "Navnîşana daxistinê ya Apple ne pêbawer bû, ji ber vê hat sekinandin.")
        case .serviceUnavailable: return t("Apple could not finish this. Check connection, country and account, then retry.", "Apple ما قدرت تكمل. تأكد من الإنترنت والدولة والحساب.", "Apple نەیتوانی تەواوی بکات. ئینتەرنێت، وڵات و ئەکاونت بپشکنە.", "Apple nikaribû biqedîne. Înternet, welat û hesab kontrol bike.")
        case .licenseRequired: return t("This Apple Account does not own this app. Tap Get free license first (free apps only).", "حسابك ما بيملك التطبيق. دوس احصل على ترخيص مجاني أول (للمجانية بس).", "ئەم ئەکاونتە خاوەنی ئەپەکە نییە. سەرەتا مۆڵەتی بێبەرامبەر وەربگرە (تەنها بێبەرامبەرەکان).", "Ev hesab xwediyê sepanê nîne. Pêşî lîsansa belaş bigire (tenê belaş).")
        case .operationCancelled: return t("Cancelled.", "انلغت.", "هەڵوەشێنرایەوە.", "Hat betalkirin.")
        }
    }
}

#if DEBUG
extension AppStoreAccountView {
    struct UITestFixture {
        var account: MirsaStoreAccount
        var results: [MirsaStoreApp]
        var versions: [String: [String]]
        var metadata: [String: [String: MirsaStoreServerClient.VersionMetadata]]
        var limits: [String: Int]
        var selected: MirsaStoreApp?
    }
    /// UI-test screenshots only (`-MirsaUITestHarness -MirsaStoreFixtureAccount`). No Apple request.
    static func uiTestFixture() -> UITestFixture? {
        let args = ProcessInfo.processInfo.arguments
        guard MirsaUITestHarness.active, args.contains("-MirsaStoreFixtureAccount") else { return nil }
        let apps = [
            MirsaStoreApp(id: 100001, bundleID: "com.example.notes", name: "Notes Pro", version: "5.2.1", price: 0, artworkURL: ""),
            MirsaStoreApp(id: 100002, bundleID: "com.example.weather", name: "Weather Live", version: "2.0", price: 0, artworkURL: ""),
            MirsaStoreApp(id: 100003, bundleID: "com.example.studio", name: "Music Studio", version: "3.4", price: 4.99, artworkURL: ""),
        ]
        let ids = ["880000001", "880000004", "880000002", "880000003"]
        let meta: [String: MirsaStoreServerClient.VersionMetadata] = [
            "880000004": .init(externalVersionID: "880000004", status: "ready", version: "5.2.0"),
            "880000003": .init(externalVersionID: "880000003", status: "ready", version: "5.1.3"),
            "880000002": .init(externalVersionID: "880000002", status: "unavailable", version: nil),
        ]
        let detail = args.contains("-MirsaStoreFixtureDetail")
        return UITestFixture(account: MirsaStoreAccount(email: "sample.user@example.com", country: "tr", name: "Sample User"),
                             results: apps, versions: detail ? [apps[0].bundleID: ids] : [:],
                             metadata: detail ? [apps[0].bundleID: meta] : [:], limits: [apps[0].bundleID: 20],
                             selected: detail ? apps[0] : nil)
    }
}
#endif

/// Indeterminate progress bar (UI only).
struct MirsaIndeterminateBar: View {
    var body: some View {
        MirsaLiquidProgress()
    }
}

private extension View {
    func fieldStyle() -> some View {
        self.padding(12).background(MirsaPalette.cardRaised, in: RoundedRectangle(cornerRadius: MirsaRadius.m, style: .continuous))
            .foregroundStyle(.white)
    }
}
