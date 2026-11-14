import UIKit
import ImageIO

/// Original images are immutable; the optional local mask is reversible.
struct WallpaperPhotoLayer: Identifiable {
    enum Role: String, CaseIterable { case background, middle, foreground }
    let id: UUID
    let image: UIImage
    var role: Role
    enum CutoutStatus: String { case pending, ready, noSubject, unavailable }
    var cutoutEnabled = true
    var cutoutImage: UIImage?
    var cutoutStatus: CutoutStatus = .pending
    var renderedImage: UIImage { role == .foreground && cutoutEnabled ? (cutoutImage ?? image) : image }
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
    static let wallpaperName = "7400.WWDC_2022-390w-844h@3x~iphone.wallpaper"
    static let backgroundName = "7400.WWDC_2022_Background-390w-844h@3x~iphone.ca"
    static let floatingName = "7400.WWDC_2022_Floating-390w-844h@3x~iphone.ca"
    static let simpleName = "wallpaper.ca"
    static let foregroundName = "7400.WWDC_2022_Foreground-390w-844h@3x~iphone.ca"

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
        return layers.filter { $0.role == .background } + layers.filter { $0.role == .middle } + layers.filter { $0.role == .foreground }
    }

    /// First photo is the background, the last is the foreground, everything between is middle.
    static func defaultRoles(existing: Int, adding: Int) -> [WallpaperPhotoLayer.Role] {
        let total = existing + adding
        return (0..<adding).map { i in
            let index = existing + i
            if index == 0 { return .background }
            return index == total - 1 && total > 1 ? .foreground : .middle
        }
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

    struct Effects: Equatable {
        enum Unlock: String, CaseIterable { case none, zoom, slide }
        var unlock: Unlock = .none
        var gyro = false
        var floating = false
    }

    static func makeArchive(layers: [WallpaperPhotoLayer], screenAspect: CGFloat,
                            crop: Bool = true, depth: Bool = false, effects: Effects = Effects()) throws -> URL {
        guard !layers.isEmpty, layers.count <= maximumLayers,
              Set(layers.map(\.id)).count == layers.count,
              screenAspect.isFinite, screenAspect >= 0.3, screenAspect <= 2 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("photo-wallpaper-" + UUID().uuidString)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        guard let template = Bundle.main.url(forResource: "VideoCAML", withExtension: nil),
              let metadata = Bundle.main.url(forResource: "WallpaperMakerMetadata", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let root = work.appendingPathComponent("package")
        let uuid = UUID().uuidString
        let descriptor = root.appendingPathComponent("Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors/\(uuid)")
        try fm.createDirectory(at: descriptor.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: template, to: descriptor)
        let contents = descriptor.appendingPathComponent("versions/1/contents")
        // Remove every old template media document; retain the GPL metadata, never its artwork.
        for old in try fm.contentsOfDirectory(at: contents, includingPropertiesForKeys: nil)
            where old.pathExtension == "wallpaper" { try fm.removeItem(at: old) }
        if let files = fm.enumerator(at: metadata, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let file as URL in files {
                let relative = String(file.path.dropFirst(metadata.path.count + 1))
                let target = descriptor.appendingPathComponent(relative)
                if try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                    try fm.createDirectory(at: target, withIntermediateDirectories: true)
                } else {
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    var bytes = try Data(contentsOf: file)
                    if relative.contains("suggestionMetadata") {
                        var archive = try PropertyListSerialization.propertyList(from: bytes, format: nil) as! [String: Any]
                        archive["$objects"] = (archive["$objects"] as! [Any]).map {
                            ($0 as? String) == "MIRSA-GENERATED-UUID" ? uuid : $0
                        }
                        bytes = try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
                    }
                    try bytes.write(to: target)
                }
            }
        }
        try Data("7400".utf8).write(to: descriptor.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier"))
        try Data("PRPosterRoleLockScreen".utf8).write(to: descriptor.appendingPathComponent("com.apple.posterkit.role.identifier"))
        try plist(["wallpaperRepresentingIdentifier": "7400", "wallpaperRepresentingFileName": wallpaperName,
                   "posterEnvironmentOverrides": Data("{}".utf8)],
                  to: contents.appendingPathComponent("com.apple.posterkit.provider.contents.userInfo"))

        let wallpaper = contents.appendingPathComponent(wallpaperName)
        try fm.createDirectory(at: wallpaper, withIntermediateDirectories: true)
        let width = 1080, height = Int((CGFloat(width) / screenAspect / 2).rounded()) * 2
        let size = CGSize(width: width, height: height)
        let sorted = ordered(layers, depth: depth)
        // Compute descriptor snapshot colour metadata from the user's own rendered composition.
        let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            for layer in sorted {
                if let data = try? render(layer.renderedImage, size: CGSize(width: 32, height: 64),
                                          crop: crop && layer.crop, zoom: layer.zoom, x: layer.x, y: layer.y),
                   let image = UIImage(data: data) { image.draw(in: CGRect(x: 0, y: 0, width: 1, height: 1)) }
            }
        }
        var rgba = [UInt8](repeating: 0, count: 4)
        if let cgImage = thumbnail.cgImage {
            rgba.withUnsafeMutableBytes { bytes in
                if let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                           bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                }
            }
        }
        for name in ["home", "lock"] {
            let target = descriptor.appendingPathComponent("versions/1/RuntimeSnapshotMetadata-\(name).plist")
            var archive = try PropertyListSerialization.propertyList(from: Data(contentsOf: target), format: nil) as! [String: Any]
            var objects = archive["$objects"] as! [Any]
            var color = objects[2] as! [String: Any]
            color["r"] = Double(rgba[0]) / 255; color["g"] = Double(rgba[1]) / 255
            color["b"] = Double(rgba[2]) / 255
            objects[2] = color; archive["$objects"] = objects
            try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0).write(to: target)
        }
        let bundles: [(String, WallpaperPhotoLayer.Role?)] = depth
            ? [(backgroundName, .background), (floatingName, .middle), (foregroundName, .foreground)]
            : [(simpleName, nil)]
        for (name, role) in bundles {
            let ca = wallpaper.appendingPathComponent(name), assets = ca.appendingPathComponent("assets")
            try fm.createDirectory(at: assets, withIntermediateDirectories: true)
            var nodes = "", motionGroups = ""
            for (index, layer) in sorted.enumerated() {
                guard role == nil || layer.role == role else { continue }
                try Task.checkCancellation()
                let filename = layer.id.uuidString + ".png"
                try autoreleasepool {
                    try render(layer.renderedImage, size: size, crop: crop && layer.crop, zoom: layer.zoom, x: layer.x, y: layer.y)
                        .write(to: assets.appendingPathComponent(filename))
                }
                let layerName = "layer-\(index)-\(layer.role.rawValue)"
                let floatAnimation = effects.floating ? """
                <animations><animation type="CAKeyframeAnimation" keyPath="position.y" beginTime="1e-100" duration="6" fillMode="both" removedOnCompletion="0" repeatCount="inf">
                <keyTimes><integer value="0"/><real value="0.5"/><integer value="1"/></keyTimes>
                <values><real value="\(height / 2)"/><real value="\(height / 2 - 12)"/><real value="\(height / 2)"/></values>
                </animation></animations>
                """ : ""
                // Separate motion wrapper keeps timed floating independent of gyro translation.
                nodes += """
                <CALayer name="motion-\(index)" bounds="0 0 \(width) \(height)" position="\(width/2) \(height/2)">
                <sublayers><CALayer name="\(layerName)" bounds="0 0 \(width) \(height)" position="\(width/2) \(height/2)" contentsFormat="RGBA8">
                <contents type="CGImage" src="assets/\(filename)"/>\(floatAnimation)
                </CALayer></sublayers></CALayer>
                """
                if effects.gyro {
                    for axis in ["x", "y"] {
                        motionGroups += """
                        <NSDictionary><axis type="string" value="\(axis)"/><image type="string" value="null"/>
                        <keyPath type="string" value="transform.translation.\(axis)"/><layerName type="string" value="motion-\(index)"/>
                        <mapMaxTo type="integer" value="\(12 + index * 3)"/><mapMinTo type="integer" value="-\(12 + index * 3)"/>
                        <title type="string" value="Mirsa"/><view type="string" value="\(role == .background ? "Background" : role == .foreground ? "Foreground" : "Floating")"/></NSDictionary>
                        """
                    }
                }
            }
            let caml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <caml xmlns="http://www.apple.com/CoreAnimation/1.0">
            <CALayer name="Root Layer" bounds="0 0 \(width) \(height)" position="\(width/2) \(height/2)" geometryFlipped="1">
            <sublayers><CALayer id="#1" name="Mirsa Photos" bounds="0 0 \(width) \(height)" position="\(width/2) \(height/2)">
            <sublayers>\(nodes)</sublayers></CALayer></sublayers>
            \(stateXML(effects.unlock, width: width, height: height))
            <style><wallpaperBackgroundAssetNames type="NSArray"/><wallpaperFloatingAssetNames type="NSArray"/>
            <wallpaperParallaxGroups type="NSArray">\(motionGroups)</wallpaperParallaxGroups></style>
            </CALayer></caml>
            """
            try Data(caml.utf8).write(to: ca.appendingPathComponent("main.caml"))
            try Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <caml xmlns="http://www.apple.com/CoreAnimation/1.0"><MicaAssetManifest><modules type="NSArray"/></MicaAssetManifest></caml>
            """.utf8).write(to: ca.appendingPathComponent("assetManifest.caml"))
            try plist(["rootDocument": "main.caml", "documentWidth": width, "documentHeight": height,
                       "documentResizesToView": true, "geometryFlipped": true,
                       "scalesToFitInPlayer": true, "unitsInPixelsInPlayer": true], to: ca.appendingPathComponent("index.xml"))
        }
        var route: [String: Any] = ["identifier": 7400, "name": "Mirsa"]
        if depth {
            route.merge(["type": "LayeredAnimation", "backgroundAnimationFileName": backgroundName,
                         "floatingAnimationFileNameKey": floatingName, "foregroundAnimationFileName": foregroundName]) { _, new in new }
        } else {
            route.merge(["type": "ParameterizedCA", "assetFileName": simpleName]) { _, new in new }
        }
        try plist(["assets": ["lockAndHome": ["default": route]], "family": depth ? "WWDC22" : "Marble",
                   "logicalScreenClass": "any", "appearanceAware": false, "identifier": 7400,
                   "version": depth ? 1 : 6, "contentVersion": "1.07", "name": "Mirsa",
                   "wantsDeviceMotion": effects.gyro], to: wallpaper.appendingPathComponent("Wallpaper.plist"))
        // Remove archive junk at every level before producing the package.
        if let files = fm.enumerator(at: descriptor, includingPropertiesForKeys: nil) {
            var junk: [URL] = []
            for case let file as URL in files {
                if file.lastPathComponent == "__MACOSX" || file.lastPathComponent == ".DS_Store" || file.lastPathComponent.hasPrefix("._") {
                    junk.append(file); files.skipDescendants()
                }
            }
            for file in junk { try fm.removeItem(at: file) }
        }
        let output = fm.temporaryDirectory.appendingPathComponent("Mirsa-" + UUID().uuidString + ".tendies")
        do { try PasscodeThemePackager.archiveDirectory(root, to: output) }
        catch { try? fm.removeItem(at: output); throw error }
        return output
    }

    private static func plist(_ value: [String: Any], to url: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: url)
    }

    static func stateXML(_ effect: Effects.Unlock, width: Int, height: Int) -> String {
        let key = effect == .slide ? "position" : "transform"
        func value(unlock: Bool) -> String {
            if effect == .slide { return "<value type=\"CGPoint\" value=\"\(width/2) \(height/2 + (unlock ? -30 : 0))\"/>" }
            let scale = unlock ? "1.06" : "1"
            return "<value type=\"CATransform3D\" value=\"scale(\(scale), \(scale), 1)\"/>"
        }
        let states = ["Locked", "Unlock", "Sleep"].map { state in
            "<LKState name=\"\(state)\"><elements>" +
            (effect == .none ? "" : "<LKStateSetValue targetId=\"#1\" keyPath=\"\(key)\" final=\"false\">\(value(unlock: state == "Unlock"))</LKStateSetValue>") +
            "</elements></LKState>"
        }.joined()
        let transitions = effect == .none ? "" : ["Locked", "Unlock", "Sleep"].flatMap { state in
            [("*", state), (state, "*")].map { from, to in
                """
                <LKStateTransition fromState="\(from)" toState="\(to)"><elements>
                <LKStateTransitionElement targetId="#1" key="\(key)"><animation type="CASpringAnimation" damping="50" mass="2" stiffness="300" velocity="0" duration="0.8" fillMode="backwards"/></LKStateTransitionElement>
                </elements></LKStateTransition>
                """
            }
        }.joined()
        return "<states>\(states)</states><stateTransitions>\(transitions)</stateTransitions>"
    }
}
