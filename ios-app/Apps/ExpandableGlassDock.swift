import SwiftUI

/// Native adaptation of rit3zh's expandable dock. Two glass cards lift out of
/// the dock, with a separate context/menu pill. This is navigation context, not
/// a fabricated account-presence service. The original six destinations stay
/// in their original physical order.
struct ExpandableGlassDock: View {
    @Binding var selection: AppTab
    let items: [LiquidTabItem]
    var light = false
    private enum Card { case workspace, profile }
    @State private var card: Card?
    @State private var menuOpen = false
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ink: Color { light ? Color(sourcesRGB: 0x17132E) : .white }
    private var current: LiquidTabItem? { items.first { $0.tab == selection } }
    private var menuTitle: String {
        tr5("Navigate", "التنقّل", de: "Navigation", ckb: "گەڕان", kmr: "Rêgez")
    }
    private var spring: Animation? {
        reduceMotion ? nil : .spring(response: 0.40, dampingFraction: 0.80)
    }
    private func show(_ value: Card?) {
        withAnimation(spring) { card = value; menuOpen = false }
    }
    private func choose(_ tab: AppTab) {
        withAnimation(spring) { selection = tab; card = nil; menuOpen = false }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Only expanded overlays intercept the page. The compact dock must
            // never turn its full-screen layout frame into an invisible blocker.
            if card != nil {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { show(nil) }
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("dock-dismiss-region")
            }
            DockGlassGroup {
                VStack(alignment: .trailing, spacing: 9) {
                    Spacer(minLength: 0)
                    if menuOpen {
                        navigationMenu
                            .transition(.scale(scale: 0.90, anchor: .bottomTrailing).combined(with: .opacity))
                    }
                    if card == .workspace {
                        workspaceCard
                            .transition(.scale(scale: 0.88, anchor: .bottomLeading).combined(with: .opacity))
                    }
                    if card != nil {
                        contextPill
                            .transition(.scale(scale: 0.88, anchor: .bottomTrailing).combined(with: .opacity))
                    }
                    // Keep the expansion hit area in its own layout row. An
                    // offset overlay outside the bar's bounds was exposed to
                    // accessibility but hit-tested as the AI tab underneath it.
                    if card == nil {
                        HStack {
                            Spacer(minLength: 0)
                            Button { show(.profile) } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(ink.opacity(0.70))
                                    .frame(width: 44, height: 22)
                                    .modifier(MirsaDockGlass(shape: Capsule(), light: light))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("dock-expand-handle")
                            .accessibilityLabel(menuTitle)
                        }
                        .padding(.horizontal, MirsaTabBarMetrics.sideInset + 12)
                    }
                    LiquidTabBar(selection: $selection, items: items, light: light)
                        .simultaneousGesture(DragGesture(minimumDistance: 16).onEnded { value in
                            guard abs(value.translation.height) > abs(value.translation.width) else { return }
                            if value.translation.height < -28 { show(.profile) }
                            else if value.translation.height > 28 { show(nil) }
                        })
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in show(.workspace) })
                }
            }
        }
        .foregroundStyle(ink)
        .environment(\.colorScheme, light ? .light : .dark)
        .environment(\.layoutDirection, .leftToRight)
        .onChange(of: selection) { _, _ in show(nil) }
        .accessibilityAction(.escape) { show(nil) }
    }

    // The left quick button and right profile/context capsule reproduce the
    // reference's split layout instead of placing a duplicate tab grid above it.
    private var contextPill: some View {
        HStack(spacing: 9) {
            Button { show(card == .workspace ? .profile : .workspace) } label: {
                Image(systemName: card == .workspace ? "bubble.left.and.bubble.right.fill" : "square.stack.3d.up.fill")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 58, height: 58)
                    .modifier(MirsaDockGlass(shape: Circle(), light: light))
                    .modifier(DockGlassIdentity(id: "workspace-toggle", namespace: glassNamespace))
            }
            .buttonStyle(.mirsaPress)
            .accessibilityIdentifier("dock-workspace-toggle")
            .accessibilityLabel(tr5("Workspace", "مساحة العمل", de: "Arbeitsbereich", ckb: "شوێنی کار", kmr: "Qada xebatê"))

            HStack(spacing: 10) {
                Button { choose(.personalHub) } label: { appMark }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dock-certificate-shortcut")
                    .accessibilityLabel(items.first { $0.tab == .personalHub }?.title ?? "Mirsa")
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mirsa").font(.system(size: 16, weight: .semibold))
                    Text(current?.title ?? menuTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ink.opacity(0.58))
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer(minLength: 4)
                Button {
                    withAnimation(spring) { menuOpen.toggle() }
                } label: {
                    Image(systemName: menuOpen ? "chevron.down" : (current?.icon ?? "ellipsis"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor.opacity(0.13), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dock-status-menu")
                .accessibilityLabel(menuTitle)
            }
            .padding(.horizontal, 12)
            .frame(height: 58)
            .modifier(MirsaDockGlass(shape: Capsule(), light: light))
            .modifier(DockGlassIdentity(id: "context-pill", namespace: glassNamespace))
        }
        .padding(.horizontal, MirsaTabBarMetrics.sideInset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dock-context-pill")
    }

    private var appMark: some View {
        Image("DockMirsaMark").resizable().scaledToFill()
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityHidden(true)
    }

    private var workspaceCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                appMark
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mirsa").font(.system(size: 20, weight: .bold))
                    Text(current?.title ?? menuTitle).font(.system(size: 12)).foregroundStyle(ink.opacity(0.6))
                }
                Spacer()
                Button { show(nil) } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .frame(width: 30, height: 30).background(ink.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dock-card-close")
                .accessibilityLabel(tr5("Close", "إغلاق", de: "Schließen", ckb: "داخستن", kmr: "Bigire"))
            }
            HStack(spacing: 8) {
                workspaceShortcut(.apps)
                workspaceShortcut(.sources)
            }
        }
        .padding(18)
        .modifier(MirsaDockGlass(shape: RoundedRectangle(cornerRadius: 28, style: .continuous), light: light))
        .modifier(DockGlassIdentity(id: "workspace-card", namespace: glassNamespace))
        .padding(.horizontal, MirsaTabBarMetrics.sideInset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dock-expanded-card")
    }

    private func workspaceShortcut(_ tab: AppTab) -> some View {
        let item = items.first { $0.tab == tab }
        return Button { choose(tab) } label: {
            HStack(spacing: 8) {
                Image(systemName: item?.icon ?? "square.grid.2x2")
                Text(item?.title ?? "Mirsa").lineLimit(1).minimumScaleFactor(0.65)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(12)
            .background(ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.mirsaPress)
        .accessibilityIdentifier("dock-card-tab-" + tab.rawValue)
    }

    private var navigationMenu: some View {
        VStack(spacing: 2) {
            ForEach(items) { item in
                Button { choose(item.tab) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .opacity(item.tab == selection ? 1 : 0)
                            .frame(width: 16)
                        Text(item.title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Spacer(minLength: 10)
                        Image(systemName: item.icon)
                            .foregroundStyle(item.tab == selection ? Color.accentColor : ink.opacity(0.60))
                            .frame(width: 22)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 42)
                    .contentShape(Rectangle())
                    .background(item.tab == selection ? ink.opacity(0.07) : .clear,
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dock-menu-tab-" + item.tab.rawValue)
                .accessibilityAddTraits(item.tab == selection ? .isSelected : [])
            }
        }
        .padding(7)
        .frame(width: 248)
        .modifier(MirsaDockGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous), light: light))
        .modifier(DockGlassIdentity(id: "context-menu", namespace: glassNamespace))
        .padding(.trailing, MirsaTabBarMetrics.sideInset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dock-navigation-menu")
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

private struct DockGlassIdentity: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}

private struct DockGlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8, content: content)
        } else {
            content()
        }
    }
}
