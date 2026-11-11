import SwiftUI

/// Own-account App Store downloads (no sharing, no decryption, no signing).
/// Self-contained: the host passes `onDownloaded` which must import the file into the
/// encrypted-IPA flow WITHOUT modifying it. After it returns normally this view removes
/// the file's private temp directory. Hook: AppStoreAccountView(onDownloaded: { url in ... }).
struct AppStoreAccountView: View {
    var onDownloaded: (URL) async throws -> Void

    private let client = MirsaStoreServerClient.shared
    @State private var account: MirsaStoreAccount?
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
    @FocusState private var focus: Bool

    private func t(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String { tr(en, ar, ckb: ckb, kmr: kmr) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MirsaSpacing.m) {
                Text(t("My App Store", "حسابي بالـApp Store", "ئەپستۆری من", "App Store ya min"))
                    .font(MirsaFont.pageTitle).foregroundStyle(.white)
                infoCard
                if let account { signedInCards(account) } else if needsCode { verificationCard } else { signInCard }
                if let busy {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text(busy).font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                        Spacer()
                        Button(t("Cancel", "إلغاء", "هەڵوەشاندنەوە", "Betal")) { work?.cancel() }
                            .buttonStyle(.mirsaSecondary)
                    }
                    .padding(MirsaSpacing.card).mirsaCard()
                }
            }
            .padding(.horizontal, MirsaSpacing.page)
            .padding(.bottom, MirsaSpacing.tabBarClearance)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AuroraBackground().ignoresSafeArea())
        .preferredColorScheme(.dark)
        .environment(\.layoutDirection, .leftToRight)
        .task { account = try? await client.currentAccount() }
        .onDisappear { password = ""; code = ""; work?.cancel(); cancelMetadata() }
        .alert(t("Notice", "تنبيه", "ئاگاداری", "Agahdarî"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(t("OK", "تمام", "باشە", "Baş e")) { notice = nil }
        } message: { Text(notice ?? "") }
        .confirmationDialog(t("Sign out of this Apple Account?", "تطلع من حساب Apple؟", "لە ئەکاونتی Apple بچیتە دەرەوە؟", "Ji hesabê Apple derkevî?"),
                            isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(t("Sign out", "تسجيل الخروج", "چوونە دەرەوە", "Derkeve"), role: .destructive) { signOut() }
            Button(t("Cancel", "إلغاء", "هەڵوەشاندنەوە", "Betal"), role: .cancel) {}
        } message: {
            Text(t("Your server session, challenges and server downloads are deleted. Imported IPAs stay.",
                   "بتنمسح جلسة دخولك ورموز التحقق والتنزيلات عن سيرفر مرسى. ملفات IPA المستوردة بتضل.",
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
            Text(t("Your email and password go over HTTPS to the Mirsa server for Apple sign-in. The password is not saved. Apple may require a verification code.",
                   "إيميلك وكلمة السر بينبعتوا لسيرفر مرسى عبر HTTPS للدخول عند Apple. كلمة السر ما بتنحفظ وممكن Apple تطلب رمز تحقق.",
                   "ئیمەیڵ و وشەی نهێنی بە HTTPS بۆ سێرڤەری Mirsa دەنێردرێن بۆ Apple. وشەی نهێنی هەڵناگیرێت و Apple ڕەنگە کۆد بخوازێت.",
                   "E-name û şîfreya te bi HTTPS ji servera Mirsa re ji bo Apple tên şandin. Şîfre nayê tomarkirin û dibe ku Apple kodê bixwaze."))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning)
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
                    step("1", t("Mirsa sends your email and password over HTTPS to its server to sign in to Apple. Your password is not saved. Only the session is kept.",
                                "مرسى بيبعت إيميلك وكلمة السر لسيرفرو عبر HTTPS ليسجّل دخول عند Apple. كلمة السر ما بتنحفظ، بس جلسة الدخول.",
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
            SecureField(t("Re-enter password for this verification", "اكتب كلمة السر من جديد للتحقق", "وشەی نهێنی بۆ پشتڕاستکردنەوە دووبارە بنووسە", "Ji bo piştrastkirinê şîfreyê dîsa binivîse"), text: $password)
                .textContentType(.password).focused($focus).fieldStyle().disabled(busy != nil)
            Button { submitCode() } label: { Text(t("Verify code", "تحقق من الرمز", "کۆدەکە پشتڕاست بکەرەوە", "Kodê piştrast bike")).frame(maxWidth: .infinity) }
                .buttonStyle(.mirsaPrimary).disabled(MirsaStoreCode.valid(code) == nil || password.isEmpty || busy != nil)
            Text(t("Re-enter your password for this request. Two verification tries within five minutes, then start again. A challenge does not confirm that a code was delivered.", "اكتب كلمة السر من جديد لهالطلب. محاولتين خلال 5 دقايق وبعدين ابدأ من جديد. طلب الرمز مو تأكيد إنو وصلك.",
                   "وشەی نهێنی بۆ ئەم داواکارییە دووبارە بنووسە. دوو هەوڵ لە پێنج خولەکدا، پاشان دووبارە دەست پێبکە. داوای کۆد گەیشتنی کۆد پشتڕاست ناکاتەوە.", "Ji bo vê daxwazê şîfreyê dîsa binivîse. Di pênc deqeyan de du hewil, paşê ji nû ve dest pê bike. Daxwaza kodê ne piştrastkirina gihîştina kodê ye."))
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
            Text(t("Sent over HTTPS to the Mirsa server for Apple sign-in. Your password is not saved. Apple may ask for a code.", "بتنبعت لسيرفر مرسى عبر HTTPS للدخول عند Apple. كلمة السر ما بتنحفظ. ممكن Apple تطلب رمز تحقق.",
                   "بە HTTPS بۆ سێرڤەری Mirsa دەنێردرێت بۆ چوونەژوورەوەی Apple. وشەی نهێنی هەڵناگیرێت. Apple ڕەنگە کۆد بخوازێت.", "Bi HTTPS ji servera Mirsa re ji bo têketina Apple tê şandin. Şîfre nayê tomarkirin. Dibe ku Apple kodê bixwaze."))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
            Button { signIn() } label: { Text(t("Sign in", "تسجيل الدخول", "چوونەژوورەوە", "Têkeve")).frame(maxWidth: .infinity) }
                .buttonStyle(.mirsaPrimary)
                .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || busy != nil)
        }
        .padding(MirsaSpacing.card).frame(maxWidth: .infinity, alignment: .leading).mirsaCard()
    }

    @ViewBuilder private func signedInCards(_ a: MirsaStoreAccount) -> some View {
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

        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            Text(t("Search", "بحث", "گەڕان", "Lêgerîn")).font(MirsaFont.cardTitle).foregroundStyle(.white)
            HStack {
                TextField(t("App name", "اسم التطبيق", "ناوی ئەپ", "Navê sepanê"), text: $term)
                    .submitLabel(.search).onSubmit { search() }.focused($focus).fieldStyle()
            }
            Text(t("Search uses your Apple Account storefront.", "البحث بمتجر حساب Apple تبعك.",
                   "گەڕان لە ستۆری ئەکاونتی Apple ت دەکرێت.", "Lêgerîn li stoya hesabê Apple ye."))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
            Button { search() } label: { Text(t("Search", "بحث", "گەڕان", "Lêgerîn")).frame(maxWidth: .infinity) }
                .buttonStyle(.mirsaPrimary)
                .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty || busy != nil)
        }
        .padding(MirsaSpacing.card).frame(maxWidth: .infinity, alignment: .leading).mirsaCard()

        if searched && results.isEmpty && busy == nil {
            Text(t("No results in this country.", "ما في نتائج بهالدولة.", "لەم وڵاتەدا هیچ ئەنجامێک نییە.", "Li vî welatî encam tune."))
                .font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
        }
        ForEach(results) { app in resultCard(app) }
    }

    private func resultCard(_ app: MirsaStoreApp) -> some View {
        let free = app.price == 0
        let key = app.bundleID
        return VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: app.artworkURL)) { $0.resizable().scaledToFill() } placeholder: { MirsaPalette.cardRaised }
                    .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(MirsaFont.cardTitle).foregroundStyle(.white).lineLimit(2)
                    Text("\(app.bundleID) · \(app.version)").font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary).lineLimit(1)
                    Text(free ? t("Free", "مجاني", "بێبەرامبەر", "Belaş")
                              : t("Paid: cannot be bought here", "مدفوع: ما بينشترى هون", "پارەدار: لێرە ناکڕدرێت", "Bi pere: li vir nayê kirîn"))
                        .font(MirsaFont.badge).foregroundStyle(free ? MirsaPalette.success : MirsaPalette.warning)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Button { acquire(app) } label: { Text(t("Get free license", "احصل على ترخيص مجاني", "مۆڵەتی بێبەرامبەر وەربگرە", "Lîsansa belaş bigire")).frame(maxWidth: .infinity) }
                    .buttonStyle(.mirsaSecondary).disabled(!free || busy != nil)
                Text(t("Only if this account never got the app. Adds it to your Apple Account; costs nothing.",
                       "بس إذا حسابك ما حصل عالتطبيق قبل. بيضيفو لحساب Apple تبعك وبلا مصاري.",
                       "تەنها ئەگەر ئەم ئەکاونتە پێشتر ئەپەکەی نەهێنابێت. دەیخاتە ئەکاونتی Apple ت بێ پارە.",
                       "Tenê heke ev hesab berê sepan negirtibe. Li hesabê Apple zêde dike, bêpere."))
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Button { loadVersions(app) } label: { Text(t("Older versions", "نسخ أقدم", "وەشانە کۆنەکان", "Guhertoyên kevn")).frame(maxWidth: .infinity) }
                    .buttonStyle(.mirsaSecondary).disabled(busy != nil)
                Text(t("Optional. Lists official Apple external version IDs, not human version names. The account must own the app. Leave empty for latest.",
                       "اختياري. هاي أرقام نسخ Apple الرسمية مو أسماء النسخ. لازم حسابك يملك التطبيق. اتركو فاضي للأحدث.",
                       "ئارەزوومەندانە. ناسنامە فەرمییەکانی وەشانی Apple نیشان دەدات نەک ناو. دەبێت خاوەنی ئەپەکە بیت. بەتاڵی بهێڵە بۆ نوێترین.",
                       "Bijarte. ID-yên fermî yên Apple ne, ne navên guhertoyan. Divê hesab xwedî be. Ji bo herî nû vala bihêle."))
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                if let list = versions[key] {
                    if list.isEmpty {
                        Text(t("Apple returned no versions.", "Apple ما رجّعت نسخ.", "Apple هیچ وەشانێکی نەگەڕاندەوە.", "Apple guhertoyek neda."))
                            .font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning)
                    } else {
                        let visible = Array(list.prefix(metadataLimit[key] ?? 20))
                        Picker("", selection: Binding(get: { chosen[key] ?? "" }, set: { chosen[key] = $0.isEmpty ? nil : $0; manualID[key] = "" })) {
                            Text(t("Latest", "الأحدث", "نوێترین", "Ya herî nû")).tag("")
                            ForEach(visible, id: \.self) { id in Text(versionLabel(app, id)).tag(id) }
                        }.pickerStyle(.menu).tint(MirsaPalette.accentSoft)
                        if visible.count < list.count {
                            Button(t("Show 20 more versions", "عرض 20 نسخة كمان", "٢٠ وەشانی تریش نیشان بدە", "20 guhertoyên din nîşan bide")) {
                                let next = min(list.count, visible.count + 20)
                                metadataLimit[key] = next
                                requestMetadata(app, ids: Array(list.prefix(next).suffix(20)))
                            }.buttonStyle(.mirsaSecondary)
                        }
                        Text(t("Version names come from Apple's official metadata. While loading or unavailable, External ID is shown. Downloads do not wait for names.",
                               "أسماء النسخ من بيانات Apple الرسمية. إذا الاسم عم يتحمّل أو مو متاح بيظهر رقم النسخة الخارجي. التنزيل ما بينتظر الاسم.",
                               "ناوی وەشان لە زانیارییە فەرمییەکانی Apple دێت. لە بارکردن یان نەبووندا ناسنامەی دەرەکی نیشان دەدرێت. داگرتن چاوەڕێی ناو ناکات.",
                               "Navên guhertoyan ji metadata fermî ya Apple ne. Dema barkirinê an ne berdest be ID ya derveyî tê nîşandan. Daxistin li navan nasekine."))
                            .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                    }
                }
                TextField(t("Version ID (optional)", "رقم النسخة (اختياري)", "ناسنامەی وەشان (ئارەزوومەندانە)", "ID ya guhertoyê (bijarte)"),
                          text: Binding(get: { manualID[key] ?? "" }, set: { v in
                              let d = String(v.filter { $0.isASCII && $0.isNumber }.prefix(20)); manualID[key] = d; chosen[key] = d.isEmpty ? nil : d }))
                    .keyboardType(.numberPad).focused($focus).fieldStyle()
            }
            VStack(alignment: .leading, spacing: 4) {
                Button { download(app) } label: {
                    HStack { Image(systemName: "arrow.down.circle"); Text(t("Download", "تنزيل", "داگرتن", "Daxe")) }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.mirsaPrimary).disabled(busy != nil)
                Text(t("Needs this account to own the app. Saved unchanged in the App Store tab.",
                       "لازم الحساب يملك التطبيق. بينحفظ متل ما هو بتبويب متجر أبل.",
                       "پێویستە ئەکاونتەکە خاوەنی ئەپەکە بێت. وەک خۆی لە بەشی فرۆشگای ئەپڵ هەڵدەگیرێت.",
                       "Divê hesab xwediyê sepanê be. Wekî xwe li Firoşgeha Apple tê tomarkirin."))
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
            }
        }
        .padding(MirsaSpacing.card).frame(maxWidth: .infinity, alignment: .leading).mirsaCard()
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
        let c = code
        let secret = password
        password = ""; code = ""
        run(t("Verifying…", "عم نتحقق…", "پشتڕاستکردنەوە…", "Piştrastkirin…")) {
            switch try await client.verify(code: c, password: secret) {
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

    private func search() {
        let q = term.trimmingCharacters(in: .whitespaces)
        run(t("Searching…", "عم نبحث…", "گەڕان…", "Lêgerîn…")) {
            let found = try await client.search(term: q, limit: 25)
            results = found; searched = true
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
            requestMetadata(app, ids: Array(ids.prefix(20)))
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
            var remaining = ids
            // At most six metadata requests for the visible batch, never all catalog versions.
            for attempt in 0..<6 {
                guard !Task.isCancelled, generation == operationGeneration, !remaining.isEmpty else { return }
                do {
                    let entries = try await client.versionMetadata(app, externalVersionIDs: remaining)
                    guard !Task.isCancelled, generation == operationGeneration else { return }
                    for item in entries { metadata[key, default: [:]][item.externalVersionID] = item }
                    for id in remaining where !entries.contains(where: { $0.externalVersionID == id }) {
                        metadata[key, default: [:]][id] = .init(externalVersionID: id, status: "unavailable", version: nil)
                    }
                    remaining = remaining.filter { metadata[key]?[$0]?.status == "queued" }
                    if !remaining.isEmpty && attempt < 5 { try await Task.sleep(nanoseconds: 3_000_000_000) }
                } catch {
                    guard !Task.isCancelled, generation == operationGeneration else { return }
                    for id in remaining {
                        metadata[key, default: [:]][id] = .init(externalVersionID: id, status: "unavailable", version: nil)
                    }
                    return
                }
            }
            guard !Task.isCancelled, generation == operationGeneration else { return }
            for id in remaining {
                metadata[key, default: [:]][id] = .init(externalVersionID: id, status: "unavailable", version: nil)
            }
        }
    }

    private func codeReset() { code = "" }

    private func describe(_ error: Error) -> String {
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

private extension View {
    func fieldStyle() -> some View {
        self.padding(12).background(MirsaPalette.cardRaised, in: RoundedRectangle(cornerRadius: MirsaRadius.m, style: .continuous))
            .foregroundStyle(.white)
    }
}
