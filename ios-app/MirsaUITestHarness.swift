import SwiftUI

/// UI-test only. Active solely when launched with -MirsaUITestHarness (never in normal launches).
/// Hosts the REAL MirsaHomeScreen and PersonalAppsHome with seeded fixture apps so XCUITest can drag.
enum MirsaUITestHarness {
    static var active: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-MirsaUITestHarness")
        #else
        return false
        #endif
    }
}

struct MirsaUITestHarnessView: View {
    @State private var which = 0
    @State private var tick = 0
    @State private var snapshot = "none"
    private let mainApps: [ManagedApp] = (1...6).map { i in
        ManagedApp(id: "com.example.uit\(i)", name: "UIT Main \(i)", version: "1.0", sizeBytes: 1, location: .container,
                   installedBundleID: nil, expires: nil, signedSerial: nil, wantsNotifications: false,
                   hasExtensions: false, addedAt: Date(timeIntervalSince1970: Double(i)))
    }
    private let personalApps: [PersonalLibraryApp] = (1...6).map { i in
        PersonalLibraryApp(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(i)")!, name: "UIT Personal \(i)",
                           bundleID: "com.example.p\(i)", version: "1.0", signed: false, date: Date(timeIntervalSince1970: Double(i)))
    }

    private func layoutText(_ ns: String) -> String {
        guard let d = UserDefaults.standard.data(forKey: "mirsa.home.layout.v1." + ns),
              let l = try? JSONDecoder().decode(MirsaHomeLayout.self, from: d) else { return "none" }
        return l.items.map { item -> String in
            switch item {
            case .app(let id): return id
            case .folder(let f): return "[" + f.appIDs.joined(separator: "+") + "]"
            }
        }.joined(separator: ",")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Main") { which = 0; snapshot = layoutText("main") }.accessibilityIdentifier("uit.main")
                Button("Personal") { which = 1; snapshot = layoutText("personal") }.accessibilityIdentifier("uit.personal")
            }
            .buttonStyle(.bordered)
            Text(snapshot).font(.system(size: 9))
                .accessibilityIdentifier("uit.layout")
            Button("refresh") { snapshot = layoutText(which == 0 ? "main" : "personal"); tick += 1 }.accessibilityIdentifier("uit.refresh")
            ZStack {
                if which == 0 {
                    MirsaHomeScreen(apps: mainApps, allAppIDs: mainApps.map(\.id), onLaunch: { _ in }, onSettings: {},
                                    onImport: {}, onImportLink: {}, onDownloads: {}, menu: { _ in EmptyView() })
                } else {
                    PersonalAppsHome(apps: personalApps, allAppIDs: personalApps.map(\.id), library: PersonalAppsLibrary.shared,
                                     onOpen: { _ in }, menu: { _ in EmptyView() }, iconOverlay: { _ in EmptyView() })
                }
            }
            .id(tick * 2 + which)
        }
        .background(Color.black).preferredColorScheme(.dark)
    }
}
