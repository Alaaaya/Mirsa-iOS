import SwiftUI

// MARK: - Five-language text for the redesigned Sources screens and the Tools Store

/// Same convention as `StoreFeatureText`: every string carries en, ar, de, ckb and kmr.
enum SourcesText {
    static func t(_ en: String, _ ar: String, _ de: String, _ ckb: String, _ kmr: String) -> String {
        switch AppLanguageStore.snapshot {
        case .english: return en
        case .arabic: return ar
        case .german: return de
        case .sorani: return ckb
        case .kurmanji: return kmr
        }
    }

    static var title: String { t("Sources", "السورسات", "Quellen", "سەرچاوەکان", "Çavkanî") }
    static var library: String { t("Your library", "مكتبتك", "Deine Bibliothek", "کتێبخانەکەت", "Pirtûkxaneya te") }
    static var statSources: String { t("Sources", "سورسات", "Quellen", "سەرچاوە", "Çavkanî") }
    static var statApps: String { t("Apps", "تطبيق", "Apps", "ئەپ", "Sepan") }
    static var statUpdatedToday: String { t("Updated today", "تحديث اليوم", "Heute aktualisiert", "ئەمڕۆ نوێکراوە", "Îro hate nûkirin") }
    static var newBadge: String { t("New", "جديد", "Neu", "نوێ", "Nû") }
    static var lastUpdated: String { t("Last updated", "آخر تحديث", "Zuletzt aktualisiert", "دوایین نوێکردنەوە", "Nûkirina dawî") }
    static var today: String { t("Today", "اليوم", "Heute", "ئەمڕۆ", "Îro") }
    static var newThisWeek: String { t("New this week", "جديد هذا الأسبوع", "Neu diese Woche", "نوێ لەم هەفتەیە", "Nû vê hefteyê") }
    static var appsSection: String { t("Apps", "التطبيقات", "Apps", "ئەپەکان", "Sepan") }
    static var all: String { t("All", "الكل", "Alle", "هەموو", "Hemû") }
    static var searchSources: String { t("Search sources", "ابحث في السورسات", "Quellen durchsuchen", "گەڕان لە سەرچاوەکان", "Di çavkaniyan de bigere") }
    static var searchApps: String { t("Search apps", "ابحث عن تطبيق", "Apps suchen", "گەڕان بۆ ئەپ", "Li sepanan bigere") }
    static var noMatchingSources: String { t("No matching sources.", "ما في سورسات مطابقة.", "Keine passenden Quellen.", "هیچ سەرچاوەیەکی گونجاو نییە.", "Çavkaniyên lihevhatî tune ne.") }
    static var edit: String { t("Edit", "تعديل", "Bearbeiten", "دەستکاری", "Biguherîne") }
    static var done: String { t("Done", "تم", "Fertig", "تەواو", "Qediya") }
    static var addSource: String { t("Add Source", "أضف سورس", "Quelle hinzufügen", "زیادکردنی سەرچاوە", "Çavkanî zêde bike") }
    static var findOnWeb: String { t("Find apps", "اكتشف تطبيقات", "Apps finden", "دۆزینەوەی ئەپ", "Sepanan bibîne") }
    static var shareSource: String { t("Share source", "مشاركة السورس", "Quelle teilen", "هاوبەشکردنی سەرچاوە", "Çavkaniyê parve bike") }
    static var grid: String { t("Grid", "شبكة", "Raster", "تۆڕ", "Tor") }
    static var list: String { t("List", "قائمة", "Liste", "لیست", "Lîste") }
    static var theme: String { t("Source theme", "ثيم السورس", "Quellen-Design", "ڕووکاری سەرچاوە", "Rûkara çavkaniyê") }

    // App detail sheet
    static var get: String { t("GET", "تثبيت", "LADEN", "دامەزراندن", "SAZ BIKE") }
    static var installed: String { t("Installed", "مثبّت", "Installiert", "دامەزراوە", "Sazkirî") }
    static var update: String { t("UPDATE", "تحديث", "UPDATE", "نوێکردنەوە", "NÛ BIKE") }
    static var choose: String { t("Choose", "اختيار", "Auswählen", "هەڵبژاردن", "Hilbijêre") }
    static var downloading: String { t("Downloading…", "عم يتحمّل…", "Wird geladen…", "دادەبەزێت…", "Tê daxistin…") }
    static var installNow: String { t("Install now", "تثبيت الآن", "Jetzt installieren", "ئێستا دابمەزرێنە", "Niha saz bike") }
    static var updateNow: String { t("Update now", "تحديث الآن", "Jetzt aktualisieren", "ئێستا نوێی بکەرەوە", "Niha nû bike") }
    static var reinstall: String { t("Install again", "إعادة التثبيت", "Erneut installieren", "دووبارە دامەزراندن", "Dîsa saz bike") }
    static var downloadIPA: String { t("Download IPA", "تنزيل الـIPA", "IPA laden", "داگرتنی IPA", "IPA daxe") }
    static var savedToDownloads: String { t("Saved to Mirsa Downloads.", "انحفظ بتنزيلات مرسى.", "In Mirsa-Downloads gesichert.", "لە داگرتنەکانی Mirsa پاشەکەوت کرا.", "Di daxistinên Mirsa de hate tomarkirin.") }
    static var version: String { t("Version", "الإصدار", "Version", "وەشان", "Guherto") }
    static var size: String { t("Size", "الحجم", "Größe", "قەبارە", "Mezinahî") }
    static var source: String { t("Source", "السورس", "Quelle", "سەرچاوە", "Çavkanî") }
    static var compatibility: String { t("Compatibility", "التوافق", "Kompatibilität", "گونجاندن", "Lihevhatin") }
    static var whatsNew: String { t("What's New", "ما الجديد", "Neuigkeiten", "چی نوێیە", "Çi nû ye") }
    static var about: String { t("About", "عن التطبيق", "Info", "دەربارە", "Derbar") }
    static var close: String { t("Close", "إغلاق", "Schließen", "داخستن", "Bigire") }
    static var notice: String { t("Notice", "تنبيه", "Hinweis", "ئاگاداری", "Agahdarî") }
    static var ok: String { t("OK", "تمام", "OK", "باشە", "Baş e") }

    // Themes
    static var aurora: String { t("Aurora", "شفق", "Polarlicht", "شەفەق", "Berbang") }
    static var sunset: String { t("Sunset", "غروب", "Sonnenuntergang", "خۆرئاوابوون", "Avabûna rojê") }
    static var ocean: String { t("Ocean", "محيط", "Ozean", "زەریا", "Okyanûs") }
    static var light: String { t("Light", "فاتح", "Hell", "ڕووناک", "Ronî") }
}

// MARK: - Theme for the Sources screens (and the Tools Store, which follows it)

enum SourcesTheme: String, CaseIterable, Identifiable {
    case aurora, sunset, ocean, light
    static let key = "mirsa.sourceTheme"
    var id: String { rawValue }

    static var current: SourcesTheme {
        SourcesTheme(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .aurora
    }

    var title: String {
        switch self {
        case .aurora: return SourcesText.aurora
        case .sunset: return SourcesText.sunset
        case .ocean: return SourcesText.ocean
        case .light: return SourcesText.light
        }
    }

    var isLight: Bool { self == .light }
    var colorScheme: ColorScheme { isLight ? .light : .dark }

    /// Gradient pair for primary buttons (install, +, store actions).
    var accent: [Color] {
        switch self {
        case .aurora: return [Color(sourcesRGB: 0x8B5CF6), Color(sourcesRGB: 0x5B8CFF)]
        case .sunset: return [Color(sourcesRGB: 0xF97316), Color(sourcesRGB: 0xEC4899)]
        case .ocean: return [Color(sourcesRGB: 0x14B8A6), Color(sourcesRGB: 0x3B82F6)]
        case .light: return [Color(sourcesRGB: 0x7C3AED), Color(sourcesRGB: 0x6366F1)]
        }
    }
    var accentGradient: LinearGradient { LinearGradient(colors: accent, startPoint: .leading, endPoint: .trailing) }

    var glow: Color {
        switch self {
        case .aurora: return Color(sourcesRGB: 0x4B2A9C)
        case .sunset: return Color(sourcesRGB: 0x9A3412)
        case .ocean: return Color(sourcesRGB: 0x0F766E)
        case .light: return Color(sourcesRGB: 0xE9DCFF)
        }
    }

    var base: [Color] {
        isLight ? [Color(sourcesRGB: 0xF6F4FB), Color(sourcesRGB: 0xEFEAF9)]
                : [Color(sourcesRGB: 0x120C2E), Color(sourcesRGB: 0x0A0A1C)]
    }

    var text: Color { isLight ? Color(sourcesRGB: 0x17132E) : .white }
    var secondary: Color { isLight ? Color(sourcesRGB: 0x7D7896) : Color(sourcesRGB: 0xA7A2C4) }
    var card: Color { isLight ? .white : Color.white.opacity(0.07) }
    var stroke: Color { isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12) }
    var success: Color { isLight ? Color(sourcesRGB: 0x15803D) : Color(sourcesRGB: 0x86EFAC) }
    var sheetBase: [Color] {
        isLight ? base : [Color(sourcesRGB: 0x2A1D5E), Color(sourcesRGB: 0x151036), Color(sourcesRGB: 0x0D0B22)]
    }
}

extension Color {
    /// 0xRRGGBB literal. Named apart from the existing `Color(hex: String?)` so call sites never become ambiguous.
    init(sourcesRGB hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

private struct SourcesThemeKey: EnvironmentKey {
    static let defaultValue: SourcesTheme? = nil
}

extension EnvironmentValues {
    /// Set by the Sources screens. Shared rows (e.g. `RepoAppRow`, also used by Discovery) fall back to the
    /// dark Aurora colours when they are shown outside a themed Sources screen.
    var sourcesTheme: SourcesTheme? {
        get { self[SourcesThemeKey.self] }
        set { self[SourcesThemeKey.self] = newValue }
    }
}

/// Full-page backdrop for a Sources screen in the selected theme.
struct SourcesThemeBackground: View {
    let theme: SourcesTheme
    var glowTint: Color? = nil
    var body: some View {
        ZStack {
            LinearGradient(colors: theme.base, startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [theme.glow.opacity(theme.isLight ? 1 : 0.9), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [theme.accent[1].opacity(theme.isLight ? 0.15 : 0.25), .clear],
                           center: .leading, startRadius: 0, endRadius: 380)
            if let glowTint {
                RadialGradient(colors: [glowTint.opacity(theme.isLight ? 0.35 : 0.55), .clear],
                               center: UnitPoint(x: 0.5, y: 0.08), startRadius: 0, endRadius: 280)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct SourcesGlass<S: InsettableShape>: ViewModifier {
    let theme: SourcesTheme
    let shape: S
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if theme.isLight {
                        shape.fill(Color.white)
                    } else {
                        shape.fill(.ultraThinMaterial.opacity(0.6))
                        shape.fill(theme.card)
                    }
                }
            }
            .overlay(shape.strokeBorder(theme.stroke, lineWidth: 1))
            .shadow(color: theme.isLight ? Color(sourcesRGB: 0x3C2878).opacity(0.08) : .clear, radius: 12, y: 4)
    }
}

extension View {
    func sourcesGlass(_ theme: SourcesTheme, radius: CGFloat = 22) -> some View {
        modifier(SourcesGlass(theme: theme, shape: RoundedRectangle(cornerRadius: radius, style: .continuous)))
    }
    func sourcesGlassCapsule(_ theme: SourcesTheme) -> some View {
        modifier(SourcesGlass(theme: theme, shape: Capsule()))
    }
}

/// 42 pt round button label; `filled` uses the theme gradient (the + button).
struct SourcesCircleLabel: View {
    let systemName: String
    let theme: SourcesTheme
    var filled = false
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(filled ? Color.white : theme.text)
            .frame(width: 42, height: 42)
            .background {
                if filled {
                    Circle().fill(theme.accentGradient)
                        .shadow(color: theme.accent[0].opacity(0.45), radius: 10, y: 5)
                } else {
                    Circle().fill(theme.card).overlay(Circle().stroke(theme.stroke))
                }
            }
            .contentShape(Circle())
    }
}

/// Capsule action label: gradient when it is the primary action, green tick when installed.
struct SourcesPillLabel: View {
    let title: String
    let theme: SourcesTheme
    var installed = false
    /// Fills the available width (grid tiles) instead of hugging the title.
    var expand = false
    var body: some View {
        Group {
            if installed {
                Label(title, systemImage: "checkmark")
                    .lineLimit(1)
                    .frame(maxWidth: expand ? .infinity : nil)
                    .foregroundStyle(theme.isLight ? Color(sourcesRGB: 0x15803D) : Color(sourcesRGB: 0x6EE7B7))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color(sourcesRGB: 0x34D399).opacity(0.15)))
                    .overlay(Capsule().stroke(Color(sourcesRGB: 0x34D399).opacity(0.35)))
            } else {
                Text(title)
                    .lineLimit(1)
                    .frame(maxWidth: expand ? .infinity : nil)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Capsule().fill(theme.accentGradient))
                    .shadow(color: theme.accent[0].opacity(0.4), radius: 8, y: 4)
            }
        }
        .font(.system(size: 13, weight: .bold))
        .fixedSize(horizontal: !expand, vertical: false)
    }
}

/// Palette menu that switches the Sources theme. The choice is persisted in `SourcesTheme.key`.
struct SourcesThemeMenu: View {
    @AppStorage(SourcesTheme.key) private var themeRaw = SourcesTheme.aurora.rawValue
    private var theme: SourcesTheme { SourcesTheme(rawValue: themeRaw) ?? .aurora }
    var body: some View {
        Menu {
            Picker(SourcesText.theme, selection: Binding(get: { theme }, set: { value in
                withAnimation(.easeInOut(duration: 0.35)) { themeRaw = value.rawValue }
            })) {
                ForEach(SourcesTheme.allCases) { item in
                    Label(item.title, systemImage: item.isLight ? "sun.max.fill" : "moon.stars.fill").tag(item)
                }
            }
        } label: {
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: theme.accent, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 42, height: 42)
                .background(Circle().fill(theme.card).overlay(Circle().stroke(theme.stroke)))
                .contentShape(Circle())
        }
        .accessibilityLabel(SourcesText.theme)
        .accessibilityIdentifier("sources-theme-menu")
    }
}

/// Search capsule used on the Sources list, the source page and the Tools Store.
struct SourcesSearchField: View {
    let placeholder: String
    let theme: SourcesTheme
    @Binding var text: String
    var identifier: String = "sources-search"
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.secondary)
            TextField(placeholder, text: $text)
                .foregroundStyle(theme.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MirsaTr.lit("Clear"))
                .accessibilityIdentifier(identifier + "-clear")
            }
        }
        .padding(.horizontal, 16).frame(height: 46)
        .sourcesGlass(theme, radius: 23)
    }
}

enum SourcesDates {
    /// "Recently updated" for the New badge: within the last 48 hours.
    static func isRecent(_ date: Date?, now: Date = Date()) -> Bool {
        guard let date else { return false }
        let age = now.timeIntervalSince(date)
        return age >= -3600 && age <= 48 * 3600
    }
    static func label(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? SourcesText.today : date.formatted(date: .numeric, time: .omitted)
    }
}
