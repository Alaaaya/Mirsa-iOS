import SwiftUI

/// The retained Tools subtree reports only its current section. ContentView scopes it to the active tab.
struct ToolsStoreActiveKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Second tab: pairing and the device tools, all in one place, in Mirsa's design.
struct ToolsTab: View {
    @EnvironmentObject var vm: AppViewModel
    enum Section: String, CaseIterable, Identifiable {
        // Fixed physical order in every language (same as the dock): Pairing, Device, Tendies, Tweaks, Store.
        case pairing, device, wallpapers, tweaks, store
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .pairing: return "antenna.radiowaves.left.and.right"
            case .device: return "iphone.gen3"
                case .tweaks: return "wand.and.stars"
            case .wallpapers: return "play.rectangle.fill"
            case .store: return "bag.fill"
            }
        }
    }
    @State private var section: Section = .pairing
    @Namespace private var ns
    @State private var chatComposerFocused = false
    @AppStorage(SourcesTheme.key) private var storeThemeRaw = SourcesTheme.aurora.rawValue
    private var storeTheme: SourcesTheme { SourcesTheme(rawValue: storeThemeRaw) ?? .aurora }

    var body: some View {
        VStack(spacing: 0) {
            if !chatComposerFocused {
                // Floats on the page backdrop like the dock; no strip of its own behind it.
                picker
                    .padding(.horizontal, MirsaSpacing.page)
                    .padding(.vertical, MirsaSpacing.xs)
                    // UIKit navigation content below must not cover the section controls.
                    .zIndex(1)
            }
            Group {
                switch section {
                case .pairing: SetupPairingSheet(showsClose: false)
                case .device: DeviceToolsView()
                case .wallpapers: TendiesView()
                case .tweaks: NavigationView { ForgeView() }.navigationViewStyle(.stack)
                case .store: ToolsStoreView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Animate the picker highlight, never the incoming UIKit/Form viewport.
            .animation(nil, value: section)
        }
        // One continuous page background behind the picker and every section.
        // The Tools Store follows the Sources theme, so its whole page (picker strip included) uses that backdrop.
        .background {
            if section == .store {
                SourcesThemeBackground(theme: storeTheme)
            } else {
                AuroraBackground().ignoresSafeArea()
            }
        }
        .preferredColorScheme(section == .store ? storeTheme.colorScheme : .dark)
        .preference(key: ToolsStoreActiveKey.self, value: section == .store)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("mirsa.wallpaper.imported.open"))) { _ in
            section = .wallpapers
        }
        .onPreferenceChange(ForgeChatComposerFocusKey.self) { chatComposerFocused = $0 }
    }

    private var picker: some View {
        HStack(spacing: 4) {
            ForEach(Section.allCases) { s in
                Button {
                    withAnimation(MirsaMotion.select) { section = s }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: s.icon).font(.system(size: 16, weight: .semibold)).frame(height: 18)
                        Text(s == .device ? MirsaTr.german(tr("Device", "الجهاز")) : s == .wallpapers ? TendiesSection.name : s == .tweaks ? tr("Tweaks", "التويكس", ckb: "تویکەکان", kmr: "Tweak") : s == .store ? ToolsStoreText.tab : L.t("tools.\(s.rawValue)")).font(MirsaFont.tabLabel).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(section == s ? .white : MirsaPalette.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if section == s {
                            Capsule().fill(MirsaPalette.accentGradient).opacity(0.9)
                                .shadow(color: MirsaPalette.accent.opacity(0.45), radius: 8, y: 3)
                                .matchedGeometryEffect(id: "sel", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.mirsaPress)
                .accessibilityIdentifier("tools-section-" + s.rawValue)
                .accessibilityAddTraits(section == s ? .isSelected : [])
            }
        }
        .padding(4)
        .background {
            // Glass and its rim are decoration, never an input surface over the buttons.
            Capsule().fill(.clear)
                .appsGlassCapsule()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay {
            Capsule()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.26), .white.opacity(0.05)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
        .environment(\.layoutDirection, .leftToRight)
    }
}
