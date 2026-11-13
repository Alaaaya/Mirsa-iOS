import SwiftUI

// MARK: - Apple Store style (Settings › شكل متجر Apple): Classic (default) or New
//
// View layer only. Both styles host the same shared models and services
// (MirsaStoreOnDeviceClient, AppStoreSectionModel, EncryptedAppsStore, StoreLibraryModel),
// so sign-in, AMD, license/Get, downloads, installs and the wishlist behave the same.

enum StoreStyle: String, CaseIterable, Identifiable {
    case classic, new
    /// UserDefaults / @AppStorage key. UI tests can pass `-mirsa.store.style new`.
    static let key = "mirsa.store.style"
    static let fallback = StoreStyle.classic
    var id: String { rawValue }

    static func from(_ raw: String) -> StoreStyle { StoreStyle(rawValue: raw) ?? fallback }

    var title: String {
        switch self {
        case .classic: return StoreFeatureText.t("Classic", "الكلاسيكي", "Klassisch", "کلاسیکی", "Klasîk")
        case .new: return StoreFeatureText.t("New", "الجديد", "Neu", "نوێ", "Nû")
        }
    }

    static var settingTitle: String {
        StoreFeatureText.t("Apple Store style", "شكل متجر Apple", "Apple-Store-Stil", "شێوازی ستۆری Apple", "Şêwaza Apple Store")
    }

    static var explanation: String {
        StoreFeatureText.t(
            "Classic keeps the familiar store layout. New adds glass cards, animations and a single floating bar. Sign-in, downloads, installs and your wishlist stay the same.",
            "الكلاسيكي بيحافظ على شكل المتجر المعتاد. الجديد بيضيف بطاقات زجاجية وحركات وشريط عائم واحد. تسجيل الدخول والتنزيلات والتثبيت وقائمة الأمنيات تبعك بيضلوا متل ما هني.",
            "Klassisch behält das gewohnte Store-Layout. Neu bringt Glaskarten, Animationen und eine einzige schwebende Leiste. Anmeldung, Downloads, Installationen und deine Wunschliste bleiben gleich.",
            "کلاسیکی ڕووکاری ئاشنای ستۆرەکە دەهێڵێتەوە. نوێ کارتی شووشەیی، جووڵە و یەک شریتی هەڵواسراو زیاد دەکات. چوونەژوورەوە، داگرتن، دامەزراندن و لیستی خواستەکانت وەک خۆیان دەمێننەوە.",
            "Klasîk xuyanga naskirî ya store diparêze. Nû kartên camî, anîmasyon û yek darikê herikî lê zêde dike. Têketin, daxistin, sazkirin û lîsteya te ya daxwazan wekî xwe dimînin.")
    }
}

/// The App Store tab: picks the Classic or New views on the fly (no restart).
struct StoreStyleTab: View {
    @AppStorage(StoreStyle.key) private var style = StoreStyle.fallback.rawValue
    var body: some View {
        switch StoreStyle.from(style) {
        case .classic: ClassicEncryptedAppsTab()
        case .new: EncryptedAppsTab()
        }
    }
}

/// Picker used by the store's own settings page and Mirsa's main settings.
struct StoreStylePicker: View {
    @AppStorage(StoreStyle.key) private var style = StoreStyle.fallback.rawValue
    var body: some View {
        Picker(StoreStyle.settingTitle, selection: $style) {
            ForEach(StoreStyle.allCases) { s in Text(s.title).tag(s.rawValue) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("store-style-picker")
    }
}

/// Store settings row: the two choices inside the style's own settings group
/// (the group carries the title and the explanation footer).
struct StoreStyleSettingBlock: View {
    var body: some View {
        StoreStylePicker()
            .padding(.horizontal, MirsaSpacing.card).padding(.vertical, 12)
            .accessibilityIdentifier("store-style-setting")
    }
}
