import Foundation

/// Layout strings for the reorganised wallpaper page (primary buttons, installed cards, closed tools).
enum TendiesPageText {
    enum Key { case install, request, yours, yoursEmpty, tools, toolsHint, ready, skippedNote, nothingNew, importMore }
    static func text(_ key: Key, language: AppLanguage = AppLanguageStore.snapshot) -> String {
        let v = values[key]!
        switch language {
        case .english: return v[0]
        case .arabic: return v[1]
        case .german: return v[2]
        case .kurmanji: return v[3]
        case .sorani: return v[4]
        }
    }
    /// Visible note after an install that skipped already-installed wallpapers.
    static func skipped(_ titles: [String], language: AppLanguage = AppLanguageStore.snapshot) -> String {
        text(.skippedNote, language: language) + " " + titles.joined(separator: ", ")
    }
    static func selected(_ n: Int, language: AppLanguage = AppLanguageStore.snapshot) -> String {
        let w: String
        switch language {
        case .english: w = "Install selected (\(n))"
        case .arabic: w = "ركّب المختار (\(n))"
        case .german: w = "Auswahl installieren (\(n))"
        case .kurmanji: w = "Yên hilbijartî saz bike (\(n))"
        case .sorani: w = "هەڵبژێردراوەکان دابنێ (\(n))"
        }
        return w
    }
    private static let values: [Key: [String]] = [
        .install: ["Install wallpaper", "ركّب خلفية", "Hintergrund installieren", "Wêneya paşîn saz bike", "وێنەی پشتەوە دابنێ"],
        .request: ["Request wallpaper", "اطلب خلفية", "Hintergrund anfragen", "Wêneya paşîn bixwaze", "داوای وێنەی پشتەوە بکە"],
        .yours: ["Your wallpapers", "خلفياتك", "Deine Hintergründe", "Wêneyên te yên paşîn", "وێنە پشتەوەکانت"],
        .yoursEmpty: ["No wallpapers installed by Mirsa yet.", "ما في خلفيات مركّبة من مرسى لسا.", "Noch keine von Mirsa installierten Hintergründe.", "Hê wêneyên paşîn yên ji Mirsa nehatine saz kirin.", "هێشتا هیچ وێنەیەکی پشتەوە لەلایەن مرسی دانەنراوە."],
        .tools: ["Tools", "أدوات", "Werkzeuge", "Amûr", "ئامرازەکان"],
        .toolsHint: ["Logs and advanced details.", "السجلات والتفاصيل المتقدمة.", "Protokolle und erweiterte Details.", "Rojname û hûrgiliyên pêşketî.", "تۆمارەکان و وردەکارییە پێشکەوتووەکان."],
        .ready: ["Ready to install", "جاهزة للتركيب", "Bereit zur Installation", "Amade ji bo sazkirinê", "ئامادە بۆ دانان"],
        .skippedNote: ["Already installed, skipped:", "كانت مركّبة أصلاً، تم تخطيها:", "Bereits installiert, übersprungen:", "Berê hatibû saz kirin, derbas bû:", "پێشتر دانرابوو، بازدرا:"],
        .nothingNew: ["Nothing new to install. Everything selected is already installed.", "ما في شي جديد للتركيب. كل المحدد مركّب أصلاً.", "Nichts Neues zu installieren. Alles Gewählte ist bereits installiert.", "Tiştek nû tune. Hemû yên hilbijartî berê hatine saz kirin.", "هیچ شتێکی نوێ نییە. هەموو هەڵبژێردراوەکان پێشتر دانراون."],
        .importMore: ["Import wallpaper files", "استيراد ملفات خلفيات", "Hintergrunddateien importieren", "Pelên wêneyên paşîn import bike", "هاوردەکردنی فایلی وێنە پشتەوە"],
    ]
}
