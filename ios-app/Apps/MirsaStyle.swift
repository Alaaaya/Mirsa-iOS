import SwiftUI
import UIKit

/// Mirsa's look for the older Form/ScrollView screens: aurora background,
/// translucent rows, clear navigation bar, purple accent.
struct MirsaForm<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        Form { Group { content() }.listRowBackground(MirsaPalette.row) }
            .mirsaScreen()
    }
}

struct MirsaScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView { content() }
            .mirsaScreen()
    }
}

extension View {
    /// For plain Lists/Forms in sheets and pushed screens: hides the system grouped
    /// background (pure black in dark mode) and draws the page backdrop edge to edge.
    func mirsaListBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AuroraBackground().ignoresSafeArea())
    }

    func mirsaScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AuroraBackground().ignoresSafeArea())
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .tint(MirsaPalette.accentSoft)
            .environment(\.defaultMinListRowHeight, 50)
            .preferredColorScheme(.dark)
    }
}

// MARK: - Themes (Settings › Theme): Classic or Liquid Glass

enum MirsaTheme: String, CaseIterable, Identifiable {
    case liquid, classic
    static let key = "mirsa.theme"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .liquid: return tr("Liquid Glass", "زجاج سائل")
        case .classic: return tr("Classic", "الكلاسيكي")
        }
    }
    static var isLiquid: Bool { (UserDefaults.standard.string(forKey: key) ?? MirsaTheme.liquid.rawValue) == MirsaTheme.liquid.rawValue }
}

extension View {
    /// Every card in Mirsa goes through here: real glass with the Liquid Glass theme, solid with Classic.
    func appsGlass(cornerRadius: CGFloat = 24, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(MirsaSolidCard(shape: RoundedRectangle(cornerRadius: MirsaRadius.snap(cornerRadius), style: .continuous),
                                tint: tint, elevation: cornerRadius >= 20 ? 1 : 0.6))
    }
    func appsGlassCapsule(tint: Color? = nil) -> some View {
        modifier(MirsaSolidCard(shape: Capsule(), tint: tint, elevation: 0.6))
    }
}

enum GlassShapeKind { case rect(cornerRadius: CGFloat), capsule }

/// Kept for source compatibility: renders the same solid card for both themes.
struct ThemedGlass: ViewModifier {
    let shape: GlassShapeKind
    let tint: Color?
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        switch shape {
        case .rect(let r): content.appsGlass(cornerRadius: r, tint: tint, interactive: interactive)
        case .capsule: content.appsGlassCapsule(tint: tint)
        }
    }
}

/// Former glass look, now solid. Kept as a thin alias so older call sites keep compiling.
struct LiquidGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    var depth: Double = 1
    func body(content: Content) -> some View {
        content.modifier(MirsaSolidCard(shape: shape, tint: tint, elevation: depth))
    }
}

/// Base #090A1E with violet, cyan and pink light and two floating orbs.
/// Sampled at window size and pinned to its origin, so every copy of the
/// page background (root, tab, picker strip, padded dock area) lines up pixel for
/// pixel and the app reads as one continuous backdrop from the status bar to the
/// home indicator.
struct LiquidBackground: View {
    var paused = false
    var body: some View {
        MirsaScreenAnchored { size in
            LiquidBackdrop(size: size, paused: paused)
        }
    }
}

private struct LiquidBackdrop: View {
    let size: CGSize
    let paused: Bool
    @Environment(\.mirsaTabActive) private var tabActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// Drift phases. Driven by Core Animation (repeat-forever springs on offsets), not a
    /// per-frame TimelineView: the old 15 fps timeline rebuilt and re-blurred both orbs on
    /// the main thread in every retained tab copy, which stuttered scrolling app-wide.
    @State private var drift = false
    private var animating: Bool { !paused && tabActive && !reduceMotion && scenePhase == .active }

    var body: some View {
        let w = size.width, h = size.height
        ZStack {
            Color(red: 9 / 255, green: 10 / 255, blue: 30 / 255)
            RadialGradient(colors: [Color(red: 139 / 255, green: 92 / 255, blue: 246 / 255).opacity(0.8), .clear],
                           center: UnitPoint(x: 0.88, y: 0.06), startRadius: 0, endRadius: 300)
            RadialGradient(colors: [Color(red: 34 / 255, green: 211 / 255, blue: 238 / 255).opacity(0.5), .clear],
                           center: UnitPoint(x: 0, y: 0.46), startRadius: 0, endRadius: 280)
            RadialGradient(colors: [Color(red: 236 / 255, green: 72 / 255, blue: 153 / 255).opacity(0.42), .clear],
                           center: UnitPoint(x: 1, y: 0.88), startRadius: 0, endRadius: 310)
            Circle()
                .fill(LinearGradient(colors: [Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255),
                                              Color(red: 34 / 255, green: 211 / 255, blue: 238 / 255)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 190, height: 190)
                .opacity(0.55).blur(radius: 6)
                .position(x: w - 65, y: 245)
                .offset(x: drift ? 14 : -14)
                .animation(animating ? .easeInOut(duration: 15.7).repeatForever(autoreverses: true) : .default, value: drift)
                .offset(y: drift ? -18 : 18)
                .animation(animating ? .easeInOut(duration: 18.5).repeatForever(autoreverses: true) : .default, value: drift)
            Circle()
                .fill(LinearGradient(colors: [Color(red: 129 / 255, green: 140 / 255, blue: 248 / 255),
                                              Color(red: 192 / 255, green: 132 / 255, blue: 252 / 255)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 120, height: 120)
                .opacity(0.5).blur(radius: 4)
                .position(x: 100, y: min(h * 0.58, 490))
                .offset(x: drift ? -16 : 16)
                .animation(animating ? .easeInOut(duration: 20.9).repeatForever(autoreverses: true) : .default, value: drift)
                .offset(y: drift ? 20 : -20)
                .animation(animating ? .easeInOut(duration: 14.3).repeatForever(autoreverses: true) : .default, value: drift)
        }
        .frame(width: w, height: h)
        .onAppear { if animating { drift = true } }
        .onChange(of: animating) { _, on in
            // Stopping settles the orbs in place (a short default animation), restarting resumes the drift.
            drift = on
        }
    }
}

/// Geometry from this view's own window, including safe areas. Updates on rotation
/// and split-view resizing without consulting another scene or physical screen.
private struct MirsaBackdropFrameKey: EnvironmentKey {
    static let defaultValue: CGRect? = nil
}
extension EnvironmentValues {
    var mirsaBackdropFrame: CGRect? {
        get { self[MirsaBackdropFrameKey.self] }
        set { self[MirsaBackdropFrameKey.self] = newValue }
    }
}
/// False inside a retained but hidden tab of ContentView's custom tab host, so its
/// decorative animations (backdrop drift) stop instead of running off screen.
private struct MirsaTabActiveKey: EnvironmentKey {
    static let defaultValue: Bool = true
}
extension EnvironmentValues {
    var mirsaTabActive: Bool {
        get { self[MirsaTabActiveKey.self] }
        set { self[MirsaTabActiveKey.self] = newValue }
    }
}
/// Bottom room the floating dock needs, published by LiquidTabChrome to its tab.
/// Apply inside UIKit navigation hosts too, so Forms/Lists keep last-row
/// clearance without shrinking their scrollable viewport.
/// Read before any tab expands its viewport under the home indicator.
private struct MirsaDockBottomSafeAreaKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
private struct MirsaDockClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
extension EnvironmentValues {
    var mirsaDockBottomSafeArea: CGFloat {
        get { self[MirsaDockBottomSafeAreaKey.self] }
        set { self[MirsaDockBottomSafeAreaKey.self] = newValue }
    }
    var mirsaDockClearance: CGFloat {
        get { self[MirsaDockClearanceKey.self] }
        set { self[MirsaDockClearanceKey.self] = newValue }
    }
}
struct MirsaDockClearance: ViewModifier {
    @Environment(\.mirsaDockClearance) private var clearance
    func body(content: Content) -> some View {
        content.contentMargins(.bottom, clearance, for: .scrollContent)
    }
}
extension View {
    /// Apply to a Form/List/ScrollView inside a tab's NavigationStack so its last rows
    /// can scroll above the floating dock (no-op outside the tab host).
    func mirsaDockClearance() -> some View { modifier(MirsaDockClearance()) }
}
struct MirsaWindowBackdropHost: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geo in
            let local = geo.frame(in: .global)
            let safe = geo.safeAreaInsets
            let window = CGRect(x: local.minX - safe.leading, y: local.minY - safe.top,
                                width: local.width + safe.leading + safe.trailing,
                                height: local.height + safe.top + safe.bottom)
            // While the scene is resuming SwiftUI can briefly report a zero/non-finite frame.
            // Publishing it would collapse every backdrop to nothing (blank dark window).
            let usable = window.width > 50 && window.height > 50 && window.width.isFinite && window.height.isFinite
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.mirsaBackdropFrame, usable ? window : nil)
        }
    }
}

/// Nested opaque page backdrops sample the same window coordinates as the root.
/// Standalone sheets fall back to their own geometry rather than another scene.
struct MirsaScreenAnchored<Content: View>: View {
    @Environment(\.mirsaBackdropFrame) private var window
    @ViewBuilder var content: (CGSize) -> Content
    var body: some View {
        GeometryReader { geo in
            let local = geo.frame(in: .global)
            let canvas = (window ?? local).width > 50 && (window ?? local).height > 50 ? (window ?? local) : geo.frame(in: .local)
            content(canvas.size)
                .frame(width: canvas.width, height: canvas.height)
                .offset(x: canvas.minX - local.minX, y: canvas.minY - local.minY)
                .environment(\.layoutDirection, .leftToRight)
        }
        // Global canvas offsets are physical coordinates, even in an RTL Form.
        // Set this on the geometry host, not only its oversized child.
        .environment(\.layoutDirection, .leftToRight)
        .ignoresSafeArea()
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Floating glass tab bar (Liquid Glass theme)

struct LiquidTabItem: Identifiable {
    let tab: AppTab
    let title: String
    let icon: String
    var id: String { tab.rawValue }
}

struct LiquidTabBar: View {
    @Binding var selection: AppTab
    let items: [LiquidTabItem]
    var light = false
    @ObservedObject private var chatStore = ForgeChatStore.shared
    @ObservedObject private var chatLocal = ForgeChatLocal.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var chatUnread: Int { chatLocal.unreadCount(chatStore.threads) }

    private func glow(for tab: AppTab) -> Color {
        switch tab {
        case .apps: return Color(red: 1, green: 0.52, blue: 0.24)
        case .sources: return Color(red: 0.28, green: 0.62, blue: 1)
        case .pairing: return Color(red: 0.72, green: 0.48, blue: 1)
        case .encrypted: return Color(red: 0.26, green: 0.84, blue: 0.68)
        case .personalHub: return Color(red: 1, green: 0.72, blue: 0.30)
        case .mirsaAI: return Color(red: 0.42, green: 0.80, blue: 1)
        case .walletCards, .passcodeThemes, .wallpapers: return .gray
        }
    }

    private func glass<S: InsettableShape>(_ shape: S) -> some View {
        Color.clear.modifier(MirsaDockGlass(shape: shape, light: light))
            .allowsHitTesting(false)
    }

    private func tabButton(_ item: LiquidTabItem) -> some View {
        let selected = selection == item.tab
        return Button {
            withAnimation(MirsaMotion.select) { selection = item.tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: 19, weight: selected ? .semibold : .regular))
                    .frame(height: 23)
                    .background {
                        Ellipse()
                            .fill(glow(for: item.tab).opacity(selected ? 0.8 : 0.18))
                            .frame(width: selected ? 29 : 21, height: 15)
                            .blur(radius: selected ? 10 : 9)
                            .offset(y: 3)
                    }
                    .overlay(alignment: .topTrailing) {
                        if item.tab == .mirsaAI {
                            ForgeChatUnreadDot(count: chatUnread).offset(x: 9, y: -5)
                        }
                    }
                Text(item.title)
                    .font(MirsaFont.tabLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .allowsTightening(true)
            }
            .foregroundStyle(light ? Color(sourcesRGB: 0x17132E).opacity(selected ? 1 : 0.6) : Color.white.opacity(selected ? 1 : 0.57))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if selected {
                    if item.tab == .mirsaAI {
                        Circle()
                            .fill((light ? Color.black : Color.white).opacity(light ? 0.06 : 0.14))
                            .overlay(Circle().strokeBorder((light ? Color.black : Color.white).opacity(light ? 0.06 : 0.12), lineWidth: 0.5))
                    } else {
                        Capsule()
                            .fill((light ? Color.black : Color.white).opacity(light ? 0.06 : 0.14))
                            .overlay(Capsule().strokeBorder((light ? Color.black : Color.white).opacity(light ? 0.06 : 0.12), lineWidth: 0.5))
                    }
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.mirsaPress)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("main-tab-" + item.tab.rawValue)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 1) {
                ForEach(items.filter { $0.tab != .mirsaAI }) { item in
                    tabButton(item)
                }
            }
            .padding(5)
            .frame(height: MirsaTabBarMetrics.height)
            .background { glass(Capsule()) }
            // Give the pill its own container so its identifier cannot replace child IDs.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mirsa-main-tab-pill")

            if let ai = items.first(where: { $0.tab == .mirsaAI }) {
                tabButton(ai)
                    .padding(5)
                    .frame(width: MirsaTabBarMetrics.height, height: MirsaTabBarMetrics.height)
                    // No clipShape here: the glass and the selection fill are already
                    // circles, and clipping cut off the unread badge at the top edge.
                    .background { glass(Circle()) }
                    .contentShape(Circle())
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mirsa-tab-dock")
        .accessibilityValue(light ? "light" : "dark")
        .environment(\.colorScheme, light ? .light : .dark)
        // Preserve Mirsa's physical tab order in every language; Arabic/Sorani
        // labels keep their native text shaping without mirroring the icons.
        .environment(\.layoutDirection, .leftToRight)
        .padding(.horizontal, MirsaTabBarMetrics.sideInset)
        .padding(.bottom, MirsaTabBarMetrics.bottomGap)
    }
}

enum MirsaTabBarMetrics {
    static let height: CGFloat = 66
    static let bottomGap: CGFloat = 8
    /// Side margin of the floating dock, a little tighter than the page margin.
    static let sideInset: CGFloat = 14
    /// Space content must keep free so nothing hides behind the floating bar.
    static var clearance: CGFloat { height + bottomGap + 10 }
    /// Float just above the home indicator, not a whole safe area above it.
    /// Zero-inset windows retain the original eight-point bottom gap.
    static func windowBottomGap(_ safeBottom: CGFloat) -> CGFloat { max(bottomGap, safeBottom / 2) }
    /// All scroll surfaces and nested bars measure from the physical window edge.
    static func scrollClearance(_ safeBottom: CGFloat) -> CGFloat { height + windowBottomGap(safeBottom) + 10 }
}

#if DEBUG
/// Independent UIKit window geometry for native layout regression assertions.
/// Not the dock's proposed frame or a test-supplied safe-area constant.
struct MirsaDockWindowGeometryProbe: UIViewRepresentable {
    final class Probe: UIView {
        func publish() {
            guard let window else { return }
            isAccessibilityElement = true
            accessibilityIdentifier = "mirsa-dock-window-geometry"
            accessibilityLabel = "Dock window geometry"
            accessibilityValue = "height=\(window.bounds.height);safeBottom=\(window.safeAreaInsets.bottom)"
        }
        override func didMoveToWindow() { super.didMoveToWindow(); publish() }
        override func layoutSubviews() { super.layoutSubviews(); publish() }
    }
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) { uiView.publish() }
}
#endif
