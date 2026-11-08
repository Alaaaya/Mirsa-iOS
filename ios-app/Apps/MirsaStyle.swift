import SwiftUI

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
            .toolbarBackground(MirsaPalette.sheet, for: .navigationBar)
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
    /// Every card in Mirsa goes through here. Since the style unification it is
    /// always a solid card (no blur / material), whatever theme is selected.
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
struct LiquidBackground: View {
    var paused = false
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
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
                }
            }
        }
        .ignoresSafeArea()
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
    @Namespace private var ns

    var body: some View {
        HStack(spacing: MirsaSpacing.xxs) {
            ForEach(items) { item in
                let on = selection == item.tab
                Button {
                    withAnimation(MirsaMotion.select) { selection = item.tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon).font(.system(size: 19, weight: on ? .semibold : .regular))
                            .frame(height: 22)
                        Text(item.title).font(MirsaFont.tabLabel).lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .allowsTightening(true)
                    }
                    .foregroundStyle(on ? .white : MirsaPalette.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if on {
                            Capsule()
                                .fill(MirsaPalette.accentGradient)
                                .opacity(0.9)
                                .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                                .shadow(color: MirsaPalette.accent.opacity(0.45), radius: 8, y: 3)
                                .matchedGeometryEffect(id: "tab", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.mirsaPress)
            }
        }
        .padding(6)
        .frame(height: MirsaTabBarMetrics.height)
        .environment(\.layoutDirection, .leftToRight)
        .modifier(MirsaSolidCard(shape: Capsule(), tint: nil, elevation: 1.2))
        .padding(.horizontal, MirsaSpacing.page)
        .padding(.bottom, MirsaTabBarMetrics.bottomGap)
    }
}

enum MirsaTabBarMetrics {
    static let height: CGFloat = 66
    static let bottomGap: CGFloat = 8
    /// Space content must keep free so nothing hides behind the floating bar.
    static var clearance: CGFloat { height + bottomGap + 10 }
}
