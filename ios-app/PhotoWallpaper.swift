import UIKit
import ImageIO

/// User-supplied cutouts are preserved as RGBA PNGs. No segmentation is performed.
struct WallpaperPhotoLayer: Identifiable {
    enum Role: String, CaseIterable { case background, middle, foreground }
    let id: UUID
    let image: UIImage
    var role: Role
    var zoom: Double = 1
    var x: Double = 0
    var y: Double = 0
    var crop: Bool = true
    init(image: UIImage, role: Role = .background, id: UUID = UUID()) {
        self.id = id; self.image = image; self.role = role
    }
}

enum PhotoWallpaper {
    static let maximumLayers = 8
    static let wallpaperName = "9183.Custom-810w-1080h@2x~ipad.wallpaper"
    static let backgroundName = "9183.Custom_Background-810w-1080h@2x~ipad.ca"
    static let foregroundName = "9183.Custom_Floating-810w-1080h@2x~ipad.ca"

    static func loadImage(_ url: URL) throws -> UIImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        return UIImage(cgImage: cg)
    }

    /// Matches the preview: the array is back-to-front within each role.
    /// Floating is routed separately only with explicit experimental clock-depth opt-in.
    static func ordered(_ layers: [WallpaperPhotoLayer], depth: Bool) -> [WallpaperPhotoLayer] {
        guard depth else { return layers }
        return layers.filter { $0.role != .foreground } + layers.filter { $0.role == .foreground }
    }

    static func render(_ image: UIImage, size: CGSize, crop: Bool, zoom: Double = 1, x: Double = 0, y: Double = 0) throws -> Data {
        guard zoom.isFinite, x.isFinite, y.isFinite, (1...4).contains(zoom), (-1...1).contains(x), (-1...1).contains(y),
              image.size.width > 0, image.size.height > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let data = UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
            let sx = size.width / image.size.width, sy = size.height / image.size.height
            let scale = (crop ? max(sx, sy) : min(sx, sy)) * CGFloat(zoom)
            let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (size.width - target.width) / 2 + CGFloat(x) * size.width / 2,
                                  y: (size.height - target.height) / 2 + CGFloat(y) * size.height / 2,
                                  width: target.width, height: target.height))
        }
        return data
    }

    static func makeArchive(layers: [WallpaperPhotoLayer], screenAspect: CGFloat,
                            crop: Bool = true, depth: Bool = false) throws -> URL {
        guard !layers.isEmpty, layers.count <= maximumLayers,
              screenAspect.isFinite, screenAspect >= 0.3, screenAspect <= 2 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("photo-wallpaper-" + UUID().uuidString)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        guard let template = Bundle.main.url(forResource: "VideoCAML", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let root = work.appendingPathComponent("package")
        let descriptor = root.appendingPathComponent("Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors")
            .appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: descriptor.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: template, to: descriptor)
        let wallpaper = descriptor.appendingPathComponent("versions/1/contents/" + wallpaperName)
        let width = 1080
        let height = Int((CGFloat(width) / screenAspect / 2).rounded()) * 2
        let size = CGSize(width: CGFloat(width), height: CGFloat(height))
        let sorted = ordered(layers, depth: depth)
        for (name, floating) in [(backgroundName, false), (foregroundName, true)] {
            let ca = wallpaper.appendingPathComponent(name)
            try? fm.removeItem(at: ca)
            let assets = ca.appendingPathComponent("assets")
            try fm.createDirectory(at: assets, withIntermediateDirectories: true)
            var nodes = ""
            for (index, layer) in sorted.enumerated() {
                guard (depth && layer.role == .foreground) == floating else { continue }
                try Task.checkCancellation()
                let filename = "layer-\(index).png"
                try autoreleasepool {
                    try render(layer.image, size: size, crop: crop && layer.crop, zoom: layer.zoom, x: layer.x, y: layer.y).write(to: assets.appendingPathComponent(filename))
                }
                nodes += """
                <CALayer name="layer-\(index)-\(layer.role.rawValue)" bounds="0 0 \(width) \(height)" position="\(width/2) \(height/2)" contentsFormat="RGBA8">
                  <contents type="CGImage" src="assets/\(filename)"/>
                </CALayer>

                """
            }
            let caml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <caml xmlns="http://www.apple.com/CoreAnimation/1.0">
            <CALayer name="\(floating ? "_FLOATING" : "_BACKGROUND")" bounds="0 0 \(width) \(height)" position="\(width/2) \(height/2)">
            <sublayers>\(nodes)</sublayers>
            <states><LKState name="Locked"><elements/></LKState><LKState name="Unlock"><elements/></LKState><LKState name="Sleep"><elements/></LKState></states>
            </CALayer></caml>
            """
            try Data(caml.utf8).write(to: ca.appendingPathComponent("main.caml"))
            let index: [String: Any] = ["rootDocument": "main.caml", "documentWidth": width, "documentHeight": height,
                "documentResizesToView": true, "geometryFlipped": false, "scalesToFitInPlayer": true, "unitsInPixelsInPlayer": true]
            try PropertyListSerialization.data(fromPropertyList: index, format: .xml, options: 0)
                .write(to: ca.appendingPathComponent("index.xml"))
        }
        // These are the authentic LayeredAnimation keys in Pocket-Poster's template.
        // Both CA documents exist even when depth is off (the floating one is empty).
        let plistURL = wallpaper.appendingPathComponent("Wallpaper.plist")
        var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as! [String: Any]
        plist["assets"] = ["lockAndHome": ["default": [
            "backgroundAnimationFileName": backgroundName, "floatingAnimationFileNameKey": foregroundName,
            "identifier": 9183, "name": "Mirsa", "type": "LayeredAnimation"]]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
        let output = fm.temporaryDirectory.appendingPathComponent("Mirsa-" + UUID().uuidString + ".tendies")
        do { try PasscodeThemePackager.archiveDirectory(root, to: output) }
        catch { try? fm.removeItem(at: output); throw error }
        return output
    }
}
