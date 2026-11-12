import SwiftUI
import UniformTypeIdentifiers

/// Fourth tab: App Store (FairPlay-encrypted) IPAs, installed unmodified.
struct EncryptedAppsTab: View {
    @EnvironmentObject var vm: AppViewModel
    @ObservedObject private var store = EncryptedAppsStore.shared
    @ObservedObject private var localOTA = EncryptedLocalOTA.shared
    @State private var picking = false
    @State private var storeLoginAvailable = false
    @State private var showingAppStore = false
    @State private var pendingDelete: EncryptedIPAEntry?

    private func t(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String { EncryptedText.t(en, ar, ckb, kmr) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MirsaSpacing.m) {
                MirsaPageHeader(title: EncryptedText.tabTitle,
                                subtitle: t("App Store apps", "تطبيقات App Store", "ئەپەکانی App Store", "Sepanên App Store")) {
                    LanguageGlobeMenu(size: MirsaIconSize.button)
                }
                introCard
                benefitsCard
                importButton
                appStoreButton
                if store.entries.isEmpty {
                    emptyCard
                } else {
                    Text(t("Imported IPAs", "الـIPA المستوردة", "IPA هاوردەکراوەکان", "IPA yên hatine anîn"))
                        .font(MirsaFont.sectionTitle).foregroundStyle(.white)
                        .padding(.top, MirsaSpacing.xs)
                    ForEach(store.entries) { entry in
                        EncryptedEntryCard(entry: entry, store: store, vm: vm) { pendingDelete = entry }
                    }
                }
            }
            .padding(.horizontal, MirsaSpacing.page)
            .padding(.bottom, MirsaSpacing.tabBarClearance)
        }
        .task {
            storeLoginAvailable = false
            storeLoginAvailable = await MirsaStoreServerClient.shared.loginAvailable()
        }
        .sheet(isPresented: $showingAppStore) {
            AppStoreAccountView(onDownloaded: { url in
                let entry = try await EncryptedAppsStore.adopt(file: url, move: false)
                store.add(entry)
            })
        }
        .sheet(isPresented: $localOTA.shown) { EncryptedLocalOTAView() }
        .mirsaStatusBarScrim()
        .background(AuroraBackground().ignoresSafeArea())
        .preferredColorScheme(.dark)
        .environment(\.layoutDirection, .leftToRight)
        .sheet(isPresented: $picking) {
            DocumentPickerView(allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data]) { url in
                Task { await store.importIPA(from: url) }
            }
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

    private func t(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String { EncryptedText.t(en, ar, ckb, kmr) }

    var body: some View {
        let match = store.match(entry)
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            HStack(spacing: MirsaSpacing.s) {
                Group {
                    if let img = store.icon(entry) { Image(uiImage: img).resizable().scaledToFill() }
                    else { Image(systemName: "app.dashed").font(.title).foregroundStyle(MirsaPalette.textTertiary) }
                }
                .frame(width: 56, height: 56)
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
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(MirsaPalette.success)
                        .accessibilityLabel(t("Installed", "مثبّت", "دامەزراوە", "Sazkirî"))
                }
            }
            purchaserRow
            ForEach(warnings(match), id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle.fill")
                    .font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.installingID == entry.id {
                ProgressView(value: store.progress).tint(MirsaPalette.accentSoft)
            }
            HStack(spacing: MirsaSpacing.xs) {
                Button { Task { await EncryptedLocalOTA.shared.prepare(entry) } } label: {
                    Label(t("Install as-is", "ثبّت متل ما هو", "وەک خۆی دابمەزرێنە", "Wekî xwe saz bike"), systemImage: "arrow.down.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.mirsaPrimary)
                .disabled(store.busy != nil)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.mirsaSecondary)
                .disabled(store.installingID == entry.id)
                .accessibilityLabel(t("Delete", "حذف", "سڕینەوە", "Jê bibe"))
            }
            Button { Task { await store.install(entry, vm: vm) } } label: {
                Label(t("Native install (Wi-Fi + LocalDevVPN)", "تثبيت مباشر اختياري (Wi-Fi + LocalDevVPN)",
                        "دامەزراندنی ڕاستەوخۆ (Wi-Fi + LocalDevVPN)", "Sazkirina rasterast (Wi-Fi + LocalDevVPN)"), systemImage: "network")
                    .font(MirsaFont.caption).frame(maxWidth: .infinity)
            }
            .buttonStyle(.mirsaSecondary).disabled(store.busy != nil)
        }
        .padding(MirsaSpacing.card)
        .mirsaCard()
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
