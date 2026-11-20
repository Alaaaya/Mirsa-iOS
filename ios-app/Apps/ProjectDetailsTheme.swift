import SwiftUI

// MARK: - Five-language text for the Project details themes

/// Every string carries en, ar, de, ckb and kmr through the shared `tr5` helper.
enum ProjectThemeText {
    static var menuTitle: String { tr5("Project details theme", "ثيم تفاصيل المشروع", de: "Design der Projektdetails", ckb: "ڕووکاری وردەکارییەکانی پرۆژە", kmr: "Rûkara hûrguliyên projeyê") }

    // Theme names
    static var classic: String { tr5("Classic", "الأساسي", de: "Klassisch", ckb: "کلاسیک", kmr: "Klasîk") }
    static var obsidianGold: String { tr5("Obsidian Gold", "الذهبي الأسود", de: "Obsidian-Gold", ckb: "ئاڵتوونی ڕەش", kmr: "Zêrê reş") }
    static var aurora: String { tr5("Aurora", "الشفق", de: "Polarlicht", ckb: "شەفەق", kmr: "Berbang") }
    static var bento: String { tr5("Bento", "بينتو", de: "Bento", ckb: "بێنتۆ", kmr: "Bento") }
    static var buildPipeline: String { tr5("Build Pipeline", "خط البناء", de: "Build-Pipeline", ckb: "هێڵی دروستکردن", kmr: "Xeta avakirinê") }
    static var lightPearl: String { tr5("Light Pearl", "اللؤلؤي الفاتح", de: "Helle Perle", ckb: "مرواریی ڕووناک", kmr: "Morîya ronî") }

    // Tabs and sections
    static var tweaks: String { tr5("Tweaks", "التويكات", de: "Tweaks", ckb: "تویکەکان", kmr: "Tweak") }
    static var settings: String { tr5("Settings", "الإعدادات", de: "Einstellungen", ckb: "ڕێکخستنەکان", kmr: "Mîheng") }
    static var certificate: String { tr5("Certificate", "الشهادة", de: "Zertifikat", ckb: "بڕوانامە", kmr: "Sertîfîka") }
    static var versions: String { tr5("Versions", "النسخ", de: "Versionen", ckb: "وەشانەکان", kmr: "Guherto") }
    static var files: String { tr5("Files", "الملفات", de: "Dateien", ckb: "فایلەکان", kmr: "Pel") }
    static var app: String { tr5("App", "التطبيق", de: "App", ckb: "ئەپ", kmr: "Sepan") }
    static var appSummary: String { tr5("Name, bundle ID, version, icon", "الاسم، المعرّف، الإصدار، الأيقونة", de: "Name, Bundle-ID, Version, Symbol", ckb: "ناو، ناسنامەی ئەپ، وەشان، ئایکۆن", kmr: "Nav, nasnameya pakêtê, guherto, îkon") }
    static var injectedTweaks: String { tr5("Injected tweaks", "التويكات المحقونة", de: "Injizierte Tweaks", ckb: "تویکە تێخراوەکان", kmr: "Tweakên derzîkirî") }
    static var versionsAndTools: String { tr5("Versions & tools", "النسخ والأدوات", de: "Versionen & Werkzeuge", ckb: "وەشان و ئامرازەکان", kmr: "Guherto û amûr") }
    static var filesAndLogs: String { tr5("Files & logs", "ملفات وسجلات", de: "Dateien & Protokolle", ckb: "فایل و تۆمارەکان", kmr: "Pel û tomar") }
    static var tools: String { tr5("Tools", "أدوات", de: "Werkzeuge", ckb: "ئامرازەکان", kmr: "Amûr") }
    static var output: String { tr5("Output", "ملف الإخراج", de: "Ausgabe", ckb: "دەرچوو", kmr: "Encam") }
    static var savedVersions: String { tr5("Saved versions", "النسخ المحفوظة", de: "Gespeicherte Versionen", ckb: "وەشانە پاشەکەوتکراوەکان", kmr: "Guhertoyên tomarkirî") }
    static var version: String { tr5("Version", "الإصدار", de: "Version", ckb: "وەشان", kmr: "Guherto") }

    // Tweaks
    static var addTweak: String { tr5("Add tweak", "إضافة تويك", de: "Tweak hinzufügen", ckb: "زیادکردنی تویک", kmr: "Tweak zêde bike") }
    static var pendingChanges: String { tr5("Pending changes", "تغييرات بانتظار التوقيع", de: "Ausstehende Änderungen", ckb: "گۆڕانکاریی چاوەڕوان", kmr: "Guhertinên li bendê") }
    static var file: String { tr5("file", "ملف", de: "Datei", ckb: "فایل", kmr: "pel") }
    static var moveUp: String { tr5("Move up", "تحريك لفوق", de: "Nach oben", ckb: "بۆ سەرەوە", kmr: "Biçe jor") }
    static var moveDown: String { tr5("Move down", "تحريك لتحت", de: "Nach unten", ckb: "بۆ خوارەوە", kmr: "Biçe jêr") }
    static var share: String { tr5("Share", "مشاركة", de: "Teilen", ckb: "هاوبەشکردن", kmr: "Parve bike") }
    static var remove: String { tr5("Remove", "إزالة", de: "Entfernen", ckb: "لابردن", kmr: "Rake") }
    static var back: String { tr5("Back", "رجوع", de: "Zurück", ckb: "گەڕانەوە", kmr: "Vegere") }
    static var tapToEdit: String { tr5("Tap to edit", "اضغط للتعديل", de: "Zum Bearbeiten tippen", ckb: "بۆ دەستکاری کرتە بکە", kmr: "Ji bo guhertinê bitikîne") }

    // Settings summary
    static var enabled: String { tr5("Enabled", "مفعّلة", de: "Aktiv", ckb: "چالاک", kmr: "Çalak") }

    // Certificate
    static var signedWith: String { tr5("Signed with", "موقّع بـ", de: "Signiert mit", ckb: "واژۆکراو بە", kmr: "Îmzekirî bi") }
    static var validUntil: String { tr5("Valid until", "صالحة حتى", de: "Gültig bis", ckb: "دروستە تا", kmr: "Derbasdar heta") }
    static var daysLeft: String { tr5("Days left", "الأيام المتبقية", de: "Verbleibende Tage", ckb: "ڕۆژی ماوە", kmr: "Rojên mayî") }
    static var valid: String { tr5("Valid", "صالحة", de: "Gültig", ckb: "دروستە", kmr: "Derbasdar") }
    static var expired: String { tr5("Expired", "منتهية", de: "Abgelaufen", ckb: "بەسەرچووە", kmr: "Dema wê qediyaye") }
    static var notVerified: String { tr5("Not verified", "غير متحقق منها", de: "Nicht geprüft", ckb: "پشتڕاست نەکراوەتەوە", kmr: "Nehatiye piştrastkirin") }
    static var noCertificate: String { tr5("No certificate", "ما في شهادة", de: "Kein Zertifikat", ckb: "بڕوانامە نییە", kmr: "Sertîfîka tune ye") }

    // Short injection method names for the badges
    static func methodShort(_ method: InjectionMethod) -> String {
        switch method {
        case .direct: return tr5("Direct", "حقن مباشر", de: "Direkt", ckb: "ڕاستەوخۆ", kmr: "Rasterast")
        case .load_control: return "LoadControl"
        case .shared_library: return tr5("Shared library", "مكتبة مشتركة", de: "Geteilte Bibliothek", ckb: "کتێبخانەی هاوبەش", kmr: "Pirtûkxaneya parvekirî")
        case .separate_extension: return tr5("Extension", "امتداد منفصل", de: "Erweiterung", ckb: "پێوەکراوی جیا", kmr: "Pêveka cuda")
        }
    }
}

// MARK: - Theme

/// Visual theme of the Project details page. `classic` is the original design and the default.
enum ProjectDetailsTheme: String, CaseIterable, Identifiable {
    case classic, obsidianGold, aurora, bento, buildPipeline, lightPearl
    static let key = "mirsa.projectDetailsTheme"
    static let fallback: ProjectDetailsTheme = .classic
    var id: String { rawValue }

    /// Unknown or missing stored values fall back to Classic.
    init(stored: String?) { self = ProjectDetailsTheme(rawValue: stored ?? "") ?? .fallback }

    static var current: ProjectDetailsTheme { ProjectDetailsTheme(stored: UserDefaults.standard.string(forKey: key)) }

    var title: String {
        switch self {
        case .classic: return ProjectThemeText.classic
        case .obsidianGold: return ProjectThemeText.obsidianGold
        case .aurora: return ProjectThemeText.aurora
        case .bento: return ProjectThemeText.bento
        case .buildPipeline: return ProjectThemeText.buildPipeline
        case .lightPearl: return ProjectThemeText.lightPearl
        }
    }

    var symbol: String {
        switch self {
        case .classic: return "rectangle.stack"
        case .obsidianGold: return "crown"
        case .aurora: return "sparkles"
        case .bento: return "square.grid.2x2"
        case .buildPipeline: return "list.number"
        case .lightPearl: return "sun.max"
        }
    }

    var isLight: Bool { self == .lightPearl }
    var colorScheme: ColorScheme { isLight ? .light : .dark }

    /// Classic keeps the original forced left-to-right layout; the new themes follow the app language.
    var followsLanguageDirection: Bool { self != .classic }
    static func direction(for language: AppLanguage) -> LayoutDirection {
        (language == .arabic || language == .sorani) ? .rightToLeft : .leftToRight
    }
    func layoutDirection(for language: AppLanguage) -> LayoutDirection {
        followsLanguageDirection ? Self.direction(for: language) : .leftToRight
    }

    // Palette
    var background: Color {
        switch self {
        case .classic: return MirsaPalette.sheet
        case .obsidianGold: return Color(sourcesRGB: 0x08080A)
        case .aurora: return Color(sourcesRGB: 0x0A0A1C)
        case .bento: return Color(sourcesRGB: 0x0E1116)
        case .buildPipeline: return Color(sourcesRGB: 0x111111)
        case .lightPearl: return Color(sourcesRGB: 0xF4F3F8)
        }
    }
    var accent: Color {
        switch self {
        case .classic: return MirsaPalette.accent
        case .obsidianGold: return Color(sourcesRGB: 0xD6B36A)
        case .aurora: return Color(sourcesRGB: 0x8B5CF6)
        case .bento: return Color(sourcesRGB: 0x60A5FA)
        case .buildPipeline: return Color(sourcesRGB: 0xFF7A45)
        case .lightPearl: return Color(sourcesRGB: 0x3730A3)
        }
    }
    var accentGradient: LinearGradient {
        switch self {
        case .obsidianGold:
            return LinearGradient(colors: [Color(sourcesRGB: 0xB8924A), Color(sourcesRGB: 0xE8CD8C), Color(sourcesRGB: 0xB8924A)], startPoint: .leading, endPoint: .trailing)
        case .aurora:
            return LinearGradient(colors: [Color(sourcesRGB: 0x8B5CF6), Color(sourcesRGB: 0x5B8CFF)], startPoint: .leading, endPoint: .trailing)
        case .lightPearl:
            return LinearGradient(colors: [Color(sourcesRGB: 0x3730A3), Color(sourcesRGB: 0x6D28D9)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [accent, accent], startPoint: .leading, endPoint: .trailing)
        }
    }
    var text: Color {
        switch self {
        case .classic, .aurora: return .white
        case .obsidianGold: return Color(sourcesRGB: 0xEEE6D6)
        case .bento: return Color(sourcesRGB: 0xE8EDF3)
        case .buildPipeline: return Color(sourcesRGB: 0xF3F3F3)
        case .lightPearl: return Color(sourcesRGB: 0x16142B)
        }
    }
    var secondaryText: Color {
        switch self {
        case .classic: return MirsaPalette.textSecondary
        case .obsidianGold: return Color(sourcesRGB: 0x8F877A)
        case .aurora: return Color.white.opacity(0.62)
        case .bento: return Color(sourcesRGB: 0x7D8896)
        case .buildPipeline: return Color(sourcesRGB: 0x8A8A8A)
        case .lightPearl: return Color(sourcesRGB: 0x7A7891)
        }
    }
    var surface: Color {
        switch self {
        case .classic: return MirsaPalette.card
        case .obsidianGold: return Color.white.opacity(0.03)
        case .aurora: return Color.white.opacity(0.07)
        case .bento: return Color(sourcesRGB: 0x161B22)
        case .buildPipeline: return Color(sourcesRGB: 0x1A1A1A)
        case .lightPearl: return .white
        }
    }
    var stroke: Color {
        switch self {
        case .classic: return MirsaPalette.stroke
        case .obsidianGold: return Color(sourcesRGB: 0xD6B36A, opacity: 0.25)
        case .aurora: return Color.white.opacity(0.12)
        case .bento: return Color(sourcesRGB: 0x232A33)
        case .buildPipeline: return Color(sourcesRGB: 0x262626)
        case .lightPearl: return Color.black.opacity(0.06)
        }
    }
    var success: Color {
        switch self {
        case .bento: return Color(sourcesRGB: 0x4ADE80)
        case .buildPipeline: return Color(sourcesRGB: 0x22C55E)
        case .lightPearl: return Color(sourcesRGB: 0x15803D)
        default: return MirsaPalette.success
        }
    }
    var warning: Color { self == .buildPipeline ? Color(sourcesRGB: 0xFF7A45) : (isLight ? Color(sourcesRGB: 0xC2410C) : .orange) }
    /// Toggle tint. Classic keeps its original green.
    var toggleTint: Color {
        switch self {
        case .classic: return .green
        case .obsidianGold, .aurora, .lightPearl: return accent
        case .bento, .buildPipeline: return success
        }
    }
    /// Translucent fill for inputs, chips and rows. Classic returns exactly the original `Color.white.opacity(x)`.
    func soft(_ opacity: Double) -> Color {
        isLight ? Color.black.opacity(opacity * 0.6) : Color.white.opacity(opacity)
    }

    // Sign button
    var signForeground: Color {
        switch self {
        case .obsidianGold: return Color(sourcesRGB: 0x1A1205)
        case .bento: return Color(sourcesRGB: 0x0E1116)
        case .buildPipeline: return Color(sourcesRGB: 0x111111)
        default: return .white
        }
    }
    /// Colour scheme for content drawn on the sign button (progress view, secondary labels).
    var signLabelScheme: ColorScheme {
        switch self {
        case .obsidianGold, .bento, .buildPipeline: return .light
        default: return .dark
        }
    }
    var signShapeRadius: CGFloat {
        switch self {
        case .obsidianGold: return 4
        case .aurora: return 17
        case .bento: return 20
        default: return 29
        }
    }
    @ViewBuilder var signBackground: some View {
        let shape = RoundedRectangle(cornerRadius: signShapeRadius, style: .continuous)
        switch self {
        case .classic: shape.fill(MirsaPalette.accentGradient)
        case .obsidianGold: shape.fill(accentGradient)
        case .aurora: shape.fill(accentGradient).shadow(color: Color(sourcesRGB: 0x7C5CFF).opacity(0.5), radius: 12, y: 8)
        case .bento: shape.fill(Color(sourcesRGB: 0xE8EDF3))
        case .buildPipeline: shape.fill(accent)
        case .lightPearl: shape.fill(Color(sourcesRGB: 0x16142B)).shadow(color: Color(sourcesRGB: 0x16142B).opacity(0.35), radius: 15, y: 14)
        }
    }
}

/// Tabs used by the tabbed themes (Obsidian Gold shows all five; Aurora and Light Pearl fold Files into Versions).
enum ProjectDetailsTab: String, CaseIterable, Identifiable {
    case tweaks, settings, certificate, versions, files
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tweaks: return ProjectThemeText.tweaks
        case .settings: return ProjectThemeText.settings
        case .certificate: return ProjectThemeText.certificate
        case .versions: return ProjectThemeText.versions
        case .files: return ProjectThemeText.files
        }
    }
}

/// Bento tiles that expand into their full section.
enum ProjectBentoPanel: String, CaseIterable, Identifiable {
    case app, certificate, output, versions, settings, tools
    var id: String { rawValue }
}

/// Build Pipeline steps, in order.
enum ProjectPipelineStep: Int, CaseIterable, Identifiable {
    case app = 1, tweaks, settings, certificate, versions
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .app: return ProjectThemeText.app
        case .tweaks: return ProjectThemeText.injectedTweaks
        case .settings: return ProjectThemeText.settings
        case .certificate: return ProjectThemeText.certificate
        case .versions: return ProjectThemeText.versionsAndTools
        }
    }
}

enum ProjectStepStatus: Equatable { case done, attention, idle }

/// Summary of the selected signing certificate for the theme headers and tiles.
enum ProjectCertificateState: Equatable {
    case missing, valid, unverified, expired
    var title: String {
        switch self {
        case .missing: return ProjectThemeText.noCertificate
        case .valid: return ProjectThemeText.valid
        case .unverified: return ProjectThemeText.notVerified
        case .expired: return ProjectThemeText.expired
        }
    }
    static func evaluate(hasCertificate: Bool, verified: Bool, expiry: Date?, now: Date = Date()) -> ProjectCertificateState {
        guard hasCertificate else { return .missing }
        if let expiry, expiry < now { return .expired }
        return verified ? .valid : .unverified
    }
    /// Whole days until `expiry`, never negative.
    static func daysLeft(until expiry: Date?, now: Date = Date()) -> Int? {
        guard let expiry else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: now, to: expiry).day ?? 0)
    }
}

// MARK: - Shared themed chrome

/// Round header button chrome (back and theme menu) for each theme.
struct ProjectThemeButtonChrome: ViewModifier {
    let theme: ProjectDetailsTheme
    @ViewBuilder func body(content: Content) -> some View {
        switch theme {
        case .classic:
            content.appsGlass(cornerRadius: 20)
        case .obsidianGold:
            content.foregroundStyle(theme.accent)
        case .aurora:
            content.sourcesGlass(.aurora, radius: 20)
        case .bento:
            content.background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.stroke))
        case .buildPipeline:
            content.background(Circle().fill(theme.surface)).overlay(Circle().stroke(theme.stroke))
        case .lightPearl:
            content.background(Circle().fill(Color.white).shadow(color: .black.opacity(0.06), radius: 4, y: 2))
        }
    }
}

/// Card / section chrome of the new themes. Not used by Classic.
struct ProjectSectionChrome: ViewModifier {
    let theme: ProjectDetailsTheme
    @ViewBuilder func body(content: Content) -> some View {
        switch theme {
        case .classic:
            content.padding(16).appsGlass(cornerRadius: 24)
        case .obsidianGold:
            content.padding(.horizontal, 22).padding(.vertical, 14)
                .overlay(alignment: .bottom) { ProjectGoldDivider().opacity(0.6) }
        case .aurora:
            content.padding(16).sourcesGlass(.aurora, radius: 22)
        case .bento:
            content.padding(13)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(theme.stroke))
        case .buildPipeline:
            content.padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.stroke))
        case .lightPearl:
            content.padding(14)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white)
                    .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
                    .shadow(color: Color(sourcesRGB: 0x281E5A).opacity(0.06), radius: 12, y: 8))
        }
    }
}

/// Existing self-styled cards (saved versions, already-present libraries) keep their own dark card;
/// on the light theme they sit on a dark island so their white text stays readable.
struct ProjectEmbeddedCard: ViewModifier {
    let theme: ProjectDetailsTheme
    @ViewBuilder func body(content: Content) -> some View {
        if theme.isLight {
            content
                .environment(\.colorScheme, .dark)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(sourcesRGB: 0x16142B)))
        } else {
            content
        }
    }
}

/// Input chrome for the editable text fields. Classic keeps the original bare field.
struct ProjectFieldChrome: ViewModifier {
    let theme: ProjectDetailsTheme
    @ViewBuilder func body(content: Content) -> some View {
        if theme == .classic {
            content
        } else {
            content.padding(.horizontal, 10).padding(.vertical, 8)
                .background(theme.soft(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

/// Method badge next to a tweak in the new themes.
struct ProjectMethodBadge: ViewModifier {
    let theme: ProjectDetailsTheme
    @ViewBuilder func body(content: Content) -> some View {
        switch theme {
        case .obsidianGold, .buildPipeline:
            content.foregroundStyle(theme.accent).padding(.horizontal, 8).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(theme.accent.opacity(0.5)))
        case .bento:
            content.padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(sourcesRGB: 0x1F2937)))
        case .lightPearl:
            content.foregroundStyle(theme.accent).padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(sourcesRGB: 0xEEECFB)))
        case .aurora, .classic:
            content.padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
    }
}

/// Container of one tweak row in the new themes.
struct ProjectTweakRowChrome: ViewModifier {
    let theme: ProjectDetailsTheme
    let first: Bool
    @ViewBuilder func body(content: Content) -> some View {
        switch theme {
        case .classic:
            content
        case .obsidianGold:
            content.padding(.vertical, 13)
                .overlay(alignment: .top) { if !first { ProjectGoldDivider().opacity(0.4) } }
        case .aurora:
            content.padding(11).sourcesGlass(.aurora, radius: 18)
        case .bento:
            content.padding(.vertical, 9)
                .overlay(alignment: .top) { Rectangle().fill(theme.stroke).frame(height: 1) }
        case .buildPipeline:
            content.padding(9)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(sourcesRGB: 0x222222)))
        case .lightPearl:
            content.padding(.vertical, 11)
                .overlay(alignment: .top) { if !first { Rectangle().fill(Color(sourcesRGB: 0xEFEEF5)).frame(height: 1) } }
        }
    }
}

/// Thin champagne hairline used by Obsidian Gold.
struct ProjectGoldDivider: View {
    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [.clear, Color(sourcesRGB: 0xD6B36A, opacity: 0.45), .clear], startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// Sign & Install button style of the new themes. Disabled state dims; press scales slightly.
struct ProjectThemeSignStyle: ButtonStyle {
    let theme: ProjectDetailsTheme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(theme.signForeground)
            .tint(theme.signForeground)
            .environment(\.colorScheme, theme.signLabelScheme)
            .background { theme.signBackground }
            .contentShape(RoundedRectangle(cornerRadius: theme.signShapeRadius, style: .continuous))
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(MirsaMotion.press, value: configuration.isPressed)
    }
}

/// Palette button in the Project details header. Persists the choice in `ProjectDetailsTheme.key`.
struct ProjectDetailsThemeMenu: View {
    @Binding var selection: String
    let theme: ProjectDetailsTheme
    var body: some View {
        Menu {
            Picker(ProjectThemeText.menuTitle, selection: Binding(get: { ProjectDetailsTheme(stored: selection) }, set: { value in
                withAnimation(.easeInOut(duration: 0.3)) { selection = value.rawValue }
            })) {
                ForEach(ProjectDetailsTheme.allCases) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
        } label: {
            Image(systemName: "paintpalette.fill")
                .font(.headline)
                .foregroundStyle(theme == .classic ? AnyShapeStyle(MirsaPalette.accentGradient) : AnyShapeStyle(theme.accent))
                .frame(width: 40, height: 40)
                .modifier(ProjectThemeButtonChrome(theme: theme))
                .contentShape(Circle())
        }
        .accessibilityLabel(ProjectThemeText.menuTitle)
        .accessibilityIdentifier("mirsa.project.theme-menu")
    }
}
