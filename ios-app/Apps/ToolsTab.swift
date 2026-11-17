import SwiftUI

/// Second tab: pairing and the device tools, all in one place, in Mirsa's design.
struct ToolsTab: View {
    @EnvironmentObject var vm: AppViewModel
    enum Section: String, CaseIterable, Identifiable {
        // Fixed physical order in every language (same as the dock): Pairing, Device, Tendies, Tweaks.
        case pairing, device, wallpapers, tweaks
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .pairing: return "antenna.radiowaves.left.and.right"
            case .device: return "iphone.gen3"
                case .tweaks: return "wand.and.stars"
            case .wallpapers: return "play.rectangle.fill"
            }
        }
    }
    @State private var section: Section = .pairing
    @Namespace private var ns
    @State private var chatComposerFocused = false

    var body: some View {
        VStack(spacing: 0) {
            if !chatComposerFocused {
                // Floats on the page backdrop like the dock; no strip of its own behind it.
                picker
                    .padding(.horizontal, MirsaSpacing.page)
                    .padding(.vertical, MirsaSpacing.xs)
            }
            Group {
                switch section {
                case .pairing: SetupPairingSheet(showsClose: false)
                case .device: DeviceToolsView()
                case .wallpapers: TendiesView()
                case .tweaks: NavigationView { ForgeView() }.navigationViewStyle(.stack)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // One continuous page background behind the picker and every section.
        .background(AuroraBackground().ignoresSafeArea())
        .preferredColorScheme(.dark)
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
                        Text(s == .device ? MirsaTr.german(tr("Device", "الجهاز")) : s == .wallpapers ? TendiesSection.name : s == .tweaks ? tr("Tweaks", "التويكس", ckb: "تویکەکان", kmr: "Tweak") : L.t("tools.\(s.rawValue)")).font(MirsaFont.tabLabel).lineLimit(1).minimumScaleFactor(0.7)
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
        .appsGlassCapsule()
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
