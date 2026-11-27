import SwiftUI

/// Expandable Liquid Glass dock. The compact LiquidTabBar is unchanged (same tabs, same
/// order, left to right). Swiping up on it, or tapping the grabber, lifts a glass card
/// that holds every tab; tapping outside or choosing a tab folds it back down.
/// iOS 26 uses real Liquid Glass; earlier systems keep Mirsa's material glass.
struct ExpandableGlassDock: View {
    @Binding var selection: AppTab
    let items: [LiquidTabItem]
    var light = false
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var spring: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78)
    }
    private func set(_ value: Bool) {
        guard expanded != value else { return }
        withAnimation(spring) { expanded = value }
    }
    private var ink: Color { light ? Color(sourcesRGB: 0x17132E) : .white }

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            if expanded { card.transition(.scale(scale: 0.88, anchor: .bottom).combined(with: .opacity)) }
            grabber
            LiquidTabBar(selection: $selection, items: items, light: light)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 14)
                        .onEnded { value in
                            if value.translation.height < -28, abs(value.translation.width) < abs(value.translation.height) { set(true) }
                            else if value.translation.height > 28 { set(false) }
                        }
                )
        }
        .background {
            if expanded {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { set(false) }
                    .accessibilityHidden(true)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .onChange(of: selection) { _, _ in set(false) }
    }

    private var grabber: some View {
        Button { set(!expanded) } label: {
            Capsule()
                .fill(ink.opacity(expanded ? 0.55 : 0.32))
                .frame(width: 38, height: 5)
                .frame(width: 88, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dock-expand-handle")
        .accessibilityLabel(expanded ? "Collapse tabs" : "Expand tabs")
    }

    private var card: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items) { item in
                Button {
                    withAnimation(MirsaMotion.select) { selection = item.tab }
                    set(false)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: item.icon).font(.system(size: 24, weight: .semibold)).frame(height: 28)
                        Text(item.title).font(MirsaFont.tabLabel).lineLimit(1).minimumScaleFactor(0.65)
                    }
                    .foregroundStyle(ink.opacity(selection == item.tab ? 1 : 0.72))
                    .frame(maxWidth: .infinity, minHeight: 78)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(ink.opacity(selection == item.tab ? 0.14 : 0.05))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.mirsaPress)
                .accessibilityIdentifier("dock-card-tab-" + item.tab.rawValue)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selection == item.tab ? .isSelected : [])
            }
        }
        .padding(14)
        .modifier(DockCardGlass(light: light, solid: reduceTransparency))
        .padding(.horizontal, MirsaTabBarMetrics.sideInset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dock-expanded-card")
    }
}

private struct DockCardGlass: ViewModifier {
    let light: Bool
    let solid: Bool
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        if #available(iOS 26.0, *), !solid {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.fill((light ? Color.white : Color.black).opacity(solid ? 0.88 : (light ? 0.76 : 0.42))))
                        .overlay(shape.strokeBorder((light ? Color.black : Color.white).opacity(light ? 0.08 : 0.18), lineWidth: 0.75))
                        .shadow(color: .black.opacity(light ? 0.10 : 0.30), radius: 16, y: 8)
                }
        }
    }
}
