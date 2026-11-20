import SwiftUI
import AVKit
import PhotosUI
import UniformTypeIdentifiers

/// One store preview (image or short muted looping video). URLs are private signed URLs that expire,
/// so the list is refreshed on foreground and views fall back gracefully on load errors.
struct ToolsStorePreviewMedia: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var kind: String
    var url: String
    var posterURL: String?
    var contentType: String?
    enum CodingKeys: String, CodingKey { case id, kind, url, contentType = "content_type"; case posterURL = "poster_url" }

    var isVideo: Bool { kind == "video" }
    var mediaURL: URL? { Self.safe(url) }
    /// Still frame: the poster for videos, the image itself otherwise.
    var stillURL: URL? { isVideo ? Self.safe(posterURL) : Self.safe(url) }
    static func safe(_ raw: String?) -> URL? {
        #if DEBUG
        if let raw, raw.hasPrefix("file://"), let u = URL(string: raw) { return u }
        #endif
        guard let raw, let u = URL(string: raw), u.scheme?.lowercased() == "https",
              u.host?.isEmpty == false, u.user == nil, u.password == nil else { return nil }
        return u
    }
}

/// Muted, looping, inline video without controls.
struct ToolsStoreLoopingVideo: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> LoopView { LoopView(url: url) }
    func updateUIView(_ view: LoopView, context: Context) {}
    static func dismantleUIView(_ view: LoopView, coordinator: ()) { view.stop() }

    final class LoopView: UIView {
        private let queuePlayer = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        init(url: URL) {
            super.init(frame: .zero)
            let layer = self.layer as! AVPlayerLayer
            layer.player = queuePlayer
            layer.videoGravity = .resizeAspectFill
            queuePlayer.isMuted = true
            queuePlayer.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(url: url))
            queuePlayer.play()
        }
        required init?(coder: NSCoder) { fatalError() }
        func stop() { queuePlayer.pause(); looper?.disableLooping(); looper = nil }
    }
}

/// Detail-sheet gallery: swipeable real previews.
struct ToolsStorePreviewGallery: View {
    let items: [ToolsStorePreviewMedia]
    let card: Color
    var body: some View {
        TabView {
            ForEach(items) { m in
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(card)
                    if m.isVideo, let v = m.mediaURL {
                        ToolsStoreLoopingVideo(url: v)
                    } else if let u = m.stillURL {
                        AsyncImage(url: u) { phase in
                            if let image = phase.image { image.resizable().scaledToFit() } else { ProgressView() }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 2)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))
        .frame(height: 380)
        .accessibilityIdentifier("tools-store-preview-gallery")
    }
}

/// A preview the uploader picked, already compressed into a temp file.
struct ToolsStorePickedPreview: Identifiable {
    let id = UUID()
    let kind: String
    let file: URL
    let thumb: UIImage?
    var duration: Double = 0
    var contentType: String { kind == "video" ? "video/mp4" : "image/jpeg" }
    var size: Int64 { Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }

    static let maxImageBytes: Int64 = 8 * 1_048_576
    static let maxVideoBytes: Int64 = 20 * 1_048_576

    /// Loads a PhotosPicker item: images are downscaled to <=1600px JPEG, videos exported to <=720p mp4.
    static func load(_ item: PhotosPickerItem) async -> ToolsStorePickedPreview? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("store-preview-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
            let src = dir.appendingPathComponent("in.mov")
            guard (try? data.write(to: src)) != nil else { return nil }
            let asset = AVURLAsset(url: src)
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else { return nil }
            let out = dir.appendingPathComponent("preview.mp4")
            export.outputURL = out
            export.outputFileType = .mp4
            export.shouldOptimizeForNetworkUse = true
            if let d = try? await asset.load(.duration), d.seconds > 30 {
                export.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 30, preferredTimescale: 600))
            }
            await export.export()
            guard export.status == .completed else { return nil }
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: out))
            gen.appliesPreferredTrackTransform = true
            let cg = try? await gen.image(at: .zero).image
            var p = ToolsStorePickedPreview(kind: "video", file: out, thumb: cg.map { UIImage(cgImage: $0) })
            let dur = (try? await AVURLAsset(url: out).load(.duration).seconds) ?? 0
            p.duration = dur.isFinite ? min(max(dur, 0), 30) : 0
            return p.size > 0 && p.size <= maxVideoBytes ? p : nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(img.size.width, img.size.height))
        let target = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let small = UIGraphicsImageRenderer(size: target, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: target)) }
        var q: CGFloat = 0.85
        var jpg = small.jpegData(compressionQuality: q)
        while let j = jpg, Int64(j.count) > maxImageBytes, q > 0.3 { q -= 0.15; jpg = small.jpegData(compressionQuality: q) }
        guard let j = jpg else { return nil }
        let out = dir.appendingPathComponent("preview.jpg")
        guard (try? j.write(to: out)) != nil else { return nil }
        return ToolsStorePickedPreview(kind: "image", file: out, thumb: small)
    }
}
