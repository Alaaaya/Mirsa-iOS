import SwiftUI

/// Five-language text for the store library tools (wishlist, pins, accounts, cleanup).
/// German is picked only when AppLanguage.current raw value is "de" (added globally by the main worker).
enum StoreFeatureText {
    static func pick(_ en: String, _ ar: String, _ de: String, _ ckb: String, _ kmr: String) -> String { t(en, ar, de, ckb, kmr) }
    static func t(_ en: String, _ ar: String, _ de: String, _ ckb: String, _ kmr: String) -> String {
        switch AppLanguageStore.snapshot.rawValue {
        case "ar": return ar
        case "de": return de
        case "ckb": return ckb
        case "kmr": return kmr
        default: return en
        }
    }
    static var wishlistNote: String { t("Best effort: iOS decides when background checks run, so alerts can be late. Without LocalDevVPN and Wi-Fi the inventory may not refresh. Open the app to check right away.", "على قدر المستطاع: iOS هو يلي بيقرر وقت الفحص بالخلفية فممكن التنبيه يتأخر. بدون LocalDevVPN وWi-Fi ممكن القائمة ما تتحدث. افتح التطبيق لتتحقق فوراً.", "Nach Möglichkeit: iOS entscheidet, wann Hintergrundprüfungen laufen, Hinweise können sich verspäten. Ohne LocalDevVPN und WLAN wird der Bestand evtl. nicht aktualisiert. Öffne die App für eine sofortige Prüfung.", "بە باشترین شێوە: iOS دیاری دەکات کەی پشکنین لە پاشبنەما ئەنجام بدرێت، ئاگادارکردنەوە لەوانەیە دوابکەوێت. بێ LocalDevVPN و Wi-Fi لەوانەیە لیست نوێ نەبێتەوە. ئەپەکە بکەرەوە بۆ پشکنینی یەکسەر.", "Bi qasî ku mimkûn e: iOS diyar dike kengî kontrolên paşperdeyê dixebitin, hişyarî dikarin dereng bin. Bêyî LocalDevVPN û Wi-Fi lîste nayê nûkirin. Ji bo kontrola tavilê sepanê veke.") }
    static var osConfirmTitle: String { t("This version may not run on your iOS", "هالنسخة ممكن ما تشتغل على iOS تبعك", "Diese Version läuft evtl. nicht auf deinem iOS", "ئەم وەشانە لەوانەیە لەسەر iOSەکەت کار نەکات", "Ev guherto dibe ku li ser iOSa te nexebite") }
    static var continueAnyway: String { t("Continue anyway", "كمّل", "Trotzdem fortfahren", "بەردەوام بە", "Dîsa jî berdewam bike") }
    static var cancel: String { t("Cancel", "إلغاء", "Abbrechen", "هەڵوەشاندنەوە", "Betal") }
    static var shareWarning: String { t("This encrypted file may include your Apple purchase identity. Never share it with anyone you don't trust.", "هالملف المشفّر ممكن يحتوي هوية شراء Apple تبعك. لا تشاركه مع حدا ما بتثق فيه.", "Diese verschlüsselte Datei kann deine Apple-Kaufidentität enthalten. Teile sie nie mit Personen, denen du nicht vertraust.", "ئەم فایلە ڕمزکراوە لەوانەیە ناسنامەی کڕینی Appleی تۆی تێدا بێت. هەرگیز لەگەڵ کەسێکی نابڕوادار هاوبەشی مەکە.", "Ev pela şîfrekirî dibe ku nasnameya kirîna te ya Apple tê de be. Qet bi kesê ku pê nabawerî re parve neke.") }
    static var tools: String { t("Library tools", "أدوات المكتبة", "Bibliothek-Tools", "ئامرازەکانی کتێبخانە", "Amûrên pirtûkxaneyê") }
    static var wishlist: String { t("Wishlist", "قائمة الأمنيات", "Wunschliste", "لیستی خواستەکان", "Lîsteya daxwazan") }
    static var pins: String { t("Pinned versions", "الإصدارات المثبّتة", "Fixierte Versionen", "وەشانە جێگیرکراوەکان", "Guhertoyên sabît") }
    static var settings: String { t("Settings", "الإعدادات", "Einstellungen", "ڕێکخستنەکان", "Mîheng") }
    static var noWishes: String { t("No paid apps saved yet.", "ما في تطبيقات مدفوعة محفوظة.", "Noch keine kostenpflichtigen Apps gemerkt.", "هێشتا هیچ ئەپێکی پارەدار پاشەکەوت نەکراوە.", "Hê tu sepana bi pere nehatiye tomarkirin.") }
    static var noPins: String { t("No pinned versions.", "ما في إصدارات مثبّتة.", "Keine fixierten Versionen.", "هیچ وەشانێکی جێگیرکراو نییە.", "Tu guherto sabît nîne.") }
    static var becameFree: String { t("Now free!", "صار مجاني!", "Jetzt kostenlos!", "ئێستا بێبەرامبەرە!", "Niha belaş e!") }
    static var remove: String { t("Remove", "إزالة", "Entfernen", "لابردن", "Rake") }
    static var unpin: String { t("Unpin", "إلغاء التثبيت", "Lösen", "لابردنی جێگیرکردن", "Sabîtiyê rake") }
    static var notifications: String { t("Notify me when a saved app becomes free", "نبّهني لما تطبيق محفوظ يصير مجاني", "Benachrichtigen, wenn eine gemerkte App gratis wird", "ئاگادارم بکەرەوە کاتێک ئەپێکی پاشەکەوتکراو بێبەرامبەر دەبێت", "Gava sepanek belaş bibe min agahdar bike") }
    static var autoClean: String { t("Delete the IPA after a confirmed successful install", "احذف الـIPA بعد تثبيت ناجح مؤكّد", "IPA nach bestätigter Installation löschen", "IPA بسڕەوە دوای دامەزراندنی سەرکەوتووی دڵنیاکراو", "Piştî sazkirina serkeftî IPA jê bibe") }
    static var autoCleanNote: String { t("Off by default. Saved or shared files are never deleted.", "مطفأ افتراضياً. الملفات المحفوظة أو المشاركة ما بتنحذف.", "Standardmäßig aus. Gespeicherte oder geteilte Dateien werden nie gelöscht.", "بە بنەڕەت کوژاوەتەوە. فایلە پاشەکەوتکراو یان هاوبەشکراوەکان نابڕێنەوە.", "Bi berdestî girtî ye. Pelên tomarkirî an parvekirî nayên jêbirin.") }
    static var share: String { t("Share IPA", "مشاركة IPA", "IPA teilen", "IPA هاوبەش بکە", "IPA parve bike") }
    static var whatsNew: String { t("What's new", "شو الجديد", "Neuerungen", "نوێیەکان", "Çi nû ye") }
    static var notesUnavailable: String { t("Notes are only available for the latest version.", "الملاحظات متوفرة فقط لآخر إصدار.", "Hinweise gibt es nur für die neueste Version.", "تێبینییەکان تەنها بۆ دوایین وەشان بەردەستن.", "Nîşe tenê ji bo guhertoya herî dawî hene.") }
    static var minOSWarn: String { t("Needs a newer iOS than this device has.", "بدو iOS أحدث من جهازك.", "Benötigt ein neueres iOS als dieses Gerät.", "iOSی نوێتر دەوێت لەوەی ئەم ئامێرە هەیەتی.", "iOSeke nûtir ji vê cîhazê dixwaze.") }
    static var accounts: String { t("Accounts", "الحسابات", "Konten", "هەژمارەکان", "Hesab") }
    static var addAccount: String { t("Add account", "إضافة حساب", "Konto hinzufügen", "زیادکردنی هەژمار", "Hesab zêde bike") }
}
