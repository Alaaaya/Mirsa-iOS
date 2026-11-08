import SwiftUI
import UIKit

// MARK: - Mirsa design tokens
//
// One place for every visual constant. Views should use these instead of ad-hoc
// numbers so the same element looks and measures the same on every screen.

enum MirsaPalette {
    /// Brand accent (violet) and its partner (blue) used for gradients.
    static let accent = Color(red: 0.49, green: 0.38, blue: 1.0)          // #7D61FF
    static let accent2 = Color(red: 0.20, green: 0.60, blue: 0.98)        // #339AFA
    static let accentSoft = Color(red: 0.62, green: 0.55, blue: 1.0)      // links / tint on dark
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Solid surfaces (no blur). Card sits on the aurora background; sheet is a page colour.
    static let card = Color(red: 0.110, green: 0.114, blue: 0.212)        // #1C1D36
    static let cardTop = Color(red: 0.137, green: 0.141, blue: 0.255)     // #232441
    static let cardRaised = Color(red: 0.160, green: 0.165, blue: 0.290)  // #292A4A
    static let row = Color(red: 0.118, green: 0.122, blue: 0.224)         // list / form rows
    static let sheet = Color(red: 0.066, green: 0.070, blue: 0.150)       // #111226
    static let stroke = Color.white.opacity(0.09)
    static let strokeStrong = Color.white.opacity(0.16)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.68)
    static let textTertiary = Color.white.opacity(0.46)

    static let success = Color(red: 0.25, green: 0.82, blue: 0.56)
    static let warning = Color(red: 1.0, green: 0.66, blue: 0.24)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.40)
}

enum MirsaSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Horizontal margin of every page.
    static let page: CGFloat = 20
    /// Inner padding of every card.
    static let card: CGFloat = 16
    /// Room kept free above the floating tab bar.
    static var tabBarClearance: CGFloat { MirsaTabBarMetrics.clearance }
}

enum MirsaRadius {
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 22
    static let xl: CGFloat = 28
    /// App icon squircle.
    static let icon: CGFloat = 14

    /// Snaps legacy radii to the scale so cards share a handful of corner sizes.
    static func snap(_ r: CGFloat) -> CGFloat {
        switch r {
        case ..<10: return xs
        case ..<14: return s
        case ..<19: return m
        case ..<26: return l
        default: return xl
        }
    }
}

enum MirsaIconSize {
    static let s: CGFloat = 13
    static let m: CGFloat = 17
    static let l: CGFloat = 22
    static let xl: CGFloat = 28
    /// Round icon buttons (globe, gear, close…).
    static let button: CGFloat = 42
    /// Leading icon well in rows and cards.
    static let well: CGFloat = 40
}

enum MirsaFont {
    static let pageTitle = Font.system(size: 34, weight: .heavy, design: .rounded)
    static let sheetTitle = Font.system(.title2, design: .rounded).weight(.bold)
    static let sectionTitle = Font.headline
    static let cardTitle = Font.headline
    static let body = Font.body
    static let secondary = Font.subheadline
    static let caption = Font.caption.weight(.medium)
    static let badge = Font.caption2.weight(.bold)
    static let button = Font.subheadline.weight(.semibold)
    static let tabLabel = Font.system(size: 11, weight: .semibold)
}

enum MirsaMotion {
    static let press = Animation.spring(response: 0.28, dampingFraction: 0.72)
    static let appear = Animation.spring(response: 0.5, dampingFraction: 0.86)
    static let select = Animation.spring(response: 0.35, dampingFraction: 0.82)
}

// MARK: - Solid card

/// The single card surface: opaque fill with a gentle top-lit gradient, a hairline
/// border and a soft shadow. A tint mixes a little colour into the fill (still solid).
struct MirsaSolidCard<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color? = nil
    var elevation: Double = 1

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(LinearGradient(colors: [MirsaPalette.cardTop, MirsaPalette.card],
                                              startPoint: .top, endPoint: .bottom))
                    if let tint {
                        shape.fill(LinearGradient(colors: [tint.opacity(0.30), tint.opacity(0.12)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                .shadow(color: .black.opacity(0.30 * elevation), radius: 14 * elevation, y: 8 * elevation)
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .contentShape(shape)
    }
}

extension View {
    /// Solid card with the standard radius.
    func mirsaCard(radius: CGFloat = MirsaRadius.l, tint: Color? = nil) -> some View {
        modifier(MirsaSolidCard(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint))
    }

    /// Solid page colour for sheets (replaces the old translucent material).
    func mirsaSheetBackground() -> some View {
        presentationBackground(MirsaPalette.sheet)
    }

    /// Soft fade-and-rise when a card first appears.
    func mirsaAppear(delay: Double = 0) -> some View {
        modifier(MirsaAppear(delay: delay))
    }
}

struct MirsaAppear: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                guard !shown else { return }
                withAnimation(MirsaMotion.appear.delay(delay)) { shown = true }
            }
    }
}

// MARK: - Buttons

/// Plain button with a gentle press scale. Use for custom-drawn buttons and tappable cards.
struct MirsaPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(MirsaMotion.press, value: configuration.isPressed)
    }
}

/// Main call to action: accent gradient capsule, white semibold label.
struct MirsaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var controlSize
    func makeBody(configuration: Configuration) -> some View {
        let destructive = configuration.role == .destructive
        configuration.label
            .font(MirsaFont.button)
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, controlSize == .small || controlSize == .mini ? 12 : 18)
            .frame(minHeight: controlSize == .small || controlSize == .mini ? 34 : (controlSize == .large ? 50 : 44))
            .background {
                Capsule().fill(destructive
                               ? AnyShapeStyle(MirsaPalette.danger)
                               : AnyShapeStyle(MirsaPalette.accentGradient))
            }
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: (destructive ? MirsaPalette.danger : MirsaPalette.accent).opacity(enabled ? 0.35 : 0), radius: 10, y: 4)
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(MirsaMotion.press, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Secondary action: solid raised capsule with a hairline border.
struct MirsaSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var controlSize
    func makeBody(configuration: Configuration) -> some View {
        let destructive = configuration.role == .destructive
        configuration.label
            .font(MirsaFont.button)
            .foregroundStyle(destructive ? MirsaPalette.danger : MirsaPalette.textPrimary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, controlSize == .small || controlSize == .mini ? 12 : 16)
            .frame(minHeight: controlSize == .small || controlSize == .mini ? 34 : (controlSize == .large ? 50 : 40))
            .background(Capsule().fill(MirsaPalette.cardRaised))
            .overlay(Capsule().strokeBorder(MirsaPalette.strokeStrong, lineWidth: 1))
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(MirsaMotion.press, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == MirsaPressStyle {
    static var mirsaPress: MirsaPressStyle { MirsaPressStyle() }
}
extension ButtonStyle where Self == MirsaPrimaryButtonStyle {
    static var mirsaPrimary: MirsaPrimaryButtonStyle { MirsaPrimaryButtonStyle() }
}
extension ButtonStyle where Self == MirsaSecondaryButtonStyle {
    static var mirsaSecondary: MirsaSecondaryButtonStyle { MirsaSecondaryButtonStyle() }
}

/// Round icon button used in page headers (globe, gear, close).
struct MirsaIconButtonLabel: View {
    let systemName: String
    var size: CGFloat = MirsaIconSize.button
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: MirsaIconSize.m, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
    }
}

// MARK: - Global UIKit chrome

@MainActor
enum MirsaChrome {
    /// Physical left-to-right everywhere, including UIKit-hosted chrome (navigation
    /// bars, alerts, menus, search fields, sheets) that SwiftUI's environment does
    /// not reach. Text inside keeps its natural alignment.
    static func apply() {
        UIView.appearance().semanticContentAttribute = .forceLeftToRight
        UINavigationBar.appearance().semanticContentAttribute = .forceLeftToRight
        UITabBar.appearance().semanticContentAttribute = .forceLeftToRight
        UIToolbar.appearance().semanticContentAttribute = .forceLeftToRight
        UISearchBar.appearance().semanticContentAttribute = .forceLeftToRight
        UIStackView.appearance().semanticContentAttribute = .forceLeftToRight
        UICollectionView.appearance().semanticContentAttribute = .forceLeftToRight
        UITableView.appearance().semanticContentAttribute = .forceLeftToRight

        // Rounded heavy titles like the in-page headers. The bar is transparent at the
        // scroll edge and a solid page colour (no blur) once content scrolls under it.
        let titleColor = UIColor.white
        func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        }
        let solid = UINavigationBarAppearance()
        solid.configureWithOpaqueBackground()
        solid.backgroundColor = UIColor(red: 0.066, green: 0.070, blue: 0.150, alpha: 1)
        solid.shadowColor = UIColor.white.withAlphaComponent(0.08)
        solid.largeTitleTextAttributes = [.font: rounded(32, .heavy), .foregroundColor: titleColor]
        solid.titleTextAttributes = [.font: rounded(17, .bold), .foregroundColor: titleColor]
        let clear = UINavigationBarAppearance()
        clear.configureWithTransparentBackground()
        clear.largeTitleTextAttributes = solid.largeTitleTextAttributes
        clear.titleTextAttributes = solid.titleTextAttributes
        UINavigationBar.appearance().standardAppearance = solid
        UINavigationBar.appearance().compactAppearance = solid
        UINavigationBar.appearance().scrollEdgeAppearance = clear
        // Windows do not exist yet when this runs from App.init (UIApplication.shared
        // is not created); mirsaLeftToRightChrome() applies the window override later.
    }

    /// Trait override on every window, so presented sheets, alerts and menus (which
    /// inherit the window's traits) lay out left-to-right too.
    static func forceWindowsLeftToRight() {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            // Reading an override that was never set raises, so test membership first.
            for w in ws.windows where !w.traitOverrides.contains(UITraitLayoutDirection.self) {
                w.traitOverrides.layoutDirection = .leftToRight
                w.semanticContentAttribute = .forceLeftToRight
            }
        }
    }
}

extension View {
    /// Applies MirsaChrome once the window exists and again whenever a window appears.
    func mirsaLeftToRightChrome() -> some View {
        self
            .onAppear { MirsaChrome.forceWindowsLeftToRight() }
            .onReceive(NotificationCenter.default.publisher(for: UIWindow.didBecomeKeyNotification)) { _ in MirsaChrome.forceWindowsLeftToRight() }
            .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { _ in MirsaChrome.forceWindowsLeftToRight() }
    }
}

// MARK: - Page header

/// Large leading page title with optional subtitle and trailing round buttons.
/// Shared by the in-page headers of the main tabs so they line up identically.
struct MirsaPageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .bottom, spacing: MirsaSpacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                if let subtitle {
                    Text(subtitle)
                        .font(MirsaFont.secondary.weight(.medium))
                        .foregroundStyle(MirsaPalette.textSecondary)
                        .lineLimit(1)
                }
                Text(title)
                    .font(MirsaFont.pageTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: MirsaSpacing.xs)
            trailing()
        }
        .padding(.top, MirsaSpacing.s)
    }
}

/// Round solid icon button label (42 pt) used next to page titles.
struct MirsaRoundIcon: View {
    let systemName: String
    var body: some View {
        MirsaIconButtonLabel(systemName: systemName)
            .appsGlassCapsule()
    }
}

// MARK: - Status bar scrim

/// Soft solid fade behind the status bar so scrolled content never collides with
/// the clock and battery on pages without a navigation bar.
struct MirsaStatusBarScrim: View {
    var body: some View {
        // A thin strip below the status bar whose background grows up into the
        // top safe area, so the fade covers exactly the status bar plus 14 pt.
        Color.clear
            .frame(height: 14)
            .frame(maxWidth: .infinity)
            .background {
                LinearGradient(stops: [
                    .init(color: MirsaPalette.sheet, location: 0),
                    .init(color: MirsaPalette.sheet.opacity(0.8), location: 0.55),
                    .init(color: MirsaPalette.sheet.opacity(0), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Shows the scrim only once the scroll view has actually scrolled, so the page
/// top keeps its background at rest. Apply directly to a ScrollView.
struct MirsaScrollScrim: ViewModifier {
    @State private var scrolled = false
    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { g in
                g.contentOffset.y + g.contentInsets.top > 6
            } action: { _, now in
                withAnimation(.easeOut(duration: 0.2)) { scrolled = now }
            }
            .overlay(alignment: .top) { MirsaStatusBarScrim().opacity(scrolled ? 1 : 0) }
    }
}

extension View {
    func mirsaStatusBarScrim() -> some View {
        modifier(MirsaScrollScrim())
    }
}
