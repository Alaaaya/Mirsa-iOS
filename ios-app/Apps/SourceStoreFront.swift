import SwiftUI

enum SourceStoreLayout {
    static let key = "mirsa.sources.layout"
    static let store = "store"
    static let classic = "classic"
}

/// Explicit five-language copy, including German rather than the bilingual fallback.
enum SourceStoreText {
    static func pick(_ en: String, _ ar: String, _ de: String, _ ckb: String, _ kmr: String) -> String {
        switch L.lang {
        case .english: return en
        case .arabic: return ar
        case .german: return de
        case .sorani: return ckb
        case .kurmanji: return kmr
        }
    }
    static var layout: String { pick("Sources layout", "شكل قسم السورسات", "Darstellung der Quellen", "شێوازی بەشی سەرچاوەکان", "Şêwaza beşa çavkaniyan") }
    static var store: String { pick("Store", "متجر", "Store", "فرۆشگا", "Dikan") }
    static var classic: String { pick("Classic", "كلاسيكي", "Klassisch", "کلاسیک", "Klasîk") }
    static var all: String { pick("All sources", "كل السورسات", "Alle Quellen", "هەموو سەرچاوەکان", "Hemû çavkanî") }
    static var manage: String { pick("Manage sources", "إدارة السورسات", "Quellen verwalten", "بەڕێوەبردنی سەرچاوەکان", "Rêvebirina çavkaniyan") }
    static var featured: String { pick("Featured apps", "تطبيقات مميزة", "Empfohlene Apps", "ئەپە تایبەتەکان", "Sepanên bijarte") }
    static var recent: String { pick("Recently updated", "آخر التحديثات", "Zuletzt aktualisiert", "تازە نوێکراوەکان", "Nûhatî nûkirin") }
    static var discover: String { pick("Explore the catalogue", "اكتشف التطبيقات", "Katalog entdecken", "ئەپەکان بدۆزەرەوە", "Katalogê keşf bike") }
    static var browse: String { pick("Browse apps", "تصفّح التطبيقات", "Apps entdecken", "گەڕان بەناو ئەپەکان", "Li sepanan bigere") }
    static var empty: String { pick("Your source apps will appear here.", "تطبيقات سورساتك بتظهر هون.", "Hier erscheinen die Apps deiner Quellen.", "ئەپەکانی سەرچاوەکانت لێرە دەردەکەون.", "Sepanên çavkaniyên te dê li vir xuya bibin.") }
    static var loading: String { pick("Loading catalogues…", "عم تتحمّل التطبيقات…", "Kataloge werden geladen…", "لیستەکان بار دەکرێن…", "Katalog tên barkirin…") }
    static var retry: String { pick("Retry failed sources", "إعادة تحميل السورسات المتعذّرة", "Fehlgeschlagene Quellen erneut laden", "دووبارە بارکردنی سەرچاوەکان", "Çavkaniyên biser neketin dîsa bar bike") }
    static var more: String { pick("See all", "عرض الكل", "Alle anzeigen", "هەمووی ببینە", "Hemûyan bibîne") }
}

struct SourceStoreLayoutPicker: View {
    @AppStorage(SourceStoreLayout.key) private var layout = SourceStoreLayout.store
    var body: some View {
        Picker(SourceStoreText.layout, selection: $layout) {
            Text(SourceStoreText.store).tag(SourceStoreLayout.store)
            Text(SourceStoreText.classic).tag(SourceStoreLayout.classic)
        }
        .accessibilityIdentifier("sources-layout-picker")
    }
}

/// Only actual parsed catalogues participate. No inferred popularity or invented metrics.
enum SourceStoreCatalogue {
    struct Entry: Identifiable {
        let source: RepoSource
        let app: RepoApp
        var id: String { source.id + "|" + app.id }
    }
    static func entries(sources: [RepoSource], apps: [String: [RepoApp]]) -> [Entry] {
        var seen = Set<String>()
        return sources.flatMap { source in
            (apps[source.url] ?? []).compactMap { app in
                // One tile per bundle/version; source ordering breaks duplicate ties.
                seen.insert(app.id).inserted ? Entry(source: source, app: app) : nil
            }
        }
    }
    static func recent(_ entries: [Entry]) -> [Entry] {
        entries.sorted {
            let lhs = $0.app.date.flatMap(SourcesStore.date) ?? .distantPast
            let rhs = $1.app.date.flatMap(SourcesStore.date) ?? .distantPast
            if lhs != rhs { return lhs > rhs }
            return $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending
        }
    }
}

struct SourceStoreFront: View {
    @ObservedObject var store: SourcesStore
    var onSelectIPA: ((URL) async throws -> Void)? = nil
    @ObservedObject private var installed = AppsStore.shared
    @State private var sourceID: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var sources: [RepoSource] {
        store.visibleSources.filter { sourceID == nil || $0.id == sourceID }
    }
    private var entries: [SourceStoreCatalogue.Entry] {
        SourceStoreCatalogue.entries(sources: sources, apps: store.apps)
    }
    private var recent: [SourceStoreCatalogue.Entry] { SourceStoreCatalogue.recent(entries) }
    private var featured: [SourceStoreCatalogue.Entry] {
        let selected = entries.filter { entry in
            guard let meta = store.presentation[entry.source.url] else { return false }
            return meta.featuredIDs.contains(entry.app.bundleID) || meta.news.contains { $0.appID == entry.app.bundleID }
        }
        return Array((selected.isEmpty ? recent : selected).prefix(6))
    }
    private var categories: [String] {
        Array(Set(entries.compactMap { entry -> String? in
            let value = entry.app.category?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        })).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            sourceChips
            if !featured.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(SourceStoreText.featured).font(.title2.bold()).padding(.horizontal, MirsaSpacing.page)
                    TabView {
                        ForEach(featured) { entry in
                            NavigationLink {
                                SourceDetailView(source: entry.source, store: store, onSelectIPA: onSelectIPA)
                            } label: { hero(entry) }
                            .buttonStyle(.plain)
                            .padding(.horizontal, MirsaSpacing.page)
                            .padding(.bottom, 26)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: featured.count > 1 ? .always : .never))
                    .frame(height: typeSize.isAccessibilitySize ? 330 : 246)
                    .accessibilityIdentifier("sources-store-featured")
                }
                shelf(SourceStoreText.recent, entries: recent)
                ForEach(categories, id: \.self) { category in
                    shelf(category, entries: recent.filter { $0.app.category?.trimmingCharacters(in: .whitespacesAndNewlines) == category })
                }
                if categories.isEmpty && recent.count > 24 {
                    shelf(SourceStoreText.browse, entries: Array(recent.dropFirst(24).prefix(24)))
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "square.stack.3d.up").font(.largeTitle).foregroundStyle(.secondary)
                    Text(SourceStoreText.empty).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(30)
            }
            if !store.loading.isEmpty {
                ProgressView(SourceStoreText.loading).frame(maxWidth: .infinity).padding()
            }
            if !store.loadErrors.isEmpty {
                Button(SourceStoreText.retry) { Task { await store.refreshAll() } }
                    .buttonStyle(.mirsaSecondary).padding(.horizontal, MirsaSpacing.page)
            }
        }
        .accessibilityIdentifier("sources-store-front")
        .onChange(of: store.visibleSources.map(\.id)) { _, ids in
            if let sourceID, !ids.contains(sourceID) { self.sourceID = nil }
        }
    }

    private var sourceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(SourceStoreText.all, id: nil, icon: nil)
                ForEach(store.visibleSources) { source in
                    chip(source.name, id: source.id, icon: source.iconURL.flatMap(URL.init(string:)))
                }
            }.padding(.horizontal, MirsaSpacing.page)
        }
        .accessibilityIdentifier("sources-store-filters")
    }

    private func chip(_ title: String, id: String?, icon: URL?) -> some View {
        Button { sourceID = id } label: {
            HStack(spacing: 6) {
                if let icon { RemoteIcon(url: icon, size: 22, corner: 6) }
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(sourceID == id ? Color.white : MirsaPalette.textSecondary)
            .background(sourceID == id ? Color.accentColor.opacity(0.36) : MirsaPalette.cardRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(sourceID == id ? Color.accentColor.opacity(0.7) : MirsaPalette.strokeStrong))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(sourceID == id ? .isSelected : [])
    }

    private func hero(_ entry: SourceStoreCatalogue.Entry) -> some View {
        let metadata = store.presentation[entry.source.url]
        let tint = Color(hex: entry.source.tint) ?? Color.accentColor
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 26).fill(LinearGradient(colors: [tint.opacity(0.6), MirsaPalette.cardRaised], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let header = metadata?.headerURL {
                AsyncImage(url: header) { image in
                    image.resizable().scaledToFill()
                } placeholder: { Color.clear }
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped().opacity(0.22)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.source.name.uppercased()).font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.white.opacity(0.75))
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(entry.app.name).font(.title.bold()).lineLimit(2)
                        Text(entry.app.subtitle.isEmpty ? entry.app.developer : entry.app.subtitle)
                            .font(.subheadline).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    RemoteIcon(url: entry.app.iconURL, size: 84, corner: 21)
                        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                }
                Label(SourceStoreText.discover, systemImage: "arrow.forward")
                    .font(.subheadline.bold()).padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
            }.padding(22)
        }
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(MirsaPalette.strokeStrong))
        .accessibilityElement(children: .combine)
    }

    private func shelf(_ title: String, entries: [SourceStoreCatalogue.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer(minLength: 4)
                NavigationLink {
                    SourceStoreAllApps(title: title, entries: entries, onSelectIPA: onSelectIPA)
                } label: { Text(SourceStoreText.more).font(.subheadline.weight(.semibold)) }
            }.padding(.horizontal, MirsaSpacing.page)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(typeSize.isAccessibilitySize ? 118 : 78)), count: 3), spacing: 18) {
                    ForEach(Array(entries.prefix(24))) { entry in
                        RepoAppRow(app: entry.app, installed: installed.apps.first { $0.id == entry.app.bundleID }, onSelectIPA: onSelectIPA)
                            .frame(width: typeSize.isAccessibilitySize ? 355 : 310)
                    }
                }.padding(.horizontal, MirsaSpacing.page)
            }
        }
    }
}

private struct SourceStoreAllApps: View {
    let title: String
    let entries: [SourceStoreCatalogue.Entry]
    var onSelectIPA: ((URL) async throws -> Void)?
    @ObservedObject private var installed = AppsStore.shared
    @State private var query = ""
    var body: some View {
        List {
            ForEach(entries.filter {
                query.isEmpty || $0.app.name.localizedCaseInsensitiveContains(query) || $0.app.bundleID.localizedCaseInsensitiveContains(query)
            }) { entry in
                RepoAppRow(app: entry.app, installed: installed.apps.first { $0.id == entry.app.bundleID }, onSelectIPA: onSelectIPA)
                    .listRowBackground(Color.clear)
            }
        }
        .searchable(text: $query)
        .navigationTitle(title)
        .mirsaScreen()
    }
}
