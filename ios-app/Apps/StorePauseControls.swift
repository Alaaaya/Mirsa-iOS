import SwiftUI

enum StorePauseText {
    static var pause: String { StoreFeatureText.t("Pause", "إيقاف مؤقت", "Pausieren", "وەستاندن", "Rawestîne") }
    static var resume: String { StoreFeatureText.t("Resume", "استئناف", "Fortsetzen", "بەردەوامبوون", "Bidomîne") }
    static var paused: String { StoreFeatureText.t("Paused", "متوقف مؤقتاً", "Pausiert", "وەستێنراوە", "Hatiye rawestandin") }
    static var waiting: String { StoreFeatureText.t("Waiting for network", "بانتظار الشبكة", "Warte auf Netzwerk", "چاوەڕێی تۆڕ", "Li benda torê") }
    static var note: String {
        StoreFeatureText.t("Pause keeps what is already downloaded. Cancel deletes it. If the file changed on Apple's side, the download restarts from zero.",
                           "الإيقاف المؤقت بيحفظ اللي نزل. الإلغاء بيحذفه. إذا تغيّر الملف عند Apple بيبدأ التنزيل من الصفر.",
                           "Pausieren behält das Geladene. Abbrechen löscht es. Hat sich die Datei bei Apple geändert, beginnt der Download neu.",
                           "وەستاندن ئەوەی داگیراوە دەیپارێزێت. هەڵوەشاندنەوە دەیسڕێتەوە. ئەگەر فایلەکە لای Apple گۆڕا، دابەزاندن لە سفرەوە دەست پێدەکاتەوە.",
                           "Rawestandin tiştê daxistî diparêze. Betalkirin jê dibe. Heke pela li Apple guherî, daxistin ji sifirê dest pê dike.")
    }
}

/// Pause / resume for the running App Store download. Hidden when nothing is downloading.
struct StorePauseButton: View {
    @ObservedObject private var control = StoreTransferControl.shared
    var body: some View {
        if control.phase != .idle {
            Button(control.phase == .paused ? StorePauseText.resume : StorePauseText.pause) {
                if control.phase == .paused { control.resume() } else { control.pause() }
            }
            .buttonStyle(.mirsaSecondary)
            .accessibilityIdentifier("store-pause-resume")
        }
    }
}

struct StorePauseStatus: View {
    @ObservedObject private var control = StoreTransferControl.shared
    var body: some View {
        if control.phase == .paused || control.phase == .waitingForNetwork {
            Text(control.phase == .paused ? StorePauseText.paused : StorePauseText.waiting)
                .font(MirsaFont.caption).foregroundStyle(MirsaPalette.textSecondary)
        }
        if control.phase != .idle {
            Text(StorePauseText.note).font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
        }
    }
}
