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
    /// A single image keeps its identity across lock/home/sleep; only state properties change.
    enum Scene: String, CaseIterable { case shared, lock, home }
    var scene: Scene = .shared
    enum Appearance: String, CaseIterable { case both, light, dark }
    var appearance: Appearance = .both
    var homeOffsetX: Double = 0
    var homeOffsetY: Double = 0
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
        var mechanism: WallpaperMechanism? = nil
        enum Unlock: String, CaseIterable { case none, zoom, slide }
        var unlock: Unlock = .none
        var gyro = false
        enum GyroStrength: Int, CaseIterable { case subtle = 12, medium = 24, strong = 40 }
        var gyroStrength: GyroStrength = .medium
        var floating = false
        enum Motion: String, CaseIterable { case left, right, up, down, float }
        var motion: Motion = .float
        var spin = false
        enum Particles: String, CaseIterable { case none, snow, leaves, stars }
        var particles: Particles = .none
        enum ParticleDirection: String, CaseIterable { case falling, rising }
        var particleDirection: ParticleDirection = .falling
        /// Sleep is a scene state, not a claim that iOS enables Always On for this package.
        var dimOnSleep = false
        var gradient = false
        var replicate = false
        enum Blend: String, CaseIterable { case normal, screen, overlay }
        var blend: Blend = .normal
        var blur = false
        var liquidGlass = false
    }

    static func usesReferenceEngine(layers: [WallpaperPhotoLayer], effects: Effects) -> Bool {
        effects.mechanism != nil || effects.gyro || effects.unlock != .none || effects.spin || effects.particles != .none ||
        effects.dimOnSleep || effects.gradient || effects.replicate || effects.blend != .normal || effects.blur || effects.liquidGlass || layers.contains { $0.appearance != .both || $0.scene != .shared || $0.homeOffsetX != 0 || $0.homeOffsetY != 0 }
    }

    static func makeArchive(layers: [WallpaperPhotoLayer], screenAspect: CGFloat,
                            crop: Bool = true, depth: Bool = false, effects: Effects = Effects()) throws -> URL {
        guard !layers.isEmpty, layers.count <= maximumLayers,
              Set(layers.map(\.id)).count == layers.count,
              screenAspect.isFinite, screenAspect >= 0.3, screenAspect <= 2 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let effects = try normalizedEffects(effects)
        let referenceEngine = usesReferenceEngine(layers: layers, effects: effects)
        // Every actual gyro reference uses ParameterizedCA. Never silently drop gyro or clock depth.
        guard !(depth && effects.gyro), !(effects.gyro && layers.contains { $0.appearance != .both }),
              layers.allSatisfy({ $0.homeOffsetX.isFinite && $0.homeOffsetY.isFinite &&
                  (-1...1).contains($0.homeOffsetX) && (-1...1).contains($0.homeOffsetY) }) else {
            throw CocoaError(.featureUnsupported)
        }
        let layered = !effects.gyro && (depth || effects.floating || referenceEngine)
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
        // Continuous presets use the on-device-confirmed envelope and point geometry.
        // Static export keeps its original variable-aspect route.
        let pointGeometry = referenceEngine || effects.floating
        let width = pointGeometry ? 390 : 1080
        let height = pointGeometry ? 844 : Int((CGFloat(width) / screenAspect / 2).rounded()) * 2
        let overscan = effects.floating || effects.gyro ? 40 : 0
        let size = CGSize(width: pointGeometry ? (width + overscan * 2) * 3 : width,
                          height: pointGeometry ? (height + overscan * 2) * 3 : height)
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
        let bundles: [(String, WallpaperPhotoLayer.Role?)] = layered
            ? [(backgroundName, .background), (floatingName, .middle), (foregroundName, .foreground)]
            : [(simpleName, nil)]
        for (name, role) in bundles {
            let ca = wallpaper.appendingPathComponent(name), assets = ca.appendingPathComponent("assets")
            try fm.createDirectory(at: assets, withIntermediateDirectories: true)
            var nodes = ""
            var stateLayers: [(Int, WallpaperPhotoLayer)] = []
            for (index, layer) in sorted.enumerated() {
                // With clock depth OFF, retain manual ordering in the background bundle.
                // Still emit the three documents required by the proven animation envelope.
                let exportRole: WallpaperPhotoLayer.Role = depth ? layer.role : .background
                guard role == nil || exportRole == role else { continue }
                try Task.checkCancellation()
                let filename = layer.id.uuidString + ".png"
                try autoreleasepool {
                    try render(layer.renderedImage, size: size, crop: crop && layer.crop, zoom: layer.zoom, x: layer.x, y: layer.y)
                        .write(to: assets.appendingPathComponent(filename))
                }
                if effects.mechanism?.rawValue == "property:contents" {
                    // A second bounded crop of the user's own source, not a copied animation asset.
                    try render(layer.renderedImage, size: size, crop: crop && layer.crop,
                               zoom: layer.zoom < 3.8 ? layer.zoom + 0.15 : layer.zoom - 0.15,
                               x: layer.x, y: layer.y)
                        .write(to: assets.appendingPathComponent(filename.replacingOccurrences(of: ".png", with: "-alternate.png")))
                }
                let layerName = "layer-\(index)-\(layer.role.rawValue)"
                let floatAnimation = effects.floating
                    ? continuousAnimation(role: layer.role, preset: effects.motion) : ""
                if referenceEngine {
                    stateLayers.append((index, layer))
                    nodes += referenceLayer(index: index, layer: layer, filename: filename, effects: effects)
                } else if effects.floating {
                    // Exact proven hierarchy: root -> state target #1 -> animated image.
                    // Do not add gyro wrappers or change the position-axis value types.
                    nodes += """
                    <CALayer id="#\(index + 2)" name="\(layerName)" bounds="0 0 470 924" position="195 422" contentsFormat="RGBA8">
                    <contents type="CGImage" src="assets/\(filename)"/>\(floatAnimation)
                    </CALayer>
                    """
                } else {
                    nodes += """
                    <CALayer name="motion-\(index)" bounds="0 0 \(width) \(height)" position="\(width/2) \(height/2)">
                    <sublayers><CALayer name="\(layerName)" bounds="0 0 \(width + overscan * 2) \(height + overscan * 2)" position="\(width/2) \(height/2)" contentsFormat="RGBA8">
                    <contents type="CGImage" src="assets/\(filename)"/>
                    </CALayer></sublayers></CALayer>
                    """
                }
            }
            if effects.gradient && (role == nil || role == .background) {
                if effects.mechanism?.rawValue == "class:CAGradientLayer" {
                    // Overlay tint stays observable even with a full-size opaque user photo.
                    nodes += gradientLayer().replacingOccurrences(of: "startPoint=", with: "opacity=\"0.28\" startPoint=")
                } else { nodes = gradientLayer() + nodes }
            }
            if effects.liquidGlass && (role == nil || role == .middle) { nodes += selectedGlass(effects) }
            if effects.particles != .none && (role == nil || role == .middle) {
                try particlePNG(effects.particles).write(to: assets.appendingPathComponent("mirsa-particle.png"))
                nodes += selectedParticles(effects)
            }
            if role == nil || role == .middle { nodes += mechanismDecorations(effects) }
            let caml: String
            if referenceEngine {
                caml = referenceDocument(nodes: nodes, layers: stateLayers, effects: effects)
            } else {
                let states = effects.floating ? continuousStates() : referenceStates(layers: [], effects: Effects())
                caml = """
                <?xml version="1.0" encoding="UTF-8"?>
                <caml xmlns="http://www.apple.com/CoreAnimation/1.0">
                <CALayer id="root" name="Root Layer" bounds="0 0 \(width) \(height)" position="\(width/2) \(height/2)" geometryFlipped="0">
                <sublayers><CALayer id="#1" name="Mirsa composition" bounds="0 0 \(width) \(height)" position="\(width/2) \(height/2)">
                <sublayers>\(nodes)</sublayers></CALayer></sublayers>\(states)
                </CALayer></caml>
                """
            }
            try Data(caml.utf8).write(to: ca.appendingPathComponent("main.caml"))
            try Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <caml xmlns="http://www.apple.com/CoreAnimation/1.0"><MicaAssetManifest><modules type="NSArray"/></MicaAssetManifest></caml>
            """.utf8).write(to: ca.appendingPathComponent("assetManifest.caml"))
            var index: [String: Any] = ["rootDocument": "main.caml"]
            if !effects.gyro {
                index.merge(["documentWidth": width, "documentHeight": height,
                    "documentResizesToView": !pointGeometry, "geometryFlipped": !pointGeometry,
                    "loopingEnabled": effects.floating || effects.spin || effects.mechanism != nil, "scalesToFitInPlayer": true,
                    "unitsInPixelsInPlayer": !pointGeometry]) { _, new in new }
                if pointGeometry {
                    index["assetManifest"] = "assetManifest.caml"
                    index["loopStart"] = 0.0
                    index["loopEnd"] = Double.infinity
                }
            }
            try plist(index, to: ca.appendingPathComponent("index.xml"))
        }
        var route: [String: Any] = ["identifier": 7400, "name": "Mirsa"]
        if layered {
            route.merge(["type": "LayeredAnimation", "backgroundAnimationFileName": backgroundName,
                         "floatingAnimationFileNameKey": floatingName, "foregroundAnimationFileName": foregroundName]) { _, new in new }
        } else {
            route.merge(["type": "ParameterizedCA", "assetFileName": simpleName]) { _, new in new }
        }
        try plist(["assets": ["lockAndHome": ["default": route]], "family": layered ? "WWDC22" : "Marble",
                   "logicalScreenClass": layered ? "390w-844h@3x~iphone" : "any", "appearanceAware": sorted.contains { $0.appearance != .both }, "identifier": 7400,
                   "version": layered ? 1 : 6, "contentVersion": "1.07", "name": "Mirsa",
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



    /// A catalogue selection owns its entire preset. Manual switches cannot hide an unsupported
    /// selection or accidentally combine incompatible loops. Layer geometry is still validated.
    static func normalizedEffects(_ input: Effects) throws -> Effects {
        guard let mechanism = input.mechanism else { return input }
        guard mechanism.isSupported else { throw CocoaError(.featureUnsupported) }
        var result = Effects(mechanism: mechanism)
        switch mechanism.rawValue {
        case "class:CATransformLayer":
            result.gyro = true; result.gyroStrength = .subtle
        case "class:wallpaperParallaxGroups":
            result.gyro = true
        case "class:wallpaperPropertyGroups":
            result.gyro = true; result.unlock = .slide
        case "class:LKState":
            result.unlock = .zoom
        case "type:CASpringAnimation":
            result.unlock = .slide
        case "class:CAGradientLayer":
            result.gradient = true
        case "class:CAReplicatorLayer":
            result.replicate = true
        case "class:CABackdropLayer", "class:CASDFLayer", "class:CASDFElementLayer",
             "filter:displacementMap", "type:CASDFGlassDisplacementEffect":
            result.liquidGlass = true
        case "class:CAEmitterLayer", "class:CAEmitterCell", "class:CAEmitterBehavior",
             "emitterMode:outline", "emitterMode:volume", "emitterShape:line",
             "emitterShape:point", "emitterShape:rectangle", "renderMode:additive", "renderMode:unordered":
            result.particles = .stars
        default: break
        }
        return result
    }

    /// Only fixed compiler-owned keys and finite numeric values enter this generator.
    /// No scripts, external source names, copied reference images or arbitrary XML input.
    static func mechanismImage(index: Int, layer: WallpaperPhotoLayer, filename: String,
                               effects: Effects, fallback: String) -> String {
        guard let mechanism = effects.mechanism else { return fallback }
        let key = mechanism.rawValue
        let id = "mechanism-\(index)"
        let contents = "<contents type=\"CGImage\" src=\"assets/\(filename)\"/>"
        var attributes = ""
        var children = contents
        let scalar: [String: (Double, Double)] = [
            "bounds.size.height": (844, 790), "bounds.size.width": (390, 354),
            "cornerRadius": (0, 90), "position.x": (195, 225), "position.y": (422, 462),
            "shadowOpacity": (0.2, 0.9), "transform.rotation.x": (-0.16, 0.16),
            "transform.rotation.y": (-0.22, 0.22), "transform.rotation.z": (-0.12, 0.12),
            "transform.scale": (1, 1.08), "transform.scale.x": (0.92, 1.08),
            "transform.scale.xy": (1, 1.12), "transform.translation.x": (-22, 22),
            "transform.translation.y": (-28, 28), "zPosition": (-20, 20)
        ]
        if key.hasPrefix("property:"), let values = scalar[String(key.dropFirst(9))] {
            let property = String(key.dropFirst(9))
            children += mechanismAnimation(property: property, values: [values.0, values.1, values.0])
            if property == "cornerRadius" { attributes += " masksToBounds=\"1\"" }
            if property == "shadowOpacity" {
                attributes += " shadowColor=\"0 0 0\" shadowRadius=\"24\" shadowOffset=\"0 16\""
                // An inset visible image edge makes the animated shadow observable.
                return "<CALayer id=\"\(id)\" name=\"\(id)\" bounds=\"0 0 350 804\" position=\"195 422\"\(attributes)>\(children)</CALayer>"
            }
        } else {
            switch key {
            case "property:bounds":
                children += mechanismVectorAnimation(property: "bounds", type: "CGRect",
                    values: ["0 0 390 844", "0 0 350 784", "0 0 390 844"])
            case "property:position":
                children += mechanismVectorAnimation(property: "position", type: "CGPoint",
                    values: ["195 422", "220 450", "195 422"])
            case "property:contents":
                let alternate = filename.replacingOccurrences(of: ".png", with: "-alternate.png")
                children += """
                <animations><animation type="CAKeyframeAnimation" key="mirsa-contents" keyPath="contents" beginTime="1e-100" duration="4" removedOnCompletion="0" repeatCount="inf" calculationMode="discrete">
                <values><CGImage src="assets/\(filename)"/><CGImage src="assets/\(alternate)"/><CGImage src="assets/\(filename)"/></values>
                <keyTimes><real value="0"/><real value="0.5"/><real value="1"/></keyTimes></animation></animations>
                """
            case "property:anchorPoint":
                attributes += " anchorPoint=\"0.35 0.5\""
                children += mechanismAnimation(property: "transform.rotation.z", values: [-0.08, 0.08, -0.08])
            case "property:backgroundColor":
                children = "<sublayers><CALayer name=\"mirsa-inset-photo\" bounds=\"0 0 342 796\" position=\"195 422\">\(contents)</CALayer></sublayers>"
                attributes += " backgroundColor=\"0.08 0.18 0.36\""
            case "property:continuousCorners":
                attributes += " continuousCorners=\"1\" cornerRadius=\"72\" masksToBounds=\"1\""
            case "property:masksToBounds":
                attributes += " masksToBounds=\"1\" cornerRadius=\"96\""
            case "property:speed":
                attributes += " speed=\"0.6\""
                children += mechanismAnimation(property: "transform.rotation.z", values: [0, 6.283185307179586])
            case "property:compositingFilter":
                children = "<compositingFilter type=\"CAFilter\" filter=\"screenBlendMode\" name=\"Mirsa screen\"/>" + children
            case "class:LKStateAddAnimation": break // serialized as a real state element below
            case "type:CABasicAnimation":
                children += """
                <animations><animation type="CABasicAnimation" key="mirsa-basic" keyPath="transform.translation.y" beginTime="1e-100" duration="3" autoreverses="1" removedOnCompletion="0" repeatCount="inf">
                <fromValue type="real" value="-18"/><toValue type="real" value="18"/></animation></animations>
                """
            case "type:CAKeyframeAnimation":
                children += mechanismAnimation(property: "transform.translation.x", values: [-24, 8, 24, -24])
            case "filter:Contrast 1":
                children = mechanismFilter("colorContrast", name: "Contrast 1", attributes: "inputAmount=\"1.45\"") + children
            case "filter:Gaussian Blur 1":
                children = mechanismFilter("gaussianBlur", name: "Gaussian Blur 1", attributes: "inputRadius=\"12\"") + children
            case "filter:Hue Rotate 1":
                children = mechanismFilter("colorHueRotate", name: "Hue Rotate 1", attributes: "inputAngle=\"0.8\"") + children
            case "filter:Saturate 1":
                children = mechanismFilter("colorSaturate", name: "Saturate 1", attributes: "inputAmount=\"1.8\"") + children
            case "filter:colorSaturate":
                children = mechanismFilter("colorSaturate", name: "colorSaturate", attributes: "inputAmount=\"0.25\"") + children
            case "filter:Sepia 1":
                children = "<filters><CIFilter filter=\"CISepiaTone\" name=\"Sepia 1\" enabled=\"true\"><inputIntensity type=\"real\" value=\"0.75\"/></CIFilter></filters>" + children
            case "filter:ciboxBlur":
                children = "<filters><CIFilter filter=\"CIBoxBlur\" name=\"ciboxBlur\"><inputRadius type=\"real\" value=\"8\"/></CIFilter></filters>" + children
            case "filter:cigaussianBlur":
                children = "<filters><CIFilter filter=\"CIGaussianBlur\" name=\"cigaussianBlur\"><inputRadius type=\"real\" value=\"10\"/></CIFilter></filters>" + children
            case "filter:cicolorControls":
                children = "<filters><CIFilter filter=\"CIColorControls\" name=\"cicolorControls\"><inputSaturation type=\"real\" value=\"0.4\"/><inputBrightness type=\"real\" value=\"0.05\"/><inputContrast type=\"real\" value=\"1.1\"/></CIFilter></filters>" + children
            case "type:CAFilter":
                children = "<compositingFilter type=\"CAFilter\" filter=\"overlayBlendMode\" name=\"Mirsa overlay\"/>" + children
            default: break
            }
        }
        return "<CALayer id=\"\(id)\" name=\"\(id)\" bounds=\"0 0 390 844\" position=\"195 422\" contentsFormat=\"RGBA8\"\(attributes)>\(children)</CALayer>"
    }

    static func mechanismFilter(_ filter: String, name: String, attributes: String) -> String {
        "<filters><CAFilter filter=\"\(filter)\" name=\"\(name)\" enabled=\"true\" \(attributes)/></filters>"
    }

    static func mechanismAnimation(property: String, values: [Double]) -> String {
        mechanismVectorAnimation(property: property, type: "real", values: values.map { String($0) })
    }

    static func mechanismVectorAnimation(property: String, type: String, values: [String]) -> String {
        let nodes = values.map { "<\(type) value=\"\($0)\"/>" }.joined()
        return """
        <animations><animation type="CAKeyframeAnimation" key="mirsa-mechanism" keyPath="\(property)" beginTime="1e-100" duration="8" removedOnCompletion="0" repeatCount="inf" repeatDuration="inf" calculationMode="linear"><values>\(nodes)</values></animation></animations>
        """
    }

    /// Non-interpolatable booleans and opacity use state assignments, never an infinite opacity loop.
    static func mechanismStateElements(index: Int, state: Int, effects: Effects) -> String {
        guard let raw = effects.mechanism?.rawValue else { return "" }
        let values: [String: (String, [String])] = [
            "property:anchorPoint": ("CGPoint", ["0.35 0.5", "0.65 0.5", "0.5 0.5"]),
            "property:backgroundColor": ("CGColor", ["0.08 0.18 0.36", "0.30 0.12 0.24", "0.02 0.04 0.08"]),
            "property:continuousCorners": ("integer", ["1", "0", "1"]),
            "property:hidden": ("integer", ["0", "0", "1"]),
            "property:masksToBounds": ("integer", ["1", "0", "1"]),
            "property:opacity": ("real", ["1", "0.8", "0.3"]),
            "property:speed": ("real", ["0.6", "1.4", "0.2"])
        ]
        if let entry = values[raw] {
            return "<LKStateSetValue targetId=\"mechanism-\(index)\" keyPath=\"\(raw.dropFirst(9))\"><value type=\"\(entry.0)\" value=\"\(entry.1[state])\"/></LKStateSetValue>"
        }
        if raw == "property:compositingFilter" {
            // A missing value is the observed native reset-to-default assignment in Sleep.
            return state == 2 ? "<LKStateSetValue targetId=\"mechanism-\(index)\" keyPath=\"compositingFilter\"/>" : ""
        }
        if raw == "class:LKStateAddAnimation", state == 1 {
            return """
            <LKStateAddAnimation targetId="mechanism-\(index)" key="mirsa-state-entry">
            <animation type="CASpringAnimation" keyPath="transform.translation.y" beginTime="1e-100" duration="1" mass="1" stiffness="100" damping="16" removedOnCompletion="1">
            <fromValue type="real" value="32"/><toValue type="real" value="0"/></animation></LKStateAddAnimation>
            """
        }
        return ""
    }

    static func mechanismDecorations(_ effects: Effects) -> String {
        guard effects.mechanism?.rawValue == "class:CATextLayer" else { return "" }
        return """
        <CATextLayer id="mirsa-text" name="Mirsa text" bounds="0 0 260 52" position="195 650" fontSize="30" foregroundColor="1 1 1" alignmentMode="center" wrapped="0" contentsScale="3">
        <font type="string" value="SFProText-Regular"/><string type="string" value="Mirsa"/></CATextLayer>
        """
    }

    static func selectedGlass(_ effects: Effects) -> String {
        let base = liquidGlassLayer()
        // Distinct class-focused recipes vary the actual geometry/effect, never just labels.
        switch effects.mechanism?.rawValue {
        case "class:CABackdropLayer": return base.replacingOccurrences(of: "inputAmount=\"-80\"", with: "inputAmount=\"-24\"")
        case "class:CASDFLayer": return base.replacingOccurrences(of: "height=\"40\"", with: "height=\"20\"")
        case "class:CASDFElementLayer": return base.replacingOccurrences(of: "cornerRadius=\"60\"", with: "cornerRadius=\"28\"")
        case "filter:displacementMap": return base.replacingOccurrences(of: "inputAmount=\"-80\"", with: "inputAmount=\"-56\"")
        default: return base
        }
    }

    static func selectedParticles(_ effects: Effects) -> String {
        var xml = particleLayer(effects.particles, direction: effects.particleDirection)
        switch effects.mechanism?.rawValue {
        case "class:CAEmitterCell":
            xml = xml.replacingOccurrences(of: "lifetime=\"5\"", with: "lifetime=\"3\"")
                .replacingOccurrences(of: "scale=\"0.08\"", with: "scale=\"0.14\"")
        case "emitterMode:outline":
            xml = xml.replacingOccurrences(of: "emitterMode=\"volume\"", with: "emitterMode=\"outline\"")
                .replacingOccurrences(of: "emitterShape=\"point\"", with: "emitterShape=\"rectangle\"")
                .replacingOccurrences(of: "emitterSize=\"0 0\"", with: "emitterSize=\"300 500\"")
        case "emitterMode:volume":
            xml = xml.replacingOccurrences(of: "emitterShape=\"point\"", with: "emitterShape=\"rectangle\"")
                .replacingOccurrences(of: "emitterSize=\"0 0\"", with: "emitterSize=\"260 420\"")
        case "emitterShape:line":
            xml = xml.replacingOccurrences(of: "emitterShape=\"point\"", with: "emitterShape=\"line\"")
                .replacingOccurrences(of: "emitterSize=\"0 0\"", with: "emitterSize=\"300 0\"")
        case "emitterShape:point":
            xml = xml.replacingOccurrences(of: "emitterPosition=\"-20 0\"", with: "emitterPosition=\"195 160\"")
        case "emitterShape:rectangle":
            xml = xml.replacingOccurrences(of: "emitterShape=\"point\"", with: "emitterShape=\"rectangle\"")
                .replacingOccurrences(of: "emitterSize=\"0 0\"", with: "emitterSize=\"300 120\"")
        case "renderMode:additive":
            xml = xml.replacingOccurrences(of: "renderMode=\"unordered\"", with: "renderMode=\"additive\"")
        case "renderMode:unordered":
            xml = xml.replacingOccurrences(of: "birthRate=\"10\"", with: "birthRate=\"16\"")
        default: break
        }
        return xml
    }

    // Structure-only study at CAPlayground/wallpapers@799fcf81d51dd04b9b8248830959eb1f7fe24d57.
    // No community artwork or external URLs are emitted. All sources are generated UUID assets.
    // Manosaba_Gyro: ParameterizedCA, named transform layers, typed style dictionaries.
    // Hatsune-Miku: per-image Locked/Unlock/Sleep numeric assignments with stable identities.
    // spiderman/Mario_Galaxy_Movie: timed loops coexist with parameter groups.
    // Snow_Emitters/Autumn_Horizon: CAEmitterLayer + CAEmitterCell + local CGImage.
    static func referenceLayer(index: Int, layer: WallpaperPhotoLayer, filename: String, effects: Effects) -> String {
        let pad = effects.gyro || effects.floating ? 40 : 0
        let motion = effects.floating ? continuousAnimation(role: layer.role, preset: effects.motion) : ""
        let spin = effects.spin ? spinAnimation() : ""
        let blend = effects.blend == .normal ? "" :
            "<compositingFilter type=\"CAFilter\" filter=\"\(effects.blend.rawValue)BlendMode\" name=\"Mirsa blend\"/>"
        let blur = effects.blur ? "<filters><CAFilter filter=\"gaussianBlur\" name=\"Mirsa blur\" enabled=\"true\" inputRadius=\"12\"/></filters>" : ""
        let replicaOpen = effects.replicate ? "<CAReplicatorLayer name=\"mirsa-replicator-\(index)\" bounds=\"0 0 390 844\" position=\"195 422\" instanceCount=\"6\" instanceDelay=\"0\" instanceTransform=\"rotate(60deg)\" preservesDepth=\"1\"><sublayers>" : ""
        let replicaClose = effects.replicate ? "</sublayers></CAReplicatorLayer>" : ""
        let image = """
        <CALayer name="layer-\(index)-\(layer.role.rawValue)" bounds="0 0 \(390 + pad * 2) \(844 + pad * 2)" position="195 422" contentsFormat="RGBA8">
        \(blend)\(blur)<contents type="CGImage" src="assets/\(filename)"/>
        </CALayer>
        """
        let selectedImage = mechanismImage(index: index, layer: layer, filename: filename, effects: effects, fallback: image)
        // Position state, gyro translation, timed float and spin get DIFFERENT nodes.
        // A home transition must not fight an infinite position animation on the same property.
        return """
        <CATransformLayer id="state-\(index)" name="state-\(index)" bounds="0 0 390 844" position="195 422">
        <sublayers><CATransformLayer id="gyro-\(index)" name="gyro-\(index)" bounds="0 0 390 844" position="195 422">
        <sublayers><CALayer id="float-\(index)" name="float-\(index)" bounds="0 0 390 844" position="195 422">
        \(motion)<sublayers><CALayer id="spin-\(index)" name="spin-\(index)" bounds="0 0 390 844" position="195 422">
        \(spin)<sublayers>\(replicaOpen)\(selectedImage)\(replicaClose)</sublayers></CALayer></sublayers></CALayer></sublayers></CATransformLayer></sublayers></CATransformLayer>
        """
    }

    static func spinAnimation() -> String {
        """
        <animations><animation type="CAKeyframeAnimation" key="mirsa-spin" keyPath="transform.rotation.z" beginTime="1e-100" duration="16" removedOnCompletion="0" repeatCount="inf" repeatDuration="inf" calculationMode="linear">
        <values><real value="0"/><real value="\(Double.pi * 2)"/></values>
        </animation></animations>
        """
    }

    /// Shared layer offsets are explicit state changes, not inferred artwork/magic image recognition.
    static func sceneValues(layer: WallpaperPhotoLayer, effects: Effects) -> [(String, Double, Double, Double)] {
        let cx = 195.0, cy = 422.0
        let lockOnly = layer.scene == .lock
        let homeOnly = layer.scene == .home
        let slide = effects.unlock == .slide ? 844.0 : 0
        let lockedY = homeOnly ? cy + slide : cy + (lockOnly ? 0 : slide / 20)
        let homeY = lockOnly ? cy - slide : cy + layer.homeOffsetY * 422
        let scale = effects.unlock == .zoom ? 1.06 : 1.0
        return [
            ("position.x", cx, cx + layer.homeOffsetX * 195, cx),
            ("position.y", lockedY, homeY, lockedY),
            ("transform.scale.xy", scale, 1, scale),
            ("opacity", homeOnly ? 0 : 1, lockOnly ? 0 : 1, homeOnly ? 0 : (effects.dimOnSleep ? 0.25 : 1))
        ]
    }

    static func referenceDocument(nodes: String, layers: [(Int, WallpaperPhotoLayer)], effects: Effects) -> String {
        let states = effects.gyro ? "" : referenceStates(layers: layers, effects: effects)
        let style = effects.gyro ? referenceStyle(layers: layers, effects: effects) : ""
        let children: String
        if effects.gyro {
            children = """
            <CALayer id="background" name="BACKGROUND" bounds="0 0 390 844" position="195 422"/>
            <CALayer id="floating" name="FLOATING" bounds="0 0 390 844" position="195 422" geometryFlipped="0">
            <sublayers>\(nodes)</sublayers></CALayer>
            """
        } else {
            children = """
            <CALayer id="#1" name="Mirsa composition" bounds="0 0 390 844" position="195 422">
            <sublayers>\(nodes)</sublayers></CALayer>
            """
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <caml xmlns="http://www.apple.com/CoreAnimation/1.0">
        <CALayer id="root" name="Root Layer" bounds="0 0 390 844" position="195 422" geometryFlipped="0">
        \(style)<sublayers>\(children)</sublayers>\(states)
        </CALayer></caml>
        """
    }

    static func referenceStyle(layers: [(Int, WallpaperPhotoLayer)], effects: Effects) -> String {
        let gyro = layers.map { index, layer in
            let rank = layer.role == .background ? 0.4 : layer.role == .middle ? 0.7 : 1.0
            let amount = Int(Double(effects.gyroStrength.rawValue) * rank)
            return ["x", "y"].map { axis in
                """
                <NSDictionary><axis type="string" value="\(axis)"/><image type="string" value="null"/>
                <keyPath type="string" value="transform.translation.\(axis)"/><layerName type="string" value="gyro-\(index)"/>
                <mapMaxTo type="integer" value="\(amount)"/><mapMinTo type="integer" value="-\(amount)"/>
                <title type="string" value="Mirsa motion"/><view type="string" value="Floating"/></NSDictionary>
                """
            }.joined()
        }.joined()
        let properties = layers.map { index, layer in
            sceneValues(layer: layer, effects: effects).map { key, lock, home, sleep in
                """
                <NSDictionary><image type="null"/><keyPath type="string" value="\(key)"/>
                <layerName type="string" value="state-\(index)"/><v_home type="integer" value="\(home)"/>
                <v_lock type="integer" value="\(lock)"/><v_sleep type="integer" value="\(sleep)"/>
                <view type="string" value="Floating"/></NSDictionary>
                """
            }.joined()
        }.joined()
        return """
        <style><wallpaperParallaxGroups type="NSArray">\(gyro)</wallpaperParallaxGroups>
        <wallpaperPropertyGroups type="NSArray">\(properties)</wallpaperPropertyGroups></style>
        """
    }

    static func referenceStates(layers: [(Int, WallpaperPhotoLayer)], effects: Effects) -> String {
        let baseNames = ["Locked", "Unlock", "Sleep"]
        let variants: [String?] = layers.contains { $0.1.appearance != .both } ? ["Light", "Dark"] : [nil]
        // A7X_dark_and_light_wallpaper: Locked/Unlock/Sleep + Light/Dark state suffixes.
        // This follows the system appearance, NOT an invented clock/sunrise trigger.
        let names: [(Int, String, String?)] = variants.flatMap { variant in
            baseNames.enumerated().map { index, base in
                (index, base + (variant.map { " " + $0 } ?? ""), variant)
            }
        }
        let states = names.map { stateIndex, name, appearance in
            let assignments = layers.map { index, layer in
                let sceneAssignments = sceneValues(layer: layer, effects: effects).map { key, lock, home, sleep in
                    var value = [lock, home, sleep][stateIndex]
                    if key == "opacity", let appearance,
                       layer.appearance != .both, layer.appearance.rawValue.lowercased() != appearance.lowercased() {
                        value = 0
                    }
                    return """
                    <LKStateSetValue targetId="state-\(index)" keyPath="\(key)">
                    <value type="real" value="\(value)"/></LKStateSetValue>
                    """
                }.joined()
                return sceneAssignments + mechanismStateElements(index: index, state: stateIndex, effects: effects)
            }.joined()
            return """
            <LKState name="\(name)" initial="\(stateIndex == 0 && appearance != "Dark")" final="false"><elements>\(assignments)</elements></LKState>
            """
        }.joined()
        let transitions = names.flatMap { _, state, _ in
            [("*", state), (state, "*")].map { from, to in
                let elements = layers.map { index, layer in
                    sceneValues(layer: layer, effects: effects).map { key, _, _, _ in
                        """
                        <LKStateTransitionElement targetId="state-\(index)" key="\(key)">
                        <animation type="CASpringAnimation" keyPath="\(key)" mass="1" stiffness="120" damping="20" duration="0.8"/>
                        </LKStateTransitionElement>
                        """
                    }.joined()
                }.joined()
                return """
                <LKStateTransition fromState="\(from)" toState="\(to)"><elements>\(elements)</elements></LKStateTransition>
                """
            }
        }.joined()
        return "<states>\(states)</states><stateTransitions>\(transitions)</stateTransitions>"
    }

    /// Zoro/discord use a native CAGradientLayer; these colours are ours.
    static func gradientLayer() -> String {
        """
        <CAGradientLayer id="mirsa-gradient" name="Mirsa gradient" bounds="0 0 390 844" position="195 422" startPoint="0 0" endPoint="1 1">
        <colors><CGColor value="0.04 0.08 0.18"/><CGColor value="0.20 0.12 0.36"/></colors><type value="axial"/>
        </CAGradientLayer>
        """
    }

    /// Minecraft_Liquid_Glass__beta_: displacementMap driven by an SDF glass effect.
    /// This is deliberately not relabelled blur. Requires device verification before delivery.
    static func liquidGlassLayer() -> String {
        """
        <CABackdropLayer id="mirsa-glass" name="Mirsa glass" bounds="0 0 120 120" position="195 422" cornerRadius="60" caplayKind="liquidGlass">
        <filters><CAFilter filter="displacementMap" name="displacementMap" inputSourceSublayerName="sdfLayer" inputOffset="0 0" inputAmount="-80"/></filters>
        <sublayers><CASDFLayer id="mirsa-sdf" name="sdfLayer" bounds="0 0 120 120" position="60 60" contentsFormat="RGBA8" cornerCurve="circular">
        <effect type="CASDFGlassDisplacementEffect" height="40" maskOffset="0"/>
        <sublayers><CASDFElementLayer id="mirsa-sdf-element" name="elementLayer" bounds="0 0 120 120" position="60 60" cornerRadius="60" cornerCurve="continuous" contentsFormat="RGBA8"/></sublayers>
        </CASDFLayer></sublayers></CABackdropLayer>
        """
    }

    static func particleLayer(_ kind: Effects.Particles, direction: Effects.ParticleDirection = .falling) -> String {
        // The reference envelopes differ in flipped geometry. Keep a single matched snow envelope;
        // leaf/star choices change only our original bitmap, not an invented unsupported cell type.
        let rising = direction == .rising
        let rate = kind == .leaves ? 3 : 10
        // Mr_krabs_drowning uses unflipped geometry, a bottom emitter and negative acceleration.
        let flipped = rising ? 0 : 1
        let emitter = rising ? "195 840" : "-20 0"
        let acceleration = rising ? -100 : 200
        let xAcceleration = rising ? 0 : 100
        let speed = kind == .leaves ? 80 : 200
        return """
        <CAEmitterLayer id="mirsa-emitter" name="Mirsa particles" bounds="0 0 390 844" position="195 422" geometryFlipped="\(flipped)" emitterPosition="\(emitter)" emitterSize="0 0" emitterShape="point" emitterMode="volume" renderMode="unordered" birthRate="1">
        <emitterCells><CAEmitterCell name="Mirsa particle" birthRate="\(rate)" lifetime="5" velocity="\(speed)" emissionRange="3.490658503988659" scale="0.08" spin="0.3490658503988659" xAcceleration="\(xAcceleration)" yAcceleration="\(acceleration)">
        <contents><CGImage src="assets/mirsa-particle.png"/></contents>
        </CAEmitterCell></emitterCells></CAEmitterLayer>
        """
    }

    /// Original procedural art only, no downloaded symbol image or community artwork.
    static func particlePNG(_ kind: Effects.Particles) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128), format: format).pngData { context in
            let cg = context.cgContext
            if kind == .leaves {
                UIColor.systemOrange.setFill()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 12, y: 116))
                path.addCurve(to: CGPoint(x: 116, y: 12), controlPoint1: CGPoint(x: 0, y: 10), controlPoint2: CGPoint(x: 90, y: 0))
                path.addCurve(to: CGPoint(x: 12, y: 116), controlPoint1: CGPoint(x: 125, y: 100), controlPoint2: CGPoint(x: 70, y: 128))
                path.fill()
            } else if kind == .stars {
                UIColor.white.setFill()
                let path = UIBezierPath()
                for i in 0..<10 {
                    let angle = Double(i) * Double.pi / 5 - Double.pi / 2
                    let radius = i.isMultiple(of: 2) ? 56.0 : 24.0
                    let point = CGPoint(x: 64 + cos(angle) * radius, y: 64 + sin(angle) * radius)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.close(); path.fill()
            } else {
                UIColor.white.setFill()
                cg.fillEllipse(in: CGRect(x: 12, y: 12, width: 104, height: 104))
            }
        }
    }

    /// Exact two-real endpoint axis layout from the confirmed Jellyfish-v2 recipe.
    /// Foreground moves faster/further; no opacity animations or downloaded code.
    static func continuousAnimation(role: WallpaperPhotoLayer.Role, preset: Effects.Motion) -> String {
        let dx: Int, dy: Int, tx: Int, ty: Int
        switch role {
        case .background: (dx, dy, tx, ty) = (4, 3, 18, 23)
        case .middle: (dx, dy, tx, ty) = (13, 7, 12, 15)
        case .foreground: (dx, dy, tx, ty) = (28, 12, 8, 11)
        }
        func axis(_ key: String, center: Int, amplitude: Int, duration: Int, reverse: Bool = false) -> String {
            let tag = key == "position.y" ? "animation" : "p"
            let extra = tag == "animation" ? "" : " key=\"animation-1\" beginTimeMode=\"absolute\""
            let start = center + (reverse ? amplitude : -amplitude)
            let end = center + (reverse ? -amplitude : amplitude)
            return """
            <\(tag)\(extra) type="CAKeyframeAnimation" keyPath="\(key)" autoreverses="1" beginTime="1e-100" duration="\(duration)" removedOnCompletion="0" repeatCount="inf" repeatDuration="inf"><values><real value="\(start)"/><real value="\(end)"/></values></\(tag)>
            """
        }
        let horizontal = preset == .float || preset == .left || preset == .right
        let vertical = preset == .float || preset == .up || preset == .down
        return "<animations>" +
            (vertical ? axis("position.y", center: 422, amplitude: dy, duration: ty, reverse: preset == .up) : "") +
            (horizontal ? axis("position.x", center: 195, amplitude: dx, duration: tx, reverse: preset == .left) : "") +
            "</animations>"
    }

    /// State assignments and six springs copied from the confirmed layered builder.
    /// These move the parent only; the child keeps looping in Locked/Unlock/Sleep.
    static func continuousStates() -> String {
        let names = ["Locked", "Unlock", "Sleep"]
        let states = names.map { state in
            "<LKState name=\"\(state)\"><elements><LKStateSetValue final=\"false\" targetId=\"#1\" keyPath=\"position\"><value type=\"CGPoint\" value=\"195 422\"/></LKStateSetValue></elements></LKState>"
        }.joined()
        let transitions = names.flatMap { state in
            [("*", state), (state, "*")].map { from, to in
                """
                <LKStateTransition fromState="\(from)" toState="\(to)"><elements><LKStateTransitionElement final="false" key="position" targetId="#1"><animation type="CASpringAnimation" keyPath="position" damping="50" mass="2" stiffness="300" velocity="0" duration="0.8" fillMode="backwards"/></LKStateTransitionElement></elements></LKStateTransition>
                """
            }
        }.joined()
        return "<states>\(states)</states><stateTransitions>\(transitions)</stateTransitions>"
    }

    private static func plist(_ value: [String: Any], to url: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: url)
    }

}
