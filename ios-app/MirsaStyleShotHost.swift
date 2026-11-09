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

    private static let appNames = ["Telegram", "Spotify", "YouTube", "Notes Pro", "Camera+", "Weather", "Reader", "Music Studio"]
    private static let personalNames = ["Instagram", "WhatsApp", "Snapchat", "Twitch", "Discord", "Reddit"]

    private static func fixtureApp(_ i: Int) -> ManagedApp {
        let real: Bool = i % 3 == 0
        let size: Int64 = Int64(i) * 21_000_000
        let expiry: Date? = real ? Date().addingTimeInterval(5 * 86_400) : nil
        let location: AppLocation = real ? .real : .container
        return ManagedApp(id: "com.example.style\(i)", name: appNames[i - 1], version: "2.\(i).0", sizeBytes: size,
                          location: location, installedBundleID: nil, expires: expiry, signedSerial: nil,
                          wantsNotifications: false, hasExtensions: false, addedAt: Date(timeIntervalSince1970: Double(i)))
    }
    private static func fixturePersonalApp(_ i: Int) -> PersonalLibraryApp {
        let id: UUID = UUID(uuidString: "00000000-0000-0000-0000-00000000010\(i)") ?? UUID()
        let signed: Bool = i % 2 == 0
        return PersonalLibraryApp(id: id, name: personalNames[i - 1], bundleID: "com.example.personal\(i)",
                                  version: "1.\(i)", signed: signed, date: Date(timeIntervalSince1970: Double(i)))
    }
    private static let fixtureApps: [ManagedApp] = (1...8).map(fixtureApp)
    private static let fixturePersonal: [PersonalLibraryApp] = (1...6).map(fixturePersonalApp)

    var body: some View {
        switch page {
        case "apps": tab(.apps)
        case "sources": tab(.sources)
        #if DEBUG
        case "sources-delete-validation": SourcesDeleteValidationHost()
        #endif
        case "tools": tab(.pairing)
        case "more": tab(.personalHub)
        case "encrypted": tab(.encrypted)
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
        case "login": LoginSheet(store: store).presentationDetents([.large]).mirsaSheetBackground()
        case "url-import": PersonalURLImportSheet(disabled: false) { _ in }
        case "discovery": DiscoveryView()
        case "certificates": PersonalCertificateManagerView()
        case "personal-certificate": NavigationStack { ScrollView { PersonalCertificateView().padding(20) }.background(AuroraBackground()) }.preferredColorScheme(.dark)
        case "signing-queue": SigningQueueView()
        case "telemetry": NavigationStack { ScrollView { MirsaTelemetryView(bundleID: "com.alaa.mirsa").padding() }.background(AuroraBackground()) }.preferredColorScheme(.dark)
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
                .presentationDetents([.large]).mirsaSheetBackground()
        case "hidden": HiddenAppsView(store: HiddenAppsStore.shared) { HiddenAppsGrid(apps: Self.fixtureApps, pendingHide: $pendingHide) }
        case "prompt":
            PromptSheet(prompt: SideloadPrompt(kind: .twoFactor, sms: false, lastError: nil, phones: [], certs: [])) {}
                .presentationDetents([.medium, .large]).mirsaSheetBackground()
        case "app-info": AppInfoSheet(app: app, store: store).presentationDetents([.medium]).mirsaSheetBackground()
        case "backups": BackupsSheet(app: app)
        case "tweak-library": IPATweakLibraryView()
        case "no-profile-guide": NoProfileShortcutGuide(app: app)
        default: Text("Unknown page \(page)")
        }
    }
}

#if DEBUG
/// Isolated UI-test fixture. Uses the real source list and real swipe/delete dialog.
private struct SourcesDeleteValidationHost: View {
    @StateObject private var store: SourcesStore
    init() {
        let defaults = UserDefaults(suiteName: "mirsa.sources.delete.validation")!
        defaults.removePersistentDomain(forName: "mirsa.sources.delete.validation")
        let store = SourcesStore(defaults: defaults)
        store.sources = [RepoSource(url: MirsaSourceFeed.primary, name: "Mirsa", uid: RepoSource.canonicalID),
                         RepoSource(url: "https://dup.example/source.json", name: "Delete Fixture")]
        // Keep the screenshot offline without changing the production refresh logic.
        store.apps[MirsaSourceFeed.primary] = []
        _store = StateObject(wrappedValue: store)
    }
    var body: some View { SourcesTab(store: store) }
}
#endif
