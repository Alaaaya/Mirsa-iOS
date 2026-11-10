import SwiftUI
import AirliftFFI

/// Entry point called from main.m once the Container loader has had its turn.
@_cdecl("mirsa_swift_main")
public func mirsaSwiftMain() {
    MirsaContainerCleanup.captureProcessStart()
    MirsaApp.main()
}

struct MirsaApp: App {
    @UIApplicationDelegateAdaptor(MirsaDownloadAppDelegate.self) private var downloadDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vm = AppViewModel()
    @StateObject private var language = AppLanguageStore.shared

    init() {
        // Route Rust tracing/idevice logs into the app's vm log array.
        al_log_init({ _, msg in
            guard let msg = msg else { return }
            let line = String(cString: msg)
            DispatchQueue.main.async {
                AppViewModel.sharedLogSink?(line)
            }
        }, nil)

        // Point the sink at the vm once it's created (set in AppViewModel.init).
        // Ensure ALGetGrappaToken symbol is retained and linked into the binary
        _ = ALGetGrappaToken(0, 0, 0, nil, 0, nil, nil, 0)

        // Apps tab: background refresh of sideloaded apps must be registered
        // before launch finishes.
        AppsStore.registerBackgroundTask()
        AppsStore.importHandoffIfNeeded()
        MirsaChrome.apply()
        // Cold/background launch may still be handing a URLSession file to its delegate.
        // Automatic sweeping starts only after the scene becomes active.
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let page = MirsaStyleShots.page { MirsaStyleShotHost(page: page) } else if MirsaUITestHarness.active { MirsaUITestHarnessView() } else if AppsStore.isSetupMode { SetupView() } else { ContentView() }
            }
            .background { OpenInProjectPresenter().frame(width: 0, height: 0) }
            .onOpenURL { url in
                if AppsStore.isSetupMode, OpenInTweak.accepts(url) { OpenInProjectCoordinator.shared.receive([url]) }
            }
            .environmentObject(vm)
            .environment(\.layoutDirection, .leftToRight)
            .environment(\.locale, language.current.locale)
            .id(language.current)
            .mirsaKeyboardDismissal()
            .mirsaLeftToRightChrome()
            .task { if !MirsaUITestHarness.active { await ForgeStore.shared.syncFixInbox() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { OpenInProjectCoordinator.shared.presentNext() }
                if phase == .active, !MirsaUITestHarness.active { DispatchQueue.global(qos: .utility).async { MirsaManagedTmp.sweep() } }
                if phase == .active, !MirsaUITestHarness.active { Task { await ForgeStore.shared.syncFixInbox() } }
            }
        }
    }
}

@_silgen_name("ALGetGrappaToken")
func ALGetGrappaToken(
    _ inVersion: UInt32,
    _ inDeviceType: UInt32,
    _ inProtocolVersion: UInt32,
    _ outBuf: UnsafeMutablePointer<UInt8>?,
    _ maxLen: Int,
    _ outLen: UnsafeMutablePointer<Int>?,
    _ errBuf: UnsafeMutablePointer<CChar>?,
    _ errLen: Int
) -> Int32

