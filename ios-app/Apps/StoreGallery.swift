import SwiftUI

// MARK: - Apple Store «معرض» (Gallery): the look of the New store style (UI only)
//
// Presentation pieces for the New Apple Store style: a near-black page with a violet and
// cyan aurora at the top, editorial cards, a floating glass capsule for the store's own
// pages (it sits directly above Mirsa's dock, which stays visible), a gradient progress
// ring and grouped glass lists. Nothing here signs in, buys, downloads or installs:
// callers pass their existing actions in as closures. The Classic style never uses this file.

enum StoreGallery {
    static let ink = Color(red: 0.020, green: 0.016, blue: 0.039)      // #05040a
    static let violet = Color(red: 0.486, green: 0.361, blue: 1.0)      // #7c5cff
    static let blue = Color(red: 0.310, green: 0.545, blue: 1.0)        // #4f8bff
    static let cyan = Color(red: 0.0, green: 0.784, blue: 1.0)          // #00c8ff
    static let lilac = Color(red: 0.663, green: 0.584, blue: 1.0)       // #a995ff, links
    static let sky = Color(red: 0.561, green: 0.890, blue: 1.0)         // #8fe3ff, live speed
    static let badge = Color(red: 1.0, green: 0.231, blue: 0.361)       // #ff3b5c
    static let mint = Color(red: 0.239, green: 1.0, blue: 0.557)        // #3dff8e, connected
    static let rose = Color(red: 1.0, green: 0.361, blue: 0.478)        // #ff5c7a, sign out
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.42)
    static let hairline = Color.white.opacity(0.08)

    /// Selected capsule item and primary accents.
    static var accent: LinearGradient {
        LinearGradient(colors: [violet, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// Progress ring and identity glow.
    static var ring: LinearGradient {
        LinearGradient(colors: [violet, cyan], startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    /// Arabic and Sorani pages read right to left. The capsule and the dock keep their
    /// fixed physical order in every language.
    static var isRightToLeft: Bool {
        let language = AppLanguageStore.snapshot
        return language == .arabic || language == .sorani
    }
    static var direction: LayoutDirection { isRightToLeft ? .rightToLeft : .leftToRight }

    static let capsuleHeight: CGFloat = 56
    /// Space kept above the capsule so the last rows of a page scroll clear of it.
    static let capsuleTopGap: CGFloat = 8
    /// Everything at the bottom of the store tab: Mirsa's dock plus the capsule above it.
    static var bottomClearance: CGFloat { MirsaTabBarMetrics.clearance + capsuleHeight + capsuleTopGap }

    static let titleFont = Font.system(size: 34, weight: .heavy, design: .rounded)
    static let sectionFont = Font.system(size: 22, weight: .bold, design: .rounded)
    static let eyebrowFont = Font.system(size: 13, weight: .bold, design: .rounded)

    /// "Friday 20 November" in the app language.
    static func todayEyebrow(_ date: Date = Date()) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguageStore.snapshot.locale))
    }

    /// "a••••@icloud.com": the account card shows the address masked; VoiceOver reads it in full.
    static func maskedEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, let first = parts[0].first else { return email }
        return String(first) + "••••@" + parts[1]
    }
}

// MARK: Strings (five languages)

enum StoreGalleryText {
    static var discover: String { storeText("Discover", "اكتشف", de: "Entdecken", ckb: "دۆزینەوە", kmr: "Keşf bike") }
    static var topFreeTag: String { storeText("No. 1 · Top free", "رقم ١ · الأكثر تنزيلًا مجانًا", de: "Nr. 1 · Top-Gratis", ckb: "ژمارە ١ · زۆرترین داگرتنی بێبەرامبەر", kmr: "Hejmar 1 · Belaş ên herî zêde") }
    static var mostDownloaded: String { storeText("Most downloaded", "الأكثر تنزيلًا", de: "Meistgeladen", ckb: "زۆرترین داگیراو", kmr: "Yên herî zêde hatine daxistin") }
    static var collections: String { storeText("Collections", "مجموعات", de: "Sammlungen", ckb: "کۆمەڵەکان", kmr: "Kom") }
    static var view: String { storeText("View", "عرض", de: "Ansehen", ckb: "بینین", kmr: "Bibîne") }
    static var install: String { storeText("Install", "تثبيت", de: "Installieren", ckb: "دامەزراندن", kmr: "Saz bike") }
    static var nowDownloading: String { storeText("Downloading now", "يتم التنزيل الآن", de: "Wird gerade geladen", ckb: "ئێستا دادەبەزێت", kmr: "Niha tê daxistin") }
    static var nowInstalling: String { storeText("Installing now", "يتم التثبيت الآن", de: "Wird gerade installiert", ckb: "ئێستا دادەمەزرێت", kmr: "Niha tê sazkirin") }
    static var appStoreDownload: String { storeText("App Store download", "تنزيل من App Store", de: "App-Store-Download", ckb: "داگرتن لە App Store", kmr: "Daxistina App Store") }
    static var readyToInstall: String { storeText("Ready to install", "جاهزة للتثبيت", de: "Bereit zur Installation", ckb: "ئامادەی دامەزراندن", kmr: "Amade ji bo sazkirinê") }
    static var installed: String { storeText("Installed", "مثبّتة", de: "Installiert", ckb: "دامەزراوە", kmr: "Sazkirî") }
    static var connected: String { storeText("Connected", "متصل", de: "Verbunden", ckb: "پەیوەستە", kmr: "Girêdayî") }
    static var storeRegion: String { storeText("Store region", "منطقة المتجر", de: "Store-Region", ckb: "ناوچەی ستۆر", kmr: "Herêma store") }
    static var store: String { storeText("Store", "المتجر", de: "Store", ckb: "ستۆر", kmr: "Store") }
    static var signInToBrowse: String {
        storeText("Sign in with your Apple Account to see Apple's charts and download the apps it owns.",
                  "سجّل دخول بحساب Apple تبعك لتشوف ترتيب Apple وتنزّل التطبيقات يلي بيملكها.",
                  de: "Melde dich mit deinem Apple-Konto an, um Apples Charts zu sehen und eigene Apps zu laden.",
                  ckb: "بە ئەکاونتی Apple بچۆ ژوورەوە بۆ بینینی لیستەکانی Apple و داگرتنی ئەو ئەپانەی خاوەنیانی.",
                  kmr: "Bi hesabê xwe yê Apple têkeve da ku lîsteyên Apple bibînî û sepanên wî daxî.")
    }
    static var back: String { storeText("Back", "رجوع", de: "Zurück", ckb: "گەڕانەوە", kmr: "Vegere") }
    static var minimumIOS: String { storeText("Requires", "يتطلب", de: "Benötigt", ckb: "پێویستی بە", kmr: "Pêdivî ye") }
    static var size: String { storeText("Size", "الحجم", de: "Größe", ckb: "قەبارە", kmr: "Mezinahî") }
    static var version: String { storeText("Version", "الإصدار", de: "Version", ckb: "وەشان", kmr: "Guherto") }
    static var ratings: String { storeText("Ratings", "التقييمات", de: "Bewertungen", ckb: "هەڵسەنگاندن", kmr: "Nirxandin") }
}

// MARK: Background

/// Near-black page with a soft violet and cyan aurora at the top. Static, so it needs no
/// Reduce Motion handling and costs no animation while scrolling.
struct StoreGalleryBackground: View {
    var body: some View {
        MirsaScreenAnchored { _ in
            mesh
        }
    }

    private var mesh: some View {
        ZStack {
            StoreGallery.ink
            RadialGradient(colors: [StoreGallery.violet.opacity(0.42), StoreGallery.violet.opacity(0.10), .clear],
                           center: UnitPoint(x: 0.72, y: 0.02), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [StoreGallery.cyan.opacity(0.24), .clear],
                           center: UnitPoint(x: 0.16, y: 0.0), startRadius: 0, endRadius: 300)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A page's background: clear when the store tab already draws the shared one, the full
/// gallery background when the page is shown on its own (a sheet).
struct StoreGalleryPageBackdrop: View {
    @Environment(\.storeBackdropProvided) private var provided
    var body: some View {
        if provided { Color.clear.allowsHitTesting(false) } else { StoreGalleryBackground() }
    }
}

// MARK: Glass

/// Flat glass: a faint white fill with a thin rim, solid with Reduce Transparency.
/// No live blur per card, so long lists scroll on flat layers only.
struct StoreGalleryGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(reduceTransparency ? Color(red: 0.085, green: 0.080, blue: 0.125) : Color.white.opacity(0.06))
                    if let tint {
                        shape.fill(LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.06)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            }
            .overlay { shape.strokeBorder(Color.white.opacity(0.11), lineWidth: 0.7).allowsHitTesting(false) }
    }
}

extension View {
    func galleryGlass(radius: CGFloat = 22, tint: Color? = nil) -> some View {
        modifier(StoreGalleryGlass(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint))
    }
    func galleryGlassCapsule(tint: Color? = nil) -> some View {
        modifier(StoreGalleryGlass(shape: Capsule(), tint: tint))
    }
    /// Pill label: light (white with black text), dark (glass) or accent (violet to blue).
    func galleryPill(_ style: StoreGalleryPillStyle, height: CGFloat = 34) -> some View {
        self
            .font(.system(size: height >= 44 ? 17 : 14, weight: .bold, design: .rounded))
            .lineLimit(1).minimumScaleFactor(0.75)
            .foregroundStyle(style.foreground)
            .padding(.horizontal, height >= 44 ? 22 : 16)
            .frame(minHeight: height)
            .background(Capsule().fill(style.fill))
            .contentShape(Capsule())
    }
}

enum StoreGalleryPillStyle {
    case light, dark, accent
    var foreground: Color { self == .light ? Color.black : Color.white }
    var fill: AnyShapeStyle {
        switch self {
        case .light: return AnyShapeStyle(Color.white.opacity(0.95))
        case .dark: return AnyShapeStyle(Color.white.opacity(0.12))
        case .accent: return AnyShapeStyle(StoreGallery.accent)
        }
    }
}

/// Round glass button face (back, share, wishlist, small tools).
struct StoreGalleryRoundLabel: View {
    let systemName: String
    var size: CGFloat = 40
    var tint: Color = .white
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.black.opacity(0.28)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7))
            .contentShape(Circle())
    }
}

// MARK: Header and titles

/// Transparent page header: small eyebrow, large bold title, optional trailing control.
/// No strip, blur or fade behind it.
struct StoreGalleryHeader<Trailing: View>: View {
    var eyebrow: String? = nil
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: MirsaSpacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow).font(StoreGallery.eyebrowFont).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
                }
                Text(title).font(StoreGallery.titleFont).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: MirsaSpacing.xs)
            trailing()
        }
        .padding(.top, MirsaSpacing.s)
        .environment(\.layoutDirection, StoreGallery.direction)
    }
}

/// Section title with an optional trailing link ("All", "Clear") in lilac.
struct StoreGallerySectionTitle: View {
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MirsaSpacing.xs) {
            Text(title).font(StoreGallery.sectionFont).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: MirsaSpacing.xs)
            if let trailing {
                if let action {
                    Button(trailing, action: action)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(StoreGallery.lilac)
                } else {
                    Text(trailing).font(.system(size: 15, weight: .semibold)).foregroundStyle(StoreGallery.tertiary).monospacedDigit()
                }
            }
        }
    }
}

// MARK: Discover pieces

/// The big featured card: a tall gradient from the app's artwork tint, a large tilted icon,
/// a tag, the headline, a small app row and a light pill. The whole card is one button.
struct StoreGalleryHeroCard: View {
    let tag: String
    let headline: String
    let subtitle: String
    let artworkURL: String
    let seed: String
    let actionTitle: String
    let action: () -> Void
    @ObservedObject private var tints = StoreArtworkTint.shared

    var body: some View {
        let tint = tints.tint(artworkURL, seed: seed)
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        Button(action: action) {
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [tint, tint.opacity(0.62), Color.black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color.white.opacity(0.30), .clear], center: UnitPoint(x: 0.3, y: 0.22), startRadius: 0, endRadius: 210)
                StoreArtwork(url: artworkURL, seed: seed, name: headline, size: 150)
                    .rotationEffect(.degrees(-8))
                    .frame(maxHeight: .infinity, alignment: .center)
                    .padding(.bottom, 120)
                VStack(alignment: .leading, spacing: 6) {
                    Text(tag).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.white.opacity(0.78)).lineLimit(1)
                    Text(headline).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: MirsaSpacing.s) {
                        StoreArtwork(url: artworkURL, seed: seed, name: headline, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(headline).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                            Text(subtitle).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.7)).lineLimit(1)
                        }
                        Spacer(minLength: MirsaSpacing.xs)
                        Text(actionTitle).galleryPill(.light)
                    }
                    .padding(.top, 4)
                }
                .padding(18)
                .background(LinearGradient(colors: [.clear, Color.black.opacity(0.62)], startPoint: .top, endPoint: .bottom))
            }
            .frame(height: 400)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7))
            .background(shape.fill(tint.opacity(0.22)).blur(radius: 22).offset(y: 14).allowsHitTesting(false))
            .contentShape(shape)
        }
        .buttonStyle(.mirsaPress)
    }
}

/// One app of the ranked row: icon, name, rank number.
struct StoreGalleryRankedItem: View {
    let rank: Int
    let name: String
    let artworkURL: String
    let seed: String
    var body: some View {
        VStack(spacing: 6) {
            StoreArtwork(url: artworkURL, seed: seed, name: name, size: 64)
            Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(1).frame(width: 78)
            Text("\(rank)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Color.white.opacity(0.5))
                .monospacedDigit()
        }
        .frame(width: 80)
        .contentShape(Rectangle())
    }
}

/// Gradient tile with a big faint rotated symbol: collections (Discover) and categories (Search).
struct StoreGalleryTile: View {
    let title: String
    let icon: String
    let colors: [Color]
    var height: CGFloat = 84
    var selected = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: height >= 110 ? 22 : 20, style: .continuous)
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: icon)
                .font(.system(size: height * 0.72, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.32))
                .rotationEffect(.degrees(-15))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 8, y: height * 0.16)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .lineLimit(2).padding(14)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(selected ? 0.85 : 0.10), lineWidth: selected ? 2 : 0.6))
        .contentShape(shape)
    }
}

// MARK: Progress

/// Circular gradient ring (violet to cyan) around a centre view. Without a value it shows
/// a turning arc, still with Reduce Motion or under the UI-test harness.
struct StoreGalleryProgressRing<Center: View>: View {
    var fraction: Double?
    var diameter: CGFloat = 118
    var lineWidth: CGFloat = 9
    @ViewBuilder var center: () -> Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    private var animates: Bool { fraction == nil && !reduceMotion && !MirsaUITestHarness.active }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(fraction ?? 0.25, 0.02), 1)))
                .stroke(StoreGallery.ring, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(turning && animates ? 270 : -90))
                .animation(animates ? .linear(duration: 1.1).repeatForever(autoreverses: false) : .easeOut(duration: 0.25), value: turning)
            center()
        }
        .frame(width: diameter, height: diameter)
        .onAppear { turning = animates }
        .onChange(of: animates) { _, value in turning = value }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "")
    }
}

/// Thin progress bar for compact rows. Without a value it shows a short static segment.
struct StoreGalleryThinBar: View {
    var fraction: Double?
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule().fill(fraction == nil ? AnyShapeStyle(StoreGallery.lilac) : AnyShapeStyle(StoreGallery.ring))
                    .frame(width: max(6, g.size.width * CGFloat(min(max(fraction ?? 0.18, 0), 1))))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

// MARK: Grouped lists

/// Rounded glass group of rows, with an optional title above and a note below.
struct StoreGalleryGroup<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.xs) {
            if let title {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.5))
                    .padding(.horizontal, MirsaSpacing.xxs)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .galleryGlass(radius: 22)
            if let footer {
                Text(footer).font(MirsaFont.caption).foregroundStyle(StoreGallery.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MirsaSpacing.xxs)
            }
        }
    }
}

/// Row of a gallery group: tinted icon square, title, optional value, chevron.
struct StoreGalleryRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var tint: Color = StoreGallery.lilac
    var titleColor: Color = .white
    var chevron = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: MirsaSpacing.s) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(titleColor).lineLimit(2)
                if let subtitle {
                    Text(subtitle).font(MirsaFont.caption).foregroundStyle(StoreGallery.tertiary).lineLimit(2)
                }
            }
            Spacer(minLength: MirsaSpacing.xs)
            trailing()
            if chevron { StoreGalleryChevron() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct StoreGalleryRowDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.6).padding(.leading, 58)
    }
}

/// Forward chevron that points the reading direction (mirrors in Arabic and Sorani).
struct StoreGalleryChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.3))
            .flipsForRightToLeftLayoutDirection(true)
            .accessibilityHidden(true)
    }
}

/// Small glass chip with an optional symbol (store region, connected, recent searches).
struct StoreGalleryChip: View {
    let title: String
    var icon: String? = nil
    var iconColor: Color = .white
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(iconColor) }
            Text(title).lineLimit(1)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.12)))
    }
}

// MARK: Account card

/// Gradient Apple ID card: initial, name, masked email, storefront and connected chips,
/// and the existing switch-account action.
struct StoreGalleryAccountCard: View {
    let name: String
    let email: String
    let country: String
    let onSwitch: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(alignment: .leading, spacing: MirsaSpacing.m) {
            HStack(spacing: MirsaSpacing.s) {
                Text(String(StoreIdentity.initials(name: name, email: email).prefix(1)))
                    .font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(Color.white.opacity(0.2)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name.isEmpty ? StoreGallery.maskedEmail(email) : name)
                        .font(.system(size: 19, weight: .bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                    Text(StoreGallery.maskedEmail(email))
                        .font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.7)).lineLimit(1)
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityLabel(email)
                }
                Spacer(minLength: MirsaSpacing.xs)
                Button(action: onSwitch) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.mirsaPress)
                .accessibilityLabel(storeText("Switch account", "تبديل الحساب", de: "Konto wechseln", ckb: "گۆڕینی ئەکاونت", kmr: "Hesab biguherîne"))
                .accessibilityIdentifier("store-switch-account")
            }
            HStack(spacing: MirsaSpacing.xs) {
                StoreGalleryChip(title: StoreGalleryText.store + ": " + StoreIdentity.flag(country) + " " + AppStoreCountry.label(country),
                                 icon: "globe")
                StoreGalleryChip(title: StoreGalleryText.connected, icon: "checkmark.circle", iconColor: StoreGallery.mint)
                Spacer(minLength: 0)
            }
        }
        .padding(MirsaSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                shape.fill(LinearGradient(colors: [StoreGallery.violet.opacity(0.55), StoreGallery.cyan.opacity(0.26)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center))
            }
        }
        .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.7))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("store-account-profile")
    }
}

// MARK: Capsule (the store's own pages)

/// The New store style's pages. Discover and Search share one App Store screen (one sign-in,
/// one search, one download at a time); Purchases opens from Account.
enum StoreGalleryPage: String, CaseIterable, Identifiable {
    case discover, search, downloads, purchases, account
    var id: String { rawValue }

    /// The four items of the floating capsule.
    static let capsule: [StoreGalleryPage] = [.discover, .search, .downloads, .account]

    var title: String {
        switch self {
        case .discover: return StoreGalleryText.discover
        case .search: return AppStoreSectionTab.search.title
        case .downloads: return AppStoreSectionTab.downloads.title
        case .purchases: return AppStoreSectionTab.purchases.title
        case .account: return AppStoreSectionTab.account.title
        }
    }

    var icon: String {
        switch self {
        case .discover: return "safari"
        case .search: return "magnifyingglass"
        case .downloads: return "arrow.down.circle"
        case .purchases: return "bag"
        case .account: return "person.crop.circle"
        }
    }

    /// The capsule item lit while this page shows (Purchases belongs to Account).
    var capsuleItem: StoreGalleryPage { self == .purchases ? .account : self }

    init(_ tab: AppStoreSectionTab) {
        switch tab {
        case .search: self = .search
        case .downloads: self = .downloads
        case .purchases: self = .purchases
        case .account: self = .account
        }
    }

    /// Opens on Discover. UI tests can pick a page (`-MirsaStoreTab discover|search|downloads|purchases|account`).
    static var initial: StoreGalleryPage {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if MirsaUITestHarness.active, let i = args.firstIndex(of: "-MirsaStoreTab"), i + 1 < args.count,
           let page = StoreGalleryPage(rawValue: args[i + 1]) { return page }
        #endif
        return .discover
    }
}

/// Floating glass capsule centred just above Mirsa's dock: the selected item grows into a
/// violet-to-blue pill with its label, the others show their symbol only. Downloads carries a
/// red count while something downloads or installs. Fixed physical order in every language,
/// like the dock.
struct StoreGalleryCapsuleBar: View {
    @Binding var selection: StoreGalleryPage
    var downloadsBadge: Int = 0
    /// Tapping the item that is already selected (Discover and Search close an open app page).
    var onReselect: (StoreGalleryPage) -> Void = { _ in }
    @Namespace private var ns
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(StoreGalleryPage.capsule) { item in itemButton(item) }
        }
        .padding(5)
        .frame(height: StoreGallery.capsuleHeight)
        .background { glass }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("store-gallery-capsule")
    }

    @ViewBuilder private var glass: some View {
        let shape = Capsule()
        ZStack {
            if reduceTransparency {
                shape.fill(Color(red: 0.13, green: 0.12, blue: 0.19))
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color(red: 0.157, green: 0.141, blue: 0.235).opacity(0.55))
            }
        }
        .overlay(shape.strokeBorder(Color.white.opacity(0.20), lineWidth: 0.7))
        .shadow(color: Color.black.opacity(0.45), radius: 15, y: 10)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func itemButton(_ item: StoreGalleryPage) -> some View {
        let on = selection.capsuleItem == item
        let badge = item == .downloads && downloadsBadge > 0
        return Button {
            if selection == item { onReselect(item); return }
            StoreHaptics.select()
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.8)) { selection = item }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: on ? .bold : .medium))
                    .frame(height: 22)
                if on {
                    Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1).fixedSize()
                }
                if badge && !on {
                    Text("\(downloadsBadge)")
                        .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(StoreGallery.badge))
                }
            }
            .foregroundStyle(on ? Color.white : Color.white.opacity(0.7))
            .padding(.horizontal, on ? 16 : 13)
            .frame(maxHeight: .infinity)
            .background {
                if on {
                    Capsule().fill(StoreGallery.accent)
                        .shadow(color: StoreGallery.violet.opacity(0.5), radius: 8, y: 4)
                        .matchedGeometryEffect(id: "store-gallery-pill", in: ns)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.mirsaPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge ? item.title + ", \(downloadsBadge)" : item.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("store-tab-\(item.rawValue)")
    }
}

/// Mirsa's main tabs as a menu (the store's former "Mirsa" bar button). The dock stays
/// visible on the store tab, so this is a second way out, kept in the Account header.
struct StoreGalleryMirsaMenu: View {
    let onLeave: (AppTab) -> Void
    var body: some View {
        Menu {
            ForEach(LiquidTabItem.mainTabs.filter { $0.tab != .encrypted }) { item in
                Button { StoreHaptics.select(); onLeave(item.tab) } label: { Label(item.title, systemImage: item.icon) }
            }
        } label: {
            StoreGalleryRoundLabel(systemName: "square.grid.2x2", size: 42)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel(storeText("Mirsa", "مرسى", de: "Mirsa", ckb: "مرسى", kmr: "Mirsa"))
        .accessibilityIdentifier("store-tab-mirsa")
    }
}

// MARK: Live transfer (display only)

/// What the App Store screen is downloading right now, mirrored for the Downloads page.
/// Display data only: pause, resume and cancel go through StoreTransferControl as before.
@MainActor
final class StoreGalleryLiveTransfer: ObservableObject {
    static let shared = StoreGalleryLiveTransfer()
    struct App: Equatable {
        let name: String
        let artworkURL: String
        let seed: String
    }
    @Published private(set) var app: App?
    @Published private(set) var progress: StoreDownloadProgress?
    @Published private(set) var phaseText = ""

    func update(app: App?, progress: StoreDownloadProgress?, phaseText: String) {
        if self.app != app { self.app = app }
        self.progress = progress
        if self.phaseText != phaseText { self.phaseText = phaseText }
    }

    func clear() {
        if app != nil { app = nil }
        if progress != nil { progress = nil }
        if !phaseText.isEmpty { phaseText = "" }
    }
}

/// Which face of the shared App Store screen is showing.
enum StoreGalleryMode: Equatable {
    case discover, search
}

/// Apple chart genres shown as categories (Search) and collections (Discover).
struct StoreGenreTile: Identifiable {
    let id: Int
    let icon: String
    let colors: [Color]

    static let all: [StoreGenreTile] = [
        StoreGenreTile(id: 6014, icon: "gamecontroller.fill", colors: [Color(red: 1.0, green: 0.42, blue: 0.24), Color(red: 0.70, green: 0.15, blue: 0.12)]),
        StoreGenreTile(id: 6007, icon: "bolt.fill", colors: [Color(red: 1.0, green: 0.82, blue: 0.24), Color(red: 0.78, green: 0.47, blue: 0.0)]),
        StoreGenreTile(id: 6017, icon: "graduationcap.fill", colors: [Color(red: 0.24, green: 0.84, blue: 1.0), Color(red: 0.12, green: 0.36, blue: 1.0)]),
        StoreGenreTile(id: 6011, icon: "music.note", colors: [Color(red: 0.24, green: 1.0, blue: 0.56), Color(red: 0.07, green: 0.54, blue: 0.29)]),
        StoreGenreTile(id: 6016, icon: "film.fill", colors: [Color(red: 0.65, green: 0.48, blue: 1.0), Color(red: 0.29, green: 0.12, blue: 0.70)]),
        StoreGenreTile(id: 6013, icon: "heart.fill", colors: [Color(red: 1.0, green: 0.24, blue: 0.60), Color(red: 0.49, green: 0.12, blue: 1.0)]),
    ]
}

// MARK: App page details

/// Stats strip, screenshots carousel, what's new and the version pin, for the gallery app page.
/// Same public catalogue lookup and the same pin actions as StoreCatalogDetailCard (Classic keeps that card).
struct StoreGalleryCatalogSection: View {
    let app: MirsaStoreApp
    let country: String
    /// Selected external version ID, nil means latest.
    let externalVersionID: String?
    let versionLabel: String
    @ObservedObject private var library = StoreLibraryModel.shared
    @State private var item: StoreCatalogItem?
    @State private var failed = false
    private typealias T = StoreFeatureText

    var body: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.m) {
            statsStrip
            if StoreCatalogDetailCard.osWarning(item, externalVersionID: externalVersionID) {
                Text(T.minOSWarn).font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let item, !item.screenshots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(item.screenshots, id: \.self) { url in
                            AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: {
                                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.08))
                                    .frame(width: 160)
                            }
                            .frame(height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityIdentifier("store-detail-screenshots")
            }
            VStack(alignment: .leading, spacing: 8) {
                StoreGallerySectionTitle(title: T.whatsNew)
                if let item {
                    if let notes = item.notes(forVersion: externalVersionID), !notes.isEmpty {
                        Text(notes).font(MirsaFont.secondary).foregroundStyle(StoreGallery.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(T.notesUnavailable).font(MirsaFont.caption).foregroundStyle(StoreGallery.tertiary)
                    }
                } else if failed {
                    Text(T.notesUnavailable).font(MirsaFont.caption).foregroundStyle(StoreGallery.tertiary)
                } else {
                    ProgressView().tint(.white)
                }
            }
            let pinned = library.pin(bundleID: app.bundleID, country: country) != nil
            if externalVersionID != nil || pinned {
                HStack(spacing: MirsaSpacing.xs) {
                    if let id = externalVersionID {
                        Button { library.setPin(app: app, country: country, externalVersionID: id, version: versionLabel) } label: {
                            Label(T.pins + ": " + versionLabel, systemImage: "pin").galleryPill(.dark, height: 36)
                        }
                        .buttonStyle(.mirsaPress)
                    }
                    if pinned {
                        Button { library.clearPin(bundleID: app.bundleID, country: country) } label: {
                            Label(T.unpin, systemImage: "pin.slash").galleryPill(.dark, height: 36)
                        }
                        .buttonStyle(.mirsaPress)
                    }
                }
            }
        }
        .task(id: app.id) {
            item = nil; failed = false
            do { item = try await StoreCatalog.fetch(appID: app.id, bundleID: nil, country: country) } catch { failed = true }
        }
    }

    private var statsStrip: some View {
        let ratingLabel = item?.ratingCount.map { "★ " + $0.formatted(.number.notation(.compactName)) } ?? StoreGalleryText.ratings
        let minimum = item?.minimumOS(forVersion: externalVersionID)
        return HStack(spacing: 0) {
            stat(item?.rating.map { String(format: "%.1f", $0) } ?? "—", ratingLabel)
            divider
            stat(minimum.map { "iOS " + $0 } ?? "—", StoreGalleryText.minimumIOS)
            divider
            stat(item?.sizeBytes.map { StoreBytes.text($0) } ?? "—", StoreGalleryText.size)
            divider
            stat(app.version, StoreGalleryText.version)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .galleryGlass(radius: 22)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("store-detail-stats")
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 0.6, height: 30)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.white.opacity(0.5))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.55)
                .environment(\.layoutDirection, .leftToRight)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }
}
