import Foundation

extension MirsaTr {
    static func ft(_ en: String, _ args: CVarArg...) -> String {
        var s = en
        if let t = fileTools[en] {
            switch AppLanguageStore.shared.current {
            case .english: s = en
            case .arabic: s = t.0
            case .sorani: s = t.1
            case .kurmanji: s = t.2
            }
        }
        return args.isEmpty ? s : String(format: s, arguments: args)
    }

    static let fileTools: [String: (String, String, String)] = [
        "%d lines": ("%d سطر", "%d دێڕ", "%d rêz"),
        "%d matches": ("%d نتيجة", "%d گونجان", "%d lihevhatin"),
        "Architectures": ("المعماريات", "تەلارسازییەکان", "Mîmarî"),
        "Code signature": ("توقيع الكود", "واژۆی کۆد", "Îmzeya kodê"),
        "Compress to zip": ("ضغط إلى zip", "پەستاندن بۆ zip", "Bike zip"),
        "Copy": ("نسخ", "لەبەرگرتنەوە", "Kopî bike"),
        "Create": ("إنشاء", "دروستکردن", "Çêke"),
        "Cut": ("قص", "بڕین", "Bibire"),
        "Encrypted (cryptid %d)": ("مشفّر (cryptid %d)", "ڕەمزکراو (cryptid %d)", "Şîfrekirî (cryptid %d)"),
        "Encryption": ("التشفير", "ڕەمزکردن", "Şîfrekirin"),
        "Enter 1-64 bytes as hex.": ("أدخل من 1 إلى 64 بايت بصيغة hex.", "١ بۆ ٦٤ بایت بە hex بنووسە.", "1 heta 64 bayt wekî hex binivîse."),
        "Extract here": ("فك الضغط هنا", "لێرە بیکەرەوە", "Li vir derxe"),
        "File is too large for the hex editor (max 8 MB).": ("الملف كبير جداً لمحرر hex (الحد 8 ميغا).", "فایلەکە زۆر گەورەیە بۆ دەستکاری hex (زۆرینە ٨ مێگا).", "Pelê ji bo edîtora hex pir mezin e (herî zêde 8 MB)."),
        "Find hex (e.g. DE AD BE EF) or text": ("ابحث عن hex (مثل DE AD BE EF) أو نص", "hex (وەک DE AD BE EF) یان دەق بدۆزەرەوە", "Hex (mînak DE AD BE EF) an nivîs bibîne"),
        "Find": ("بحث", "دۆزینەوە", "Bibîne"),
        "Hex editor": ("محرر Hex", "دەستکاری Hex", "Edîtora Hex"),
        "Import file": ("استيراد ملف", "هێنانی فایل", "Pelê têxe"),
        "Libraries": ("المكتبات", "کتێبخانەکان", "Pirtûkxane"),
        "Mach-O info": ("معلومات Mach-O", "زانیاری Mach-O", "Agahiyên Mach-O"),
        "Minimum OS": ("أقل إصدار نظام", "کەمترین سیستەم", "Guhertoya herî kêm a pergalê"),
        "New file": ("ملف جديد", "فایلی نوێ", "Pelê nû"),
        "New folder": ("مجلد جديد", "بوخچەی نوێ", "Peldanka nû"),
        "None": ("لا يوجد", "هیچ", "Tune"),
        "Not a valid Mach-O file.": ("ليس ملف Mach-O صالحاً.", "فایلی Mach-O دروست نییە.", "Pelê Mach-O ya derbasdar nîne."),
        "Not encrypted": ("غير مشفّر", "ڕەمزکراو نییە", "Şîfrekirî nîne"),
        "Not found.": ("لم يتم العثور عليه.", "نەدۆزرایەوە.", "Nehat dîtin."),
        "Past the end of the file.": ("بعد نهاية الملف.", "لە دوای کۆتایی فایلەکە.", "Ji dawiya pelê wêdetir."),
        "Paste here": ("لصق هنا", "لێرە بیلکێنە", "Li vir bixe"),
        "Platform": ("المنصة", "پلاتفۆرم", "Platform"),
        "Present": ("موجود", "هەیە", "Heye"),
        "Replace all": ("استبدال الكل", "هەموو بگۆڕە", "Hemûyan biguherîne"),
        "Replace with": ("استبدال بـ", "بگۆڕە بە", "Biguherîne bi"),
        "Save": ("حفظ", "پاشەکەوتکردن", "Tomar bike"),
        "Search files": ("ابحث في الملفات", "فایلەکان بگەڕێ", "Di pelan de bigere"),
        "Search inside text files": ("ابحث داخل الملفات النصية", "لەناو فایلە دەقییەکان بگەڕێ", "Di pelên nivîsê de bigere"),
        "Search": ("بحث", "گەڕان", "Lêgerîn"),
        "Set": ("تعيين", "دانان", "Danîn"),
        "Showing the first %d results.": ("عرض أول %d نتيجة.", "یەکەمین %d ئەنجام پیشان دەدرێت.", "%d encamên pêşîn tên nîşandan."),
        "Tap a byte": ("اضغط على بايت", "لەسەر بایتێک دابگرە", "Li bayteke bitikîne"),
        "This XML is not well-formed.": ("هذا XML غير صحيح البنية.", "ئەم XML ـە ڕێکخراو نییە.", "Ev XML rast nehatiye çêkirin."),
        "This is not valid JSON; the app may fail to read it.": ("هذا JSON غير صالح، وقد يفشل التطبيق في قراءته.", "ئەمە JSONی دروست نییە؛ لەوانەیە ئەپەکە نەتوانێت بیخوێنێتەوە.", "Ev JSON ne derbasdar e; dibe ku sepan nikaribe bixwîne."),
        "Type": ("النوع", "جۆر", "Cure"),
    ]
}
