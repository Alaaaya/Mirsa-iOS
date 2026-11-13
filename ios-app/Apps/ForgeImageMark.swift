import SwiftUI

/// Drag a finger over the screenshot to mark the area the tweak is about. Region is normalized 0...1.
struct ForgeImageMarkView: View {
    let image: UIImage
    @Binding var region: CGRect?
    @State private var start: CGPoint?

    static var hint: String { tr("Drag a circle around the part you want to change.", "ارسم دايرة بإصبعك حوالين الجزء اللي بدك تغيّره.", ckb: "بە پەنجە بازنەیەک بکێشە بۆ ئەو بەشەی دەتەوێت بیگۆڕیت.", kmr: "Bi tiliyê xwe dorhêlekê li dora beşa ku dixwazî biguherî xêz bike.") }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let size = fitted(in: geo.size)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                    if let r = region {
                        Ellipse().stroke(Color.red, lineWidth: 3)
                            .frame(width: r.width * size.width, height: r.height * size.height)
                            .offset(x: r.minX * size.width, y: r.minY * size.height)
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 4).onChanged { v in
                    let s = start ?? v.startLocation; start = s
                    let rect = CGRect(x: min(s.x, v.location.x), y: min(s.y, v.location.y), width: abs(v.location.x - s.x), height: abs(v.location.y - s.y))
                    region = ForgeImageMark.normalize(rect, in: size)
                }.onEnded { _ in start = nil })
                .frame(maxWidth: .infinity)
            }
            .frame(height: 260)
            Text(Self.hint).font(.caption).foregroundStyle(.white.opacity(0.55))
            if region != nil { Button(tr("Clear mark", "امسح العلامة", ckb: "نیشانە بسڕەوە", kmr: "Nîşanê jê bibe")) { region = nil } }
        }
    }
    private func fitted(in box: CGSize) -> CGSize {
        let ratio = image.size.width / max(image.size.height, 1)
        var w = box.width, h = w / max(ratio, 0.01)
        if h > box.height { h = box.height; w = h * ratio }
        return CGSize(width: max(w, 1), height: max(h, 1))
    }
}

enum ForgeImageMark {
    static func normalize(_ rect: CGRect, in size: CGSize) -> CGRect {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return .zero }
        let x = max(0, min(rect.minX, size.width)), y = max(0, min(rect.minY, size.height))
        let w = max(0, min(rect.maxX, size.width) - x), h = max(0, min(rect.maxY, size.height) - y)
        return CGRect(x: x / size.width, y: y / size.height, width: w / size.width, height: h / size.height)
    }
    /// Draws a red ellipse onto a copy of the JPEG. The normalized region accompanies this marked copy for vision; coordinates stay relative to the full image.
    static func marked(_ jpeg: Data, region: CGRect) -> Data? {
        guard let image = UIImage(data: jpeg) else { return nil }
        let size = image.size
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            image.draw(at: .zero)
            let rect = CGRect(x: region.minX * size.width, y: region.minY * size.height, width: region.width * size.width, height: region.height * size.height)
            UIColor.red.setStroke()
            let path = UIBezierPath(ovalIn: rect); path.lineWidth = max(4, size.width / 120); path.stroke()
        }
        return out.jpegData(compressionQuality: 0.8)
    }
}

extension ForgeStore {
    @discardableResult
    func imageGenerate(_ id: UUID, jpeg: Data, region: CGRect, prompt: String) async throws -> Bool {
        guard let p = project(id), !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard region.width > 0.02, region.height > 0.02, let marked = ForgeImageMark.marked(jpeg, region: region) else { throw ForgeClient.Failure.message(ForgeImageMarkView.hint) }
        guard marked.count <= 1024 * 1024 else { throw ForgeClient.Failure.message("Image exceeds 1 MB.") }
        let outcome = try await ForgeClient.createCall(["action": "image-generate", "name": ForgeFeaturePolicy.name(p.name),
            "bundleID": p.bundleID, "classes": ForgeFeaturePolicy.classes(p.classes), "selectors": [String](),
            "prompt": String(prompt.prefix(2000)), "image": ["mime": "image/jpeg", "base64": marked.base64EncodedString()],
            "region": ["x": region.minX, "y": region.minY, "w": region.width, "h": region.height]])
        guard case .generated(let out) = outcome else { queuedNotice = ForgeQueued.notice; return true }
        addVersion(id, try responseVersion(out, prompt: prompt))
        return false
    }
}
