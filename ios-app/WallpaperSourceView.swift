import SwiftUI
import AVKit
import WebKit

enum WallpaperSourceText {
    enum Key { case title, add, empty, failed, install, preview, remove, url, working, close }
    static func text(_ key: Key, language: AppLanguage = AppLanguageStore.snapshot) -> String {
        let values: [Key: [String]] = [
            .title: ["Wallpaper sources", "مصادر الخلفيات", "Hintergrundquellen", "Çavkaniyên wêneyan", "سەرچاوەی وێنەکان"],
            .add: ["Add source", "أضف مصدر", "Quelle hinzufügen", "Çavkaniyê zêde bike", "سەرچاوە زیاد بکە"],
            .empty: ["No wallpapers in this source yet.", "لسا ما في خلفيات بهالمصدر.", "Noch keine Hintergründe in dieser Quelle.", "Hê di vê çavkaniyê de wêne tune.", "هێشتا هیچ وێنەیەک لەم سەرچاوەیە نییە."],
            .failed: ["Could not load this wallpaper source. Check its HTTPS URL and try again.", "ما قدرنا نحمّل مصدر الخلفيات. تأكد من رابط HTTPS وجرب كمان مرة.", "Die Hintergrundquelle konnte nicht geladen werden. HTTPS-Adresse prüfen und erneut versuchen.", "Çavkanî nehat barkirin. Girêdana HTTPS kontrol bike û dîsa biceribîne.", "سەرچاوەکە بارنەکرا. بەستەری HTTPS بپشکنە و دووبارە هەوڵ بدە."],
            .install: ["Install", "ركّب", "Installieren", "Saz bike", "دایبنێ"],
            .preview: ["Preview", "معاينة", "Vorschau", "Pêşdîtin", "پێشبینین"],
            .close: ["Close", "سكّر", "Schließen", "Bigire", "دابخە"],
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
    @State private var preview: WallpaperPreviewSelection?
    let busy: Bool
    let install: (URL) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
                Text(WallpaperSourceText.text(.title)).font(.title3.bold())
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
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .fullScreenCover(item: $preview) { selection in
            WallpaperSourcePreview(entry: selection.entry, busy: busy || downloading != nil,
                                   downloading: downloading == selection.id) {
                download(selection.entry, source: selection.source)
            }
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
            Button { preview = WallpaperPreviewSelection(entry: entry, source: source) } label: {
                Color.clear
                    .frame(height: 230)
                    .overlay {
                        GeometryReader { bounds in
                            previewImage(entry)
                                .frame(width: bounds.size.width, height: bounds.size.height)
                                .clipped()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(alignment: .bottomTrailing) {
                        if entry.previewVideo != nil || entry.previewImage.pathExtension.lowercased() == "gif" {
                            Image(systemName: "play.circle.fill").font(.title).padding(8)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.name)
            .accessibilityIdentifier("wallpaper-preview-" + entry.id)
            Text(entry.name).font(.headline).lineLimit(2)
            Text(entry.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(entry.category + " · " + (entry.sizeIsEstimated == true ? "≤ " : "") + ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Button {
                download(entry, source: source)
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

    private func download(_ entry: WallpaperSourceEntry, source: URL) {
        guard !busy, downloading == nil else { return }
                #if DEBUG
                guard !WallpaperSourceFixture.active else { return }
                #endif
                downloading = source.absoluteString + entry.id
                Task {
                    defer { downloading = nil }
                    do {
                        let archive = try await WallpaperSourceNetwork.archive(entry)
                        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
                        preview = nil
                        await install(archive)
                    } catch { store.error = WallpaperSourceText.text(.failed) }
                }
    }
}

private struct WallpaperPreviewSelection: Identifiable {
    let entry: WallpaperSourceEntry
    let source: URL
    var id: String { source.absoluteString + entry.id }
}

private struct WallpaperSourcePreview: View {
    let entry: WallpaperSourceEntry
    let busy: Bool
    let downloading: Bool
    let install: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.blue).frame(width: 40, height: 40)
                        .background(.white.opacity(0.13), in: Circle())
                }
                .accessibilityLabel(WallpaperSourceText.text(.close))
                .accessibilityIdentifier("wallpaper-preview-close")
                Spacer()
                Text(WallpaperSourceText.text(.preview)).font(.headline)
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }.padding(.horizontal, 20).padding(.vertical, 8)
            GeometryReader { bounds in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Color.clear
                            .frame(height: max(260, bounds.size.height - 85))
                            .overlay {
                                GeometryReader { card in
                                    media.frame(width: card.size.width, height: card.size.height).clipped()
                                }
                            }
                            .overlay(alignment: .bottomLeading) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.name).font(.title2.bold())
                                    Text(entry.author).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                 .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 32))
                            .accessibilityIdentifier("wallpaper-preview-media")
                        Text(entry.description?.isEmpty == false ? entry.description! : entry.category)
                            .font(.subheadline).foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.horizontal, 20).padding(.bottom, 16)
                }
            }
            Button(action: install) {
                HStack {
                    if downloading { ProgressView().tint(.white) }
                    else { Image(systemName: "arrow.down.circle.fill") }
                    Text(WallpaperSourceText.text(downloading ? .working : .install)).fontWeight(.semibold)
                }.frame(maxWidth: .infinity, minHeight: 54)
            }.buttonStyle(.plain).foregroundStyle(.white)
                .background(.blue, in: Capsule()).disabled(busy)
                .accessibilityIdentifier("wallpaper-preview-install")
                .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder private var media: some View {
        if let url = entry.previewVideo {
            WallpaperSourceVideoView(url: url)
        } else if entry.previewImage.pathExtension.lowercased() == "gif" {
            WallpaperAnimatedPreview(url: entry.previewImage)
        } else {
            #if DEBUG
            if WallpaperSourceFixture.active, let image = WallpaperSourceFixture.image(for: entry) {
                Image(uiImage: image).resizable().scaledToFill()
            } else { image }
            #else
            image
            #endif
        }
    }
    private var image: some View {
        AsyncImage(url: entry.previewImage) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else { Color.white.opacity(0.08).overlay { Image(systemName: "photo") } }
        }
    }
}

/// A single muted looping player exists only while the preview is presented.
private struct WallpaperSourceVideoView: View {
    let url: URL
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var observer: Any?
    @State private var played = false
    var body: some View {
        VideoPlayer(player: player)
            .accessibilityIdentifier("wallpaper-preview-video")
            .accessibilityValue(played ? "playing-muted" : "loading")
            .task {
                let queue = AVQueuePlayer()
                queue.isMuted = true
                looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
                player = queue
                observer = queue.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { time in
                    if time.seconds > 0.4 { played = true }
                }
                queue.play()
            }
            .onDisappear {
                player?.pause()
                if let observer { player?.removeTimeObserver(observer) }
                observer = nil; looper?.disableLooping(); looper = nil; player = nil
            }
    }
}

/// GIFs keep their animation, with remote page navigation and JavaScript disabled.
private struct WallpaperAnimatedPreview: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        let escaped = url.absoluteString.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
        view.loadHTMLString("<meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><style>body{margin:0;background:black}img{width:100%;height:100%;object-fit:cover;position:absolute}</style><img src=\"" + escaped + "\">", baseURL: nil)
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) { uiView.stopLoading() }
}
