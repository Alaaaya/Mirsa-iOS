import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVKit

/// Focus is propagated separately from chat so only the dock, not the tools picker, steps aside.
struct WallpaperMakerFocusKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Embedded directly inside the existing Tendies section.
struct WallpaperMakerSection: View {
    let applyRunning: Bool
    let onImport: (URL) async -> Void
    @State private var layers: [WallpaperPhotoLayer] = WallpaperMakerSection.fixtureLayers()
    @State private var video: URL?
    @State private var generated: URL?
    @State private var showPhotos = false
    @State private var showVideo = false
    @State private var showFiles = false
    @State private var showShare = false
    @State private var busy = false
    @State private var progress: Double = 0
    @State private var depth = false
    @State private var effects = PhotoWallpaper.Effects()
    @State private var crop = true
    @State private var message: String?
    @State private var description = ""
    @State private var planBusy = false
    /// DEBUG + UI-test harness only: plain generated sample photos so screenshots show populated layers.
    private static var fixtureAI: Bool {
        #if DEBUG
        return MirsaUITestHarness.active && ProcessInfo.processInfo.arguments.contains("-MirsaWallpaperAIFixture")
        #else
        return false
        #endif
    }
    private static func fixtureLayers() -> [WallpaperPhotoLayer] {
        #if DEBUG
        guard MirsaUITestHarness.active, ProcessInfo.processInfo.arguments.contains("-MirsaWallpaperFixture") else { return [] }
        let colors: [(UIColor, UIColor)] = [(.systemIndigo, .systemTeal), (.systemOrange, .systemPink), (.systemGreen, .systemYellow)]
        let roles: [WallpaperPhotoLayer.Role] = [.background, .middle, .foreground]
        return (0..<3).map { i in
            let size = CGSize(width: 600, height: 1200)
            let img = UIGraphicsImageRenderer(size: size).image { ctx in
                let g = CGGradient(colorsSpace: nil, colors: [colors[i].0.cgColor, colors[i].1.cgColor] as CFArray, locations: [0, 1])!
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
                UIColor.white.withAlphaComponent(0.8).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 150 + CGFloat(i) * 40, y: 300 + CGFloat(i) * 200, width: 300, height: 300))
            }
            var l = WallpaperPhotoLayer(image: img, role: roles[i]); l.zoom = 1; return l
        }
        #else
        return []
        #endif
    }
    @FocusState private var descriptionFocused: Bool
    private var textDirection: LayoutDirection {
        let language = AppLanguageStore.snapshot
        return language == .arabic || language == .sorani ? .rightToLeft : .leftToRight
    }
    private func t(_ key: WallpaperMakerStrings.Key) -> String { WallpaperMakerStrings.text(key) }
    private var aspect: CGFloat { UIScreen.main.bounds.width / UIScreen.main.bounds.height }

    var body: some View {
        Group {
            Label(t(.title), systemImage: "square.3.layers.3d")
                .font(.headline)
            Text(t(.steps)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { showPhotos = true } label: { Label(t(.photos), systemImage: "photo.stack") }
                Spacer()
                Button { showVideo = true } label: { Image(systemName: "video.badge.plus") }
                    .accessibilityLabel(t(.video))
            }.disabled(busy || applyRunning || planBusy)
            Button { showFiles = true } label: { Label(t(.files), systemImage: "folder") }
                .disabled(busy || applyRunning || planBusy)
            if !layers.isEmpty {
                photoControls
            }
            if let video {
                VideoPlayer(player: AVPlayer(url: video))
                    .frame(height: 220).accessibilityLabel(t(.preview))
            }
            if WallpaperLayoutAI.enabled || Self.fixtureAI {
                TextField(t(.describe), text: $description, axis: .vertical)
                    .font(.body)
                    .lineSpacing(4)
                    .lineLimit(3...)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
                    .environment(\.layoutDirection, textDirection)
                    .multilineTextAlignment(.leading)
                    .focused($descriptionFocused)
                    .accessibilityIdentifier("wallpaper-description")
                    // Attach to the single input, not Group's many Form rows.
                    .preference(key: WallpaperMakerFocusKey.self, value: descriptionFocused)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button(MirsaTr.lit("Done")) { descriptionFocused = false }
                                .accessibilityIdentifier("wallpaper-keyboard-done")
                        }
                    }
                    .onChange(of: description) { _, value in
                        if value.utf8.count > 2000 { description = String(value.prefix(500)) }
                    }
                Button(t(.plan)) { requestPlan() }
                    .disabled(busy || planBusy || layers.isEmpty || description.isEmpty || applyRunning)
            }
            if !layers.isEmpty || video != nil {
                Button(t(.generate)) { descriptionFocused = false; generate() }
                    .accessibilityIdentifier("wallpaper-generate")
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || planBusy || applyRunning)
                Button(t(.clear), role: .destructive) { clear() }
                    .disabled(busy || planBusy)
            }
            if busy || planBusy { ProgressView(value: busy ? progress : nil) { Text(t(.preparing)) } }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if let generated {
                Text(t(.ready)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { showShare = true } label: { Label(t(.share), systemImage: "square.and.arrow.up") }
                Button(t(.importFile)) {
                    Task { await onImport(generated) }
                }.disabled(applyRunning || busy)
            }
            Text(t(.videoHelp)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(t(.compatibility)).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("wallpaper-compatibility")
        }
        .sheet(isPresented: $showPhotos) {
            WallpaperPhotosPicker { result in
                showPhotos = false
                receivePhotos(result)
            }.interactiveDismissDisabled()
        }
        .sheet(isPresented: $showVideo) {
            WallpaperVideoPicker { result in
                showVideo = false
                guard let result else { return }
                switch result {
                case .failure: message = t(.error)
                case .success(let url): setVideo(url)
                }
            }.interactiveDismissDisabled()
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image, .movie], allowsMultipleSelection: true) { result in
            switch result {
            case .failure: break // Cancel is not an error.
            case .success(let urls): receiveFiles(urls)
            }
        }
        .sheet(isPresented: $showShare) {
            if let generated { ShareSheet(items: [generated]) }
        }
        .onAppear {
            #if DEBUG
            if Self.fixtureAI {
                description = textDirection == .rightToLeft
                    ? "رتّب الصور بطبقات واضحة\nخلّي الصورة الأمامية فوق الخلفية\nوحافظ على التفاصيل والألوان"
                    : "Arrange the photos in clear layers\nKeep the foreground above the background\nPreserve details and colours"
            }
            #endif
        }
        .onDisappear { clear() }
    }

    private var photoControls: some View {
        Group {
            ZStack {
                Color.black
                ForEach(PhotoWallpaper.ordered(layers, depth: depth)) { layer in
                    GeometryReader { geometry in
                        Image(uiImage: layer.image).resizable()
                            .aspectRatio(contentMode: crop && layer.crop ? .fill : .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(layer.zoom)
                            .offset(x: CGFloat(layer.x) * geometry.size.width / 2,
                                    y: CGFloat(layer.y) * geometry.size.height / 2)
                    }
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxHeight: 300)
            .clipped()
            .accessibilityLabel(t(.preview))
            Toggle(t(.crop), isOn: $crop)
            Toggle(t(.depth), isOn: $depth)
            Text(t(.depthHelp)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker(t(.unlock), selection: $effects.unlock) {
                Text(t(.off)).tag(PhotoWallpaper.Effects.Unlock.none)
                Text(t(.unlockZoom)).tag(PhotoWallpaper.Effects.Unlock.zoom)
                Text(t(.unlockSlide)).tag(PhotoWallpaper.Effects.Unlock.slide)
            }
            Toggle(t(.gyro), isOn: $effects.gyro)
            Toggle(t(.floating), isOn: $effects.floating)
            Text(t(.effectsHelp)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(t(.reorder)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach($layers) { $layer in
                DisclosureGroup {
                    Picker(t(.layers), selection: $layer.role) {
                        Text(t(.background)).tag(WallpaperPhotoLayer.Role.background)
                        Text(t(.middle)).tag(WallpaperPhotoLayer.Role.middle)
                        Text(t(.foreground)).tag(WallpaperPhotoLayer.Role.foreground)
                    }.pickerStyle(.segmented)
                    Toggle(t(.crop), isOn: $layer.crop)
                    Text(t(.zoom)).font(.caption)
                    Slider(value: $layer.zoom, in: 1...4)
                    Text(t(.horizontal)).font(.caption)
                    Slider(value: $layer.x, in: -1...1)
                    Text(t(.vertical)).font(.caption)
                    Slider(value: $layer.y, in: -1...1)
                    Button(t(.remove), role: .destructive) { layers.removeAll { $0.id == layer.id }; invalidate() }
                } label: {
                    HStack {
                        Image(uiImage: layer.image).resizable().scaledToFit().frame(width: 40, height: 48)
                        Text(t(layer.role == .foreground ? .foreground : layer.role == .middle ? .middle : .background))
                        Spacer()
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                    }
                }
            }
            .onMove { source, target in layers.move(fromOffsets: source, toOffset: target); invalidate() }
            .environment(\.editMode, .constant(.active))
        }
        .disabled(busy || planBusy)
        .onChange(of: depth) { _, _ in invalidate() }
        .onChange(of: crop) { _, _ in invalidate() }
        .onChange(of: effects) { _, _ in invalidate() }
        // Any manual edit invalidates the previous archive, preventing stale export.
        .onChange(of: layers.map { "\($0.id):\($0.role.rawValue):\($0.zoom):\($0.x):\($0.y):\($0.crop)" }) { _, _ in invalidate() }
    }

    private func invalidate() {
        if let generated { try? FileManager.default.removeItem(at: generated) }
        generated = nil
        message = nil
    }
    private func clear() {
        invalidate(); layers = []
        if let video { try? FileManager.default.removeItem(at: video) }
        video = nil
    }
    private func setVideo(_ url: URL) { clear(); video = url }
    private func receivePhotos(_ result: Result<[UIImage], Error>?) {
        guard let result else { return }
        switch result {
        case .failure: message = t(.error)
        case .success(let images):
            guard layers.count + images.count <= PhotoWallpaper.maximumLayers else { message = t(.limit); return }
            if let video { try? FileManager.default.removeItem(at: video) }; video = nil
            invalidate()
            layers += images.map { WallpaperPhotoLayer(image: $0, role: layers.isEmpty ? .background : .middle) }
        }
    }
    private func receiveFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        do {
            let movies = urls.filter { (try? $0.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .movie)) == true
                || UTType(filenameExtension: $0.pathExtension)?.conforms(to: .movie) == true }
            guard movies.isEmpty || (urls.count == 1 && movies.count == 1) else { message = t(.limit); return }
            if let source = movies.first {
                let access = source.startAccessingSecurityScopedResource()
                defer { if access { source.stopAccessingSecurityScopedResource() } }
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
                try FileManager.default.copyItem(at: source, to: copy)
                setVideo(copy)
            } else {
                guard urls.count + layers.count <= PhotoWallpaper.maximumLayers else { message = t(.limit); return }
                let images = try urls.map { url -> UIImage in
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try PhotoWallpaper.loadImage(url)
                }
                receivePhotos(.success(images))
            }
        } catch { message = t(.error) }
    }
    private func generate() {
        invalidate(); busy = true; progress = 0
        let snapshot = layers, source = video, ratio = aspect, cropPhotos = crop, useDepth = depth, chosenEffects = effects
        Task {
            defer { busy = false }
            do {
                generated = try await Task.detached(priority: .userInitiated) {
                    if let source {
                        return try await VideoWallpaper.makeArchive(from: source, screenAspect: ratio) { value in
                            Task { @MainActor in progress = value }
                        }
                    }
                    return try PhotoWallpaper.makeArchive(layers: snapshot, screenAspect: ratio, crop: cropPhotos, depth: useDepth, effects: chosenEffects)
                }.value
                progress = 1
            } catch { message = t(.error) }
        }
    }
    private func requestPlan() {
        planBusy = true
        let snapshot = layers
        Task {
            defer { planBusy = false }
            do {
                let plan = try await WallpaperLayoutAI.request(description: description, layers: snapshot)
                layers = try plan.apply(to: snapshot)
                invalidate()
            } catch { message = t(.manualFallback) }
        }
    }
}

/// Only the chosen images are readable. Load copied files, not whole-library permissions.
struct WallpaperPhotosPicker: UIViewControllerRepresentable {
    let completion: (Result<[UIImage], Error>?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = PhotoWallpaper.maximumLayers
        config.selection = .ordered
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: (Result<[UIImage], Error>?) -> Void
        init(_ completion: @escaping (Result<[UIImage], Error>?) -> Void) { self.completion = completion }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else { completion(nil); return }
            Task { @MainActor in
                do {
                    var images: [UIImage] = []
                    // Sequential callbacks preserve selection order and bound decoded memory.
                    for result in results {
                        let url: URL = try await withCheckedThrowingContinuation { continuation in
                            result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                                do {
                                    guard let url else { throw error ?? CocoaError(.fileReadUnknown) }
                                    let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
                                    try FileManager.default.copyItem(at: url, to: copy)
                                    continuation.resume(returning: copy)
                                } catch { continuation.resume(throwing: error) }
                            }
                        }
                        defer { try? FileManager.default.removeItem(at: url) }
                        images.append(try PhotoWallpaper.loadImage(url))
                    }
                    completion(.success(images))
                } catch { completion(.failure(error)) }
            }
        }
    }
}
