import Foundation

enum WallpaperCatalogText {
    enum Key: CaseIterable { case title, source, load, export, notice, failed, loading, preview }
    static func text(_ key: Key, language: AppLanguage = AppLanguageStore.snapshot) -> String {
        let index: Int
        switch language {
        case .english: index = 0
        case .arabic: index = 1
        case .german: index = 2
        case .kurmanji: index = 3
        case .sorani: index = 4
        }
        return values[key]![index]
    }
    static let values: [Key: [String]] = [
        .title: ["Wallpaper sources", "مصادر الخلفيات", "Hintergrundquellen", "Çavkaniyên dîwaran", "سەرچاوەکانی پاشبنەما"],
        .source: ["HTTPS JSON source", "رابط مصدر JSON آمن", "HTTPS-JSON-Quelle", "Çavkaniya HTTPS JSON", "سەرچاوەی HTTPS JSON"],
        .load: ["Load catalog", "تحميل الكتالوج", "Katalog laden", "Katalogê bar bike", "بارکردنی کەتەلۆگ"],
        .export: ["Export / Open in…", "تصدير / فتح باستخدام…", "Exportieren / Öffnen mit…", "Derxe / Bi vê veke…", "هەناردە / کردنەوە بە…"],
        .notice: ["Catalog only. Files are exported, never installed. Use sources you trust; compatibility is not verified.", "كتالوج فقط. الملفات للتصدير، مو للتثبيت. استخدم مصادر موثوقة؛ التوافق مو مضمون.", "Nur Katalog. Dateien werden exportiert, nie installiert. Nur vertrauenswürdige Quellen nutzen; Kompatibilität ungeprüft.", "Tenê katalog. Pel tên derxistin, nayên sazkirin. Çavkaniyên pêbawer bi kar bîne; lihevhatin nehatiye piştrastkirin.", "تەنها کەتەلۆگ. فایلەکان هەناردە دەکرێن، دانامەزرێن. سەرچاوەی متمانەپێکراو بەکاربهێنە؛ گونجان پشتڕاست نەکراوەتەوە."],
        .failed: ["Could not load this source or file. Check its format, size and HTTPS URL.", "ما قدرت حمّل المصدر أو الملف. تأكد من الصيغة والحجم ورابط HTTPS.", "Quelle oder Datei konnte nicht geladen werden. Format, Größe und HTTPS-Adresse prüfen.", "Çavkanî an pel nehat barkirin. Format, mezinahî û navnîşana HTTPS kontrol bike.", "سەرچاوە یان فایل بار نەکرا. شێواز، قەبارە و بەستەری HTTPS بپشکنە."],
        .loading: ["Loading…", "عم حمّل…", "Wird geladen…", "Tê barkirin…", "بار دەکرێت…"],
        .preview: ["Preview", "معاينة", "Vorschau", "Pêşdîtin", "پێشبینین"]
    ]
}
