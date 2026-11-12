import SwiftUI
import ApplePackage

/// Own-account App Store downloads (no sharing, no decryption, no signing).
/// Self-contained: the host passes `onDownloaded` which must import the file into the
/// encrypted-IPA flow WITHOUT modifying it. After it returns normally this view removes
/// the file's private temp directory. Hook: AppStoreAccountView(onDownloaded: { url in ... }).
struct AppStoreAccountView: View {
    var onDownloaded: (URL) async throws -> Void
    var searchOnly = false
    var onOpenAccount: () -> Void = {}
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
    private var effectiveCountry: String { searchCountry ?? account?.country ?? "tr" }
    private var otherStore: Bool { effectiveCountry.lowercased() != account?.country.lowercased() }
    private func canDownload(_ app: MirsaStoreApp) -> Bool { !otherStore || accountAvailable.contains(app.id) }

    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var needsCode = false
    @State private var versions: [String: [String]] = [:]
    @State private var metadata: [String: [String: MirsaStoreServerClient.VersionMetadata]] = [:]
    @State private var metadataTasks: [String: Task<Void, Never>] = [:]
    @State private var metadataLimit: [String: Int] = [:]
    @State private var chosen: [String: String] = [:]
    @State private var manualID: [String: String] = [:]
    @State private var term = ""
    @State private var results: [MirsaStoreApp] = []
    @State private var searched = false
    @State private var busy: String?
    @State private var work: Task<Void, Never>?
    @State private var notice: String?
    @State private var showSteps = false
    @State private var confirmSignOut = false
    @State private var operationGeneration = UUID()
    /// UI only: the app whose detail page is open, and when the current task started.
    @State private var selected: MirsaStoreApp?
    @State private var busySince: Date?
    @FocusState private var focus: Bool

    private func t(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String { tr(en, ar, ckb: ckb, kmr: kmr) }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: MirsaSpacing.m) {
                Color.clear.frame(height: 0).id("store-top")
                if let account, let app = selected {
                    if busy != nil { busyCard }
                    detailView(app, account: account)
                } else {
                    if searchOnly { searchHeader }
                    if !searchOnly {
                        Text(t("My App Store", "حسابي بالـApp Store", "ئەپستۆری من", "App Store ya min"))
                            .font(MirsaFont.pageTitle).foregroundStyle(.white)
                        infoCard
                    }
                    if let account { signedInCards(account) }
                    else if !session.loaded { ProgressView() }
                    else if searchOnly {
                        Text(t("Sign in from the Account tab to search the App Store.", "سجّل دخول من تبويب الحساب لتبحث بمتجر Apple.", "لە بەشی ئەکاونت بچۆ ژوورەوە.", "Ji beşa Hesabê têkeve."))
                            .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                    } else if needsCode { verificationCard } else { signInCard }
                    if busy != nil { busyCard }
                }
            }
            .padding(.horizontal, MirsaSpacing.page)
            .padding(.bottom, MirsaSpacing.tabBarClearance)
        }
        .onChange(of: selected?.id) { _, _ in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("store-top", anchor: .top) } }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AuroraBackground().ignoresSafeArea())
        .preferredColorScheme(.dark)
        .environment(\.layoutDirection, .leftToRight)
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
                }
                .searchable(text: $countryQuery)
                .navigationTitle(t("Search storefront", "متجر البحث", "ستۆری گەڕان", "Stoya lêgerînê"))
                .toolbar { Button(t("Done", "تمام", "تەواو", "Temam")) { showCountries = false } }
            }
            .preferredColorScheme(.dark)
        }
        .onChange(of: busy) { _, value in busySince = value == nil ? nil : (busySince ?? Date()) }
        .onChange(of: account) { _, value in if value == nil { selected = nil } }
        .onDisappear { password = ""; code = ""; work?.cancel(); cancelMetadata() }
        .alert(t("Notice", "تنبيه", "ئاگاداری", "Agahdarî"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(t("OK", "تمام", "باشە", "Baş e")) { notice = nil }
        } message: { Text(notice ?? "") }
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
                    step("5", t("Tap Older versions after obtaining the app's license. Choose an official external version ID, or enter one manually. The server checks it against Apple's current list; empty means latest.",
                                "بعد ما حسابك يملك التطبيق، دوس نسخ أقدم واختار رقم نسخة رسمي أو اكتبو بإيدك. السيرفر بيتأكد إنو موجود بقائمة Apple. الفاضي يعني الأحدث.",
                                "دوای وەرگرتنی مۆڵەت، وەشانە کۆنەکان بکەرەوە و ناسنامەیەکی فەرمی هەڵبژێرە یان بینووسە. سێرڤەر لە لیستی Apple دەپشکنێت. بەتاڵ واتە نوێترین.",
                                "Piştî lîsansê Guhertoyên kevn veke û ID-eke fermî hilbijêre an binivîse. Server di lîsteya Apple de kontrol dike. Vala tê wateya herî nû."))
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
        .padding(MirsaSpacing.card).frame(maxWidth: .infinity, alignment: .leading).mirsaCard()
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
        .padding(MirsaSpacing.card).frame(maxWidth: .infinity, alignment: .leading).mirsaCard()
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
        .padding(MirsaSpacing.card).frame(maxWidth: .infinity, alignment: .leading).mirsaCard()
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
            .padding(MirsaSpacing.card).mirsaCard()

        }

        searchControls(a)


        if searched && results.isEmpty && busy == nil {
            Text(t("No results in this country.", "ما في نتائج بهالدولة.", "لەم وڵاتەدا هیچ ئەنجامێک نییە.", "Li vî welatî encam tune."))
                .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
        }
        if !results.isEmpty {
            Text(t("Results", "النتائج", "ئەنجامەکان", "Encam")).font(MirsaFont.sectionTitle).foregroundStyle(.white)
        }
        ForEach(results) { app in resultRow(app) }
    }

    private var searchHeader: some View {
        HStack(alignment: .center) {
            Text(t("Search", "بحث", "گەڕان", "Lêgerîn"))
                .font(MirsaFont.pageTitle).foregroundStyle(.white)
            Spacer()
            Button(action: onOpenAccount) {
                AppStoreAvatar(text: account?.name ?? "", size: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("Account", "الحساب", "ئەکاونت", "Hesab"))
            .accessibilityIdentifier("store-search-account")
        }
        .padding(.top, MirsaSpacing.m)
        .environment(\.layoutDirection, (AppLanguageStore.shared.current == .arabic || AppLanguageStore.shared.current == .sorani) ? .rightToLeft : .leftToRight)
    }

    private func searchControls(_ a: MirsaStoreAccount) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(MirsaPalette.textTertiary)
                TextField(t("App name, App ID or link", "اسم التطبيق أو App ID أو الرابط", "ناوی ئەپ، App ID یان بەستەر", "Navê sepanê, App ID an girêdan"), text: $term)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search).onSubmit { search() }.focused($focus)
                    .disabled(busy != nil).foregroundStyle(.white)
                    .accessibilityIdentifier("store-search-input")
                if !term.isEmpty {
                    Button { term = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(MirsaPalette.textTertiary)
                        .accessibilityLabel(t("Clear", "مسح", "سڕینەوە", "Paqij bike"))
                }
            }
            .font(MirsaFont.body).padding(.horizontal, 16).frame(minHeight: 50)
            .background(MirsaPalette.cardRaised, in: RoundedRectangle(cornerRadius: MirsaRadius.m))
            .overlay(RoundedRectangle(cornerRadius: MirsaRadius.m).strokeBorder(MirsaPalette.stroke, lineWidth: 1))

            HStack(spacing: 10) {
                Button { showCountries = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                        Text(AppStoreCountry.label(effectiveCountry)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                    .padding(.horizontal, 13).frame(minHeight: 38)
                    .background(MirsaPalette.cardRaised, in: Capsule())
                }.buttonStyle(.plain).disabled(busy != nil)
                Label("iOS", systemImage: "iphone")
                    .padding(.horizontal, 13).frame(minHeight: 38)
                    .background(MirsaPalette.cardRaised, in: Capsule())
                    .accessibilityLabel(t("Platform: iOS", "المنصة iOS", "پلاتفۆرم iOS", "Platform iOS"))
                Spacer(minLength: 0)
            }.font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)

            if otherStore {
                Text(t("Downloads use your account storefront (\(AppStoreCountry.label(a.country))).",
                       "التنزيل من متجر حسابك (\(AppStoreCountry.label(a.country))).",
                       "داگرتن لە ستۆری ئەکاونتەکەتە.", "Daxistin ji stoya hesabê te ye."))
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning)
            }
            if !StoreRecentSearches.read(recentSearchData).isEmpty {
                VStack(spacing: 12) {
                    HStack {
                        Text(t("Recent searches", "عمليات البحث الأخيرة", "گەڕانەکانی ئەم دواییە", "Lêgerînên dawî"))
                            .font(MirsaFont.sectionTitle).foregroundStyle(.white)
                        Spacer()
                        Button(t("Clear", "مسح", "سڕینەوە", "Paqij bike")) { recentSearchData = Data() }
                            .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.accentSoft)
                            .accessibilityIdentifier("store-clear-recent")
                    }
                    ForEach(StoreRecentSearches.read(recentSearchData), id: \.self) { recent in
                        Button { term = recent; search() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "magnifyingglass").foregroundStyle(MirsaPalette.textTertiary)
                                Text(recent).foregroundStyle(MirsaPalette.textSecondary).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .font(MirsaFont.body).padding(.horizontal, 16).frame(minHeight: 48)
                            .background(MirsaPalette.cardRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: MirsaRadius.m))
                        }.buttonStyle(.plain).disabled(busy != nil)
                    }
                }.padding(.top, MirsaSpacing.m)
            }
        }
        .environment(\.layoutDirection, (AppLanguageStore.shared.current == .arabic || AppLanguageStore.shared.current == .sorani) ? .rightToLeft : .leftToRight)
    }

    // MARK: result row, detail page, progress (UI only; same actions as before)

    private func artwork(_ app: MirsaStoreApp, size: CGFloat) -> some View {
        AsyncImage(url: URL(string: app.artworkURL)) { $0.resizable().scaledToFill() } placeholder: {
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

    private func resultRow(_ app: MirsaStoreApp) -> some View {
        HStack(spacing: MirsaSpacing.s) {
            Button { withAnimation(.easeOut(duration: 0.2)) { selected = app } } label: {
                HStack(spacing: MirsaSpacing.s) {
                    artwork(app, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(MirsaFont.cardTitle).foregroundStyle(.white).lineLimit(2)
                        Text("\(app.version) · \(app.bundleID)").font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary).lineLimit(1)
                        priceBadge(app)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(t("Opens the app page", "بيفتح صفحة التطبيق", "پەڕەی ئەپەکە دەکاتەوە", "Rûpela sepanê vedike"))
            Button { download(app) } label: {
                Text(canDownload(app) ? t("Download", "تنزيل", "داگرتن", "Daxe") : t("Not in account store", "مو بمتجر حسابك", "لە ستۆرەکەت نییە", "Ne li stoya te ye"))
                    .font(MirsaFont.button).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 34)
                    .background(Capsule().fill(MirsaPalette.accentGradient))
            }
            .buttonStyle(.plain)
            .disabled(busy != nil || !canDownload(app))
            .opacity(busy != nil || !canDownload(app) ? 0.5 : 1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mirsaCard()
    }

    private static func newestFirst(_ ids: [String]) -> [String] {
        ids.sorted { (UInt64($0) ?? 0) > (UInt64($1) ?? 0) }
    }

    @ViewBuilder private func detailView(_ app: MirsaStoreApp, account a: MirsaStoreAccount) -> some View {
        let key = app.bundleID
        Button { withAnimation(.easeOut(duration: 0.2)) { selected = nil } } label: {
            Label(t("Results", "النتائج", "ئەنجامەکان", "Encam"), systemImage: "chevron.left")
                .font(MirsaFont.button).foregroundStyle(MirsaPalette.accentSoft)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("store-detail-back")
        HStack(alignment: .top, spacing: MirsaSpacing.m) {
            artwork(app, size: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.title2.weight(.bold)).foregroundStyle(.white).lineLimit(3)
                Text(t("Version ", "الإصدار ", "وەشان ", "Guherto ") + app.version)
                    .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                Text(app.bundleID).font(.caption2.monospaced()).foregroundStyle(MirsaPalette.textTertiary).lineLimit(1)
                priceBadge(app)
            }
            Spacer(minLength: 0)
        }
        .padding(MirsaSpacing.card).frame(maxWidth: .infinity, alignment: .leading).mirsaCard()

        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            Button { download(app) } label: {
                HStack { Image(systemName: "arrow.down.circle"); Text(t("Download", "تنزيل", "داگرتن", "Daxe")) }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.mirsaPrimary).disabled(busy != nil || !canDownload(app))
            if !canDownload(app) {
                Text(t("Not available in your account storefront. Download is disabled.", "مو متاح بمتجر حسابك، التنزيل موقف.", "لە ستۆری ئەکاونتەکەت بەردەست نییە.", "Li stoya hesabê te ne berdest e.")).font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning)
            }
            Text(t("Version: ", "النسخة: ", "وەشان: ", "Guherto: ") + chosenLabel(app))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textSecondary)
            Text(t("Needs this account to own the app. Saved unchanged in the App Store tab.",
                   "لازم الحساب يملك التطبيق. بينحفظ متل ما هو بتبويب متجر أبل.",
                   "پێویستە ئەکاونتەکە خاوەنی ئەپەکە بێت. وەک خۆی لە بەشی فرۆشگای ئەپڵ هەڵدەگیرێت.",
                   "Divê hesab xwediyê sepanê be. Wekî xwe li Firoşgeha Apple tê tomarkirin."))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
            Divider().overlay(MirsaPalette.stroke)
            Button { acquire(app) } label: { Text(t("Get free license", "احصل على ترخيص مجاني", "مۆڵەتی بێبەرامبەر وەربگرە", "Lîsansa belaş bigire")).frame(maxWidth: .infinity) }
                .buttonStyle(.mirsaSecondary).disabled(app.price != 0 || busy != nil || !canDownload(app))
            Text(t("Only if this account never got the app. Adds it to your Apple Account; costs nothing.",
                   "بس إذا حسابك ما حصل عالتطبيق قبل. بيضيفو لحساب Apple تبعك وبلا مصاري.",
                   "تەنها ئەگەر ئەم ئەکاونتە پێشتر ئەپەکەی نەهێنابێت. دەیخاتە ئەکاونتی Apple ت بێ پارە.",
                   "Tenê heke ev hesab berê sepan negirtibe. Li hesabê Apple zêde dike, bêpere."))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
        }
        .padding(MirsaSpacing.card).frame(maxWidth: .infinity, alignment: .leading).mirsaCard()

        Text(t("Older versions", "نسخ أقدم", "وەشانە کۆنەکان", "Guhertoyên kevn")).font(MirsaFont.sectionTitle).foregroundStyle(.white)
            .padding(.top, MirsaSpacing.xs)
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            if let list = versions[key] {
                if list.isEmpty {
                    Text(t("Apple returned no versions.", "Apple ما رجّعت نسخ.", "Apple هیچ وەشانێکی نەگەڕاندەوە.", "Apple guhertoyek neda."))
                        .font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning)
                } else {
                    let sorted = Self.newestFirst(list)
                    let visible = Array(sorted.prefix(metadataLimit[key] ?? 20))
                    VStack(spacing: 0) {
                        versionRow(key: key, id: nil, title: t("Latest", "الأحدث", "نوێترین", "Ya herî nû"), subtitle: app.version)
                        ForEach(visible, id: \.self) { id in
                            Rectangle().fill(MirsaPalette.stroke).frame(height: 1)
                            versionRow(key: key, id: id, title: versionName(app, id), subtitle: "ID \(id)")
                        }
                    }
                    .background(MirsaPalette.cardRaised.opacity(0.5), in: RoundedRectangle(cornerRadius: MirsaRadius.m, style: .continuous))
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
                            requestMetadata(app, ids: visible)
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
                    .buttonStyle(.mirsaSecondary).disabled(busy != nil)
            }
            Text(t("Optional. Lists official Apple external version IDs, not human version names. The account must own the app. Leave empty for latest.",
                   "اختياري. هاي أرقام نسخ Apple الرسمية مو أسماء النسخ. لازم حسابك يملك التطبيق. اتركو فاضي للأحدث.",
                   "ئارەزوومەندانە. ناسنامە فەرمییەکانی وەشانی Apple نیشان دەدات نەک ناو. دەبێت خاوەنی ئەپەکە بیت. بەتاڵی بهێڵە بۆ نوێترین.",
                   "Bijarte. ID-yên fermî yên Apple ne, ne navên guhertoyan. Divê hesab xwedî be. Ji bo herî nû vala bihêle."))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
            TextField(t("Version ID (optional)", "رقم النسخة (اختياري)", "ناسنامەی وەشان (ئارەزوومەندانە)", "ID ya guhertoyê (bijarte)"),
                      text: Binding(get: { manualID[key] ?? "" }, set: { v in
                          let d = String(v.filter { $0.isASCII && $0.isNumber }.prefix(20)); manualID[key] = d; chosen[key] = d.isEmpty ? nil : d }))
                .keyboardType(.numberPad).focused($focus).fieldStyle()
        }
        .padding(MirsaSpacing.card).frame(maxWidth: .infinity, alignment: .leading).mirsaCard()
        Text(a.email).font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary).lineLimit(1).truncationMode(.middle)
    }

    private func versionRow(key: String, id: String?, title: String, subtitle: String) -> some View {
        let on = chosen[key] == id
        return Button {
            chosen[key] = id; manualID[key] = ""
        } label: {
            HStack(spacing: MirsaSpacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(MirsaFont.body).foregroundStyle(.white).lineLimit(1)
                    Text(subtitle).font(.caption2.monospaced()).foregroundStyle(MirsaPalette.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if on { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(MirsaPalette.accentSoft) }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
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

    private func chosenLabel(_ app: MirsaStoreApp) -> String {
        guard let id = chosen[app.bundleID] else { return t("Latest", "الأحدث", "نوێترین", "Ya herî nû") + " · " + app.version }
        if let item = metadata[app.bundleID]?[id], item.status == "ready", let version = item.version { return "\(version) · ID \(id)" }
        return "ID \(id)"
    }

    private var busyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text(busy ?? "").font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                Spacer()
                if let since = busySince {
                    TimelineView(.periodic(from: since, by: 1)) { ctx in
                        let s = max(0, Int(ctx.date.timeIntervalSince(since)))
                        Text(String(format: "%d:%02d", s / 60, s % 60)).font(MirsaFont.caption.monospacedDigit()).foregroundStyle(MirsaPalette.textTertiary)
                    }
                }
                Button(t("Cancel", "إلغاء", "هەڵوەشاندنەوە", "Betal")) { work?.cancel() }
                    .buttonStyle(.mirsaSecondary)
            }
            MirsaIndeterminateBar()
            Text(t("Size and speed are not reported for this step yet, so only the elapsed time is shown.",
                   "الحجم والسرعة مو متاحين لهالخطوة لسا، فبنعرض الوقت يلي مضى بس.",
                   "قەبارە و خێرایی بۆ ئەم هەنگاوە هێشتا نانێردرێن، بۆیە تەنها کاتی تێپەڕیو نیشان دەدرێت.",
                   "Mezinahî û lez ji bo vê gavê hêj nayên ragihandin, ji ber vê tenê dema derbasbûyî tê nîşandan."))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MirsaSpacing.card).mirsaCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: actions

    private func run(_ message: String, _ op: @escaping () async throws -> Void) {
        guard busy == nil else { return }
        focus = false
        busy = message
        let generation = operationGeneration
        work = Task {
            defer { password = ""; code = "" }
            do { try await op() }
            catch is CancellationError {}
            catch { if generation == operationGeneration { notice = describe(error) } }
            if generation == operationGeneration { busy = nil; work = nil }
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
                account = nil; results = []; versions = [:]; chosen = [:]; manualID = [:]; searched = false
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
        let q: String
        do { q = try StoreSearchQuery.parse(term).term }
        catch { notice = t("Enter an app name, numeric App ID or an Apple App Store link.", "اكتب اسم تطبيق أو App ID رقمي أو رابط من متجر Apple.", "ناو یان ناسنامە یان بەستەری Apple بنووسە.", "Nav, App ID an girêdana Apple binivîse."); return }
        run(t("Searching…", "عم نبحث…", "گەڕان…", "Lêgerîn…")) {
            let country = effectiveCountry
            let found = try await client.search(term: q, country: country, limit: 25)
            var available: Set<Int64> = []
            if otherStore, let accountCountry = account?.country {
                available = try await client.availableInStore(found, country: accountCountry)
            }
            try Task.checkCancellation()
            guard country == effectiveCountry else { return }
            results = found; accountAvailable = available; searched = true
            recentSearchData = StoreRecentSearches.adding(q, to: recentSearchData)
        }
    }

    private func acquire(_ app: MirsaStoreApp) {
        run(t("Getting free license…", "عم نجيب الترخيص المجاني…", "مۆڵەتی بێبەرامبەر وەردەگیرێت…", "Lîsansa belaş tê girtin…")) {
            try await client.acquireFreeApp(app)
            notice = t("Done. This account can now download \(app.name).", "تم. حسابك صار يقدر ينزّل \(app.name).",
                       "تەواو. ئەکاونتەکەت ئێستا دەتوانێت \(app.name) دابگرێت.", "Temam. Hesabê te niha dikare \(app.name) daxe.")
        }
    }

    private func loadVersions(_ app: MirsaStoreApp) {
        run(t("Asking Apple for versions…", "عم نسأل Apple عن النسخ…", "پرسیار لە Apple دەکرێت…", "Ji Apple guhertoyan dipirsin…")) {
            let ids = try await client.availableVersions(app)
            versions[app.bundleID] = ids
            metadataLimit[app.bundleID] = 20
            requestMetadata(app, ids: Array(Self.newestFirst(ids).prefix(20)))
        }
    }

    private func download(_ app: MirsaStoreApp) {
        let version = chosen[app.bundleID]
        run(t("Preparing and downloading…", "عم جهّز ونزّل…", "لە Apple دادەگیرێت…", "Ji Apple tê daxistin…")) {
            let generation = operationGeneration
            let url = try await client.downloadOwnedApp(app, externalVersionID: version)
            defer { MirsaManagedTmp.end(url.deletingLastPathComponent()) }
            try Task.checkCancellation()
            guard generation == operationGeneration else { throw CancellationError() }
            try await onDownloaded(url)
            notice = t("Saved to your App Store tab, unchanged.", "انحفظ بتبويب متجر أبل متل ما هو.",
                       "وەک خۆی لە بەشی فرۆشگای ئەپڵ هەڵگیرا.", "Wekî xwe li Firoşgeha Apple hat tomarkirin.")
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

    private func requestMetadata(_ app: MirsaStoreApp, ids: [String]) {
        let ids = Array(ids.filter { metadata[app.bundleID]?[$0]?.status != "ready" && metadata[app.bundleID]?[$0]?.status != "unavailable" }.prefix(20))
        guard !ids.isEmpty else { return }
        let key = app.bundleID
        metadataTasks[key]?.cancel()
        let generation = operationGeneration
        metadataTasks[key] = Task {
            // Publish each small batch as soon as it finishes. Previously all twenty
            // sequential Apple manifests had to finish before the first name appeared.
            // Keep requests serial: they share signer and account-cookie state.
            for start in stride(from: 0, to: ids.count, by: 4) {
                let batch = Array(ids[start..<min(start + 4, ids.count)])
                guard !Task.isCancelled, generation == operationGeneration else { return }
                do {
                    let entries = try await client.versionMetadata(app, externalVersionIDs: batch)
                    guard !Task.isCancelled, generation == operationGeneration else { return }
                    for id in batch {
                        let item = entries.first { $0.externalVersionID == id }
                        metadata[key, default: [:]][id] = item?.status == "ready" ? item :
                            .init(externalVersionID: id, status: "unavailable", version: nil)
                    }
                } catch {
                    guard !Task.isCancelled, generation == operationGeneration else { return }
                    for id in batch {
                        metadata[key, default: [:]][id] = .init(externalVersionID: id, status: "unavailable", version: nil)
                    }
                }
            }
        }
    }

    private func codeReset() { code = "" }

    private func describe(_ error: Error) -> String {
        if let diagnostic = error as? StorefrontMetadataMissing { return diagnostic.localizedDescription }
        if let diagnostic = error as? StoreProductDiagnostic { return diagnostic.localizedDescription }
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
        TimelineView(.animation) { ctx in
            GeometryReader { g in
                let phase = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(MirsaPalette.accentGradient)
                        .frame(width: g.size.width * 0.3)
                        .offset(x: g.size.width * 1.3 * phase - g.size.width * 0.3)
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

private extension View {
    func fieldStyle() -> some View {
        self.padding(12).background(MirsaPalette.cardRaised, in: RoundedRectangle(cornerRadius: MirsaRadius.m, style: .continuous))
            .foregroundStyle(.white)
    }
}
