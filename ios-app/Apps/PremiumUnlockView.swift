import SwiftUI

/// Premium Unlock (فك المميزات): pick one of the user's own App Store IPAs,
/// scan its binary for client-side premium checks, inject MirsaUnlock and
/// install the unlocked copy. With a preselected entry the pick screen is
/// skipped and the scan starts immediately.
struct PremiumUnlockView: View {
    let preselected: EncryptedIPAEntry?
    let vm: AppViewModel?

    @StateObject private var store = PremiumUnlockStore()
    @ObservedObject private var library = EncryptedAppsStore.shared
    @ObservedObject private var patterns = PremiumPatternStore.shared
    @ObservedObject private var history = PremiumUnlockHistory.shared
    @Environment(\.dismiss) private var dismiss
    @State private var didAutoScan = false
    @State private var showTrace = false

    init(preselected: EncryptedIPAEntry? = nil, vm: AppViewModel? = nil) {
        self.preselected = preselected
        self.vm = vm
    }

    private func t(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String {
        tr(en, ar, ckb: ckb, kmr: kmr)
    }

    private var title: String { t("Premium Unlock", "فك المميزات", "کردنەوەی پرێمیۆم", "Premium Vekirin") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MirsaSpacing.m) {
                    switch store.step {
                    case .idle:
                        if preselected == nil { pickScreen } else { scanningScreen }
                    case .scanning:
                        scanningScreen
                    case .report:
                        reportScreen
                    case .unlocking:
                        unlockingScreen
                    case .done:
                        doneScreen
                    }
                    if let error = store.error {
                        Text(error)
                            .font(MirsaFont.caption)
                            .foregroundStyle(MirsaPalette.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(MirsaSpacing.card)
                            .appsGlass(cornerRadius: MirsaRadius.m)
                    }
                }
                .padding(MirsaSpacing.page)
                .padding(.bottom, MirsaSpacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(t("Close", "إغلاق", "داخستن", "Bigire"))
                }
            }
            .mirsaScreen()
            .task {
                // Non-blocking: newest scan patterns in the background.
                patterns.refreshInBackground()
                guard let entry = preselected, !didAutoScan else { return }
                didAutoScan = true
                await store.scan(entry: entry)
            }
            .sheet(isPresented: $showTrace) { PremiumTraceSheet(store: store) }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: - 1. Pick an app

    private var pickScreen: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.m) {
            Text(t("Only apps you bought yourself can be decrypted and unlocked. Pick one to scan.",
                   "بس التطبيقات يلي اشتريتها بنفسك فينا نفك تشفيرها ونفك مميزاتها. اختار واحد للفحص.",
                   "تەنها ئەو ئەپانەی خۆت کڕیوتە دەتوانرێت ڕەمز بکرێنەوە و پرێمیۆمەکەیان بکرێتەوە. یەکێک هەڵبژێرە بۆ پشکنین.",
                   "Tenê sepanên ku te bi xwe kirîne dikarin werin vekirin. Yekê ji bo kontrolê hilbijêre."))
                .font(MirsaFont.secondary)
                .foregroundStyle(MirsaPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if library.entries.isEmpty {
                Text(t("No App Store IPAs yet. Import one from the Downloads tab first.",
                       "لسّا ما في IPA من App Store. استورد واحد من تبويب التنزيلات أولاً.",
                       "هێشتا هیچ IPAیەکی App Store نییە. سەرەتا یەکێک لە بەشی داگرتنەکان هاوردە بکە.",
                       "Hêj IPA ya App Store tune. Pêşî yekê ji tabloya Daxistinan bîne."))
                    .font(MirsaFont.secondary)
                    .foregroundStyle(MirsaPalette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(MirsaSpacing.card)
                    .appsGlass(cornerRadius: MirsaRadius.l)
            }
            ForEach(library.entries) { entry in
                HStack(spacing: MirsaSpacing.s) {
                    Group {
                        if let img = library.icon(entry) { Image(uiImage: img).resizable().scaledToFill() }
                        else { Image(systemName: "app.dashed").foregroundStyle(MirsaPalette.textTertiary) }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: MirsaRadius.icon, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).font(MirsaFont.cardTitle).foregroundStyle(.white).lineLimit(1)
                        Text(entry.version).font(MirsaFont.caption).foregroundStyle(MirsaPalette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        Task { await store.scan(entry: entry) }
                    } label: {
                        Label(t("Scan", "فحص", "پشکنین", "Kontrol bike"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.mirsaSecondary)
                    .controlSize(.small)
                    .disabled(library.busy != nil)
                    .accessibilityIdentifier("premium-unlock-scan")
                }
                .padding(MirsaSpacing.card)
                .appsGlass(cornerRadius: MirsaRadius.l)
            }
            patternUpdateRow
            if !history.entries.isEmpty {
                historySection
            }
        }
    }

    // MARK: - 2. Scanning

    private var scanningScreen: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.m) {
            if let entry = store.selectedEntry ?? preselected {
                Text(entry.name)
                    .font(MirsaFont.cardTitle)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: MirsaSpacing.s) {
                ForEach(Array(PremiumUnlockStore.scanSteps.enumerated()), id: \.offset) { i, s in
                    let done = store.progress >= Double(i + 1) * 0.25
                    let active = !done && store.progress >= Double(i) * 0.25
                    HStack(spacing: MirsaSpacing.s) {
                        if done {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(MirsaPalette.success)
                        } else if active {
                            ProgressView().tint(MirsaPalette.accentSoft)
                        } else {
                            Image(systemName: "circle").foregroundStyle(MirsaPalette.textTertiary)
                        }
                        Text(tr(s.0, s.1, ckb: s.2, kmr: s.3))
                            .font(MirsaFont.body)
                            .foregroundStyle(done || active ? .white : MirsaPalette.textSecondary)
                    }
                }
            }
            .padding(MirsaSpacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appsGlass(cornerRadius: MirsaRadius.l)
            ProgressView(value: store.progress)
                .tint(MirsaPalette.accent)
        }
    }

    // MARK: - 3. Report

    private var reportScreen: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.m) {
            if let entry = store.selectedEntry {
                Text(entry.name)
                    .font(MirsaFont.cardTitle)
                    .foregroundStyle(.white)
            }
            if let rep = store.report {
                HStack(spacing: MirsaSpacing.xs) {
                    chip(text: "\(rep.unlockableCount) " + t("unlockable", "قابلة للفتح", "دەکرێتەوە", "dikare were vekirin"),
                         color: MirsaPalette.success)
                    if rep.limitCount > 0 {
                        chip(text: "\(rep.limitCount) " + t("usage limit", "حد استخدام", "سنووری بەکارهێنان", "sînorê bikaranînê"),
                             color: MirsaPalette.warning)
                    }
                    chip(text: "\(rep.serverCount) " + t("server-side", "سيرفر", "سێرڤەر", "server"),
                         color: MirsaPalette.danger)
                    if rep.hasAds {
                        chip(text: "\(rep.adsCount) " + t("ads", "إعلانات", "ڕیکلام", "reklam"),
                             color: MirsaPalette.warning)
                    }
                }
                ForEach(rep.findings) { f in
                    HStack(alignment: .top, spacing: MirsaSpacing.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name).font(MirsaFont.body).foregroundStyle(.white)
                            Text(f.detail).font(MirsaFont.caption).foregroundStyle(MirsaPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        badge(for: f)
                    }
                    .padding(MirsaSpacing.card)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appsGlass(cornerRadius: MirsaRadius.l)
                }
                if rep.hasAds {
                    adsFallbackSection(rep: rep)
                }
                if !store.detectedFeatures.isEmpty {
                    featuresSection(rep: rep)
                }
                if store.enabledUnlockableCount > 0 {
                    Button {
                        if let entry = store.selectedEntry {
                            Task { await store.unlock(entry: entry) }
                        }
                    } label: {
                        Text(t("Unlock Premium (\(store.enabledUnlockableCount))", "فك المميزات (\(store.enabledUnlockableCount))",
                               "پرێمیۆم بکەرەوە (\(store.enabledUnlockableCount))", "Premium veke (\(store.enabledUnlockableCount))"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.mirsaPrimary)
                    .controlSize(.large)
                    .accessibilityIdentifier("premium-unlock-go")
                } else if !rep.hasAds {
                    // Nothing unlockable and no ads either: keep the
                    // disabled button so the state stays visible.
                    Button {} label: {
                        Text(t("Unlock Premium (\(store.enabledUnlockableCount))", "فك المميزات (\(store.enabledUnlockableCount))",
                               "پرێمیۆم بکەرەوە (\(store.enabledUnlockableCount))", "Premium veke (\(store.enabledUnlockableCount))"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.mirsaPrimary)
                    .controlSize(.large)
                    .disabled(true)
                    .accessibilityIdentifier("premium-unlock-go")
                }
                // Live tracing: when the static scan found nothing to
                // hook (custom / obfuscated code), watch the app while
                // it runs and learn the premium check from its calls.
                Button {
                    if let entry = store.selectedEntry {
                        Task { await store.startTracing(entry: entry) }
                    }
                } label: {
                    Label(t("Live tracing", "تتبع حي",
                            "شوێنکەوتنی زیندوو", "Şopandina zindî"),
                          systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.mirsaSecondary)
                .controlSize(.large)
                .accessibilityIdentifier("premium-unlock-trace-go")
                Text(t("Nothing found to hook? Trace the app live: open the paid feature while tracing runs, then paste the trace back here.",
                       "ما لقينا شي نعلّق عليه؟ تتبّع التطبيق مباشرة: افتح الميزة المدفوعة والتتبع شغال، بعدين الصق التتبع هون.",
                       "هیچ شتێک نەدۆزرایەوە بۆ هۆککردن؟ ئەپەکە بە زیندوویی شوێن بکەوە: تایبەتمەندییە پارەییەکە بکەرەوە لە کاتی شوێنکەوتن، پاشان شوێنکەوتنەکە لێرە بلکێنە.",
                       "Tişt nehat dîtin ku hook lê were kirin? Sepanê zindî bişopîne: taybetmendiya dravî veke dema şopandin dixebite, paşê şopandinê li vir bîne."))
                    .font(MirsaFont.caption)
                    .foregroundStyle(MirsaPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                patternUpdateRow
            }
        }
    }

    /// One toggle row per detected extra feature (usage limits, paywall
    /// skip, tracking block, …), enabled by default when detected, plus
    /// the "try all" (aggressive) mode toggle. One injection applies
    /// premium + limits + ads + every toggled-on feature together.
    private func featuresSection(rep: PremiumScanner.Report) -> some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            Text(t("Features to apply", "الميزات يلي بدك تطبقها",
                   "ئەو تایبەتمەندییانەی دەتەوێت جێبەجێی بکەیت", "Taybetmendiyên ku dixwazî bicîh bînî"))
                .font(MirsaFont.cardTitle)
                .foregroundStyle(.white)
            ForEach(store.detectedFeatures, id: \.self) { id in
                let count = rep.findings.filter { $0.kind.rawValue == id }.count
                Toggle(isOn: Binding(
                    get: { store.featureEnabled[id] ?? true },
                    set: { store.featureEnabled[id] = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PremiumUnlockStore.featureName(id))
                            .font(MirsaFont.body)
                            .foregroundStyle(.white)
                        Text("\(count) " + t("finding", "نتيجة", "ئەنجام", "encam"))
                            .font(MirsaFont.caption)
                            .foregroundStyle(MirsaPalette.textSecondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(MirsaPalette.accent)
                .disabled(store.aggressive)
            }
            Toggle(isOn: $store.aggressive) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Try-all mode", "وضع جرّب الكل",
                           "دۆخی هەمووی تاقی بکەرەوە", "Moda hemûyan biceribîne"))
                        .font(MirsaFont.body)
                        .foregroundStyle(.white)
                    Text(t("Turns on every detected hook and every built-in feature, even undetected ones.",
                           "بيشغّل كل الخطافات المكتشفة وكل الميزات المدمجة، حتى يلي ما انكشفت.",
                           "هەموو هۆکە دۆزراوەکان و هەموو تایبەتمەندییە بنیادنراوەکان چالاک دەکات، تەنانەت ئەوانەشی نەدۆزراونەتەوە.",
                           "Hemû hookên hatine dîtin û hemû taybetmendiyên çêkirî vedike, yên ku nehatine dîtin jî."))
                        .font(MirsaFont.caption)
                        .foregroundStyle(MirsaPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .tint(MirsaPalette.accent)
        }
        .padding(MirsaSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appsGlass(cornerRadius: MirsaRadius.l)
    }

    /// Unlock history (سجل الفك): past unlocks, newest first, stored
    /// locally as JSON. Shown on the pick screen.
    private var historySection: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            HStack(spacing: MirsaSpacing.s) {
                Text(t("Unlock history", "سجل الفك",
                       "مێژووی کردنەوە", "Dîroka vekirinê"))
                    .font(MirsaFont.cardTitle)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Button {
                    history.clear()
                } label: {
                    Label(t("Clear", "مسح", "سڕینەوە", "Paqij bike"), systemImage: "trash")
                }
                .buttonStyle(.mirsaSecondary)
                .controlSize(.small)
            }
            ForEach(history.entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: MirsaSpacing.s) {
                        Text(entry.appName)
                            .font(MirsaFont.body)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(MirsaFont.caption)
                            .foregroundStyle(MirsaPalette.textSecondary)
                    }
                    Text(entry.applied.joined(separator: "، "))
                        .font(MirsaFont.caption)
                        .foregroundStyle(MirsaPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(MirsaSpacing.card)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appsGlass(cornerRadius: MirsaRadius.l)
            }
        }
    }

    /// Names of the detected ad SDKs, e.g. "AdMob، Unity Ads".
    private func adSDKNames(rep: PremiumScanner.Report) -> String {
        rep.findings.filter { $0.kind == .ads }.map(\.name).joined(separator: "، ")
    }

    /// Ad fallback. When nothing premium is unlockable it is the primary
    /// action (block + accelerate the ads instead); when premium IS
    /// unlockable it is an additional toggle — both can be applied in
    /// one injection.
    private func adsFallbackSection(rep: PremiumScanner.Report) -> some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            if rep.unlockableCount == 0 {
                Text(t("Premium can't be unlocked from the device — but ads can be blocked and sped up.",
                       "المميزات ما بتنفتح على السيرفر — بس فينا نحجب الإعلانات ونسرّعها.",
                       "پرێمیۆم لەسەر ئامێرەکە ناکرێتەوە — بەڵام دەتوانین ڕیکلام بلۆک بکەین و خێرای بکەین.",
                       "Premium ji cîhazê nayê vekirin — lê reklam dikarin werin astengkirin û bileztir kirin."))
                    .font(MirsaFont.body)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(adSDKNames(rep: rep))
                    .font(MirsaFont.caption)
                    .foregroundStyle(MirsaPalette.textSecondary)
                Button {
                    store.includeAds = true
                    if let entry = store.selectedEntry {
                        Task { await store.unlock(entry: entry) }
                    }
                } label: {
                    Text(t("Block ads & speed them up", "حجب الإعلانات + تسريعها",
                           "ڕیکلام بلۆک بکە و خێرای بکە", "Reklaman asteng bike û bileztir bike"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.mirsaPrimary)
                .controlSize(.large)
                .accessibilityIdentifier("premium-unlock-ads-go")
            } else {
                Toggle(isOn: $store.includeAds) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Block ads & speed them up", "حجب الإعلانات وتسريعها",
                               "ڕیکلام بلۆک بکە و خێرای بکە", "Reklaman asteng bike û bileztir bike"))
                            .font(MirsaFont.body)
                            .foregroundStyle(.white)
                        Text(adSDKNames(rep: rep))
                            .font(MirsaFont.caption)
                            .foregroundStyle(MirsaPalette.textSecondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(MirsaPalette.accent)
            }
        }
        .padding(MirsaSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appsGlass(cornerRadius: MirsaRadius.l)
    }

    /// Unobtrusive scan-patterns row: current version/date + a manual
    /// refresh. A background refresh also runs whenever this flow opens.
    private var patternUpdateRow: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.xs) {
            HStack(spacing: MirsaSpacing.s) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(MirsaPalette.textSecondary)
                Text(patterns.versionText)
                    .font(MirsaFont.caption)
                    .foregroundStyle(MirsaPalette.textSecondary)
                Spacer(minLength: 0)
                if patterns.isUpdating {
                    ProgressView().tint(MirsaPalette.accentSoft)
                } else {
                    Button {
                        patterns.refreshInBackground()
                    } label: {
                        Label(t("Update patterns", "تحديث الأنماط",
                               "نوێکردنەوەی نەخشەکان", "Nimûneyan nûve bike"),
                              systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.mirsaSecondary)
                    .controlSize(.small)
                    .accessibilityIdentifier("premium-patterns-update")
                }
            }
            if let updateError = patterns.updateError {
                Text(updateError)
                    .font(MirsaFont.caption)
                    .foregroundStyle(MirsaPalette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(MirsaSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appsGlass(cornerRadius: MirsaRadius.l)
    }

    private func chip(text: String, color: Color) -> some View {
        Text(text)
            .font(MirsaFont.badge)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func badge(for f: PremiumScanner.Finding) -> some View {
        let (text, color): (String, Color) = {
            if f.kind == .ads {
                return (t("Blockable", "قابلة للحجب", "دەتوانرێت بلۆک بکرێت", "Dikare were astengkirin"), MirsaPalette.warning)
            }
            if f.kind == .server {
                return (t("Server-side", "سيرفر", "سێرڤەر", "Server"), MirsaPalette.danger)
            }
            if f.kind == .limit {
                if f.unlockable {
                    return (t("Usage limit", "حد استخدام", "سنووری بەکارهێنان", "Sînorê bikaranînê"), MirsaPalette.success)
                }
                return (t("Limit text only", "نص حد فقط", "تەنها دەقی سنوور", "Tenê nivîsa sînor"), MirsaPalette.textTertiary)
            }
            if f.unlockable {
                return (t("Unlockable", "قابلة للفتح", "دەکرێتەوە", "Dikare were vekirin"), MirsaPalette.success)
            }
            return (t("Not unlockable", "غير قابلة للفتح", "ناکرێتەوە", "Nayê vekirin"), MirsaPalette.textTertiary)
        }()
        return Text(text)
            .font(MirsaFont.badge)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }

    // MARK: - 4. Unlocking → done

    private var unlockingScreen: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.m) {
            HStack(spacing: MirsaSpacing.s) {
                ProgressView().tint(MirsaPalette.accentSoft)
                Text(unlockingText)
                    .font(MirsaFont.body)
                    .foregroundStyle(.white)
            }
            .padding(MirsaSpacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appsGlass(cornerRadius: MirsaRadius.l)
            ProgressView(value: store.progress).tint(MirsaPalette.accent)
        }
    }

    /// "Blocking ads…" when the unlock is ads-only, otherwise the
    /// standard unlocking text. Tracing builds get their own line.
    private var unlockingText: String {
        if store.tracing {
            return t("Building the tracing version…", "عم نجهز نسخة التتبع…", "وەشانەکەی شوێنکەوتن دروست دەکرێت…", "Guhertoya şopandinê tê çêkirin…")
        }
        let adsOnly = store.appliedAds && (store.report?.unlockableCount == 0)
        if adsOnly {
            return t("Blocking ads…", "عم نحجب الإعلانات…", "ڕیکلام بلۆک دەکرێت…", "Reklam tên astengkirin…")
        }
        return t("Unlocking…", "عم نفك المميزات…", "پرێمیۆم دەکرێتەوە…", "Premium tê vekirin…")
    }

    /// Success title follows what was actually applied.
    private var doneTitle: String {
        if store.tracing {
            return t("Tracing version ready", "نسخة التتبع جاهزة",
                     "وەشانەکەی شوێنکەوتن ئامادەیە", "Guhertoya şopandinê amade ye")
        }
        let premium = store.report?.unlockableCount ?? 0
        if store.appliedAds && premium == 0 {
            return t("Ads blocked & sped up ✓", "تم حجب الإعلانات وتسريعها ✓",
                     "ڕیکلام بلۆک کرا و خێرا کرا ✓", "Reklam hatin astengkirin û bileztir kirin ✓")
        }
        if store.appliedAds {
            return t("Premium unlocked & ads blocked ✓", "تم فك المميزات وحجب الإعلانات ✓",
                     "پرێمیۆم کرایەوە و ڕیکلام بلۆک کرا ✓", "Premium hat vekirin û reklam hatin astengkirin ✓")
        }
        return t("Premium unlocked ✓", "تم فك المميزات ✓", "پرێمیۆم کرایەوە ✓", "Premium hat vekirin ✓")
    }

    private var doneScreen: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.m) {
            if store.tracing {
                tracingInstructionsCard
            }
            VStack(spacing: MirsaSpacing.s) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(MirsaPalette.success)
                Text(doneTitle)
                    .font(MirsaFont.sheetTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if let entry = store.selectedEntry {
                    Text(entry.name)
                        .font(MirsaFont.secondary)
                        .foregroundStyle(MirsaPalette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(MirsaSpacing.card)
            .appsGlass(cornerRadius: MirsaRadius.l)
            Button {
                Task {
                    if await store.installUnlocked(vm: vm ?? AppViewModel.shared) {
                        dismiss()
                    }
                }
            } label: {
                Label(t("Install", "تثبيت", "دامەزراندن", "Saz bike"), systemImage: "arrow.down.app.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.mirsaPrimary)
            .controlSize(.large)
            .disabled(store.installing)
            .accessibilityIdentifier("premium-unlock-install")
            if store.tracing {
                Button {
                    showTrace = true
                } label: {
                    Label(t("View trace", "عرض التتبع",
                            "پیشاندانی شوێنکەوتن", "Şopandinê nîşan bide"),
                          systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.mirsaSecondary)
                .controlSize(.large)
                .accessibilityIdentifier("premium-unlock-trace-view")
            }
        }
    }

    /// Tracing how-to shown on the tracing done screen: install, open
    /// the app, tap the paid feature, copy from the floating button,
    /// paste back here.
    private var tracingInstructionsCard: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            Text(t("How live tracing works", "كيف بيشتغل التتبع الحي",
                   "شوێنکەوتنی زیندوو چۆن کار دەکات", "Şopandina zindî çawa dixebite"))
                .font(MirsaFont.cardTitle)
                .foregroundStyle(.white)
            Text(t("1. Install this version and open the app.\n2. Tap the paid feature (the paywall, the locked button).\n3. Tap the floating \"● Trace\" button in the app, then \"Copy trace\".\n4. Come back here, tap \"View trace\", and paste.",
                   "١. ثبّت هالنسخة وافتح التطبيق.\n٢. اكبس الميزة المدفوعة (شاشة الدفع أو الزر المقفول).\n٣. اكبس زر \"● Trace\" العائم بالتطبيق، بعدين \"نسخ التتبع\".\n٤. ارجع لهون، اكبس \"عرض التتبع\"، والصق.",
                   "١. ئەم وەشانە دامەزرێنە و ئەپەکە بکەرەوە.\n٢. تایبەتمەندییە پارەییەکە دابگرە (شاشەی پارەدان یان دوگمە داخراوەکە).\n٣. دوگمەی \"● Trace\" لە ئەپەکە دابگرە، پاشان \"کۆپیکردنی شوێنکەوتن\".\n٤. بگەڕێرەوە بۆ ئێرە، \"پیشاندانی شوێنکەوتن\" دابگرە، و بلکێنە.",
                   "1. Vê guhertoyê saz bike û sepanê veke.\n2. Taybetmendiya dravî bitikîne (dîmendera dravdanê an bişkoka girtî).\n3. Bişkoka \"● Trace\" ya di sepanê de bitikîne, paşê \"Şopandinê kopî bike\".\n4. Vegere vir, \"Şopandinê nîşan bide\" bitikîne, û bîne."))
                .font(MirsaFont.body)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MirsaSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appsGlass(cornerRadius: MirsaRadius.l)
    }
}

/// Live-trace viewer sheet: paste the trace copied from the target
/// app's floating "● Trace" button, see the calls in order with the
/// strongest premium-check candidate highlighted, add hooks manually
/// (one tap per call) or from the AI suggestion, then re-inject with
/// the new hook. Nothing is added to the config without the user
/// confirming it here.
struct PremiumTraceSheet: View {
    @ObservedObject var store: PremiumUnlockStore
    @Environment(\.dismiss) private var dismiss
    @State private var addedSelectors: Set<String> = []
    @State private var aiAdded = false

    private func t(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String {
        tr(en, ar, ckb: ckb, kmr: kmr)
    }

    private var strongest: PremiumTrace.Entry? {
        PremiumTrace.strongestCandidate(in: store.traceEntries)
    }

    private func returnsLabel(_ returns: String) -> String {
        switch returns {
        case "yes": return "YES"
        case "no": return "NO"
        case "count": return "999"
        case "zero": return "0"
        case "future": return t("future date", "تاريخ بعيد", "بەرواری دوور", "dîroka dûr")
        case "noop": return "—"
        case "dismiss": return t("dismiss", "إغلاق", "داخستن", "bigire")
        default: return returns
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MirsaSpacing.m) {
                    pasteSection
                    aiSection
                    if store.traceEntries.isEmpty {
                        Text(t("No trace yet. In the app, tap the floating \"● Trace\" button, then \"Copy trace\", and paste it here.",
                               "لسّا ما في تتبع. بالتطبيق اكبس زر \"● Trace\" العائم، بعدين \"نسخ التتبع\"، والصق هون.",
                               "هێشتا هیچ شوێنکەوتنێک نییە. لە ئەپەکە دوگمەی \"● Trace\" دابگرە، پاشان \"کۆپیکردنی شوێنکەوتن\"، و لێرە بلکێنە.",
                               "Hêj şopandin tune. Di sepanê de bişkoka \"● Trace\" bitikîne, paşê \"Şopandinê kopî bike\", û li vir bîne."))
                            .font(MirsaFont.secondary)
                            .foregroundStyle(MirsaPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("\(store.traceEntries.count) " + t("calls recorded", "مكالمة مسجلة", "بانگکردن تۆمارکراوە", "bang hatine tomarkirin"))
                            .font(MirsaFont.cardTitle)
                            .foregroundStyle(.white)
                        ForEach(store.traceEntries) { entry in
                            traceRow(entry)
                        }
                    }
                    if !store.extraHooks.isEmpty {
                        Button {
                            if let entry = store.selectedEntry {
                                Task { await store.unlock(entry: entry) }
                                dismiss()
                            }
                        } label: {
                            Text(t("Re-inject with the new hook (\(store.extraHooks.count))", "أعد الحقن بالخطّافة الجديدة (\(store.extraHooks.count))",
                                   "دووبارە چەسپاندن بە هۆکە نوێیەکە (\(store.extraHooks.count))", "Ji nû ve bixe bi hook-a nû (\(store.extraHooks.count))"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.mirsaPrimary)
                        .controlSize(.large)
                        .accessibilityIdentifier("premium-trace-reinject")
                    }
                }
                .padding(MirsaSpacing.page)
                .padding(.bottom, MirsaSpacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(t("Live trace", "التتبع الحي", "شوێنکەوتنی زیندوو", "Şopandina zindî"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(t("Close", "إغلاق", "داخستن", "Bigire"))
                }
            }
            .mirsaScreen()
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            Button {
                _ = store.importTraceFromPasteboard()
            } label: {
                Label(t("Paste trace from clipboard", "لصق التتبع من الحافظة",
                        "شوێنکەوتنەکە لە کلیپبۆرد بلکێنە", "Şopandinê ji panoyê bîne"),
                      systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.mirsaPrimary)
            .controlSize(.large)
            .accessibilityIdentifier("premium-trace-paste")
            if let note = store.traceNote {
                Text(note)
                    .font(MirsaFont.caption)
                    .foregroundStyle(MirsaPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            Text(t("AI hook suggestion", "اقتراح الذكاء الاصطناعي",
                   "پێشنیاری زیرەکی دەستکرد", "Pêşniyara AI"))
                .font(MirsaFont.cardTitle)
                .foregroundStyle(.white)
            if let s = store.aiSuggestion {
                VStack(alignment: .leading, spacing: 2) {
                    Text("-[" + (s.className.isEmpty ? "?" : s.className) + " " + s.selector + "] → " + returnsLabel(s.returns))
                        .font(MirsaFont.body)
                        .foregroundStyle(.white)
                    if !s.reason.isEmpty {
                        Text(s.reason)
                            .font(MirsaFont.caption)
                            .foregroundStyle(MirsaPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button {
                    if store.addAISuggestion() { aiAdded = true }
                } label: {
                    Text(aiAdded || store.extraHooks.contains(where: { $0.selector == s.selector })
                         ? t("Hook added ✓", "تمت إضافة الخطّافة ✓", "هۆکەکە زیادکرا ✓", "Hook hat lêzêdekirin ✓")
                         : t("Add this hook", "أضِف هالخطّافة", "ئەم هۆکە زیاد بکە", "Vê hookê lê zêde bike"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.mirsaSecondary)
                .controlSize(.large)
                .disabled(aiAdded || store.extraHooks.contains(where: { $0.selector == s.selector }))
                .accessibilityIdentifier("premium-trace-ai-add")
            } else if store.aiStatus == .checking {
                HStack(spacing: MirsaSpacing.s) {
                    ProgressView().tint(MirsaPalette.accentSoft)
                    Text(t("Asking the AI…", "عم نسأل الذكاء الاصطناعي…",
                           "پرسیار لە زیرەکی دەستکرد دەکرێت…", "Ji AI tê pirsîn…"))
                        .font(MirsaFont.body)
                        .foregroundStyle(.white)
                }
            } else {
                Button {
                    Task { await store.suggestHookFromAI() }
                } label: {
                    Label(t("Ask the AI", "اسأل الذكاء الاصطناعي",
                            "لە زیرەکی دەستکرد بپرسە", "Ji AI bipirse"),
                          systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.mirsaSecondary)
                .controlSize(.large)
                .disabled(store.traceEntries.isEmpty)
                .accessibilityIdentifier("premium-trace-ai-ask")
            }
            if let aiError = store.aiError {
                Text(aiError)
                    .font(MirsaFont.caption)
                    .foregroundStyle(MirsaPalette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.aiStatus == .unavailable && store.aiError == nil {
                Text(t("AI suggestion is not available. Add the hook manually from the trace below.",
                       "اقتراح الذكاء الاصطناعي مو متاح. أضِف الخطّافة يدويًا من التتبع تحت.",
                       "پێشنیاری زیرەکی دەستکرد بەردەست نییە. هۆکەکە بە دەست لە شوێنکەوتنەکەی خوارەوە زیاد بکە.",
                       "Pêşniyara AI ne berdest e. Hookê bi destan ji şopandina jêrîn lê zêde bike."))
                    .font(MirsaFont.caption)
                    .foregroundStyle(MirsaPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(MirsaSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appsGlass(cornerRadius: MirsaRadius.l)
    }

    private func traceRow(_ entry: PremiumTrace.Entry) -> some View {
        let isStrongest = strongest?.id == entry.id
        let suggested = PremiumTrace.suggestedReturns(for: entry)
        let alreadyAdded = addedSelectors.contains(entry.selector)
            || store.extraHooks.contains(where: { $0.selector == entry.selector })
        return HStack(alignment: .top, spacing: MirsaSpacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.callText)
                    .font(MirsaFont.body)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(entry.timeText + " → " + entry.returns)
                    .font(MirsaFont.caption)
                    .foregroundStyle(MirsaPalette.textSecondary)
                if isStrongest {
                    Text(t("Strongest candidate", "أقوى مرشّح", "بەهێزترین کاندید", "Kandîdê herî bihêz"))
                        .font(MirsaFont.badge)
                        .foregroundStyle(MirsaPalette.accent)
                }
            }
            Spacer(minLength: 0)
            Button {
                if store.addHookFromTrace(entry) != nil {
                    addedSelectors.insert(entry.selector)
                }
            } label: {
                Text(alreadyAdded
                     ? t("Added ✓", "أُضيفت ✓", "زیادکرا ✓", "Hat lêzêdekirin ✓")
                     : t("Add hook", "أضِف خطّافة", "هۆک زیاد بکە", "Hook lê zêde bike")
                        + (suggested.map { " (" + returnsLabel($0) + ")" } ?? ""))
            }
            .buttonStyle(.mirsaSecondary)
            .controlSize(.small)
            .disabled(alreadyAdded || suggested == nil)
            .accessibilityIdentifier("premium-trace-add-\(entry.selector)")
        }
        .padding(MirsaSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appsGlass(cornerRadius: MirsaRadius.l)
        .overlay {
            if isStrongest {
                RoundedRectangle(cornerRadius: MirsaRadius.l, style: .continuous)
                    .stroke(MirsaPalette.accent, lineWidth: 1.5)
            }
        }
    }
}
