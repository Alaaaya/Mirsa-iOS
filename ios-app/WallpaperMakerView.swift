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
    private enum MediaPicker: String, Identifiable {
        case photos, video
        var id: String { rawValue }
    }
    @State private var mediaPicker: MediaPicker?
    @State private var showFiles = false
    @State private var showShare = false
    @State private var busy = false
    @State private var progress: Double = 0
    @State private var depth = false
    @State private var autoEffectsApplied = false
    @State private var effects = PhotoWallpaper.Effects(floating: true)
    @State private var crop = true
    @State private var message: String?
    @State private var description = ""
    @State private var planBusy = false
    @State private var cutoutBusy = false
    @State private var cutoutRunID = UUID()
    @State private var generationID = UUID()
    @State private var generationTask: Task<Void, Never>?
    @State private var planTask: Task<Void, Never>?

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
            Text(t(.steps)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button {
                    guard mediaPicker == nil else { return }
                    mediaPicker = .photos
                } label: {
                    Label(t(.photos), systemImage: "photo.stack").frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("wallpaper-choose-photos")
                Button {
                    guard mediaPicker == nil else { return }
                    mediaPicker = .video
                } label: {
                    Label(t(.video), systemImage: "video.badge.plus").frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("wallpaper-choose-video")
            }
            // Automatic Form-row buttons can fire BOTH actions. Keep explicit tap targets.
            .buttonStyle(.plain)
            #if DEBUG
            .overlay(alignment: .topLeading) {
                Color.clear.frame(width: 2, height: 2).accessibilityElement()
                    .accessibilityIdentifier("wallpaper-picker-state")
                    .accessibilityValue(mediaPicker.map { "\($0)" } ?? "none")
            }
            #endif
            .disabled(busy || applyRunning || planBusy)
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
                    .id("wallpaper-description-row")
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
                    .disabled(busy || cutoutBusy || planBusy || applyRunning)
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
            // Keeps the last (destructive) button clear of the floating dock, keyboard and large text.
            Color.clear.frame(height: MirsaTabBarMetrics.clearance).listRowBackground(Color.clear)
                .accessibilityHidden(true)
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
        .task(id: layers.map { "\($0.id):\($0.role.rawValue):\($0.cutoutEnabled)" }.joined()) {
            await prepareForegrounds()
        }
        // Sheet hangs off the whole maker body so row re-renders cannot swallow the state.
        .sheet(item: $mediaPicker) { selection in
            switch selection {
            case .photos:
                WallpaperPhotosPicker { result in
                    mediaPicker = nil
                    receivePhotos(result)
                }.interactiveDismissDisabled().pickerHostMarker("photos")
            case .video:
                WallpaperVideoPicker { result in
                    mediaPicker = nil
                    guard let result else { return }
                    switch result {
                    case .failure: message = t(.error)
                    case .success(let url): setVideo(url)
                    }
                }.interactiveDismissDisabled().pickerHostMarker("video")
            }
        }
        .onDisappear { clear() }
    }

    private var photoControls: some View {
        Group {
            ZStack {
                Color.black
                ForEach(PhotoWallpaper.ordered(layers, depth: depth)) { layer in
                    GeometryReader { geometry in
                        Image(uiImage: layer.renderedImage).resizable()
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
            Toggle(t(.depth), isOn: $depth).disabled(effects.gyro)
            Text(t(.depthHelp)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            referenceEffectControls
            Toggle(t(.floating), isOn: $effects.floating)
            if effects.floating {
                Picker(t(.motionPreset), selection: $effects.motion) {
                    Text(t(.motionLeft)).tag(PhotoWallpaper.Effects.Motion.left)
                    Text(t(.motionRight)).tag(PhotoWallpaper.Effects.Motion.right)
                    Text(t(.motionUp)).tag(PhotoWallpaper.Effects.Motion.up)
                    Text(t(.motionDown)).tag(PhotoWallpaper.Effects.Motion.down)
                    Text(t(.motionFloat)).tag(PhotoWallpaper.Effects.Motion.float)
                }
            }
            Text(t(effects.floating || effects.spin || effects.particles != .none ? .animatedPhotos : .sceneOutput))
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("wallpaper-motion-output")
            Text(t(.effectsHelp)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(t(.reorder)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach($layers) { $layer in
                DisclosureGroup {
                    Picker(t(.layers), selection: $layer.role) {
                        Text(t(.background)).tag(WallpaperPhotoLayer.Role.background)
                        Text(t(.middle)).tag(WallpaperPhotoLayer.Role.middle)
                        Text(t(.foreground)).tag(WallpaperPhotoLayer.Role.foreground)
                    }.pickerStyle(.segmented)
                    if layer.role == .foreground {
                        Toggle(t(.cutout), isOn: $layer.cutoutEnabled)
                        Text(t(.cutoutHelp)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if layer.cutoutEnabled {
                            Text(t(layer.cutoutStatus == .ready ? .cutoutReady : layer.cutoutStatus == .noSubject ? .cutoutNoSubject : layer.cutoutStatus == .unavailable ? .cutoutUnavailable : .cutoutPreparing))
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Picker(t(.scene), selection: $layer.scene) {
                        Text(t(.sceneShared)).tag(WallpaperPhotoLayer.Scene.shared)
                        Text(t(.sceneLock)).tag(WallpaperPhotoLayer.Scene.lock)
                        Text(t(.sceneHome)).tag(WallpaperPhotoLayer.Scene.home)
                    }
                    Picker(t(.appearance), selection: $layer.appearance) {
                        Text(t(.appearanceBoth)).tag(WallpaperPhotoLayer.Appearance.both)
                        Text(t(.appearanceLight)).tag(WallpaperPhotoLayer.Appearance.light)
                        Text(t(.appearanceDark)).tag(WallpaperPhotoLayer.Appearance.dark)
                    }.disabled(effects.gyro)
                    Text(t(.appearanceHelp)).font(.caption).foregroundStyle(.secondary)
                    Text(t(.sceneHelp)).font(.caption).foregroundStyle(.secondary)
                    if layer.scene == .shared {
                        Text(t(.homeHorizontal)).font(.caption)
                        Slider(value: $layer.homeOffsetX, in: -1...1)
                        Text(t(.homeVertical)).font(.caption)
                        Slider(value: $layer.homeOffsetY, in: -1...1)
                    }
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
                        Image(uiImage: layer.renderedImage).resizable().scaledToFit().frame(width: 40, height: 48)
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
        .onChange(of: layers.map { "\($0.id):\($0.role.rawValue):\($0.zoom):\($0.x):\($0.y):\($0.crop):\($0.cutoutEnabled):\($0.scene):\($0.appearance):\($0.homeOffsetX):\($0.homeOffsetY)" }) { _, _ in invalidate() }
    }

    // Existing compact Form rows only. No separate editor/panel.
    // Release gate: these controls are not ready until actual export tests + macOS compile pass.
    private var referenceEffectControls: some View {
        Group {
            Picker(t(.unlock), selection: $effects.unlock) {
                Text(t(.off)).tag(PhotoWallpaper.Effects.Unlock.none)
                Text(t(.unlockZoom)).tag(PhotoWallpaper.Effects.Unlock.zoom)
                Text(t(.unlockSlide)).tag(PhotoWallpaper.Effects.Unlock.slide)
            }.accessibilityIdentifier("wallpaper-unlock-effect")
            Text(t(.unlockHelp)).font(.caption).foregroundStyle(.secondary)
            Toggle(t(.gyro), isOn: $effects.gyro)
                .disabled(depth || layers.contains { $0.appearance != .both }).accessibilityIdentifier("wallpaper-gyro-effect")
            if effects.gyro {
                Picker(t(.gyroStrength), selection: $effects.gyroStrength) {
                    Text(t(.subtle)).tag(PhotoWallpaper.Effects.GyroStrength.subtle)
                    Text(t(.mediumStrength)).tag(PhotoWallpaper.Effects.GyroStrength.medium)
                    Text(t(.strong)).tag(PhotoWallpaper.Effects.GyroStrength.strong)
                }
            }
            Text(t(.gyroHelp)).font(.caption).foregroundStyle(.secondary)
            Toggle(t(.spin), isOn: $effects.spin).accessibilityIdentifier("wallpaper-spin-effect")
            Text(t(.spinHelp)).font(.caption).foregroundStyle(.secondary)
            Picker(t(.particles), selection: $effects.particles) {
                Text(t(.off)).tag(PhotoWallpaper.Effects.Particles.none)
                Text(t(.snow)).tag(PhotoWallpaper.Effects.Particles.snow)
                Text(t(.leaves)).tag(PhotoWallpaper.Effects.Particles.leaves)
                Text(t(.stars)).tag(PhotoWallpaper.Effects.Particles.stars)
            }.accessibilityIdentifier("wallpaper-particles-effect")
            if effects.particles != .none {
                Picker(t(.particleDirection), selection: $effects.particleDirection) {
                    Text(t(.falling)).tag(PhotoWallpaper.Effects.ParticleDirection.falling)
                    Text(t(.rising)).tag(PhotoWallpaper.Effects.ParticleDirection.rising)
                }
            }
            Text(t(.particlesHelp)).font(.caption).foregroundStyle(.secondary)
            Toggle(t(.sleepDim), isOn: $effects.dimOnSleep).accessibilityIdentifier("wallpaper-sleep-effect")
            Text(t(.sleepHelp)).font(.caption).foregroundStyle(.secondary)
            Toggle(t(.gradient), isOn: $effects.gradient).accessibilityIdentifier("wallpaper-gradient-effect")
            Toggle(t(.replicate), isOn: $effects.replicate).accessibilityIdentifier("wallpaper-replicate-effect")
            Text(t(.replicateHelp)).font(.caption).foregroundStyle(.secondary)
            Picker(t(.blend), selection: $effects.blend) {
                Text(t(.normalBlend)).tag(PhotoWallpaper.Effects.Blend.normal)
                Text(t(.screenBlend)).tag(PhotoWallpaper.Effects.Blend.screen)
                Text(t(.overlayBlend)).tag(PhotoWallpaper.Effects.Blend.overlay)
            }
            Toggle(t(.blur), isOn: $effects.blur)
            Toggle(t(.liquidGlass), isOn: $effects.liquidGlass).accessibilityIdentifier("wallpaper-glass-effect")
            Text(t(.glassHelp)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func invalidate() {
        if let generated { try? FileManager.default.removeItem(at: generated) }
        generated = nil
        message = nil
    }
    private func clear() {
        generationID = UUID(); cutoutRunID = UUID(); cutoutBusy = false
        generationTask?.cancel(); planTask?.cancel()
        generationTask = nil; planTask = nil; busy = false; planBusy = false
        invalidate(); layers = []; autoEffectsApplied = false
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
            let roles = PhotoWallpaper.defaultRoles(existing: layers.count, adding: images.count)
            layers += zip(images, roles).map { WallpaperPhotoLayer(image: $0, role: $1) }
            // Never auto-enable unverified unlock/gyro effects. Timed motion is a separate,
            // visible choice and stays off if the user explicitly switched it off.
            if layers.count > 1 && !autoEffectsApplied {
                autoEffectsApplied = true
                depth = true
            }
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
    @MainActor private func prepareForegrounds() async {
        let runID = UUID(); cutoutRunID = runID
        cutoutBusy = true
        defer { if cutoutRunID == runID { cutoutBusy = false } }
        for layer in layers where layer.role == .foreground && layer.cutoutEnabled && layer.cutoutImage == nil && layer.cutoutStatus == .pending {
            let worker = Task.detached(priority: .userInitiated) { try WallpaperForeground.process(layer.image) }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                guard cutoutRunID == runID else { return }
                guard let index = layers.firstIndex(where: { $0.id == layer.id && $0.role == .foreground && $0.cutoutEnabled }) else { continue }
                switch result {
                case .masked(let image): layers[index].cutoutImage = image; layers[index].cutoutStatus = .ready
                case .noSubject: layers[index].cutoutStatus = .noSubject
                case .unavailable: layers[index].cutoutStatus = .unavailable
                }
                invalidate()
            } catch { return }
        }
    }
    private func generate() {
        guard !cutoutBusy else { return }
        invalidate(); busy = true; progress = 0
        let id = UUID(); generationID = id
        let snapshot = layers, source = video, ratio = aspect, cropPhotos = crop, useDepth = depth
        // Only the supported continuous axis loops are exposed by this maker.
        let chosenEffects = effects
        generationTask = Task { @MainActor in
            let worker = Task.detached(priority: .userInitiated) {
                if let source {
                    return try await VideoWallpaper.makeArchive(from: source, screenAspect: ratio) { value in
                        Task { @MainActor in if generationID == id { progress = value } }
                    }
                }
                return try PhotoWallpaper.makeArchive(layers: snapshot, screenAspect: ratio, crop: cropPhotos, depth: useDepth, effects: chosenEffects)
            }
            do {
                let output = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, generationID == id else { try? FileManager.default.removeItem(at: output); return }
                generated = output; progress = 1
            } catch { if !Task.isCancelled && generationID == id { message = t(.error) } }
            if generationID == id { busy = false }
        }
    }
    private func requestPlan() {
        planBusy = true
        let snapshot = layers
        planTask = Task { @MainActor in
            defer { planBusy = false }
            do {
                let plan = try await WallpaperLayoutAI.request(description: description, layers: snapshot)
                try Task.checkCancellation()
                layers = try plan.apply(to: snapshot)
                invalidate()
            } catch { if !Task.isCancelled { message = t(.manualFallback) } }
        }
    }
}

#if DEBUG
/// PHPicker content is remote, so its own view is not exposed to accessibility. This marker lives and dies
/// with one presented sheet instance, letting UI tests detect dismiss/recreate loops.
private struct PickerHostMarker: ViewModifier {
    let kind: String
    @State private var identity = UUID().uuidString
    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            Color.clear.frame(width: 2, height: 2)
                .accessibilityElement()
                .accessibilityIdentifier("wallpaper-" + kind + "-picker-" + identity)
        }
    }
}
#endif
extension View {
    @ViewBuilder func pickerHostMarker(_ kind: String) -> some View {
        #if DEBUG
        modifier(PickerHostMarker(kind: kind))
        #else
        self
        #endif
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
        #if DEBUG
        NSLog("MIRSA-PICKER photos created")
        #endif
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
