import SwiftUI

/// Own-account App Store downloads (no sharing, no decryption, no signing).
/// Self-contained: the host passes `onDownloaded` which must import the file into the
/// encrypted-IPA flow WITHOUT modifying it. After it returns normally this view removes
/// the file's private temp directory. Hook: AppStoreAccountView(onDownloaded: { url in ... }).
struct AppStoreAccountView: View {
    var onDownloaded: (URL) async throws -> Void

    private let client = MirsaStoreClient.shared
    @State private var account: MirsaStoreAccount?
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var needsCode = false
    @State private var country = "us"
    @State private var term = ""
    @State private var results: [MirsaStoreApp] = []
    @State private var searched = false
    @State private var busy: String?
    @State private var work: Task<Void, Never>?
    @State private var notice: String?
    @State private var versions: [String: [String]] = [:]
    @State private var chosen: [String: String] = [:]
    @State private var manualID: [String: String] = [:]
    @State private var showSteps = false
    @State private var confirmSignOut = false
    @FocusState private var focus: Bool

    private func t(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String { tr(en, ar, ckb: ckb, kmr: kmr) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MirsaSpacing.m) {
                Text(t("My App Store", "حسابي بالـApp Store", "ئەپستۆری من", "App Store ya min"))
                    .font(MirsaFont.pageTitle).foregroundStyle(.white)
                infoCard
                if let account { signedInCards(account) } else { signInCard }
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
        .onDisappear { password = ""; code = "" }
        .alert(t("Notice", "تنبيه", "ئاگاداری", "Agahdarî"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(t("OK", "تمام", "باشە", "Baş e")) { notice = nil }
        } message: { Text(notice ?? "") }
        .confirmationDialog(t("Sign out of this Apple Account?", "تطلع من حساب Apple؟", "لە ئەکاونتی Apple بچیتە دەرەوە؟", "Ji hesabê Apple derkevî?"),
                            isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(t("Sign out", "تسجيل الخروج", "چوونە دەرەوە", "Derkeve"), role: .destructive) { signOut() }
            Button(t("Cancel", "إلغاء", "هەڵوەشاندنەوە", "Betal"), role: .cancel) {}
        } message: {
            Text(t("Your saved login is deleted from this iPhone. Downloaded IPAs stay.",
                   "بينمسح دخولك المحفوظ من هالآيفون. ملفات IPA يلي نزلتها بتضل.",
                   "چوونەژوورەوە پاشەکەوتکراوەکەت لەم ئایفۆنە دەسڕدرێتەوە. IPAە داگیراوەکان دەمێنن.",
                   "Têketina te ya tomarkirî ji vê iPhone tê jêbirin. IPAyên daketî dimînin."))
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
                    step("1", t("Sign in with your Apple Account. Login secrets stay in this device’s protected Keychain and are sent only to Apple.",
                                "سجّل دخول بحساب Apple. بيانات الدخول بتضل بس بسلسلة المفاتيح المحمية عهالجهاز وبتنبعت لـApple بس.",
                                "بە ئەکاونتی Apple بچۆ ژوورەوە. زانیارییە نهێنییەکان تەنها لە Keychainی پارێزراوی ئەم ئامێرە هەڵدەگیرێن و بۆ Apple دەنێردرێن.",
                                "Bi hesabê Apple têkeve. Agahiyên têketinê tenê di Keychaina parastî ya vî amûrî de dimînin û tenê ji Apple re tên şandin."))
                    step("2", t("If Apple asks, type the 6-digit code it sends to your devices.",
                                "إذا طلبت Apple، اكتب الرمز من 6 أرقام يلي بيوصلك.",
                                "ئەگەر Apple داوای کرد، کۆدی ٦ ژمارەیی بنووسە کە بۆت دێت.",
                                "Heke Apple bixwaze, koda 6 hejmarî ya ku jî re tê binivîse."))
                    step("3", t("Search an app. Pick the store country if it is not found.",
                                "دوّر على تطبيق. غيّر دولة المتجر إذا ما انلقى.",
                                "ئەپێک بگەڕێ. ئەگەر نەدۆزرایەوە وڵاتی ستۆر بگۆڕە.",
                                "Sepanekê bigere. Heke nehat dîtin welatê stoyê biguherîne."))
                    step("4", t("Free apps you never got: tap Get free license once. Paid apps are never bought here.",
                                "تطبيقات مجانية ما حصلت عليها: دوس احصل على ترخيص مجاني مرة وحدة. التطبيقات المدفوعة ما بتنشترى هون.",
                                "ئەپە بێبەرامبەرەکان کە نەتهێناون: جارێک مۆڵەتی بێبەرامبەر بهێنە. ئەپی پارەدار لێرە ناکڕدرێت.",
                                "Sepanên belaş ên te negirtine: carekê lîsansa belaş bigire. Sepanên bi pere li vir nayên kirîn."))
                    step("5", t("Download. Mirsa keeps the original file and adds it to the encrypted list.",
                                "نزّل. مرسى بيحتفظ بالملف الأصلي وبيضيفو لقائمة المشفّرة.",
                                "دایبگرە. Mirsa فایلە ڕەسەنەکە دەپارێزێت و دەیخاتە لیستی شفرەکراو.",
                                "Daxe. Mirsa pelê resen diparêze û li lîsteya şîfrekirî zêde dike."))
                    Text(t("Limits: a downloaded file does not mean it will install or open. Older versions depend on Apple, and the app must belong to this Apple Account. Do not share these files; they are tied to your account.",
                           "حدود: نزول الملف ما يعني إنه رح يتثبت أو يفتح. النسخ القديمة بتتوقف على Apple، والتطبيق لازم يكون على حسابك. لا تشارك هالملفات لأنها مربوطة بحسابك.",
                           "سنوور: داگرتنی فایل مانای ئەوە نییە دامەزرێت یان بکرێتەوە. وەشانە کۆنەکان بە Apple ەوە بەستراون و ئەپەکە دەبێت هی ئەم ئەکاونتە بێت. ئەم فایلانە بڵاو مەکەرەوە، بە ئەکاونتەکەتەوە بەستراون.",
                           "Sînor: daketina pelê nayê wê wateyê ku dê saz bibe an vebe. Guhertoyên kevn bi Apple ve girêdayî ne û sepan divê yê vî hesabî be. Van pelan parve neke, bi hesabê te ve girêdayî ne."))
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

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            Text(needsCode ? t("Verification code", "رمز التحقق", "کۆدی پشتڕاستکردنەوە", "Koda piştrastkirinê")
                           : t("Apple Account", "حساب Apple", "ئەکاونتی Apple", "Hesabê Apple"))
                .font(MirsaFont.cardTitle).foregroundStyle(.white)
            if needsCode {
                Text(t("Apple sent a 6-digit code to your devices. Type it here.",
                       "Apple بعتتلك رمز من 6 أرقام عأجهزتك. اكتبو هون.",
                       "Apple کۆدێکی ٦ ژمارەیی بۆ ئامێرەکانت ناردووە. لێرە بینووسە.",
                       "Apple koda 6 hejmarî şand cihazên te. Li vir binivîse."))
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                TextField("000000", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .focused($focus).fieldStyle()
                    .onChange(of: code) { _, v in code = String(v.filter(\.isNumber).prefix(6)) }
                Button { submitCode() } label: { Text(t("Verify", "تحقق", "پشتڕاستکردنەوە", "Piştrast bike")).frame(maxWidth: .infinity) }
                    .buttonStyle(.mirsaPrimary).disabled(code.count != 6 || busy != nil)
                Text(t("Same sign-in session. Three tries, then start again.", "نفس جلسة الدخول. 3 محاولات ثم ابدأ من جديد.",
                       "هەمان دانیشتن. سێ هەوڵ، دواتر دووبارە دەست پێبکە.", "Heman danişîn. Sê hewil, paşê ji nû ve dest pê bike."))
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                Button(t("Start over", "ابدأ من جديد", "دووبارە دەستپێکردن", "Ji nû ve")) { needsCode = false; code = "" }
                    .buttonStyle(.mirsaSecondary)
            } else {
                TextField(t("Apple Account email", "إيميل حساب Apple", "ئیمەیڵی ئەکاونتی Apple", "E-nameya hesabê Apple"), text: $email)
                    .keyboardType(.emailAddress).textContentType(.username).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().focused($focus).fieldStyle()
                SecureField(t("Password", "كلمة السر", "وشەی نهێنی", "Şîfre"), text: $password)
                    .textContentType(.password).focused($focus).fieldStyle()
                Text(t("Sent only to Apple. Saved only in this device’s protected Keychain.", "بتنبعت لـApple بس. بتنحفظ بس بسلسلة المفاتيح المحمية عهالجهاز.",
                       "تەنها بۆ Apple دەنێردرێت. تەنها لە Keychainی پارێزراوی ئەم ئامێرە هەڵدەگیرێت.", "Tenê ji Apple re tê şandin. Tenê di Keychaina parastî ya vî amûrî de tê tomarkirin."))
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                Button { signIn() } label: { Text(t("Sign in", "تسجيل الدخول", "چوونەژوورەوە", "Têkeve")).frame(maxWidth: .infinity) }
                    .buttonStyle(.mirsaPrimary)
                    .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || busy != nil)
            }
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
                    .buttonStyle(.mirsaSecondary).disabled(busy != nil)
                Text(t("Sign out", "خروج", "دەرچوون", "Derkeve")).font(MirsaFont.badge).foregroundStyle(MirsaPalette.textTertiary)
            }
        }
        .padding(MirsaSpacing.card).mirsaCard()

        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            Text(t("Search", "بحث", "گەڕان", "Lêgerîn")).font(MirsaFont.cardTitle).foregroundStyle(.white)
            HStack {
                TextField(t("Country code (us, de, tr)", "رمز الدولة (us, de, tr)", "کۆدی وڵات (us, de, tr)", "Koda welat (us, de, tr)"), text: $country)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focus).fieldStyle()
                    .frame(width: 130)
                    .onChange(of: country) { _, v in country = String(v.lowercased().filter(\.isLetter).prefix(2)) }
                TextField(t("App name", "اسم التطبيق", "ناوی ئەپ", "Navê sepanê"), text: $term)
                    .submitLabel(.search).onSubmit { search() }.focused($focus).fieldStyle()
            }
            Text(t("The store country changes which apps and versions you can find.", "دولة المتجر بتغيّر التطبيقات والنسخ يلي بتلاقيها.",
                   "وڵاتی ستۆر دیاری دەکات چ ئەپ و وەشانێک دەدۆزیتەوە.", "Welatê stoyê diyar dike tu kîjan sepan û guhertoyan dibînî."))
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
            Button { search() } label: { Text(t("Search", "بحث", "گەڕان", "Lêgerîn")).frame(maxWidth: .infinity) }
                .buttonStyle(.mirsaPrimary)
                .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty || country.count != 2 || busy != nil)
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
                Text(t("Optional. Apple gives version IDs, not names, and may not allow old ones. Leave empty for the latest.",
                       "اختياري. Apple بتعطي أرقام نسخ مو أسماء، وممكن ما تسمح بالقديمة. اتركو فاضي للأحدث.",
                       "ئارەزوومەندانە. Apple ناسنامەی وەشان دەدات نەک ناو، و ڕەنگە کۆنەکان ڕێگەپێنەدات. بەتاڵی بهێڵەرەوە بۆ نوێترین.",
                       "Bijarte. Apple ID-yên guhertoyan dide, ne nav, û dibe ku yên kevn nede. Ji bo yê herî nû vala bihêle."))
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                if let list = versions[key] {
                    if list.isEmpty {
                        Text(t("Apple returned no versions.", "Apple ما رجّعت نسخ.", "Apple هیچ وەشانێکی نەگەڕاندەوە.", "Apple guhertoyek neda."))
                            .font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning)
                    } else {
                        Picker("", selection: Binding(get: { chosen[key] ?? "" }, set: { chosen[key] = $0.isEmpty ? nil : $0; manualID[key] = "" })) {
                            Text(t("Latest", "الأحدث", "نوێترین", "Ya herî nû")).tag("")
                            ForEach(list.reversed(), id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.menu).tint(MirsaPalette.accentSoft)
                    }
                }
                TextField(t("Version ID (optional)", "رقم النسخة (اختياري)", "ناسنامەی وەشان (ئارەزوومەندانە)", "ID ya guhertoyê (bijarte)"),
                          text: Binding(get: { manualID[key] ?? "" }, set: { v in
                              let d = String(v.filter(\.isNumber).prefix(12)); manualID[key] = d; chosen[key] = d.isEmpty ? nil : d }))
                    .keyboardType(.numberPad).focused($focus).fieldStyle()
            }
            VStack(alignment: .leading, spacing: 4) {
                Button { download(app) } label: {
                    HStack { Image(systemName: "arrow.down.circle"); Text(t("Download", "تنزيل", "داگرتن", "Daxe")) }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.mirsaPrimary).disabled(busy != nil)
                Text(t("Needs this account to own the app. Saved unchanged into the encrypted list.",
                       "لازم الحساب يملك التطبيق. بينحفظ متل ما هو بقائمة المشفّرة.",
                       "پێویستە ئەکاونتەکە خاوەنی ئەپەکە بێت. وەک خۆی لە لیستی شفرەکراو هەڵدەگیرێت.",
                       "Divê hesab xwediyê sepanê be. Wekî xwe li lîsteya şîfrekirî tê tomarkirin."))
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
        work = Task {
            do { try await op() }
            catch is CancellationError {}
            catch { notice = describe(error) }
            busy = nil; work = nil
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
        code = ""
        run(t("Verifying…", "عم نتحقق…", "پشتڕاستکردنەوە…", "Piştrastkirin…")) {
            switch try await client.verify(code: c) {
            case .signedIn(let a): account = a; needsCode = false; email = ""
            case .verificationRequired: notice = t("The code was not accepted. Try again.", "الرمز ما انقبل. جرّب مرة ثانية.", "کۆدەکە وەرنەگیرا. دووبارە هەوڵ بدەرەوە.", "Kod nehat pejirandin. Dîsa biceribîne.")
            }
        }
    }

    private func signOut() {
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
        let c = country
        run(t("Searching…", "عم نبحث…", "گەڕان…", "Lêgerîn…")) {
            let found = try await client.search(term: q, country: c, limit: 25)
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
            versions[app.bundleID] = try await client.availableVersions(app)
        }
    }

    private func download(_ app: MirsaStoreApp) {
        let version = chosen[app.bundleID]
        run(t("Downloading from Apple…", "عم نزّل من Apple…", "لە Apple دادەگیرێت…", "Ji Apple tê daxistin…")) {
            let url = try await client.downloadOwnedApp(app, externalVersionID: version)
            let dir = url.deletingLastPathComponent()
            try await onDownloaded(url)
            // Only after the host copied it successfully: remove the private temp directory.
            // Parent is deleted only if it is a UUID-named direct child of the temp directory.
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("MirsaStore", isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
            let parent = dir.standardizedFileURL.resolvingSymlinksInPath()
            if parent.deletingLastPathComponent() == tmp, UUID(uuidString: parent.lastPathComponent) != nil {
                try? FileManager.default.removeItem(at: dir)
            } else { try? FileManager.default.removeItem(at: url) }
            notice = t("Saved to your encrypted list, unchanged.", "انحفظ بقائمة المشفّرة متل ما هو.",
                       "وەک خۆی لە لیستی شفرەکراو هەڵگیرا.", "Wekî xwe li lîsteya şîfrekirî hat tomarkirin.")
        }
    }

    private func describe(_ error: Error) -> String {
        guard let e = error as? MirsaStoreError else {
            return t("Something went wrong. Check your connection and try again.", "صار خطأ. تأكد من الإنترنت وجرّب.",
                     "هەڵەیەک ڕوویدا. ئینتەرنێتەکەت بپشکنە و دووبارە هەوڵ بدە.", "Çewtiyek çêbû. Girêdana înternetê kontrol bike û dîsa biceribîne.")
        }
        switch e {
        case .busy: return t("Another App Store task is still running.", "في مهمة App Store ثانية لسا شغالة.", "کارێکی تری App Store هێشتا کار دەکات.", "Karekî din ê App Store hê dixebite.")
        case .signedOut: return t("Sign in first.", "سجّل دخول أول.", "سەرەتا بچۆ ژوورەوە.", "Pêşî têkeve.")
        case .verificationRequired: return t("Enter the 6-digit code from Apple.", "اكتب الرمز من 6 أرقام من Apple.", "کۆدی ٦ ژمارەیی Apple بنووسە.", "Koda 6 hejmarî ya Apple binivîse.")
        case .invalidInput: return t("Check the email, country, app or version ID.", "تأكد من الإيميل والدولة والتطبيق أو رقم النسخة.", "ئیمەیڵ، وڵات، ئەپ یان ناسنامەی وەشان بپشکنە.", "E-name, welat, sepan an ID ya guhertoyê kontrol bike.")
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
