import SwiftUI
import AVKit

enum WallpaperSourceText {
    enum Key { case title, add, empty, failed, install, preview, remove, url, working }
    static func text(_ key: Key, language: AppLanguage = AppLanguageStore.snapshot) -> String {
        let values: [Key: [String]] = [
            .title: ["Wallpaper sources", "مصادر الخلفيات", "Hintergrundquellen", "Çavkaniyên wêneyan", "سەرچاوەی وێنەکان"],
            .add: ["Add source", "أضف مصدر", "Quelle hinzufügen", "Çavkaniyê zêde bike", "سەرچاوە زیاد بکە"],
            .empty: ["No wallpapers in this source yet.", "لسا ما في خلفيات بهالمصدر.", "Noch keine Hintergründe in dieser Quelle.", "Hê di vê çavkaniyê de wêne tune.", "هێشتا هیچ وێنەیەک لەم سەرچاوەیە نییە."],
            .failed: ["Could not load this wallpaper source. Check its HTTPS URL and try again.", "ما قدرنا نحمّل مصدر الخلفيات. تأكد من رابط HTTPS وجرب كمان مرة.", "Die Hintergrundquelle konnte nicht geladen werden. HTTPS-Adresse prüfen und erneut versuchen.", "Çavkanî nehat barkirin. Girêdana HTTPS kontrol bike û dîsa biceribîne.", "سەرچاوەکە بارنەکرا. بەستەری HTTPS بپشکنە و دووبارە هەوڵ بدە."],
            .install: ["Install", "ركّب", "Installieren", "Saz bike", "دایبنێ"],
            .preview: ["Video preview", "معاينة الفيديو", "Videovorschau", "Pêşdîtina vîdyoyê", "پێشبینینی ڤیدیۆ"],
            .remove: ["Remove source", "احذف المصدر", "Quelle entfernen", "Çavkaniyê jê bibe", "سەرچاوە بسڕەوە"],
            .url: ["HTTPS source URL", "رابط مصدر HTTPS", "HTTPS-Quellenadresse", "Girêdana çavkaniya HTTPS", "بەستەری سەرچاوەی HTTPS"],
            .working: ["Downloading…", "عم ننزّل…", "Wird geladen…", "Tê daxistin…", "دادەبەزێت…"]
        ]
        let index: Int
        switch language {
        case .english: index = 0
        case .arabic: index = 1
        case .german: index = 2
        case .kurmanji: index = 3
        case .sorani: index = 4
        }
        return values[key]![index]
    }
}

struct WallpaperSourcesView: View {
    @StateObject private var store = WallpaperSourceStore()
    @State private var sourceURL = ""
    @State private var downloading: String?
    @State private var video: WallpaperSourceEntry?
    let busy: Bool
    let install: (URL) async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    TextField(WallpaperSourceText.text(.url), text: $sourceURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("wallpaper-source-url")
                    Button {
                        Task { await store.add(sourceURL); if store.error == nil { sourceURL = "" } }
                    } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .accessibilityLabel(WallpaperSourceText.text(.add))
                        .accessibilityIdentifier("wallpaper-source-add")
                        .disabled(store.loading || sourceURL.isEmpty)
                }
                .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

                if !store.urls.contains(CAPlaygroundSource.manifest) {
                    Button {
                        Task { await store.add(CAPlaygroundSource.manifest.absoluteString) }
                    } label: {
                        Label("CAPlayground · GitHub · GPL-3.0", systemImage: "plus.circle")
                    }.disabled(store.loading)
                    .accessibilityIdentifier("wallpaper-source-add-caplayground")
                }
                if store.loading { ProgressView() }
                if let error = store.error { Text(error).foregroundStyle(.red).font(.callout) }
                ForEach(store.urls, id: \.self) { url in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.feeds[url]?.name ?? url.host ?? "").font(.title3.bold())
                                if let author = store.feeds[url]?.author { Text(author).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if url != WallpaperSourceStore.official {
                                Button(role: .destructive) { store.remove(url) } label: { Image(systemName: "minus.circle") }
                                    .accessibilityLabel(WallpaperSourceText.text(.remove))
                            }
                        }
                        if url == CAPlaygroundSource.manifest {
                            Link("CAPlayground · GitHub · GPL-3.0", destination: CAPlaygroundSource.repository)
                        }
                        if let feed = store.feeds[url] {
                            if feed.wallpapers.isEmpty { Text(WallpaperSourceText.text(.empty)).foregroundStyle(.secondary).font(.callout) }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 14)], spacing: 18) {
                                ForEach(feed.wallpapers) { entry in
                                    card(entry, source: url)
                                }
                            }
                        }
                    }
                }
            }.padding()
        }
        .navigationTitle(WallpaperSourceText.text(.title))
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: $video) { entry in
            if let url = entry.previewVideo { WallpaperSourceVideoView(url: url) }
        }
    }

    @ViewBuilder
    private func previewImage(_ entry: WallpaperSourceEntry) -> some View {
        #if DEBUG
        if WallpaperSourceFixture.active, let image = WallpaperSourceFixture.image(for: entry) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            remotePreview(entry)
        }
        #else
        remotePreview(entry)
        #endif
    }

    private func remotePreview(_ entry: WallpaperSourceEntry) -> some View {
        AsyncImage(url: entry.previewImage) { image in
            image.resizable().scaledToFill()
        } placeholder: { Rectangle().fill(.quaternary).overlay { Image(systemName: "photo") } }
    }

    private func card(_ entry: WallpaperSourceEntry, source: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            previewImage(entry)
                .frame(height: 230).frame(maxWidth: .infinity)
                .clipped().clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .bottomTrailing) {
                    if entry.previewVideo != nil {
                        Button { video = entry } label: { Image(systemName: "play.circle.fill").font(.title).padding(8) }
                            .accessibilityLabel(WallpaperSourceText.text(.preview))
                    }
                }
            Text(entry.name).font(.headline).lineLimit(2)
            Text(entry.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(entry.category + " · " + (entry.sizeIsEstimated == true ? "≤ " : "") + ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Button {
                #if DEBUG
                guard !WallpaperSourceFixture.active else { return }
                #endif
                downloading = source.absoluteString + entry.id
                Task {
                    defer { downloading = nil }
                    do {
                        let archive = try await WallpaperSourceNetwork.archive(entry)
                        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
                        await install(archive)
                    } catch { store.error = WallpaperSourceText.text(.failed) }
                }
            } label: {
                HStack {
                    if downloading == source.absoluteString + entry.id { ProgressView().controlSize(.small) }
                    Text(WallpaperSourceText.text(downloading == source.absoluteString + entry.id ? .working : .install))
                }.frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || downloading != nil)
            .accessibilityIdentifier("wallpaper-source-install")
        }
    }
}

/// Video fetch/playback starts only after a deliberate tap, never for every grid cell.
private struct WallpaperSourceVideoView: View {
    let url: URL
    @State private var player: AVPlayer?
    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player = AVPlayer(url: url); player?.play() }
            .onDisappear { player?.pause(); player = nil }
    }
}
