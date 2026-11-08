import SwiftUI

/// Second tab: pairing and the device tools, all in one place, in Mirsa's design.
struct ToolsTab: View {
    @EnvironmentObject var vm: AppViewModel
    enum Section: String, CaseIterable, Identifiable {
        case pairing, device, tweaks
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .pairing: return "antenna.radiowaves.left.and.right"
            case .device: return "iphone.gen3"
                case .tweaks: return "wand.and.stars"
            }
        }
    }
    @State private var section: Section = .pairing
    @Namespace private var ns

    var body: some View {
        VStack(spacing: 0) {
            picker
                .padding(.horizontal, MirsaSpacing.page)
                .padding(.vertical, MirsaSpacing.xs)
                .background(AuroraBackground().ignoresSafeArea(edges: .top))
            Group {
                switch section {
                case .pairing: SetupPairingSheet(showsClose: false)
                case .device: DeviceToolsView()
                case .tweaks: NavigationView { ForgeView() }.navigationViewStyle(.stack)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // One continuous page background behind the picker and every section.
        .background(AuroraBackground().ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var picker: some View {
        HStack(spacing: 4) {
            ForEach(Section.allCases) { s in
                Button {
                    withAnimation(MirsaMotion.select) { section = s }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: s.icon).font(.system(size: 16, weight: .semibold)).frame(height: 18)
                        Text(s == .device ? tr("Device", "الجهاز") : s == .tweaks ? tr("Tweaks", "التويكس", ckb: "تویکەکان", kmr: "Tweak") : L.t("tools.\(s.rawValue)")).font(MirsaFont.tabLabel).lineLimit(1).minimumScaleFactor(0.7)
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
            }
        }
        .padding(4)
        .appsGlassCapsule()
    }
}
