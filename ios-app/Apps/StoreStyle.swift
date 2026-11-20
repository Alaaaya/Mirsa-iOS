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
            "Classic keeps the familiar store layout. New is a dark gallery: a large featured app, ranked charts, collections and a floating glass bar above Mirsa's dock. Sign-in, downloads, installs and your wishlist stay the same.",
            "الكلاسيكي بيحافظ على شكل المتجر المعتاد. الجديد معرض داكن: تطبيق مميّز كبير، ترتيب الأكثر تنزيلًا، مجموعات، وشريط زجاجي عائم فوق شريط مرسى. تسجيل الدخول والتنزيلات والتثبيت وقائمة الأمنيات تبعك بيضلوا متل ما هني.",
            "Klassisch behält das gewohnte Store-Layout. Neu ist eine dunkle Galerie: eine große empfohlene App, Ranglisten, Sammlungen und eine schwebende Glasleiste über Mirsas Dock. Anmeldung, Downloads, Installationen und deine Wunschliste bleiben gleich.",
            "کلاسیکی ڕووکاری ئاشنای ستۆرەکە دەهێڵێتەوە. نوێ پێشانگایەکی تاریکە: ئەپێکی دیاری گەورە، لیستی زۆرترین داگیراو، کۆمەڵەکان و شریتێکی شووشەیی هەڵواسراو لەسەر شریتی Mirsa. چوونەژوورەوە، داگرتن، دامەزراندن و لیستی خواستەکانت وەک خۆیان دەمێننەوە.",
            "Klasîk xuyanga naskirî ya store diparêze. Nû galeriyeke tarî ye: sepaneke taybet a mezin, rêzbendiyên herî zêde daxistî, kom û darikekî camî yê herikî li ser darika Mirsa. Têketin, daxistin, sazkirin û lîsteya te ya daxwazan wekî xwe dimînin.")
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
