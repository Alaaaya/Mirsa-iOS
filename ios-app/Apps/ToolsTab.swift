import SwiftUI

/// Second tab: pairing and the device tools, all in one place, in Mirsa's design.
struct ToolsTab: View {
    @EnvironmentObject var vm: AppViewModel
    enum Section: String, CaseIterable, Identifiable {
        case tweaks, create, wallpapers, device, pairing
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .pairing: return "antenna.radiowaves.left.and.right"
            case .device: return "iphone.gen3"
                case .tweaks: return "wand.and.stars"
            case .create: return "bubble.left.and.bubble.right"
            case .wallpapers: return "play.rectangle.fill"
            }
        }
    }
    @State private var section: Section = {
        #if DEBUG
        if MirsaUITestHarness.active && ProcessInfo.processInfo.arguments.contains("-MirsaChatEmbeddedFixture") { return .create }
        #endif
        return .pairing
    }()
    @Namespace private var ns
    @State private var chatComposerFocused = false
    @ObservedObject private var chatStore = ForgeChatStore.shared
    @ObservedObject private var chatLocal = ForgeChatLocal.shared
    private var unread: Int { chatLocal.unreadCount(chatStore.threads) }

    var body: some View {
        VStack(spacing: 0) {
            if !chatComposerFocused {
                picker
                    .padding(.horizontal, MirsaSpacing.page)
                    .padding(.vertical, MirsaSpacing.xs)
                    .background(AuroraBackground().ignoresSafeArea(edges: .top))
            }
            Group {
                switch section {
                case .pairing: SetupPairingSheet(showsClose: false)
                case .device: DeviceToolsView()
                case .create: ForgeChatRoot(embedded: true).environment(\.layoutDirection, .leftToRight)
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
                            .overlay(alignment: .topTrailing) { if s == .create { ForgeChatUnreadDot(count: unread).offset(x: 12, y: -8) } }
                        Text(s == .device ? tr("Device", "الجهاز") : s == .create ? ForgeChatText.title : s == .wallpapers ? wtr("Video wallpaper", "خلفية فيديو", de: "Video-Hintergrund", ckb: "ڤیدیۆ پاشبنەما", kmr: "Wêneya vîdyoyê") : s == .tweaks ? tr("Tweaks", "التويكس", ckb: "تویکەکان", kmr: "Tweak") : L.t("tools.\(s.rawValue)")).font(MirsaFont.tabLabel).lineLimit(1).minimumScaleFactor(0.7)
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
        .environment(\.layoutDirection, .leftToRight)
    }
}
