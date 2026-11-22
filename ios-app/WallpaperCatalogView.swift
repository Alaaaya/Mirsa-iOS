import SwiftUI
import ImageIO

/// Intentionally isolated from AppViewModel, import, apply and PosterBoard code.
struct WallpaperCatalogView: View {
    @AppStorage("wallpaper.catalog.url") private var source = ""
    @State private var catalog: WallpaperCatalog?
    @State private var busy = false
    @State private var failed = false
    @State private var share: Export?
    @State private var exportedURL: URL?
    @State private var operation: Task<Void, Never>?
    private struct Export: Identifiable {
        let id = UUID()
        let url: URL
    }
    private func t(_ key: WallpaperCatalogText.Key) -> String { WallpaperCatalogText.text(key) }

    var body: some View {
        List {
            Section {
                TextField(t(.source), text: $source)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("wallpaper-catalog-url")
                Button(t(.load)) { load() }
                    .disabled(busy || source.isEmpty)
                    .accessibilityIdentifier("wallpaper-catalog-load")
                Text(t(.notice)).font(.caption).foregroundStyle(.secondary)
                if busy { ProgressView(t(.loading)) }
                if failed { Text(t(.failed)).foregroundStyle(.red) }
            }
            if let catalog {
                Section {
                    ForEach(catalog.wallpapers) { entry in
                        VStack(alignment: .leading, spacing: 10) {
                            WallpaperCatalogPreview(url: entry.preview)
                            Text(entry.name).font(.headline)
                            Text(entry.author + " · " + entry.category)
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Button { export(entry) } label: {
                                Label(t(.export), systemImage: "square.and.arrow.up")
                            }.disabled(busy)
                        }.padding(.vertical, 8)
                    }
                } header: {
                    VStack(alignment: .leading) {
                        Text(catalog.name)
                        Text(catalog.author).font(.caption)
                    }
                }
            }
        }
        .navigationTitle(t(.title))
        .sheet(item: $share, onDismiss: cleanup) { export in
            ShareSheet(items: [export.url])
        }
        .onDisappear {
            operation?.cancel()
            // The share presenter retains its file until its own dismissal.
            if share == nil { cleanup() }
        }
    }

    private func cleanup() {
        if let url = exportedURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        exportedURL = nil
        share = nil
    }

    private func load() {
        operation?.cancel()
        catalog = nil
        failed = false
        busy = true
        let input = source.trimmingCharacters(in: .whitespacesAndNewlines)
        operation = Task { @MainActor in
            defer { busy = false }
            do {
                guard input.utf8.count <= 2048, let url = URL(string: input) else {
                    throw WallpaperCatalog.Invalid.url
                }
                let data = try await WallpaperCatalogNetwork().read(url, limit: WallpaperCatalog.feedLimit)
                try Task.checkCancellation()
                catalog = try WallpaperCatalog.decode(data)
            } catch is CancellationError {} catch { failed = true }
        }
    }

    private func export(_ entry: WallpaperCatalog.Entry) {
        failed = false
        busy = true
        operation = Task { @MainActor in
            defer { busy = false }
            do {
                let url = try await WallpaperCatalogNetwork().export(entry)
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                    return
                }
                exportedURL = url
                share = Export(url: url)
            } catch is CancellationError {} catch { failed = true }
        }
    }
}

/// Explicit preview tap, not 200 speculative remote image requests.
/// Decode a thumbnail, not a feed-controlled full-resolution bitmap.
private struct WallpaperCatalogPreview: View {
    let url: URL
    @State private var image: UIImage?
    @State private var loading = false
    @State private var requested = false
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                    .accessibilityLabel(WallpaperCatalogText.text(.preview))
            } else if loading {
                ProgressView()
            } else if !requested {
                Button(WallpaperCatalogText.text(.preview)) { requested = true }
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .task(id: requested) {
            guard requested else { return }
            loading = true
            defer { loading = false }
            guard let data = try? await WallpaperCatalogNetwork().read(url, limit: 2 * 1_048_576),
                  !Task.isCancelled,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int,
                  let height = props[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 8192, height <= 8192,
                  width <= 24_000_000 / height,
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 640,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else { return }
            image = UIImage(cgImage: cg)
        }
    }
}
