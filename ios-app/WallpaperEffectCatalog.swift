import Foundation

/// Presentation only. The serialized mechanism IDs and exporter stay untouched.
/// An explicit allowlist keeps implementation details and duplicate recipes out of the picker.
enum WallpaperEffectCatalog {
    enum Group: String, CaseIterable, Identifiable {
        case color, motion, shape, particles
        var id: String { rawValue }
        func title(language: AppLanguage = AppLanguageStore.snapshot) -> String {
            switch self {
            case .color: return WallpaperEffectCatalog.localize(["Colour & light", "ألوان وإضاءة", "Farbe & Licht", "Reng û ronahî", "ڕەنگ و ڕووناکی"], language: language)
            case .motion: return WallpaperEffectCatalog.localize(["Movement", "حركة", "Bewegung", "Tevger", "جووڵە"], language: language)
            case .shape: return WallpaperEffectCatalog.localize(["Shape & depth", "شكل وعمق", "Form & Tiefe", "Şikil û kûrahî", "شێوە و قووڵایی"], language: language)
            case .particles: return WallpaperEffectCatalog.localize(["Stars & particles", "نجوم وجزيئات", "Sterne & Partikel", "Stêrk û perçe", "ئەستێرە و تەنۆلکە"], language: language)
            }
        }
        func subtitle(language: AppLanguage = AppLanguageStore.snapshot) -> String {
            switch self {
            case .color: return WallpaperEffectCatalog.localize(["Change the colours and softness of your photo.", "غيّر ألوان الصورة ونعومتها.", "Ändere Farben und Weichheit deines Fotos.", "Reng û nermiya wêneyê biguherîne.", "ڕەنگ و نەرمیی وێنەکەت بگۆڕە."], language: language)
            case .motion: return WallpaperEffectCatalog.localize(["Move, rotate or zoom your photo in a loop.", "حرّك الصورة أو دوّرها أو كبّرها بحركة متكررة.", "Bewege, drehe oder vergrößere dein Foto in einer Schleife.", "Wêneyê bi tevgera dubare bide livandin, bizivirîne an mezin bike.", "وێنەکەت بە جووڵەی دووبارە بجووڵێنە، بیسووڕێنە یان گەورەی بکە."], language: language)
            case .shape: return WallpaperEffectCatalog.localize(["Change the edges, shadow or glass effect.", "غيّر الحواف أو الظل أو تأثير الزجاج.", "Ändere Ränder, Schatten oder den Glaseffekt.", "Kenar, sî an bandora camê biguherîne.", "لێوار، سێبەر یان کاریگەریی شووشە بگۆڕە."], language: language)
            case .particles: return WallpaperEffectCatalog.localize(["Choose where the animated stars appear.", "اختر مكان ظهور النجوم المتحركة.", "Wähle, wo die animierten Sterne erscheinen.", "Hilbijêre ku stêrkên livdar li ku derkevin.", "شوێنی دەرکەوتنی ئەستێرە جووڵاوەکان هەڵبژێرە."], language: language)
            }
        }
        var entries: [Entry] { WallpaperEffectCatalog.entries.filter { $0.group == self } }
    }

    struct Entry: Identifiable {
        let mechanism: WallpaperMechanism
        let group: Group
        fileprivate let titles: [String]
        var id: String { mechanism.rawValue }
        func title(language: AppLanguage = AppLanguageStore.snapshot) -> String {
            WallpaperEffectCatalog.localize(titles, language: language)
        }
    }

    static let entries: [Entry] = [
        Entry(mechanism: .filterGaussianBlur1, group: .color, titles: ["Blur", "تغبيش", "Weichzeichnen", "Tarîkirin", "لێڵکردن"]),
        Entry(mechanism: .filterSaturate1, group: .color, titles: ["Colour saturation", "تشبع ألوان", "Farbsättigung", "Têrbûna rengan", "تێریی ڕەنگ"]),
        Entry(mechanism: .filtercolorSaturate, group: .color, titles: ["Muted colours", "ألوان هادئة", "Gedämpfte Farben", "Rengên nerm", "ڕەنگی نەرم"]),
        Entry(mechanism: .filterContrast1, group: .color, titles: ["Contrast", "تباين", "Kontrast", "Kontrast", "کۆنتراست"]),
        Entry(mechanism: .filterHueRotate1, group: .color, titles: ["Colour shift", "تغيير الألوان", "Farbverschiebung", "Guhertina rengan", "گۆڕینی ڕەنگ"]),
        Entry(mechanism: .filterSepia1, group: .color, titles: ["Vintage tone", "لون قديم", "Vintage-Tönung", "Rengê kevn", "ڕەنگی کۆن"]),
        Entry(mechanism: .propertyposition, group: .motion, titles: ["Move", "تحريك", "Bewegen", "Livandin", "جووڵاندن"]),
        Entry(mechanism: .propertypositionx, group: .motion, titles: ["Move sideways", "تحريك أفقي", "Seitlich bewegen", "Ber bi kêlekê ve livandin", "جووڵاندنی ئاسۆیی"]),
        Entry(mechanism: .propertypositiony, group: .motion, titles: ["Move up and down", "تحريك عمودي", "Auf und ab bewegen", "Ber bi jor û jêr ve livandin", "جووڵاندنی ستوونی"]),
        Entry(mechanism: .propertytransformrotationz, group: .motion, titles: ["Rotate", "تدوير", "Drehen", "Zivirandin", "سووڕاندن"]),
        Entry(mechanism: .propertytransformrotationx, group: .motion, titles: ["Tilt up and down", "إمالة عمودية", "Vertikal kippen", "Ber bi jor û jêr ve xwar kirin", "لارکردنی ستوونی"]),
        Entry(mechanism: .propertytransformrotationy, group: .motion, titles: ["Tilt sideways", "إمالة جانبية", "Seitlich kippen", "Ber bi kêlekê ve xwar kirin", "لارکردنی لاوەکی"]),
        Entry(mechanism: .propertytransformscale, group: .motion, titles: ["Zoom", "تكبير", "Vergrößern", "Mezinkirin", "گەورەکردن"]),
        Entry(mechanism: .propertytransformscalex, group: .motion, titles: ["Stretch sideways", "تمديد أفقي", "Seitlich strecken", "Ber bi kêlekê ve dirêj kirin", "درێژکردنی ئاسۆیی"]),
        Entry(mechanism: .propertybounds, group: .shape, titles: ["Resize frame", "تغيير حجم الإطار", "Rahmengröße ändern", "Mezinahiya çarçoveyê biguherîne", "گۆڕینی قەبارەی چوارچێوە"]),
        Entry(mechanism: .propertycornerRadius, group: .shape, titles: ["Rounded corners", "حواف دائرية", "Runde Ecken", "Quncên gilover", "گۆشەی خڕ"]),
        Entry(mechanism: .propertyshadowOpacity, group: .shape, titles: ["Soft shadow", "ظل ناعم", "Weicher Schatten", "Siya nerm", "سێبەری نەرم"]),
        Entry(mechanism: .filterdisplacementMap, group: .shape, titles: ["Glass distortion", "تموّج زجاجي", "Glasverzerrung", "Şikestina camê", "شێواندنی شووشە"]),
        Entry(mechanism: .emitterModeoutline, group: .particles, titles: ["Stars around the edges", "نجوم حول الحواف", "Sterne am Rand", "Stêrk li dora kenaran", "ئەستێرە لە دەوری لێوارەکان"]),
        Entry(mechanism: .emitterModevolume, group: .particles, titles: ["Scattered stars", "نجوم متناثرة", "Verstreute Sterne", "Stêrkên belavbûyî", "ئەستێرەی بڵاو"]),
        Entry(mechanism: .emitterShapeline, group: .particles, titles: ["Rain of stars", "مطر نجوم", "Sternenregen", "Barana stêrkan", "بارانی ئەستێرە"]),
        Entry(mechanism: .emitterShapepoint, group: .particles, titles: ["Star fountain", "نافورة نجوم", "Sternenfontäne", "Avreşka stêrkan", "نافورەی ئەستێرە"]),
        Entry(mechanism: .emitterShaperectangle, group: .particles, titles: ["Star shower", "زخّات نجوم", "Sternenschauer", "Şilîya stêrkan", "شەپۆلی ئەستێرە"]),
    ]

    static func entry(for mechanism: WallpaperMechanism) -> Entry? {
        entries.first { $0.mechanism == mechanism }
    }

    /// Imported projects can retain hidden recipes without exposing their technical names
    /// or silently replacing the original effect during editing/export.
    static func savedEffectTitle(language: AppLanguage = AppLanguageStore.snapshot) -> String {
        localize(["Saved effect", "التأثير المحفوظ", "Gespeicherter Effekt", "Bandora tomarkirî", "کاریگەریی پاشەکەوتکراو"], language: language)
    }

    private static func localize(_ values: [String], language: AppLanguage) -> String {
        switch language {
        case .english: return values[0]
        case .arabic: return values[1]
        case .german: return values[2]
        case .kurmanji: return values[3]
        case .sorani: return values[4]
        }
    }
}
