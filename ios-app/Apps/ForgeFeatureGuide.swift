import SwiftUI

/// Text-only onboarding attached to existing tools. No requests, permissions or feature state.
enum ForgeGuide: String, CaseIterable {
    case image, crash, archive, publish

    var subtitle: String { lines[0] }
    var steps: [String] { Array(lines.dropFirst()) }
    var seenKey: String { "mirsa.featureGuide.v1." + rawValue }
    private var lines: [String] {
        switch self {
        case .image: return [
            tr("Choose a screenshot and describe your change.", "اختار صورة واحكي شو بدك تغيّر.", ckb: "وێنەیەک هەڵبژێرە و بڵێ چی دەگۆڕیت.", kmr: "Wêneyek hilbijêre û bêje çi biguherî."),
            tr("Choose a screenshot from Photos.", "اختار لقطة شاشة من الصور.", ckb: "وێنەی شاشەیەک لە وێنەکان هەڵبژێرە.", kmr: "Wêneyek ji Wêneyan hilbijêre."),
            tr("Drag your finger around the element to mark it.", "اسحب بإصبعك حوالين العنصر لتحدّده بدايرة.", ckb: "پەنجەت بە دەوری توخمەکەدا بکێشە بۆ نیشانکردنی.", kmr: "Tiliya xwe li dora hêmanê bikişîne da nîşan bikî."),
            tr("Write your request above, then tap Generate from this image.", "اكتب طلبك فوق، وبعدها اضغط توليد من هالصورة.", ckb: "داواکارییەکەت لە سەرەوە بنووسە، پاشان دروستکردن لەم وێنەیەوە دابگرە.", kmr: "Daxwaza xwe li jor binivîse, paşê Ji vê wêneyê çêke bitikîne.")
        ]
        case .crash: return [
            tr("Review a launch marker or your imported diagnostic.", "راجع علامة انقطاع التشغيل أو سجل بتستورده إنت.", ckb: "نیشانەی پچڕانی کارپێکردن یان تۆماری هاوردەکراوت بپشکنە.", kmr: "Nîşana destpêkê an loga xwe ya anînî kontrol bike."),
            tr("A loader marker can flag an interrupted container launch, not prove a tweak caused a crash. Mirsa cannot read system crash logs.", "علامة اللودر بتنبّه لانقطاع تشغيل الحاوية، مو دليل إن التويك سبّب الكراش. Mirsa ما بيقرأ سجلات كراش النظام.", ckb: "نیشانەی لۆدەر پچڕانی کارپێکردنی کۆنتەینەر نیشان دەدات، نەک بەڵگەی کڕاشی تویک. Mirsa تۆماری کڕاشی سیستەم ناخوێنێتەوە.", kmr: "Nîşana loaderê destpêka qutbûyî ya konteynerê nîşan dide, ne sedema qelibîna tweakê. Mirsa logên qelibîna pergalê naxwîne."),
            tr("Use the interrupted-launch card to review and send a fix report. For assisted repair here, import a fresh Inspector capture for this tweak with its guard enabled and paste your own diagnostic.", "من بطاقة انقطاع التشغيل راجع التقرير وابعته للإصلاح. للإصلاح المساعد هون، استورد التقاط جديد من المفتش لنفس التويك وحمايته شغّالة، والصق السجل اللي عندك.", ckb: "لە کارتی پچڕانی کارپێکردن ڕاپۆرت بپشکنە و بۆ چاککردنەوە بینێرە. بۆ چاککردنی یارمەتیدراوی لێرە، گیراوەی نوێی پشکنەر بۆ هەمان تویک بە پارێزەری چالاک هاوردە بکە و تۆماری خۆت بلکێنە.", kmr: "Ji karta destpêka qutbûyî raporê kontrol bike û bişîne. Ji bo sererastkirina li vir, girtina nû ya Mufetîşê ji bo heman tweakê bi guardê çalak bîne û loga xwe pêve bike."),
            tr("Review the redacted diagnostic, consent and request repair. Review any returned version before using it; nothing installs automatically.", "راجع السجل بعد إخفاء البيانات، وافق واطلب إصلاح. راجع النسخة اللي بترجع قبل استخدامها؛ ما في تثبيت تلقائي.", ckb: "تۆماری پاککراو بپشکنە، ڕازی بە و داوای چاککردنەوە بکە. پێش بەکارهێنان وەشانی گەڕاوە بپشکنە؛ خۆکار دانامەزرێت.", kmr: "Loga paqijkirî kontrol bike, razî bibe û sererastkirinê bixwaze. Berî bikaranînê guhertoya vegeriyayî kontrol bike; bixwe nayê sazkirin.")
        ]
        case .archive: return [
            tr("Keep IPA versions and reinstall an older copy.", "احتفظ بنسخ IPA وارجع ثبّت نسخة أقدم.", ckb: "وەشانەکانی IPA هەڵبگرە و وەشانێکی کۆنتر دابمەزرێنە.", kmr: "Guhertoyên IPA biparêze û kopiyeke kevntir saz bike."),
            tr("Added or signed IPAs are saved here for this app.", "نسخ IPA اللي بتضيفها أو بتوقّعها بتنحفظ هون لهالتطبيق.", ckb: "IPAە زیادکراو یان واژۆکراوەکان لێرە بۆ ئەم ئەپە پاشەکەوت دەکرێن.", kmr: "IPA yên zêdekirî an îmzekirî li vir ji bo vê appê tên tomarkirin."),
            tr("Choose how many versions to keep per app.", "حدّد قديش نسخة بدك تحتفظ لكل تطبيق.", ckb: "ژمارەی وەشانە پاشەکەوتکراوەکان بۆ هەر ئەپێک هەڵبژێرە.", kmr: "Hilbijêre ji bo her appê çend guhertoyan biparêzî."),
            tr("Tap the install icon beside an older version, then finish the usual import, signing and installation steps as needed. The archive copy stays here.", "اضغط رمز التثبيت جنب النسخة الأقدم، وكمّل خطوات الاستيراد والتوقيع والتثبيت المعتادة حسب الحاجة. النسخة المحفوظة بتضل هون.", ckb: "ئایکۆنی دامەزراندن لە تەنیشت وەشانی کۆنتر دابگرە و هەنگاوەکانی هاوردەکردن، واژۆکردن و دامەزراندن بەپێی پێویست تەواو بکە. لەبەرگیراوەکە لێرە دەمێنێتەوە.", kmr: "Îkona sazkirinê li kêleka guhertoya kevntir bitikîne û gavên asayî yên anîn, îmzekirin û sazkirinê biqedîne. Kopiya arşîvê li vir dimîne.")
        ]
        case .publish: return [
            tr("Review the name, target app and what it does.", "راجع الاسم والتطبيق وشو بيعمل التويك.", ckb: "ناو، ئەپی ئامانج و کاری تویکەکە بپشکنە.", kmr: "Nav, appa armanc û karê tweakê kontrol bike."),
            tr("Check the tweak name, target app and short description. You can edit all three before publishing.", "راجع اسم التويك والتطبيق المستهدف والوصف القصير. فيك تعدّل التلاتة قبل النشر.", ckb: "ناوی تویک، ئەپی ئامانج و وەسفی کورت بپشکنە. پێش بڵاوکردنەوە دەتوانیت هەر سێکیان بگۆڕیت.", kmr: "Navê tweakê, appa armanc û danasîna kurt kontrol bike. Berî weşandinê her sêyan biguherîne."),
            tr("To share your own .dylib or .deb, enable Upload and choose Files or fetch a direct HTTPS URL. Uploaded files are labeled Uploaded, not server-built.", "لملف dylib أو deb من عندك، فعّل الرفع واختار من الملفات أو حط رابط HTTPS مباشر واضغط جلب. بينعرض كـ «مرفوع»، مو مبني بالسيرفر.", ckb: "بۆ هاوبەشکردنی .dylib یان .debی خۆت، بارکردن چالاک بکە و لە فایلەکان هەڵبژێرە یان بەستەری ڕاستەوخۆی HTTPS بهێنە. وەک «بارکراو» نیشان دەدرێت، نەک دروستکراوی سێرڤەر.", kmr: "Ji bo .dylib an .deb ya xwe Barkirinê çalak bike û ji Pelan hilbijêre an URL ya rasterast a HTTPS bîne. Wekî Barkirî tê nîşandan, ne çêkirina serverê."),
            tr("Publish only after reviewing these details. Only describe what the tweak really does.", "انشر بس بعد مراجعة التفاصيل. اكتب بس شو بيعمل التويك فعلاً.", ckb: "تەنها دوای پشکنینی وردەکارییەکان بڵاوی بکەرەوە. تەنها کاری ڕاستەقینەی تویکەکە بنووسە.", kmr: "Tenê piştî kontrolkirina hûrguliyan biweşîne. Tenê karê rastîn ê tweakê binivîse.")
        ]
        }
    }
}

/// Inline on first encounter; one tap dismisses it, and help can always be reopened.
struct ForgeFeatureGuide: View {
    let feature: ForgeGuide
    var showSubtitle = true
    @AppStorage private var seen: Bool

    init(_ feature: ForgeGuide, showSubtitle: Bool = true) {
        self.feature = feature
        self.showSubtitle = showSubtitle
        _seen = AppStorage(wrappedValue: false, feature.seenKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showSubtitle { ForgeGuideSubtitle(feature: feature) }
            if seen {
                Button { seen = false } label: {
                    Label(tr("How to use", "كيف بتستخدمها", ckb: "چۆنیەتی بەکارهێنان", kmr: "Çawa bi kar bînî"), systemImage: "questionmark.circle")
                        .font(.caption)
                }.buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(tr("Quick guide", "شرح سريع", ckb: "ڕێنمایی خێرا", kmr: "Rêbera kurt")).font(.caption.bold())
                        Spacer()
                        Button { seen = true } label: {
                            Image(systemName: "xmark").font(.caption).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tr("Dismiss guide", "إخفاء الشرح", ckb: "داخستنی ڕێنمایی", kmr: "Rêberê veşêre"))
                    }
                    ForEach(Array(feature.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text(String(index + 1)).font(.caption.bold()).foregroundStyle(MirsaPalette.accent)
                                .frame(width: 18, alignment: .leading)
                            Text(step).font(.caption).lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.white.opacity(0.75))
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct ForgeGuideSubtitle: View {
    let feature: ForgeGuide

    var body: some View {
        Text(feature.subtitle).font(.caption).foregroundStyle(.white.opacity(0.6))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .leftToRight)
    }
}
