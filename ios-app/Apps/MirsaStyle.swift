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
            TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: paused)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255),
                                                      Color(red: 34 / 255, green: 211 / 255, blue: 238 / 255)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 190, height: 190)
                        .opacity(0.55).blur(radius: 6)
                        .position(x: w - 65 + sin(t * 0.20) * 14, y: 245 + cos(t * 0.17) * 18)
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 129 / 255, green: 140 / 255, blue: 248 / 255),
                                                      Color(red: 192 / 255, green: 132 / 255, blue: 252 / 255)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 120, height: 120)
                        .opacity(0.5).blur(radius: 4)
                        .position(x: 100 + cos(t * 0.15) * 16, y: min(h * 0.58, 490) + sin(t * 0.22) * 20)
                }
                .frame(width: w, height: h)
            }
        }
        .frame(width: w, height: h)
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
struct MirsaWindowBackdropHost: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geo in
            let local = geo.frame(in: .global)
            let safe = geo.safeAreaInsets
            let window = CGRect(x: local.minX - safe.leading, y: local.minY - safe.top,
                                width: local.width + safe.leading + safe.trailing,
                                height: local.height + safe.top + safe.bottom)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.mirsaBackdropFrame, window)
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
            let canvas = window ?? local
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
        shape.fill(.ultraThinMaterial)
            // Keep light glass genuinely pale even over the window's dark aurora.
            // Appearance preferences alone cannot guarantee the sampled material tint.
            .overlay(shape.fill((light ? Color.white : Color.black).opacity(reduceTransparency ? 0.86 : (light ? 0.76 : 0.36))))
            .overlay(shape.strokeBorder((light ? Color.black : Color.white).opacity(light ? 0.08 : 0.18), lineWidth: 0.75))
            .shadow(color: .black.opacity(light ? 0.10 : 0.30), radius: 14, y: 7)
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
}
