import Foundation

/// Strings for the original video wallpaper tab (restored from 2.4), all five languages.
enum VideoWallpaperSection {
    enum Key { case tab, fromPhotos, preparing, info, experimental }

    static func text(_ key: Key, language: AppLanguage = AppLanguageStore.shared.current) -> String {
        switch (key, language) {
        case (.tab, .arabic): return "خلفية فيديو"
        case (.tab, .english): return "Video wallpaper"
        case (.tab, .german): return "Videohintergrund"
        case (.tab, .kurmanji): return "Wêneya vîdyoyê"
        case (.tab, .sorani): return "ڤیدیۆ پاشبنەما"
        case (.fromPhotos, .arabic): return "فيديو من الاستوديو"
        case (.fromPhotos, .english): return "Video from Photos"
        case (.fromPhotos, .german): return "Video aus Fotos"
        case (.fromPhotos, .kurmanji): return "Vîdyo ji Wêneyan"
        case (.fromPhotos, .sorani): return "ڤیدیۆ لە وێنەکان"
        case (.preparing, .arabic): return "عم نجهّز الفيديو…"
        case (.preparing, .english): return "Preparing video…"
        case (.preparing, .german): return "Video wird vorbereitet…"
        case (.preparing, .kurmanji): return "Vîdyo tê amadekirin…"
        case (.preparing, .sorani): return "ڤیدیۆ ئامادە دەکرێت…"
        case (.info, .arabic): return "أول ١٠ ثواني، قصّ للملء بحسب الشاشة. بعد التحضير اختار تطبيق الخلفيات كالمعتاد."
        case (.info, .english): return "Uses the first 10 seconds, center-cropped to your screen. Apply through the existing wallpaper flow when ready."
        case (.info, .german): return "Nutzt die ersten 10 Sekunden, zentriert auf deinen Bildschirm zugeschnitten. Danach wie gewohnt über den Hintergrund-Ablauf anwenden."
        case (.info, .kurmanji): return "10 çirkeyên pêşîn tên bikaranîn û li gorî dîmenderê têne birîn. Piştî amadekirinê bi rêya asayî wallpaper bisepîne."
        case (.info, .sorani): return "یەکەم ١٠ چرکە بەکاردێت و بەپێی شاشە دەبڕدرێت. دوای ئامادەکردن وەک جاران وێنەی پشتەوە جێبەجێ بکە."
        case (.experimental, .arabic): return "ميزة تجريبية. طريقة التطبيق مسدودة على iOS 27.2 beta 3 والأحدث. ممكن إصدار النظام يأثر على حركة الخلفية."
        case (.experimental, .english): return "Experimental. The apply method is patched on iOS 27.2 beta 3 and later. Animation behavior may vary by iOS version."
        case (.experimental, .german): return "Experimentell. Die Anwendungsmethode ist ab iOS 27.2 Beta 3 gepatcht. Das Animationsverhalten kann je nach iOS-Version abweichen."
        case (.experimental, .kurmanji): return "Taybet ezmûnî ye. Rêbaza sepandinê li iOS 27.2 beta 3 û nûtir hatiye girtin. Tevgera wallpaperê dibe ku li gorî guhertoya iOS cuda be."
        case (.experimental, .sorani): return "تاقیکارییە. شێوازی جێبەجێکردن لە iOS 27.2 beta 3 و نوێتر داخراوە. جووڵەی وێنەی پشتەوە لەوانەیە بەپێی وەشانی iOS جیاواز بێت."
        }
    }
}
