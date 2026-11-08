import SwiftUI
import UniformTypeIdentifiers

/// Mirsa Setup's own pairing screen: network, pair on this iPhone, or import.
struct SetupPairingSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showFilePicker = false
    var showsClose = true

    private var networkOK: Bool { vm.vpnUp }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: MirsaSpacing.m) {
                    MirsaPageHeader(title: L.t("setup.pairing")) {
                        if showsClose { Button { dismiss() } label: {
                            MirsaRoundIcon(systemName: "xmark")
                        }
                        .buttonStyle(.mirsaPress) }
                    }
                    .padding(.bottom, MirsaSpacing.xxs)

                    networkCard.mirsaAppear()
                    statusCard.mirsaAppear(delay: 0.04)
                    pairCard.mirsaAppear(delay: 0.08)
                    importCard.mirsaAppear(delay: 0.12)
                }
                .padding(.horizontal, MirsaSpacing.page).padding(.top, showsClose ? MirsaSpacing.xl : MirsaSpacing.xxs).padding(.bottom, MirsaSpacing.xl)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showFilePicker) {
            DocumentPickerView(allowedContentTypes: [
                UTType(filenameExtension: "mobiledevicepairing") ?? .data,
                UTType(filenameExtension: "mobilepair") ?? .data,
                .propertyList, .data, .item
            ]) { url in
                _ = vm.importPairingFile(from: url, originalName: url.lastPathComponent)
                vm.refreshPairingFile()
            }
        }
        .task { vm.refreshNetworkStatus(); vm.refreshPairingFile() }
    }

    private func row(icon: String, ok: Bool, title: String, sub: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(ok ? MirsaPalette.success : MirsaPalette.warning).frame(width: MirsaIconSize.button, height: MirsaIconSize.button)
                Image(systemName: ok ? "checkmark" : icon).font(.system(size: MirsaIconSize.m, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(MirsaFont.cardTitle).foregroundStyle(.white)
                Text(sub).font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            row(icon: "lock.shield", ok: networkOK, title: L.t("setup.network"),
                sub: networkOK ? L.t("setup.networkOK") : L.t("setup.networkOff"))
            HStack(spacing: 10) {
                if !networkOK {
                    Button {
                        if let u = URL(string: "localdevvpn://") { UIApplication.shared.open(u) }
                    } label: {
                        Label(L.t("pair.openVPN"), systemImage: "arrow.up.forward.app")
                            .lineLimit(1)
                    }
                    .buttonStyle(.mirsaSecondary)
                }
                Spacer()
                Button { vm.refreshNetworkStatus() } label: {
                    MirsaRoundIcon(systemName: "arrow.clockwise")
                }
                .buttonStyle(.mirsaPress)
            }
        }
        .padding(MirsaSpacing.card).appsGlass(cornerRadius: MirsaRadius.l)
    }

    private var statusCard: some View {
        row(icon: "link", ok: vm.hasPairingFile, title: L.t("setup.pairing"),
            sub: vm.hasPairingFile ? L.t("setup.pairingOK") : L.t("setup.pairingOff"))
            .padding(MirsaSpacing.card).appsGlass(cornerRadius: MirsaRadius.l)
    }

    private var pairCard: some View {
        VStack(spacing: 14) {
            if vm.pairingPhase == .pairing {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text(vm.pairingStatus.isEmpty ? L.t("pair.starting") : vm.pairingStatus)
                        .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                    Spacer()
                }
                if let pin = vm.pairingPIN {
                    Text(L.t("pair.enterPIN")).font(.caption.bold()).foregroundStyle(.white.opacity(0.6))
                    HStack {
                        Text(pin).font(.system(size: 40, weight: .black, design: .monospaced)).foregroundStyle(.orange)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = pin
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: { MirsaRoundIcon(systemName: "doc.on.doc") }
                        .buttonStyle(.mirsaPress)
                    }
                    Text(L.t("pair.where")).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    } label: {
                        Text(L.t("pair.openSettings")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.mirsaPrimary)
                }
                Button(L.t("choice.cancel"), role: .destructive) { vm.cancelPairing() }
                    .buttonStyle(.mirsaSecondary)
            } else {
                if !vm.pairingStatus.isEmpty && vm.pairingStatus != "idle" {
                    Text(vm.pairingStatus).font(.subheadline).multilineTextAlignment(.center)
                        .foregroundStyle(vm.pairingStatus.contains("✅") ? .green : .white.opacity(0.7))
                }
                Button { vm.startPairing() } label: {
                    Label(vm.hasPairingFile ? L.t("pair.repair") : L.t("pair.start"),
                          systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.mirsaPrimary)
                .controlSize(.large)
                .disabled(!networkOK)
            }
        }
        .padding(MirsaSpacing.card).appsGlass(cornerRadius: MirsaRadius.l)
    }

    private var importCard: some View {
        Button { showFilePicker = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: MirsaIconSize.m, weight: .bold))
                    .frame(width: MirsaIconSize.button, height: MirsaIconSize.button)
                    .background(MirsaPalette.cardRaised, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("pair.import")).font(MirsaFont.cardTitle)
                    Text(L.t("pair.importSub")).font(MirsaFont.caption).foregroundStyle(MirsaPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: MirsaIconSize.s, weight: .bold)).foregroundStyle(MirsaPalette.textTertiary)
            }
            .foregroundStyle(.white).padding(MirsaSpacing.card)
            .appsGlass(cornerRadius: MirsaRadius.l)
        }
        .buttonStyle(.mirsaPress)
    }
}
