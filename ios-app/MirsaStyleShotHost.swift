import SwiftUI
import UIKit

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

    #if DEBUG
    /// Generated locally, no network and no arbitrary URL.
    private static let fixtureImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400)).image { c in
        UIColor.systemIndigo.setFill(); c.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        UIColor.systemOrange.setFill(); c.cgContext.fillEllipse(in: CGRect(x: 200, y: 100, width: 200, height: 200))
    }
    #endif

    var body: some View {
        switch page {
        case "apps": tab(.apps)
        case "sources": tab(.sources)
        #if DEBUG
        case "liquid-review": MirsaLiquidReviewHost()
        case "glass-dock-review": GlassDockReviewHost()
        case "sources-delete-validation": SourcesDeleteValidationHost()
        case "dock-clearance-29": SourcesDock29ValidationHost()
        case "certificate-parity-29": PersonalProjectDetailView(app: Self.fixturePersonalApp(1))
        case "sources-ts-list": SourcesToolsStoreListHost()
        case "sources-ts-small": SourcesToolsStoreDetailHost(large: false)
        case "sources-ts-large": SourcesToolsStoreDetailHost(large: true)
        case "source-news-fixture": SourceNewsValidationHost()
        case "source-news-live":
            NavigationStack { SourceDetailView(source: RepoSource(url: MirsaSourceFeed.primary, name: "Mirsa", uid: RepoSource.canonicalID)) }
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
        case "mirsa-ai-embedded": tab(.mirsaAI)
        #if DEBUG
        case "apps-design":
            // Design review only: the real Apps tab with an in-memory signed-in account
            // (9 of 10 App IDs left) and five fixture apps (one real, so 1 of 3 slots left).
            ContentView().onAppear {
                guard MirsaUITestHarness.active else { return }
                let store = AppsStore.shared
                store.account = AccountState(email: "review@mirsa.app",
                                             certExpires: Date().addingTimeInterval(5 * 86_400),
                                             appIDsAvailable: 9, appIDsMax: 10)
                store.apps = Array(Self.fixtureApps.prefix(5))
                vm.selectedTab = .apps
            }
        #endif
        #if DEBUG
        case "chat-image-fixture":
            ZStack { MirsaChatTheme.bg.ignoresSafeArea(); MirsaTappableImage(image: Self.fixtureImage, maxWidth: 220, maxHeight: 200, cornerRadius: 14) }
        #endif
        case "mirsa-ai-chat": NavigationStack { ForgeChatThreadView(threadID: ForgeChatStore.fixtureThreadID) }.preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-MirsaChatLightFixture") ? .light : .dark)
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

#if DEBUG
/// Only the input catalogue is a fixture. Navigation, all six tabs, scroll
/// containers and the floating dock are the actual ContentView implementation.
private struct SourcesDock29ValidationHost: View {
    @EnvironmentObject private var vm: AppViewModel
    @StateObject private var store: SourcesStore
    init() {
        let domain = "mirsa.sources.dock29.validation"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        let store = SourcesStore(defaults: defaults)
        let sources = (1...18).map { i in
            RepoSource(url: "https://dock29.example.invalid/source-\(i).json",
                       name: i == 18 ? "Dock Source Last" : "Dock Source \(i)")
        }
        store.sources = sources
        for source in sources { store.apps[source.url] = [] }
        store.apps[sources[17].url] = (1...35).map { i in
            RepoApp(name: i == 35 ? "Alaa Player" : "Dock App \(i)",
                    bundleID: "invalid.example.dock29.app\(i)", developer: "Mirsa UI validation",
                    subtitle: "Offline fixture", description: "", version: "1.0", iconURL: nil,
                    downloadURL: URL(string: "https://dock29.example.invalid/app\(i).ipa")!, size: nil, date: nil)
        }
        _store = StateObject(wrappedValue: store)
    }
    var body: some View {
        ContentView(sourcesStore: store).onAppear { vm.selectedTab = .sources }
    }
}

/// Isolated approved branding snapshot, used only by the explicit screenshot harness.
private struct SourceNewsValidationHost: View {
    @StateObject private var store: SourcesStore
    private let source: RepoSource
    init() {
        let defaults = UserDefaults(suiteName: "mirsa.source-news.screenshot")!
        defaults.removePersistentDomain(forName: "mirsa.source-news.screenshot")
        let bytes = Data(#"{"iconURL":"https://raw.githubusercontent.com/Alaaaya/Mirsa/main/assets/branding/mirsa-icon.png","headerURL":"https://raw.githubusercontent.com/Alaaaya/Mirsa/main/assets/branding/mirsa-banner.jpg","tintColor":"7C83FF","subtitle":"تطبيقاتك وتويكاتك وخلفياتك بمكان واحد","description":"مرسى لتثبيت تطبيقات iPhone وإدارة السورسات والتويكات وخلفيات Tendies. من تطوير علاء. الأخبار والتواصل على X @rasmtk30.","website":"https://x.com/rasmtk30","name":"Mirsa","news":[{"title":"أهلاً فيكم بمرسى 💜","caption":"أنا علاء، عملت مرسى حتى تجمعوا تطبيقاتكم وتويكاتكم وخلفيات Tendies بمكان واحد. هون بنزّل الجديد، وإذا عندكم اقتراح أو مشكلة احكولي على X https://x.com/rasmtk30","imageURL":"https://raw.githubusercontent.com/Alaaaya/Mirsa/main/assets/branding/mirsa-banner.jpg","tintColor":"7C83FF","date":"2026-11-18T00:11:35Z","identifier":"mirsa-welcome-2026","appID":"com.alaa.mirsa","url":"https://x.com/rasmtk30","notify":false}],"apps":[{"name":"Mirsa","bundleIdentifier":"com.alaa.mirsa","version":"2.5","downloadURL":"https://example.org/Mirsa.ipa","iconURL":"https://raw.githubusercontent.com/Alaaaya/Mirsa/main/assets/branding/mirsa-icon.png"}]}"#.utf8)
        let store = SourcesStore(defaults: defaults, load: { request in
            (bytes, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let source = RepoSource(url: "https://example.org/source.json", name: "Mirsa")
        store.sources = [source]
        self.source = source
        _store = StateObject(wrappedValue: store)
    }
    var body: some View { NavigationStack { SourceDetailView(source: source, store: store) } }
}
#endif

#if DEBUG
/// Isolated real dock for system light/dark material review, not an app theme change.
private struct GlassDockReviewHost: View {
    @State private var selection: AppTab = .apps
    private var light: Bool { ProcessInfo.processInfo.arguments.contains("-GlassDockLight") }
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: light
                ? [Color(red: 0.93, green: 0.89, blue: 0.84), Color(red: 0.65, green: 0.53, blue: 0.44)]
                : [Color(red: 0.16, green: 0.12, blue: 0.10), Color(red: 0.29, green: 0.20, blue: 0.17)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            LiquidTabBar(selection: $selection, items: LiquidTabItem.mainTabs)
        }
        .preferredColorScheme(light ? .light : .dark)
    }
}
#endif
