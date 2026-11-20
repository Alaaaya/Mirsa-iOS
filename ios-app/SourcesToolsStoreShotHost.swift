#if DEBUG
import SwiftUI

/// Deterministic, local-only fixtures for the Sources redesign screenshots. Never compiled into release builds.
enum SourcesToolsStoreShotHost {
    static func fixtureApps(_ n: Int, prefix: String) -> [RepoApp] {
        (1...n).map { i in
            RepoApp(name: "\(prefix) \(i)", bundleID: "com.example.\(prefix.lowercased())\(i)", developer: "Fixture Dev",
                    subtitle: "Fixture subtitle \(i)", description: "Deterministic fixture app \(i) used only for layout screenshots.",
                    version: "1.\(i)", iconURL: nil, downloadURL: URL(string: "https://example.org/\(prefix)\(i).ipa")!,
                    size: Int64(10_000_000 + i * 1_000_000), date: "2026-11-1\(i % 10)",
                    category: i % 2 == 0 ? "Utilities" : "Media")
        }
    }

    @MainActor static func makeStore() -> (SourcesStore, [RepoSource]) {
        let domain = "mirsa.sources.toolsstore.shots"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        let store = SourcesStore(defaults: defaults, load: { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        })
        let small = RepoSource(url: "https://example.org/small.json", name: "Small Source")
        let large = RepoSource(url: "https://example.org/large.json", name: "Large Source")
        store.sources = [small, large]
        store.apps[small.url] = fixtureApps(5, prefix: "Small")
        store.apps[large.url] = fixtureApps(45, prefix: "Large")
        return (store, [small, large])
    }
}

struct SourcesToolsStoreListHost: View {
    @StateObject private var holder = Holder()
    @MainActor final class Holder: ObservableObject { let store = SourcesToolsStoreShotHost.makeStore().0 }
    var body: some View { SourcesTab(store: holder.store) }
}

struct SourcesToolsStoreDetailHost: View {
    let large: Bool
    @StateObject private var holder = Holder()
    @MainActor final class Holder: ObservableObject { let made = SourcesToolsStoreShotHost.makeStore() }
    var body: some View {
        NavigationStack {
            SourceDetailView(source: holder.made.1[large ? 1 : 0], store: holder.made.0)
        }
    }
}
#endif
