import SwiftUI

/// Published by the dock so floating page controls (the Apps + button) can move
/// above an expanded card instead of colliding with it.
@MainActor
final class MirsaDockState: ObservableObject {
    static let shared = MirsaDockState()
    @Published var expansionHeight: CGFloat = 0
    @Published var isExpanded = false
}

extension Notification.Name {
    /// Carries one of the dock action ids as `object`. Tabs that own the action listen.
    static let mirsaDockAction = Notification.Name("mirsa.dock.action")
    static let mirsaDockDismiss = Notification.Name("mirsa.dock.dismiss")
}

/// Native adaptation of rit3zh's expandable bottom tabs: ONE continuous glass
/// surface. Tapping or holding the active tab grows a contextual card out of the
/// bar itself; the six tabs stay crisp, in place and in physical order.
struct ExpandableGlassDock: View {
    @Binding var selection: AppTab
    let items: [LiquidTabItem]
    var light = false
    private var expanded: Bool { dockState.isExpanded }
    @State private var lastHold = Date.distantPast
    @ObservedObject private var dockState = MirsaDockState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ink: Color { light ? Color(sourcesRGB: 0x17132E) : .white }
    private var actions: [DockAction] { DockAction.actions(for: selection) }
    private var current: LiquidTabItem? { items.first { $0.tab == selection } }
    private var spring: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)
    }
    private func setExpanded(_ value: Bool) {
        guard value == false || !actions.isEmpty else { return }
        withAnimation(spring) { dockState.isExpanded = value }
        if !value { dockState.expansionHeight = 0 }
    }
    private func run(_ action: DockAction) {
        setExpanded(false)
        if action.id == "encrypted-downloads" {
            NotificationCenter.default.post(name: Notification.Name("mirsa.store.wishlist.open"), object: nil)
        } else {
            NotificationCenter.default.post(name: .mirsaDockAction, object: action.id)
        }
    }

    var body: some View {
        // Keep the dock intrinsically sized. A flexible full-screen dismissal
        // sibling here stretches the SwiftUI accessibility host to the viewport,
        // so mirsa-tab-dock incorrectly starts at the top safe area when open.
        // ContentView owns the separate page-sized dismissal plane instead.
        VStack(spacing: 0) {
                if expanded && !actions.isEmpty {
                    card
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
                }
                LiquidTabBar(selection: $selection, items: items, light: light, embedded: true,
                             onReselect: {
                                 // The press that ends a hold must not toggle it shut again.
                                 guard Date().timeIntervalSince(lastHold) > 0.8 else { return }
                                 setExpanded(!expanded)
                             },
                             onHold: { lastHold = Date(); setExpanded(true) })
                    // A recognised vertical drag cancels the child tab tap.
                    .highPriorityGesture(DragGesture(minimumDistance: 16).onEnded { value in
                        guard abs(value.translation.height) > abs(value.translation.width) else { return }
                        if value.translation.height < -28 { setExpanded(true) }
                        else if value.translation.height > 28 { setExpanded(false) }
                    })
            }
            // The ONE material, behind all foreground content.
            .background {
                Color.clear
                    .modifier(MirsaDockGlass(shape: RoundedRectangle(cornerRadius: expanded ? 30 : 33, style: .continuous), light: light))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, MirsaTabBarMetrics.sideInset)
            .padding(.bottom, MirsaTabBarMetrics.bottomGap)
            .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(ink)
        .environment(\.colorScheme, light ? .light : .dark)
        .environment(\.layoutDirection, .leftToRight)
        .onReceive(NotificationCenter.default.publisher(for: .mirsaDockDismiss)) { _ in setExpanded(false) }
        .onChange(of: selection) { _, _ in setExpanded(false) }
        // Own the escape action on the whole dock, not on the first exposed
        // child. Otherwise SwiftUI promotes the expanded card to the enclosing
        // dock's accessibility frame, which includes the tab row below it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mirsa-expandable-dock")
        .accessibilityAction(.escape) { setExpanded(false) }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(current?.title ?? "")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ink.opacity(0.62))
                .padding(.horizontal, 6)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                ForEach(actions) { action in
                    Button { run(action) } label: {
                        VStack(spacing: 7) {
                            Image(systemName: action.icon)
                                .font(.system(size: 20, weight: .medium))
                                .frame(height: 24)
                            Text(action.title)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(2).multilineTextAlignment(.center)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 74)
                        .padding(.horizontal, 4)
                        .background(ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.mirsaPress)
                    .accessibilityIdentifier("dock-action-" + action.id)
                }
            }
        }
        .padding(.top, 14).padding(.horizontal, 12).padding(.bottom, 6)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { dockState.expansionHeight = geo.size.height + 8 }
                    .onChange(of: geo.size.height) { _, h in dockState.expansionHeight = h + 8 }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dock-expanded-card")
    }
}

/// A real, existing action of the selected tab. Tabs without one do not expand.
struct DockAction: Identifiable {
    let id: String
    let icon: String
    let title: String

    @MainActor static func actions(for tab: AppTab) -> [DockAction] {
        switch tab {
        case .apps:
            return [
                DockAction(id: "apps-files", icon: "folder",
                           title: tr5("From Files", "من الملفات", de: "Aus Dateien", ckb: "لە فایلەکانەوە", kmr: "Ji Pelan")),
                DockAction(id: "apps-link", icon: "link",
                           title: tr5("From link", "من رابط", de: "Per Link", ckb: "لە بەستەرەوە", kmr: "Ji lînkê")),
                DockAction(id: "apps-hidden", icon: "eye.slash",
                           title: tr5("Hidden apps", "التطبيقات المخفية", de: "Versteckte Apps", ckb: "ئەپە شاراوەکان", kmr: "Sepanên veşartî")),
            ]
        case .sources:
            return [
                DockAction(id: "sources-add", icon: "plus",
                           title: tr5("Add source", "أضف سورس", de: "Quelle hinzufügen", ckb: "سەرچاوە زیاد بکە", kmr: "Çavkaniyê lê zêde bike")),
                DockAction(id: "sources-search", icon: "magnifyingglass",
                           title: tr5("Search", "بحث", de: "Suchen", ckb: "گەڕان", kmr: "Lêgerîn")),
            ]
        case .encrypted:
            return [
                DockAction(id: "encrypted-downloads", icon: "arrow.down.circle",
                           title: tr5("Downloads", "التنزيلات", de: "Downloads", ckb: "داگرتنەکان", kmr: "Daxistin")),
            ]
        default:
            return []
        }
    }
}

/// All dock surfaces share the system's actual Liquid Glass on iOS 26.
/// Reduce Transparency intentionally bypasses it, including the main bar.
struct MirsaDockGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let light: Bool
    @Environment(\.accessibilityReduceTransparency) private var solid
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !solid {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.background {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill((light ? Color.white : Color.black).opacity(solid ? 0.94 : (light ? 0.76 : 0.36))))
                    .overlay(shape.strokeBorder((light ? Color.black : Color.white).opacity(light ? 0.08 : 0.18), lineWidth: 0.75))
                    .shadow(color: .black.opacity(light ? 0.10 : 0.30), radius: 14, y: 7)
                    .allowsHitTesting(false)
            }
        }
    }
}

