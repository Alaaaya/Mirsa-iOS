import SwiftUI

/// Global search reads the same complete source catalogues and uses the same
/// install action as source detail. No provider lookup or IPA download on search.
@MainActor
final class DiscoveryStore: ObservableObject {
    struct Match: Identifiable {
        let sourceURL: String
        let sourceName: String
        let app: RepoApp
        var id: String { sourceURL + "|" + app.id + "|" + app.downloadURL.absoluteString }
    }
    @Published var input = ""
    @Published var searching = false
    @Published var results: [Match] = []
    @Published var searched = false
    @Published var failures: [String] = []
    private let sources: SourcesStore

    init(sources: SourcesStore = .shared) { self.sources = sources }

    func search() async {
        guard !searching else { return }
        let term = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { results = []; searched = false; return }
        searching = true
        defer { searching = false }
        // A nonempty cache can still be partial. Join every missing source load,
        // not just refresh when the whole dictionary happens to be empty.
        await sources.loadMissing()
        var seen = Set<String>()
        results = sources.visibleSources.flatMap { source in
            (sources.apps[source.url] ?? []).compactMap { app -> Match? in
                guard app.name.localizedCaseInsensitiveContains(term) else { return nil }
                let match = Match(sourceURL: source.url, sourceName: source.name, app: app)
                return seen.insert(match.id).inserted ? match : nil
            }
        }
        failures = sources.visibleSources.compactMap { source in
            sources.loadErrors[source.url].map { source.name + " · " + $0 }
        }
        searched = true
    }
}

struct DiscoveryView: View {
    @StateObject private var store: DiscoveryStore
    @ObservedObject private var apps = AppsStore.shared
    @Environment(\.dismiss) private var dismissSheet

    @MainActor
    init(store: DiscoveryStore? = nil) {
        _store = StateObject(wrappedValue: store ?? DiscoveryStore())
    }

    var body: some View {
        NavigationStack {
            List {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(tr("App name", "اسم التطبيق"), text: $store.input)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await store.search() } }
                    Button(tr("Search", "بحث")) { Task { await store.search() } }
                        .disabled(store.searching || store.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .accessibilityIdentifier("source-global-search")
                .listRowBackground(Color.clear)
                Text(tr("Search all your added sources by app name.", "دوّر باسم التطبيق بكل سورساتك المضافة."))
                    .font(.footnote).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                if store.searching {
                    ProgressView().listRowBackground(Color.clear)
                } else if store.searched && store.results.isEmpty {
                    Text(tr("No matching apps.", "ما لقيت تطبيقات بهالاسم."))
                        .foregroundStyle(.secondary).listRowBackground(Color.clear)
                }
                ForEach(store.results) { match in
                    VStack(alignment: .leading, spacing: 6) {
                        RepoAppRow(app: match.app, installed: apps.apps.first { $0.id == match.app.bundleID })
                        Text(match.sourceName).font(.caption).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(store.failures, id: \.self) { message in
                    Text(message).font(.caption).foregroundStyle(.orange)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .navigationTitle(tr("Find an app", "دوّر على تطبيق"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(tr("Close", "إغلاق")) { dismissSheet() }
                }
            }
            .mirsaScreen()
        }
    }
}
