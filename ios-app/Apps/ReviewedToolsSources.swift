import Foundation
import SwiftUI

// Hand-curated directory cards only. No remote manifests, artwork, package bytes,
// depictions, downloads, imports or installation paths belong to this surface.
enum ReviewedToolsSourceID: String, CaseIterable {
    case googleFonts, kenney, chariz, returnYouTubeDislike
}

enum ReviewedToolsText {
    enum Key: CaseIterable, Equatable {
        case title, directory, consent, enable, revoke, hideSource, restoreSource
        case hideItem, restoreItem, hiddenItems, officialWebsite, unavailable, rightsPending
        case ofl, cc0, latinFont, arabicFont, interfaceAudio, uiAudio, cylinder, dislike
    }

    static func text(_ key: Key, language: AppLanguage = AppLanguageStore.snapshot) -> String {
        let values: [String]
        // Order is explicit and shared with the app's five language cases.
        switch key {
        case .title: values = ["Selected sources", "مصادر مختارة", "Ausgewählte Quellen", "Çavkaniyên bijartî", "سەرچاوە هەڵبژێردراوەکان"]
        case .directory: values = ["Third-party directory", "دليل مصادر خارجية", "Drittanbieter-Verzeichnis", "Rêbera aliyên sêyem", "ڕێبەری لایەنی سێیەم"]
        case .consent: values = ["Show selected information and links? Websites open outside Mirsa and have their own privacy policies. No source is contacted until you open a link.", "بدك تظهر المعلومات والروابط المختارة؟ المواقع بتفتح خارج مرسى وإلها سياسات خصوصية خاصة. ما منتصل بالمصدر إلا لما تفتح رابط.", "Ausgewählte Informationen und Links anzeigen? Websites öffnen außerhalb von Mirsa und haben eigene Datenschutzregeln. Erst beim Öffnen eines Links wird die Quelle kontaktiert.", "Agahî û girêdanên bijartî nîşan bide? Malper li derveyî Mirsa vedibin û polîtîkayên wan ên taybetiyê hene. Heta ku girêdanê venekî, têkilî bi çavkaniyê re nayê kirin.", "زانیاری و بەستەرە هەڵبژێردراوەکان پیشان بدرێن؟ ماڵپەڕەکان لە دەرەوەی میرسە دەکرێنەوە و سیاسەتی تایبەتمەندی خۆیان هەیە. تا بەستەرێک نەکەیتەوە پەیوەندی بە سەرچاوەکەوە ناکرێت."]
        case .enable: values = ["Show this source", "أظهر هالمصدر", "Diese Quelle anzeigen", "Vê çavkaniyê nîşan bide", "ئەم سەرچاوەیە پیشان بدە"]
        case .revoke: values = ["Turn off source", "أوقف هالمصدر", "Quelle deaktivieren", "Çavkaniyê neçalak bike", "سەرچاوە ناچالاک بکە"]
        case .hideSource: values = ["Hide source", "أخفي المصدر", "Quelle ausblenden", "Çavkaniyê veşêre", "سەرچاوە بشارەوە"]
        case .restoreSource: values = ["Restore source", "رجّع المصدر", "Quelle wiederherstellen", "Çavkaniyê vegerîne", "سەرچاوە بگەڕێنەوە"]
        case .hideItem: values = ["Hide item", "أخفي العنصر", "Eintrag ausblenden", "Hêmanê veşêre", "بڕگە بشارەوە"]
        case .restoreItem: values = ["Restore item", "رجّع العنصر", "Eintrag wiederherstellen", "Hêmanê vegerîne", "بڕگە بگەڕێنەوە"]
        case .hiddenItems: values = ["Hidden items", "العناصر المخفية", "Ausgeblendete Einträge", "Hêmanên veşartî", "بڕگە شاراوەکان"]
        case .officialWebsite: values = ["Official website ↗", "الموقع الرسمي ↗", "Offizielle Website ↗", "Malpera fermî ↗", "ماڵپەڕی فەرمی ↗"]
        case .unavailable: values = ["No files approved. Downloads, import and installation are unavailable in Mirsa.", "ما في ملفات موافَق عليها. التنزيل والاستيراد والتركيب مو متاحين بمرسى.", "Keine Dateien freigegeben. Download, Import und Installation sind in Mirsa nicht verfügbar.", "Tu pel nehatiye pejirandin. Daxistin, anîn û sazkirin di Mirsa de ne berdest in.", "هیچ پەڕگەیەک پەسەند نەکراوە. داگرتن و هاوردەکردن و دامەزراندن لە میرسە بەردەست نین."]
        case .rightsPending: values = ["Directory link only. Package redistribution and full repository listing rights have not been established.", "رابط دليل فقط. حقوق إعادة توزيع الحزم وعرض المستودع كامل لسا مو مؤكدة.", "Nur Verzeichnislink. Rechte zur Paketweitergabe und vollständigen Repository-Auflistung sind nicht geklärt.", "Tenê girêdana rêberê. Mafên belavkirina pakêtan û lîsteya tevahî ya depoyê nehatine piştrastkirin.", "تەنها بەستەری ڕێبەرە. مافی دابەشکردنەوەی پاکەت و لیستکردنی تەواوی کۆگا هێشتا پشتڕاست نەکراوەتەوە."]
        case .ofl: values = ["Selected font families · SIL Open Font License 1.1", "عائلات الخطوط المختارة · ترخيص SIL Open Font License 1.1", "Ausgewählte Schriftfamilien · SIL Open Font License 1.1", "Malbatên nivîsê yên bijartî · SIL Open Font License 1.1", "خێزانە فۆنتە هەڵبژێردراوەکان · SIL Open Font License 1.1"]
        case .cc0: values = ["Selected audio packs · CC0", "حزم الصوت المختارة · CC0", "Ausgewählte Audiopakete · CC0", "Pakêtên dengê yên bijartî · CC0", "پاکەتە دەنگە هەڵبژێردراوەکان · CC0"]
        case .latinFont: values = ["Sans-serif family for Latin, Greek and Cyrillic text.", "عائلة خطوط بلا زوائد للنصوص اللاتينية واليونانية والسيريلية.", "Serifenlose Schriftfamilie für lateinische, griechische und kyrillische Texte.", "Malbata nivîsa bêserî ji bo nivîsa Latînî, Yewnanî û Kirîlî.", "خێزانی فۆنتی بێسەریف بۆ دەقی لاتینی و یۆنانی و سیریلی."]
        case .arabicFont: values = ["Naskh-style family for Arabic-script text.", "عائلة بخط النسخ للنصوص المكتوبة بالحرف العربي.", "Schriftfamilie im Naskh-Stil für arabische Schrift.", "Malbata nivîsê bi şêwaza Nesxê ji bo tîpên Erebî.", "خێزانی فۆنتی شێوازی نەسخ بۆ دەقی ئەلفوبێی عەرەبی."]
        case .interfaceAudio: values = ["Interface clicks and feedback sounds by Kenney.", "نقرات وأصوات تفاعل للواجهات من Kenney.", "Klick- und Rückmeldetöne für Oberflächen von Kenney.", "Dengên tikandin û bersivê yên navrûyê ji Kenney.", "دەنگی کرتە و کارلێکی ڕووکار لەلایەن Kenney."]
        case .uiAudio: values = ["Button, switch and click sounds by Kenney.", "أصوات أزرار ومفاتيح ونقرات من Kenney.", "Tasten-, Schalter- und Klicktöne von Kenney.", "Dengên bişkok, guherker û tikandinê ji Kenney.", "دەنگی دوگمە و گۆڕین و کرتە لەلایەن Kenney."]
        case .cylinder: values = ["Home Screen icon scrolling animations by Ryan Nair. The publisher requires a jailbreak; Mirsa compatibility is not verified.", "حركات أيقونات عند تقليب الشاشة الرئيسية من Ryan Nair. الناشر بيشترط جيلبريك؛ التوافق مع مرسى مو متحقق منه.", "Animationen für Symbole beim Blättern des Home-Bildschirms von Ryan Nair. Laut Anbieter ist ein Jailbreak nötig; Mirsa-Kompatibilität ist nicht geprüft.", "Anîmasyonên îkonan di guherandina rûpelên ekrana sereke de ji Ryan Nair. Belavker jailbreak dixwaze; lihevhatina Mirsa nehatiye piştrastkirin.", "جوڵەی ئایکۆنەکانی شاشەی سەرەکی لەلایەن Ryan Nair. بڵاوکەرەوە جەیلبریک داوا دەکات؛ گونجانی میرسە پشتڕاست نەکراوەتەوە."]
        case .dislike: values = ["Displays estimated YouTube dislike counts. Project information only; no ready-made iOS package is approved here.", "بيعرض تقديرات عدد عدم الإعجاب على YouTube. معلومات عن المشروع فقط؛ ما في حزمة iOS جاهزة موافَق عليها هون.", "Zeigt geschätzte YouTube-Dislikes. Nur Projektinformationen; hier ist kein fertiges iOS-Paket freigegeben.", "Hejmara texmînkirî ya nehezkirinan li YouTube nîşan dide. Tenê agahiya projeyê; li vir tu pakêta iOS ya amade nehatiye pejirandin.", "ژمارەی خەمڵێنراوی دیسلایکی YouTube پیشان دەدات. تەنها زانیاریی پڕۆژەیە؛ لێرە هیچ پاکەتێکی ئامادەی iOS پەسەند نەکراوە."]
        }
        switch language {
        case .english: return values[0]
        case .arabic: return values[1]
        case .german: return values[2]
        case .kurmanji: return values[3]
        case .sorani: return values[4]
        }
    }
}

/// Allow only the exact reviewed landing pages, never arbitrary same-host paths,
/// query strings, depictions, custom schemes or package URLs. No network fetching.
enum ReviewedToolsLinkPolicy {
    static let pages: [ReviewedToolsSourceID: Set<String>] = [
        .googleFonts: ["https://fonts.google.com/noto/specimen/Noto+Sans",
                       "https://fonts.google.com/noto/specimen/Noto+Naskh+Arabic"],
        .kenney: ["https://kenney.nl/assets/interface-sounds", "https://kenney.nl/assets/ui-audio"],
        .chariz: ["https://chariz.com/get/cylinder-reborn"],
        .returnYouTubeDislike: ["https://returnyoutubedislike.com/"]
    ]

    static func officialPage(_ raw: String, source: ReviewedToolsSourceID) -> URL? {
        guard pages[source]?.contains(raw) == true,
              let c = URLComponents(string: raw), c.scheme == "https",
              c.user == nil, c.password == nil, c.port == nil,
              c.query == nil, c.fragment == nil,
              let url = c.url, url.absoluteString == raw else { return nil }
        return url
    }
}

struct ReviewedToolsEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: ReviewedToolsText.Key
    let officialPage: String
}

struct ReviewedToolsSource: Identifiable {
    let id: ReviewedToolsSourceID
    let category: ToolsStoreCategory
    let name: String
    let notice: ReviewedToolsText.Key
    let entries: [ReviewedToolsEntry]

    /// Landing-page approval never grants any binary capability.
    var allowsDownloads: Bool { false }
    var allowsImport: Bool { false }
    var allowsInstallation: Bool { false }
    var allowsRepositoryIngestion: Bool { false }
}

enum ReviewedToolsDirectory {
    // Facts checked against original landing/license pages on 2026-11-22.
    // License labels apply ONLY to the selected font families / audio packs.
    // Chariz has no asserted repository-wide open-content license.
    static let sources: [ReviewedToolsSource] = [
        .init(id: .googleFonts, category: .fonts, name: "Google Fonts · Noto", notice: .ofl, entries: [
            .init(id: "noto-sans", title: "Noto Sans", detail: .latinFont,
                  officialPage: "https://fonts.google.com/noto/specimen/Noto+Sans"),
            .init(id: "noto-naskh-arabic", title: "Noto Naskh Arabic", detail: .arabicFont,
                  officialPage: "https://fonts.google.com/noto/specimen/Noto+Naskh+Arabic")
        ]),
        .init(id: .kenney, category: .sounds, name: "Kenney", notice: .cc0, entries: [
            .init(id: "interface-sounds", title: "Interface Sounds", detail: .interfaceAudio,
                  officialPage: "https://kenney.nl/assets/interface-sounds"),
            .init(id: "ui-audio", title: "UI Audio", detail: .uiAudio,
                  officialPage: "https://kenney.nl/assets/ui-audio")
        ]),
        .init(id: .chariz, category: .tweaks, name: "Chariz", notice: .rightsPending, entries: [
            .init(id: "cylinder-reborn", title: "Cylinder Reborn", detail: .cylinder,
                  officialPage: "https://chariz.com/get/cylinder-reborn")
        ]),
        .init(id: .returnYouTubeDislike, category: .appTweaks, name: "Return YouTube Dislike", notice: .rightsPending, entries: [
            .init(id: "return-youtube-dislike", title: "Return YouTube Dislike", detail: .dislike,
                  officialPage: "https://returnyoutubedislike.com/")
        ])
    ]

    static func sources(for category: ToolsStoreCategory) -> [ReviewedToolsSource] {
        // This feature has no wallpaper catalog and cannot alter existing sources.
        guard category != .wallpapers else { return [] }
        return sources.filter { $0.category == category }
    }
}

/// Local-only preferences, with versioned consent. Hide/restore never opts in.
/// Revocation preserves hidden choices, but removes every item and link.
struct ReviewedToolsPreferences {
    private let defaults: UserDefaults
    private static let prefix = "mirsa.reviewed-tools.directory.v1."
    private(set) var enabled: Set<String>
    private(set) var hiddenSources: Set<String>
    private(set) var hiddenItems: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = Set(defaults.stringArray(forKey: Self.prefix + "enabled") ?? [])
        hiddenSources = Set(defaults.stringArray(forKey: Self.prefix + "hiddenSources") ?? [])
        hiddenItems = Set(defaults.stringArray(forKey: Self.prefix + "hiddenItems") ?? [])
    }

    func isEnabled(_ source: ReviewedToolsSourceID) -> Bool { enabled.contains(source.rawValue) }
    func isHidden(_ source: ReviewedToolsSourceID) -> Bool { hiddenSources.contains(source.rawValue) }
    private func key(_ item: ReviewedToolsEntry, source: ReviewedToolsSource) -> String {
        source.id.rawValue + "/" + item.id
    }
    func isHidden(_ item: ReviewedToolsEntry, source: ReviewedToolsSource) -> Bool {
        hiddenItems.contains(key(item, source: source))
    }
    mutating func setEnabled(_ value: Bool, source: ReviewedToolsSourceID) {
        if value { enabled.insert(source.rawValue) } else { enabled.remove(source.rawValue) }
        persist()
    }
    mutating func setHidden(_ value: Bool, source: ReviewedToolsSourceID) {
        if value { hiddenSources.insert(source.rawValue) } else { hiddenSources.remove(source.rawValue) }
        persist()
    }
    mutating func setHidden(_ value: Bool, item: ReviewedToolsEntry, source: ReviewedToolsSource) {
        guard source.entries.contains(item) else { return }
        let id = key(item, source: source)
        if value { hiddenItems.insert(id) } else { hiddenItems.remove(id) }
        persist()
    }
    func visibleEntries(in source: ReviewedToolsSource) -> [ReviewedToolsEntry] {
        guard isEnabled(source.id), !isHidden(source.id), source.category != .wallpapers else { return [] }
        return source.entries.filter {
            !isHidden($0, source: source) &&
            ReviewedToolsLinkPolicy.officialPage($0.officialPage, source: source.id) != nil
        }
    }
    func link(for item: ReviewedToolsEntry, source: ReviewedToolsSource) -> URL? {
        guard visibleEntries(in: source).contains(item) else { return nil }
        return ReviewedToolsLinkPolicy.officialPage(item.officialPage, source: source.id)
    }
    private func persist() {
        defaults.set(enabled.sorted(), forKey: Self.prefix + "enabled")
        defaults.set(hiddenSources.sorted(), forKey: Self.prefix + "hiddenSources")
        defaults.set(hiddenItems.sorted(), forKey: Self.prefix + "hiddenItems")
    }
}

/// Embedded in the parent store ScrollView. No nested vertical scrolling or web content.
struct ReviewedToolsSourcesView: View {
    let category: ToolsStoreCategory
    @State private var preferences = ReviewedToolsPreferences()
    @ObservedObject private var language = AppLanguageStore.shared
    @AppStorage(SourcesTheme.key) private var themeRaw = SourcesTheme.aurora.rawValue
    private var theme: SourcesTheme { SourcesTheme(rawValue: themeRaw) ?? .aurora }
    private func text(_ key: ReviewedToolsText.Key) -> String {
        ReviewedToolsText.text(key, language: language.current)
    }

    var body: some View {
        let sources = ReviewedToolsDirectory.sources(for: category)
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(text(.title)).font(.title3.bold()).foregroundStyle(theme.text)
                ForEach(sources) { source in sourceCard(source) }
            }
            .accessibilityIdentifier("reviewed-tools-sources")
        }
    }

    private func sourceCard(_ source: ReviewedToolsSource) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: source.category.icon)
                    .font(.title3).foregroundStyle(theme.accentGradient)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.name).font(.headline).foregroundStyle(theme.text)
                    Text(text(.directory)).font(.caption).foregroundStyle(theme.secondary)
                }
                Spacer(minLength: 0)
            }
            if preferences.isHidden(source.id) {
                Button(text(.restoreSource)) { preferences.setHidden(false, source: source.id) }
                    .accessibilityIdentifier("reviewed-source-restore-" + source.id.rawValue)
            } else {
                if preferences.isEnabled(source.id) {
                    Text(text(source.notice)).font(.caption).foregroundStyle(theme.secondary)
                    Text(text(.unavailable)).font(.caption).foregroundStyle(theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(preferences.visibleEntries(in: source)) { item in itemRow(item, source: source) }
                    hiddenItems(source)
                    Button(text(.revoke)) { preferences.setEnabled(false, source: source.id) }
                        .accessibilityIdentifier("reviewed-source-revoke-" + source.id.rawValue)
                } else {
                    Text(text(.consent)).font(.callout).foregroundStyle(theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(text(.enable)) { preferences.setEnabled(true, source: source.id) }
                        .accessibilityIdentifier("reviewed-source-enable-" + source.id.rawValue)
                }
                Button(text(.hideSource)) { preferences.setHidden(true, source: source.id) }
                    .font(.caption)
                    .accessibilityIdentifier("reviewed-source-hide-" + source.id.rawValue)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(theme.stroke))
        .accessibilityIdentifier("reviewed-source-" + source.id.rawValue)
    }

    private func itemRow(_ item: ReviewedToolsEntry, source: ReviewedToolsSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(theme.stroke)
            Text(item.title).font(.subheadline.bold()).foregroundStyle(theme.text)
            Text(text(item.detail)).font(.caption).foregroundStyle(theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let url = preferences.link(for: item, source: source) {
                Link(text(.officialWebsite), destination: url)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityLabel(item.title + " · " + text(.officialWebsite))
                    .accessibilityIdentifier("reviewed-item-link-" + item.id)
            }
            Button(text(.hideItem)) { preferences.setHidden(true, item: item, source: source) }
                .font(.caption)
                .accessibilityLabel(item.title + " · " + text(.hideItem))
                .accessibilityIdentifier("reviewed-item-hide-" + item.id)
        }
    }

    @ViewBuilder private func hiddenItems(_ source: ReviewedToolsSource) -> some View {
        let hidden = source.entries.filter { preferences.isHidden($0, source: source) }
        if !hidden.isEmpty {
            DisclosureGroup(text(.hiddenItems)) {
                ForEach(hidden) { item in
                    Button { preferences.setHidden(false, item: item, source: source) } label: {
                        Text(item.title + " · " + text(.restoreItem))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("reviewed-item-restore-" + item.id)
                }
            }.font(.caption).foregroundStyle(theme.secondary)
        }
    }
}
