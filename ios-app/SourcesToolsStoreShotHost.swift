#if DEBUG
import SwiftUI

/// Deterministic, local-only fixtures for the Sources redesign screenshots. Never compiled into release builds.
enum SourcesToolsStoreShotHost {
    static func fixtureApps(_ n: Int, prefix: String) -> [RepoApp] {
        guard n > 0 else { return [] }
        return (1...n).map { (i: Int) -> RepoApp in
            let name: String = "\(prefix) \(i)"
            let bundleID: String = "com.example.\(prefix.lowercased())\(i)"
            let subtitle: String = "Fixture subtitle \(i)"
            let description: String = "Deterministic fixture app \(i) used only for layout screenshots."
            let version: String = "1.\(i)"
            let downloadURL: URL = URL(string: "https://example.org/\(prefix)\(i).ipa")!
            let size: Int64 = 10_000_000 + Int64(i) * 1_000_000
            let date: String = "2026-11-1\(i % 10)"
            let category: String = i % 2 == 0 ? "Utilities" : "Media"
            return RepoApp(name: name, bundleID: bundleID, developer: "Fixture Dev",
                           subtitle: subtitle, description: description, version: version,
                           iconURL: nil, downloadURL: downloadURL, size: size, date: date,
                           category: category)
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
        // Explicit opt-in, DEBUG-only feed text fixture. Default fixtures and tests stay unchanged.
        if ProcessInfo.processInfo.arguments.contains("-MirsaArabicFeedFixture22") {
            let arabic = RepoSource(url: small.url, name: "مكتبة مرسى العربية")
            var app = RepoApp(name: "يوتيوب بلس", bundleID: "com.example.rtl22",
                              developer: "مطور عربي", subtitle: "فيديو وموسيقى بلا حدود",
                              description: "هذا وصف عربي لاختبار ترتيب الكلمات وعلامات الترقيم.\nيدعم الإصدار 2.0 عرض النص العربي مع English داخل الفقرة.",
                              version: "2.0", iconURL: nil, downloadURL: URL(string: "https://example.org/rtl22.ipa")!,
                              size: 12_000_000, date: "2026-11-22", category: "وسائط")
            app.versionNotes = "تحسين عرض النص العربي مع الإصدار 2.0."
            store.sources = [arabic]
            store.apps[arabic.url] = [app]
            return (store, [arabic])
        }
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
