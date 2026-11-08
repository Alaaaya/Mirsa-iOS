import SwiftUI

/// UI-test only (DEBUG + `-MirsaUITestHarness -MirsaStylePage <id>`): hosts one real
/// screen of the app with harmless fixture data so the style screenshot test can
/// capture every page on a simulator. Never reachable in a normal launch.
enum MirsaStyleShots {
    static var page: String? {
        guard MirsaUITestHarness.active else { return nil }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-MirsaStylePage"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

struct MirsaStyleShotHost: View {
    let page: String
    @EnvironmentObject var vm: AppViewModel
    @State private var pendingHide: String?

    private static let fixtureApps: [ManagedApp] = (1...8).map { i in
        ManagedApp(id: "com.example.style\(i)", name: ["Telegram", "Spotify", "YouTube", "Notes Pro", "Camera+", "Weather", "Reader", "Music Studio"][i - 1],
                   version: "2.\(i).0", sizeBytes: Int64(i) * 21_000_000, location: i % 3 == 0 ? .real : .container,
                   installedBundleID: nil, expires: i % 3 == 0 ? Date().addingTimeInterval(5 * 86_400) : nil, signedSerial: nil,
                   wantsNotifications: false, hasExtensions: false, addedAt: Date(timeIntervalSince1970: Double(i)))
    }
    private static let fixturePersonal: [PersonalLibraryApp] = (1...6).map { i in
        PersonalLibraryApp(id: UUID(uuidString: "00000000-0000-0000-0000-00000000010\(i)")!, name: ["Instagram", "WhatsApp", "Snapchat", "Twitch", "Discord", "Reddit"][i - 1],
                           bundleID: "com.example.personal\(i)", version: "1.\(i)", signed: i % 2 == 0, date: Date(timeIntervalSince1970: Double(i)))
    }

    var body: some View {
        switch page {
        case "apps": tab(.apps)
        case "sources": tab(.sources)
        case "tools": tab(.pairing)
        case "more": tab(.personalHub)
        case "home-main":
            ZStack {
                AuroraBackground()
                MirsaHomeScreen(apps: Self.fixtureApps, allAppIDs: Self.fixtureApps.map(\.id), onLaunch: { _ in }, onSettings: {},
                                onImport: {}, onImportLink: {}, onDownloads: {}, menu: { _ in EmptyView() })
            }
            .preferredColorScheme(.dark)
        case "home-personal":
            ZStack {
                AuroraBackground()
                PersonalAppsHome(apps: Self.fixturePersonal, allAppIDs: Self.fixturePersonal.map(\.id), library: PersonalAppsLibrary.shared,
                                 onOpen: { _ in }, menu: { _ in EmptyView() }, iconOverlay: { _ in EmptyView() })
            }
            .preferredColorScheme(.dark)
        case "setup": SetupView()
        default: sheetHost
        }
    }

    private func tab(_ t: AppTab) -> some View {
        ContentView().onAppear { vm.selectedTab = t }
    }

    private var sheetHost: some View {
        ZStack { AuroraBackground() }
            .preferredColorScheme(.dark)
            .sheet(isPresented: .constant(true)) { sheet }
    }

    @ViewBuilder private var sheet: some View {
        let store = AppsStore.shared
        let app = Self.fixtureApps[0]
        switch page {
        case "settings": AppsSettingsSheet(store: store, onSignIn: {}).environmentObject(vm)
        case "login": LoginSheet(store: store).presentationDetents([.large]).presentationBackground(.ultraThinMaterial)
        case "url-import": PersonalURLImportSheet(disabled: false) { _ in }
        case "discovery": DiscoveryView()
        case "certificates": PersonalCertificateManagerView()
        case "personal-certificate": NavigationStack { ScrollView { PersonalCertificateView().padding(20) }.background(AuroraBackground()) }.preferredColorScheme(.dark)
        case "signing-queue": SigningQueueView()
        case "telemetry": NavigationStack { ScrollView { MirsaTelemetryView(bundleID: "com.alaa.mirsa").padding() }.background(Color.black) }.preferredColorScheme(.dark)
        case "credits": CreditsSheet()
        case "pairing-guide": PairingGuideSheet(onImportTapped: {})
        case "support-popup": SupportPopupSheet(dontShowOnLaunch: .constant(false))
        case "licenses": NavigationStack { LicensesView() }
        case "github-sources": NavigationStack { GitHubSourcesView() }
        case "expiry": NavigationStack { ExpiryListView(store: store) }
        case "web-upload": NavigationStack { WebUploadView() }
        case "browser": MirsaBrowserView(initialURL: nil, onClose: {})
        case "update":
            MirsaUpdateSheet(release: .init(tag_name: "1.3.200", name: "Mirsa 1.3.200",
                                            body: "• Faster signing\n• New Sources layout\n• Bug fixes", assets: []),
                             updater: MirsaUpdater.shared, onUpdate: {})
                .presentationDetents([.large]).presentationBackground(.ultraThinMaterial)
        case "hidden": HiddenAppsView(store: HiddenAppsStore.shared) { HiddenAppsGrid(apps: Self.fixtureApps, pendingHide: $pendingHide) }
        case "prompt":
            PromptSheet(prompt: SideloadPrompt(kind: .twoFactor, sms: false, lastError: nil, phones: [], certs: [])) {}
                .presentationDetents([.medium, .large]).presentationBackground(.ultraThinMaterial)
        case "app-info": AppInfoSheet(app: app, store: store).presentationDetents([.medium]).presentationBackground(.ultraThinMaterial)
        case "backups": BackupsSheet(app: app)
        case "tweak-library": IPATweakLibraryView()
        case "no-profile-guide": NoProfileShortcutGuide(app: app)
        default: Text("Unknown page \(page)")
        }
    }
}
