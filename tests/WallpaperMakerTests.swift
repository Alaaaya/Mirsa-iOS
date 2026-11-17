import XCTest
import UIKit
import AVFoundation
import ZIPFoundation
@testable import Mirsa

final class WallpaperMakerTests: XCTestCase {
    private func photo(_ color: UIColor = .red, transparent: Bool = false) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 96), format: format).image { c in
            color.setFill()
            c.fill(transparent ? CGRect(x: 16, y: 16, width: 32, height: 32) : CGRect(x: 0, y: 0, width: 64, height: 96))
        }
    }
    private func recordEvidence(_ archive: URL, name: String) throws {
        let path = ProcessInfo.processInfo.environment["MIRSA_WALLPAPER_EVIDENCE"] ??
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("wallpaper-evidence").path
        let root = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(name + ".tendies")
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: archive, to: destination)
        let files = try unpack(archive)
        var alpha: [String: Bool] = [:]
        for (path, data) in files where path.hasSuffix(".png") {
            alpha[path] = WallpaperForeground.hasTransparency(try XCTUnwrap(UIImage(data: data)?.cgImage))
        }
        let proof: [String: Any] = ["listing": files.keys.sorted(), "alpha": alpha,
                                    "galleryRegistrationVerified": false, "realVisionSegmentation": false,
                                    "devicePlaybackVerified": false]
        try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent(name + ".json"))
    }
    private func unpack(_ url: URL) throws -> [String: Data] {
        let archive = try Archive(url: url, accessMode: .read)
        var output: [String: Data] = [:]
        for entry in archive where entry.type == .file {
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            output[entry.path] = data
        }
        return output
    }
    private func file(_ suffix: String, in files: [String: Data]) throws -> Data {
        let matches = files.filter { $0.key.hasSuffix(suffix) }
        XCTAssertEqual(matches.count, 1, suffix)
        return try XCTUnwrap(matches.first?.value)
    }
    func testRealPhotoArchiveHasDescriptorAndPNG() throws {
        let layer = WallpaperPhotoLayer(image: photo())
        let url = try PhotoWallpaper.makeArchive(layers: [layer], screenAspect: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "tendies")
        let files = try unpack(url)
        XCTAssertTrue(files.keys.allSatisfy { $0.hasPrefix("Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors/") })
        XCTAssertNotNil(try file("providerInfo.plist", in: files))
        let caml = String(decoding: try file(PhotoWallpaper.simpleName + "/main.caml", in: files), as: UTF8.self)
        XCTAssertTrue(caml.contains("layer-0-background"))
        let png = try file(PhotoWallpaper.simpleName + "/assets/\(layer.id.uuidString).png", in: files)
        XCTAssertNotNil(UIImage(data: png))
        XCTAssertTrue(caml.contains("assets/\(layer.id.uuidString).png"))
        let index = try PropertyListSerialization.propertyList(from: file(PhotoWallpaper.simpleName + "/index.xml", in: files), format: nil) as? [String: Any]
        XCTAssertEqual(index?["documentWidth"] as? Int, 1080)
        XCTAssertEqual(index?["documentHeight"] as? Int, 2160)
    }
    func testRealMultilayerArchiveSeparateLayersRolesAndAlpha() throws {
        let photos: [WallpaperPhotoLayer] = [.init(image: photo(.blue)),
            .init(image: photo(.green, transparent: true), role: .middle),
            .init(image: photo(.red, transparent: true), role: .foreground)]
        let url = try PhotoWallpaper.makeArchive(layers: photos, screenAspect: 0.5, depth: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let files = try unpack(url)
        let bg = String(decoding: try file(PhotoWallpaper.backgroundName + "/main.caml", in: files), as: UTF8.self)
        let mid = String(decoding: try file(PhotoWallpaper.floatingName + "/main.caml", in: files), as: UTF8.self)
        let fg = String(decoding: try file(PhotoWallpaper.foregroundName + "/main.caml", in: files), as: UTF8.self)
        XCTAssertTrue(bg.contains("layer-0-background")); XCTAssertTrue(mid.contains("layer-1-middle"))
        XCTAssertFalse(bg.contains("layer-1-middle"))
        XCTAssertFalse(bg.contains("layer-2-foreground")); XCTAssertTrue(fg.contains("layer-2-foreground"))
        XCTAssertEqual(files.keys.filter { $0.hasSuffix(".png") }.count, 3)
        let png = try file(PhotoWallpaper.foregroundName + "/assets/\(photos[2].id.uuidString).png", in: files)
        let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
        XCTAssertNotEqual(image.alphaInfo, .none)
        let bytes = try XCTUnwrap(image.dataProvider?.data) as Data
        // Top-left is transparent; do not flatten user cutouts onto black.
        XCTAssertEqual(bytes.prefix(4), Data([0, 0, 0, 0]))
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: file("/Wallpaper.plist", in: files), format: nil) as? [String: Any])
        let assets = try XCTUnwrap(plist["assets"] as? [String: Any])
        let both = try XCTUnwrap(assets["lockAndHome"] as? [String: Any])
        let spec = try XCTUnwrap(both["default"] as? [String: Any])
        XCTAssertEqual(spec["backgroundAnimationFileName"] as? String, PhotoWallpaper.backgroundName)
        XCTAssertEqual(spec["floatingAnimationFileNameKey"] as? String, PhotoWallpaper.floatingName)
        XCTAssertEqual(spec["foregroundAnimationFileName"] as? String, PhotoWallpaper.foregroundName)
        XCTAssertEqual(spec["type"] as? String, "LayeredAnimation")
    }
    func testDepthDefaultOffKeepsEveryLayerInSingleBundleInManualOrder() throws {
        let layers: [WallpaperPhotoLayer] = [.init(image: photo(), role: .foreground), .init(image: photo(.blue))]
        let url = try PhotoWallpaper.makeArchive(layers: layers, screenAspect: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let files = try unpack(url)
        let caml = String(decoding: try file(PhotoWallpaper.simpleName + "/main.caml", in: files), as: UTF8.self)
        XCTAssertTrue(caml.contains("layer-0-foreground")); XCTAssertTrue(caml.contains("layer-1-background"))
        XCTAssertFalse(files.keys.contains { $0.contains(PhotoWallpaper.foregroundName) })
        XCTAssertEqual(PhotoWallpaper.ordered(layers, depth: false).map(\.id), layers.map(\.id))
    }
    private func checkBundle(_ name: String, count: Int, files: [String: Data]) throws -> String {
        let caml = try file(name + "/main.caml", in: files)
        XCTAssertTrue(XMLParser(data: caml).parse())
        let manifest = try file(name + "/assetManifest.caml", in: files)
        XCTAssertTrue(XMLParser(data: manifest).parse())
        XCTAssertTrue(String(decoding: manifest, as: UTF8.self).contains("MicaAssetManifest"))
        let index = try PropertyListSerialization.propertyList(from: file(name + "/index.xml", in: files), format: nil) as! [String: Any]
        XCTAssertEqual(index["rootDocument"] as? String, "main.caml")
        let assets = files.filter { $0.key.contains(name + "/assets/") }
        XCTAssertEqual(assets.count, count)
        let xml = String(decoding: caml, as: UTF8.self)
        for (path, bytes) in assets {
            XCTAssertNotNil(UIImage(data: bytes))
            XCTAssertTrue(xml.contains("src=\"assets/\(URL(fileURLWithPath: path).lastPathComponent)\""))
        }
        if !xml.contains("wallpaperPropertyGroups") {
            for state in ["Locked", "Unlock", "Sleep"] { XCTAssertTrue(xml.contains("LKState name=\"\(state)\"")) }
        }
        return xml
    }
    func testBothVariantsCompleteMetadataEveryReferencedAssetAndFreshIDs() throws {
        let photos: [WallpaperPhotoLayer] = [.init(image: photo()), .init(image: photo(.blue), role: .middle),
                                            .init(image: photo(.green, transparent: true), role: .foreground)]
        var identifiers = Set<String>()
        for depth in [false, true] {
            let url = try PhotoWallpaper.makeArchive(layers: photos, screenAspect: 0.5, depth: depth)
            defer { try? FileManager.default.removeItem(at: url) }
            let files = try unpack(url)
            XCTAssertFalse(files.keys.contains { $0.contains("__MACOSX") || $0.hasSuffix(".DS_Store") || URL(fileURLWithPath: $0).lastPathComponent.hasPrefix("._") })
            let component = try XCTUnwrap(files.keys.first).split(separator: "/")[3]
            let uuid = String(component)
            XCTAssertNotNil(UUID(uuidString: uuid)); XCTAssertTrue(identifiers.insert(uuid).inserted)
            for path in [
                "providerInfo.plist", "com.apple.posterkit.role.identifier", "com.apple.posterkit.provider.descriptor.identifier",
                "com.apple.posterkit.provider.identifierURL.suggestionMetadata.plist",
                "versions/1/com.apple.posterkit.provider.instance.complicationLayout.plist",
                "versions/1/com.apple.posterkit.provider.instance.titleStyleConfiguration.plist",
                "versions/1/supplements/0/com.apple.posterkit.provider.supplementURL.homescreenConfiguration.plist",
                "versions/1/contents/com.apple.posterkit.provider.contents.otherMetadata.plist",
                "versions/1/contents/.com.apple.posterkit.provider.contents.configurableOptions.plist"
            ] { XCTAssertNotNil(try file(path, in: files)) }
            let suggestion = try PropertyListSerialization.propertyList(from: file("com.apple.posterkit.provider.identifierURL.suggestionMetadata.plist", in: files), format: nil) as! [String: Any]
            XCTAssertTrue((suggestion["$objects"] as! [Any]).contains { ($0 as? String) == uuid })
            let info = try PropertyListSerialization.propertyList(from: file("com.apple.posterkit.provider.contents.userInfo", in: files), format: nil) as! [String: Any]
            XCTAssertEqual(info["wallpaperRepresentingFileName"] as? String, PhotoWallpaper.wallpaperName)
            let plist = try PropertyListSerialization.propertyList(from: file("/Wallpaper.plist", in: files), format: nil) as! [String: Any]
            XCTAssertEqual(plist["wantsDeviceMotion"] as? Bool, false)
            let route = ((plist["assets"] as! [String: Any])["lockAndHome"] as! [String: Any])["default"] as! [String: Any]
            if depth {
                XCTAssertEqual(route["type"] as? String, "LayeredAnimation")
                for name in [PhotoWallpaper.backgroundName, PhotoWallpaper.floatingName, PhotoWallpaper.foregroundName] {
                    _ = try checkBundle(name, count: 1, files: files)
                }
            } else {
                XCTAssertEqual(route["type"] as? String, "ParameterizedCA")
                XCTAssertEqual(route["assetFileName"] as? String, PhotoWallpaper.simpleName)
                let caml = try checkBundle(PhotoWallpaper.simpleName, count: 3, files: files)
                XCTAssertFalse(caml.contains("LKStateTransitionElement"))
                XCTAssertFalse(caml.contains("CAKeyframeAnimation"))
                XCTAssertFalse(caml.contains("<NSDictionary>"))
            }
        }
    }
    func testEveryEffectInBothGeneratedArchiveVariants() throws {
        for depth in [false, true] {
            for effect in [PhotoWallpaper.Effects(unlock: .zoom),
                           PhotoWallpaper.Effects(unlock: .slide),
                           PhotoWallpaper.Effects(gyro: true),
                           PhotoWallpaper.Effects(floating: true),
                           PhotoWallpaper.Effects(unlock: .zoom, gyro: true, floating: true)] {
                let layer = WallpaperPhotoLayer(image: photo(), role: .middle)
                if depth && effect.gyro {
                    XCTAssertThrowsError(try PhotoWallpaper.makeArchive(layers: [layer], screenAspect: 0.5,
                                                                        depth: depth, effects: effect))
                    continue
                }
                let url = try PhotoWallpaper.makeArchive(layers: [layer], screenAspect: 0.5, depth: depth, effects: effect)
                defer { try? FileManager.default.removeItem(at: url) }
                let files = try unpack(url)
                let bundle = effect.gyro ? PhotoWallpaper.simpleName :
                    depth ? PhotoWallpaper.floatingName : PhotoWallpaper.backgroundName
                let caml = try checkBundle(bundle, count: 1, files: files)
                XCTAssertEqual(caml.contains("CASpringAnimation"), !effect.gyro)
                if effect.unlock != .none {
                    XCTAssertTrue(caml.contains(effect.unlock == .slide ? "position.y" : "transform.scale.xy"))
                    XCTAssertFalse(caml.contains("CATransform3D"))
                }
                XCTAssertEqual(caml.contains("CAKeyframeAnimation"), effect.floating)
                if effect.floating {
                    XCTAssertTrue(caml.contains("duration=\"15\""))
                    XCTAssertTrue(caml.contains("repeatCount=\"inf\""))
                    XCTAssertTrue(caml.contains("autoreverses=\"1\""))
                    XCTAssertTrue(caml.contains("bounds=\"0 0 390 844\""))
                    XCTAssertTrue(caml.contains("bounds=\"0 0 470 924\""))
                }
                XCTAssertEqual(caml.contains("transform.translation.x"), effect.gyro)
                if effect.gyro {
                    XCTAssertTrue(caml.contains("value=\"gyro-0\""))
                    XCTAssertTrue(caml.contains("transform.translation.y"))
                    XCTAssertTrue(caml.contains("name=\"FLOATING\""))
                    XCTAssertFalse(caml.contains("LKState"))
                }
                let plist = try PropertyListSerialization.propertyList(from: file("/Wallpaper.plist", in: files), format: nil) as! [String: Any]
                XCTAssertEqual(plist["wantsDeviceMotion"] as? Bool, effect.gyro)
            }
        }
    }
    func testContinuousPresetsKeepRoleSpecificSpeedsAndTwoRealEndpoints() throws {
        for preset in PhotoWallpaper.Effects.Motion.allCases {
            var animations = Set<String>()
            for role in WallpaperPhotoLayer.Role.allCases {
                let xml = PhotoWallpaper.continuousAnimation(role: role, preset: preset)
                XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse())
                XCTAssertTrue(xml.contains("repeatDuration=\"inf\""))
                XCTAssertFalse(xml.contains("opacity"))
                let axes = preset == .float ? 2 : 1
                XCTAssertEqual(xml.components(separatedBy: "<real value=").count - 1, axes * 2)
                XCTAssertTrue(animations.insert(xml).inserted, "Each depth role must have distinct motion")
            }
        }
        let layers: [WallpaperPhotoLayer] = [
            .init(image: photo(.blue), role: .background),
            .init(image: photo(.green, transparent: true), role: .middle),
            .init(image: photo(.red, transparent: true), role: .foreground)]
        let url = try PhotoWallpaper.makeArchive(layers: layers, screenAspect: 0.5,
                                                depth: true, effects: .init(floating: true))
        defer { try? FileManager.default.removeItem(at: url) }
        try recordEvidence(url, name: "confirmed-recipe-three-layer")
        let files = try unpack(url)
        for name in [PhotoWallpaper.backgroundName, PhotoWallpaper.floatingName, PhotoWallpaper.foregroundName] {
            let xml = try checkBundle(name, count: 1, files: files)
            XCTAssertTrue(xml.contains("beginTimeMode=\"absolute\""))
            XCTAssertTrue(xml.contains("position.x"))
            XCTAssertTrue(xml.contains("position.y"))
        }
    }


    /// Parse the ACTUAL generated archive, not the SwiftUI preview or helper output.
    private final class ExportMotionProbe: NSObject, XMLParserDelegate {
        var animations: [[String: String]] = []
        var values: [[Double]] = []
        private var current: Int?
        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String]) {
            if attributeDict["type"] == "CAKeyframeAnimation" {
                current = animations.count
                animations.append(attributeDict); values.append([])
            } else if elementName == "real", let index = current,
                      let text = attributeDict["value"], let value = Double(text) {
                values[index].append(value)
            }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "animation" || elementName == "p" { current = nil }
        }
    }

    func testActualAnimatedExportsUseProvenRouteGeometryEndpointsDurationsAndLoopRange() throws {
        let photos: [WallpaperPhotoLayer] = [
            .init(image: photo(.blue), role: .background),
            .init(image: photo(.green, transparent: true), role: .middle),
            .init(image: photo(.red, transparent: true), role: .foreground)]
        let specs: [(WallpaperPhotoLayer.Role, String, Double, Double, Double, Double)] = [
            (.background, PhotoWallpaper.backgroundName, 4, 3, 18, 23),
            (.middle, PhotoWallpaper.floatingName, 13, 7, 12, 15),
            (.foreground, PhotoWallpaper.foregroundName, 28, 12, 8, 11)]
        for depth in [false, true] {
            // Preserve the original device-confirmed float-only route independently of the new engine.
            let archive = try PhotoWallpaper.makeArchive(layers: photos, screenAspect: 0.5, depth: depth,
                effects: .init(floating: true))
            defer { try? FileManager.default.removeItem(at: archive) }
            let files = try unpack(archive)
            try recordEvidence(archive, name: depth ? "motion-proven-depth" : "motion-proven-manual")
            let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(
                from: file("/Wallpaper.plist", in: files), format: nil) as? [String: Any])
            XCTAssertEqual(plist["family"] as? String, "WWDC22")
            XCTAssertEqual(plist["logicalScreenClass"] as? String, "390w-844h@3x~iphone")
            XCTAssertEqual(plist["version"] as? Int, 1)
            XCTAssertEqual(plist["wantsDeviceMotion"] as? Bool, false)
            let route = try XCTUnwrap((((plist["assets"] as? [String: Any])?["lockAndHome"]
                as? [String: Any])?["default"]) as? [String: Any])
            XCTAssertEqual(route["type"] as? String, "LayeredAnimation")
            XCTAssertEqual(route["backgroundAnimationFileName"] as? String, PhotoWallpaper.backgroundName)
            XCTAssertEqual(route["floatingAnimationFileNameKey"] as? String, PhotoWallpaper.floatingName)
            XCTAssertEqual(route["foregroundAnimationFileName"] as? String, PhotoWallpaper.foregroundName)
            for (_, bundle, _, _, _, _) in specs {
                let data = try file(bundle + "/main.caml", in: files)
                let xml = String(decoding: data, as: UTF8.self)
                let parser = XMLParser(data: data), probe = ExportMotionProbe()
                parser.delegate = probe
                XCTAssertTrue(parser.parse())
                let expected = depth ? specs.filter { $0.1 == bundle }
                    : bundle == PhotoWallpaper.backgroundName ? specs : []
                XCTAssertEqual(probe.animations.count, expected.count * 2)
                for (index, spec) in expected.enumerated() {
                    for (axis, center, amplitude, duration) in [
                        ("position.y", 422.0, spec.3, spec.5), ("position.x", 195.0, spec.2, spec.4)] {
                        let offset = index * 2 + (axis == "position.y" ? 0 : 1)
                        guard offset < probe.animations.count else { continue }
                        let animation = probe.animations[offset]
                        XCTAssertEqual(animation["keyPath"], axis)
                        XCTAssertEqual(Double(animation["duration"] ?? ""), duration)
                        XCTAssertEqual(animation["repeatCount"], "inf")
                        XCTAssertEqual(animation["repeatDuration"], "inf")
                        XCTAssertEqual(animation["beginTime"], "1e-100")
                        XCTAssertEqual(animation["autoreverses"], "1")
                        XCTAssertEqual(animation["removedOnCompletion"], "0")
                        XCTAssertEqual(probe.values[offset], [center - amplitude, center + amplitude])
                    }
                }
                XCTAssertTrue(xml.contains("bounds=\"0 0 390 844\""))
                if !expected.isEmpty { XCTAssertTrue(xml.contains("bounds=\"0 0 470 924\"")) }
                XCTAssertFalse(xml.contains("keyPath=\"opacity\""))
                XCTAssertFalse(xml.contains("transform.translation"))
                XCTAssertFalse(xml.contains("scale("))
                XCTAssertFalse(xml.contains("<style>"))
                let index = try XCTUnwrap(try PropertyListSerialization.propertyList(
                    from: file(bundle + "/index.xml", in: files), format: nil) as? [String: Any])
                XCTAssertEqual(index["documentWidth"] as? Int, 390)
                XCTAssertEqual(index["documentHeight"] as? Int, 844)
                XCTAssertEqual(index["loopingEnabled"] as? Bool, true)
                XCTAssertEqual(index["loopStart"] as? Double, 0)
                XCTAssertEqual(index["loopEnd"] as? Double, Double.infinity)
                XCTAssertEqual(index["unitsInPixelsInPlayer"] as? Bool, false)
                XCTAssertEqual(index["documentResizesToView"] as? Bool, false)
            }
            if !depth {
                let xml = String(decoding: try file(PhotoWallpaper.backgroundName + "/main.caml", in: files), as: UTF8.self)
                let positions = try photos.map { layer in try XCTUnwrap(xml.range(of: layer.id.uuidString)?.lowerBound) }
                XCTAssertEqual(positions, positions.sorted(), "Clock depth off must preserve manual image order")
            }
        }
    }

    func testActualExportEveryDirectionalPresetHasCorrectAxisAndDistinctEndpoints() throws {
        for preset in PhotoWallpaper.Effects.Motion.allCases {
            let archive = try PhotoWallpaper.makeArchive(layers: [.init(image: photo())], screenAspect: 0.5,
                effects: .init(floating: true, motion: preset))
            defer { try? FileManager.default.removeItem(at: archive) }
            let files = try unpack(archive)
            let parser = XMLParser(data: try file(PhotoWallpaper.backgroundName + "/main.caml", in: files))
            let probe = ExportMotionProbe(); parser.delegate = probe
            XCTAssertTrue(parser.parse())
            let horizontal = preset == .float || preset == .left || preset == .right
            let vertical = preset == .float || preset == .up || preset == .down
            XCTAssertEqual(probe.animations.count, (horizontal ? 1 : 0) + (vertical ? 1 : 0))
            for (i, animation) in probe.animations.enumerated() {
                let isX = animation["keyPath"] == "position.x"
                XCTAssertEqual(isX ? horizontal : vertical, true)
                let center = isX ? 195.0 : 422.0, amplitude = isX ? 4.0 : 3.0
                let reverse = isX ? preset == .left : preset == .up
                XCTAssertEqual(probe.values[i], reverse
                    ? [center + amplitude, center - amplitude] : [center - amplitude, center + amplitude])
                XCTAssertEqual(Double(animation["duration"] ?? ""), isX ? 18 : 23)
                XCTAssertEqual(animation["repeatCount"], "inf")
                XCTAssertEqual(animation["repeatDuration"], "inf")
            }
        }
    }

    func testMakerOutputLabelsDistinguishStaticAndAnimationInAllLanguages() {
        for language in AppLanguage.allCases {
            XCTAssertNotEqual(WallpaperMakerStrings.text(.staticPhotos, language: language),
                              WallpaperMakerStrings.text(.animatedPhotos, language: language))
            XCTAssertEqual(WallpaperMakerStrings.values[.staticPhotos]?.count, 5)
            XCTAssertEqual(WallpaperMakerStrings.values[.animatedPhotos]?.count, 5)
        }
    }

    func testInvalidPhotoRequestsAndTransformsRejected() throws {
        XCTAssertThrowsError(try PhotoWallpaper.makeArchive(layers: [], screenAspect: 0.5))
        XCTAssertThrowsError(try PhotoWallpaper.makeArchive(layers: [.init(image: photo())], screenAspect: .nan))
        XCTAssertThrowsError(try PhotoWallpaper.render(photo(), size: CGSize(width: 20, height: 40), crop: true, zoom: .infinity))
        XCTAssertThrowsError(try PhotoWallpaper.makeArchive(layers: (0..<9).map { _ in .init(image: photo()) }, screenAspect: 0.5))
    }
    private func plan(_ ids: [UUID]) -> [String: Any] {
        ["version": 1, "parallaxStrength": 0, "clockArea": "none",
         "layers": ids.map { ["id": $0.uuidString, "role": "background", "zoom": 1.0, "x": 0.0, "y": 0.0, "crop": true] as [String: Any] }]
    }
    private func data(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    func testStrictPlanValidReordersAndManualControlsRemainEditable() throws {
        let a = WallpaperPhotoLayer(image: photo()), b = WallpaperPhotoLayer(image: photo(.blue))
        var p = plan([b.id, a.id]); p["clockArea"] = "avoidTop"
        var rows = try XCTUnwrap(p["layers"] as? [[String: Any]])
        rows[0]["role"] = "foreground"; rows[0]["zoom"] = 1.5; rows[0]["x"] = -0.2; p["layers"] = rows
        let result = try WallpaperLayoutPlan.parse(data(p), knownIDs: [a.id, b.id]).apply(to: [a,b])
        XCTAssertEqual(result.map(\.id), [b.id, a.id]); XCTAssertEqual(result[0].zoom, 1.5)
        XCTAssertEqual(result[0].y, 0.35); XCTAssertEqual(result[0].role, .foreground)
        var manual = result; manual[0].zoom = 2
        XCTAssertEqual(manual[0].zoom, 2)
        XCTAssertThrowsError(try WallpaperLayoutPlan.parse(data(p), knownIDs: [a.id, b.id]).apply(to: [a]))
    }
    func testInvalidPlansRejectUnknownKeysIDsDuplicatesTypesBoundsAndCode() throws {
        let id = UUID(), other = UUID()
        let original = plan([id])
        var bad: [[String: Any]] = []
        var value = original; value["url"] = "https://example.com"; bad.append(value)
        value = original; value["version"] = true; bad.append(value)
        value = original; value["version"] = 2; bad.append(value)
        value = original; value["parallaxStrength"] = 0.5; bad.append(value)
        value = original; value["clockArea"] = "run code"; bad.append(value)
        for (key, item) in ([("id", other.uuidString), ("role", "file:///tmp/a"), ("zoom", 5.0),
                                          ("x", true), ("y", -2.0), ("crop", 1), ("code", "evil")] as [(String, Any)]) {
            value = original
            var rows = try XCTUnwrap(value["layers"] as? [[String: Any]])
            rows[0][key] = item; value["layers"] = rows; bad.append(value)
        }
        for invalid in bad { XCTAssertThrowsError(try WallpaperLayoutPlan.parse(data(invalid), knownIDs: [id])) }
        value = plan([id,id])
        XCTAssertThrowsError(try WallpaperLayoutPlan.parse(data(value), knownIDs: [id,other]))
        XCTAssertThrowsError(try WallpaperLayoutPlan.parse(Data(repeating: 32, count: 16385), knownIDs: [id]))
        XCTAssertThrowsError(try WallpaperLayoutPlan.parse(Data("{\"version\":NaN}".utf8), knownIDs: [id]))
    }
    func testManualFallbackFlagOffNeverCallsTransportAndUnavailableKeepsPhotos() async throws {
        XCTAssertFalse(WallpaperLayoutAI.enabled)
        let photos = [WallpaperPhotoLayer(image: photo())]
        do {
            _ = try await WallpaperLayoutAI.request(description: "layout", layers: photos, allowed: false) { _ in
                XCTFail("OFF gate made a network call"); return Data()
            }
            XCTFail("must fail closed")
        } catch {}
        do {
            _ = try await WallpaperLayoutAI.request(description: "layout", layers: photos, allowed: true) { _ in
                throw URLError(.notConnectedToInternet)
            }
            XCTFail("must use manual fallback")
        } catch {}
        do {
            _ = try await WallpaperLayoutAI.request(description: "layout", layers: photos, allowed: true) { body in
                XCTAssertNil(body["image"]); XCTAssertNotNil(body["photos"])
                return Data("{\"url\":\"https://example.com\"}".utf8)
            }
            XCTFail("invalid plan")
        } catch {}
        XCTAssertEqual(photos.count, 1); XCTAssertEqual(photos[0].zoom, 1)
    }
    func testSupportedRangeAndImportCopyInAllFiveLanguages() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(WallpaperMakerStrings.text(.compatibility, language: language), "iOS (18.0 – 27.2 beta 2)")
            XCTAssertTrue(WallpaperMakerStrings.text(.chooseTendies, language: language).contains(".tendies"))
            XCTAssertTrue(WallpaperMakerStrings.text(.importHint, language: language).contains("Mirsa"))
            if language != .english {
                XCTAssertFalse(WallpaperMakerStrings.text(.importHint, language: language).contains("On My iPhone"))
                XCTAssertFalse(WallpaperMakerStrings.text(.chooseTendies, language: language).contains("Choose"))
            }
        }
    }
    func testEveryMakerStringInAllFiveLanguages() {
        for language in AppLanguage.allCases {
            for key in WallpaperMakerStrings.Key.allCases {
                XCTAssertFalse(WallpaperMakerStrings.text(key, language: language).isEmpty)
                XCTAssertEqual(WallpaperMakerStrings.values[key]?.count, 5)
            }
        }
        XCTAssertTrue(WallpaperMakerStrings.text(.steps, language: .german).contains("wählen"))
        XCTAssertTrue(WallpaperMakerStrings.text(.steps, language: .sorani).contains("وێنە"))
        XCTAssertTrue(WallpaperMakerStrings.text(.middle, language: .kurmanji).contains("Navîn"))
    }
    func testGeneratedRealVideoArchiveContainsAnimationAndFrames() async throws {
        let input = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: input) }
        let writer = try AVAssetWriter(outputURL: input, fileType: .mov)
        let track = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 96])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: track, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 96])
        writer.add(track)
        XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        // requestMediaDataWhenReady provides real readiness without a polling loop.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var frame = 0
            track.requestMediaDataWhenReady(on: DispatchQueue(label: "wallpaper-test-video")) {
                while track.isReadyForMoreMediaData && frame < 12 {
                    var pixel: CVPixelBuffer?
                    let status = CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixel)
                    guard status == kCVReturnSuccess, let pixel else {
                        track.markAsFinished(); writer.cancelWriting(); continuation.resume(throwing: CocoaError(.fileWriteUnknown)); return
                    }
                    CVPixelBufferLockBaseAddress(pixel, [])
                    memset(CVPixelBufferGetBaseAddress(pixel), Int32(frame * 12), CVPixelBufferGetDataSize(pixel))
                    CVPixelBufferUnlockBaseAddress(pixel, [])
                    guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 24)) else {
                        track.markAsFinished(); writer.cancelWriting(); continuation.resume(throwing: writer.error ?? CocoaError(.fileWriteUnknown)); return
                    }
                    frame += 1
                }
                if frame == 12 {
                    frame += 1
                    track.markAsFinished()
                    writer.finishWriting {
                        if writer.status == .completed { continuation.resume() }
                        else { continuation.resume(throwing: writer.error ?? CocoaError(.fileWriteUnknown)) }
                    }
                }
            }
        }
        let output = try await VideoWallpaper.makeArchive(from: input, screenAspect: 0.5) { _ in }
        defer { try? FileManager.default.removeItem(at: output) }
        let files = try unpack(output)
        let caml = String(decoding: try file("9183.Custom_Background-810w-1080h@2x~ipad.ca/main.caml", in: files), as: UTF8.self)
        XCTAssertTrue(caml.contains("CAKeyframeAnimation"))
        XCTAssertGreaterThan(files.keys.filter { $0.hasSuffix(".jpg") }.count, 1)
        XCTAssertNotNil(try file("providerInfo.plist", in: files))
    }
    func testDefaultRolesSpreadAcrossDepthAndEveryPickedLayerIsOutput() throws {
        XCTAssertEqual(PhotoWallpaper.defaultRoles(existing: 0, adding: 1), [.background])
        XCTAssertEqual(PhotoWallpaper.defaultRoles(existing: 0, adding: 4), [.background, .middle, .middle, .foreground])
        for n in 2...5 {
            let roles = PhotoWallpaper.defaultRoles(existing: 0, adding: n)
            let photos = roles.map { WallpaperPhotoLayer(image: photo(.blue, transparent: $0 == .foreground), role: $0) }
            let url = try PhotoWallpaper.makeArchive(layers: photos, screenAspect: 0.5, depth: true,
                                                     effects: .init(unlock: .zoom, floating: false))
            defer { try? FileManager.default.removeItem(at: url) }
            let files = try unpack(url)
            let pngs = files.keys.filter { $0.hasSuffix(".png") && $0.contains("/assets/") }
            XCTAssertEqual(pngs.count, n)
            var referenced = 0
            for name in [PhotoWallpaper.backgroundName, PhotoWallpaper.floatingName, PhotoWallpaper.foregroundName] {
                let xml = String(decoding: try file(name + "/main.caml", in: files), as: UTF8.self)
                let layerCount = xml.components(separatedBy: #"src="assets/"#).count - 1
                referenced += layerCount
                // Empty role bundles have no state targets. Every populated
                // bundle must still carry real per-layer spring transitions.
                XCTAssertEqual(xml.contains("LKStateTransitionElement"), layerCount > 0)
            }
            XCTAssertEqual(referenced, n)
            let fg = String(decoding: try file(PhotoWallpaper.foregroundName + "/main.caml", in: files), as: UTF8.self)
            XCTAssertTrue(fg.contains(photos.last!.id.uuidString))
            let plist = try PropertyListSerialization.propertyList(from: file("/Wallpaper.plist", in: files), format: nil) as! [String: Any]
            XCTAssertEqual(plist["wantsDeviceMotion"] as? Bool, false)
        }
    }

    /// Opaque full-frame photos: every file exists and is referenced, but later layers visually cover earlier ones.
    /// This exporter-only fixture intentionally does not run automatic foreground segmentation.
    func testOpaqueNPhotosEveryAssetReferencedExplicitRolesHonoredAndNoCutoutClaim() throws {
        let roles: [WallpaperPhotoLayer.Role] = [.foreground, .background, .middle, .foreground]
        let colors: [UIColor] = [.red, .green, .blue, .yellow]
        let opaque = zip(colors, roles).map { WallpaperPhotoLayer(image: photo($0), role: $1) }
        for depth in [false, true] {
            let url = try PhotoWallpaper.makeArchive(layers: opaque, screenAspect: 0.5, depth: depth, effects: .init())
            defer { try? FileManager.default.removeItem(at: url) }
            try recordEvidence(url, name: depth ? "opaque-4-depth" : "opaque-4-flat")
            let files = try unpack(url)
            XCTAssertEqual(files.keys.filter { $0.hasSuffix(".png") && $0.contains("/assets/") }.count, 4)
            let names = depth ? [PhotoWallpaper.backgroundName, PhotoWallpaper.floatingName, PhotoWallpaper.foregroundName]
                              : [PhotoWallpaper.simpleName]
            var refs: [String: Int] = [:]
            for name in names {
                let xml = String(decoding: try file(name + "/main.caml", in: files), as: UTF8.self)
                refs[name] = xml.components(separatedBy: #"src="assets/"#).count - 1
            }
            XCTAssertEqual(refs.values.reduce(0, +), 4)
            if depth {
                // Explicit user roles decide the bundle, not the default spread.
                XCTAssertEqual(refs[PhotoWallpaper.backgroundName], 1)
                XCTAssertEqual(refs[PhotoWallpaper.floatingName], 1)
                XCTAssertEqual(refs[PhotoWallpaper.foregroundName], 2)
            }
        }
        // A real alpha channel is preserved in the stored PNG (cutout input), opaque stays opaque.
        let cut = [WallpaperPhotoLayer(image: photo(.red), role: .background),
                   WallpaperPhotoLayer(image: photo(.blue, transparent: true), role: .foreground)]
        let url = try PhotoWallpaper.makeArchive(layers: cut, screenAspect: 0.5, depth: true, effects: .init())
        defer { try? FileManager.default.removeItem(at: url) }
        try recordEvidence(url, name: "transparent-2-depth")
        let files = try unpack(url)
        func alphaAtCorner(_ id: UUID) throws -> CGFloat {
            let data = try XCTUnwrap(files.first { $0.key.hasSuffix(id.uuidString + ".png") }?.value)
            let img = try XCTUnwrap(UIImage(data: data)?.cgImage)
            var px = [UInt8](repeating: 0, count: 4)
            let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: -img.width + 1, y: -img.height + 1, width: img.width, height: img.height))
            return CGFloat(px[3]) / 255
        }
        XCTAssertEqual(try alphaAtCorner(cut[0].id), 1, accuracy: 0.01)
        XCTAssertEqual(try alphaAtCorner(cut[1].id), 0, accuracy: 0.01)
    }
    // Reference mechanism tests name actual pinned packages, not screenshots/preview guesses.
    private final class ReferenceXML: NSObject, XMLParserDelegate {
        final class Node {
            let name: String; let attributes: [String: String]
            var children: [Node] = []
            init(_ name: String, _ attributes: [String: String]) { self.name = name; self.attributes = attributes }
            var all: [Node] { [self] + children.flatMap(\.all) }
        }
        var roots: [Node] = []; var stack: [Node] = []
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            let node = Node(elementName, attributeDict)
            if let parent = stack.last { parent.children.append(node) } else { roots.append(node) }
            stack.append(node)
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            stack.removeLast()
        }
        static func read(_ data: Data) throws -> [Node] {
            let result = ReferenceXML(); let parser = XMLParser(data: data)
            parser.delegate = result; parser.shouldResolveExternalEntities = false
            XCTAssertTrue(parser.parse(), String(describing: parser.parserError))
            return result.roots.flatMap(\.all)
        }
    }

    private func referenceNodes(_ files: [String: Data]) throws -> [ReferenceXML.Node] {
        var all: [ReferenceXML.Node] = []
        for (path, bytes) in files where path.hasSuffix("/main.caml") {
            let nodes = try ReferenceXML.read(bytes)
            let ids = nodes.compactMap { $0.attributes["id"] }
            XCTAssertEqual(ids.count, Set(ids).count, "duplicate CAML target in \(path)")
            let names = Set(nodes.compactMap { $0.attributes["name"] })
            let directory = String(path.dropLast("main.caml".count))
            for node in nodes {
                if let target = node.attributes["targetId"] { XCTAssertTrue(ids.contains(target), target) }
                if let src = node.attributes["src"] {
                    XCTAssertTrue(src.hasPrefix("assets/")); XCTAssertFalse(src.contains(".."))
                    XCTAssertNotNil(files[directory + src], "missing local asset \(src)")
                }
                if node.name == "layerName", let target = node.attributes["value"] {
                    XCTAssertTrue(names.contains(target), "parameter target \(target)")
                }
                if node.name == "animation", node.attributes["type"] == "CASpringAnimation" {
                    XCTAssertNotNil(node.attributes["keyPath"], "spring missing key path")
                }
            }
            all += nodes
        }
        return all
    }

    func testReferenceGyroManosabaEnvelopeStrengthAndIndependentTimedNodes() throws {
        for strength in PhotoWallpaper.Effects.GyroStrength.allCases {
            let effects = PhotoWallpaper.Effects(unlock: .slide, gyro: true, gyroStrength: strength, floating: true, spin: true)
            let url = try PhotoWallpaper.makeArchive(layers: [.init(image: photo(), role: .middle)],
                                                     screenAspect: 0.5, effects: effects)
            defer { try? FileManager.default.removeItem(at: url) }
            let files = try unpack(url)
            let nodes = try referenceNodes(files)
            let plist = try PropertyListSerialization.propertyList(from: file("/Wallpaper.plist", in: files), format: nil) as! [String: Any]
            XCTAssertEqual(plist["family"] as? String, "Marble")
            XCTAssertEqual(plist["version"] as? Int, 6)
            XCTAssertEqual(plist["wantsDeviceMotion"] as? Bool, true)
            let index = try PropertyListSerialization.propertyList(from: file(PhotoWallpaper.simpleName + "/index.xml", in: files), format: nil) as! [String: Any]
            XCTAssertEqual(Set(index.keys), ["rootDocument"])
            XCTAssertEqual(nodes.filter { $0.name == "wallpaperParallaxGroups" }.count, 1)
            let groups = try XCTUnwrap(nodes.first { $0.name == "wallpaperParallaxGroups" }).children
            XCTAssertEqual(groups.count, 2)
            for group in groups {
                let values = Dictionary(uniqueKeysWithValues: group.children.map { ($0.name, $0.attributes["value"] ?? "") })
                XCTAssertEqual(values["view"], "Floating")
                XCTAssertEqual(values["layerName"], "gyro-0")
                XCTAssertEqual(values["mapMaxTo"], String(Int(Double(strength.rawValue) * 0.7)))
                XCTAssertEqual(values["mapMinTo"], String(-Int(Double(strength.rawValue) * 0.7)))
            }
            let state = try XCTUnwrap(nodes.first { $0.attributes["id"] == "state-0" })
            XCTAssertEqual(state.name, "CATransformLayer")
            XCTAssertFalse(state.children.contains { $0.name == "animations" })
            let floatNode = try XCTUnwrap(nodes.first { $0.attributes["id"] == "float-0" })
            XCTAssertTrue(floatNode.children.contains { $0.name == "animations" })
            let spin = try XCTUnwrap(nodes.first { $0.attributes["id"] == "spin-0" })
            XCTAssertTrue(spin.children.contains { $0.name == "animations" })
            XCTAssertFalse(nodes.contains { $0.name == "LKState" })
            let propertyGroups = try XCTUnwrap(nodes.first { $0.name == "wallpaperPropertyGroups" }).children
            XCTAssertEqual(propertyGroups.count, 4)
            XCTAssertTrue(propertyGroups.allSatisfy { group in
                group.children.filter { ["v_home", "v_lock", "v_sleep"].contains($0.name) }.count == 3
            })
            try recordEvidence(url, name: "Manosaba-Gyro-strength-\(strength.rawValue)-timed-spin")
        }
    }

    func testReferenceHatsuneMikuDistinctScenesPersistentStickerAndSleepState() throws {
        var lock = WallpaperPhotoLayer(image: photo(.blue)); lock.scene = .lock
        var home = WallpaperPhotoLayer(image: photo(.red)); home.scene = .home
        var sticker = WallpaperPhotoLayer(image: photo(.green, transparent: true), role: .middle)
        sticker.homeOffsetX = 0.4; sticker.homeOffsetY = -0.3
        let effects = PhotoWallpaper.Effects(unlock: .slide, floating: true, dimOnSleep: true)
        let url = try PhotoWallpaper.makeArchive(layers: [lock, home, sticker], screenAspect: 0.5, effects: effects)
        defer { try? FileManager.default.removeItem(at: url) }
        let files = try unpack(url); let nodes = try referenceNodes(files)
        let populated = try XCTUnwrap(files.first { $0.key.hasSuffix(PhotoWallpaper.backgroundName + "/main.caml") }).value
        let tree = try ReferenceXML.read(populated)
        let states = tree.filter { $0.name == "LKState" }
        XCTAssertEqual(Set(states.compactMap { $0.attributes["name"] }), ["Locked", "Unlock", "Sleep"])
        func value(_ state: String, _ target: String, _ key: String) throws -> Double {
            let root = try XCTUnwrap(states.first { $0.attributes["name"] == state })
            let assignment = try XCTUnwrap(root.all.first {
                $0.name == "LKStateSetValue" && $0.attributes["targetId"] == target && $0.attributes["keyPath"] == key
            })
            return try XCTUnwrap(Double(try XCTUnwrap(assignment.children.first?.attributes["value"])))
        }
        XCTAssertEqual(try value("Locked", "state-0", "opacity"), 1)
        XCTAssertEqual(try value("Unlock", "state-0", "opacity"), 0)
        XCTAssertEqual(try value("Locked", "state-1", "opacity"), 0)
        XCTAssertEqual(try value("Unlock", "state-1", "opacity"), 1)
        XCTAssertLessThan(try value("Unlock", "state-0", "position.y"), 0)
        XCTAssertGreaterThan(try value("Locked", "state-1", "position.y"), 844)
        XCTAssertEqual(try value("Locked", "state-2", "opacity"), 1)
        XCTAssertEqual(try value("Unlock", "state-2", "opacity"), 1)
        XCTAssertEqual(try value("Sleep", "state-2", "opacity"), 0.25)
        XCTAssertNotEqual(try value("Locked", "state-2", "position.x"), try value("Unlock", "state-2", "position.x"))
        XCTAssertEqual(tree.filter { $0.name == "contents" && $0.attributes["src"] != nil }.count, 3)
        for layer in [lock, home, sticker] {
            XCTAssertEqual(tree.filter { $0.attributes["src"] == "assets/\(layer.id.uuidString).png" }.count, 1)
        }
        // The confirmed recipe encodes x as <p> and y as <animation>.
        // Assert BOTH axes on each timed node, not a spelling-specific count.
        for index in 0..<3 {
            let node = try XCTUnwrap(tree.first { $0.attributes["id"] == "float-\(index)" })
            let loops = node.all.filter { $0.attributes["type"] == "CAKeyframeAnimation" }
            XCTAssertEqual(loops.count, 2)
            XCTAssertEqual(Set(loops.compactMap { $0.attributes["keyPath"] }), ["position.x", "position.y"])
            XCTAssertTrue(loops.allSatisfy { $0.attributes["repeatCount"] == "inf" })
        }
        XCTAssertTrue(nodes.contains { $0.name == "LKStateTransition" })
        try recordEvidence(url, name: "Hatsune-Miku-original-scenes-persistent-sticker")
    }

    func testReferenceParticlesSpinGradientReplicationBlendBlurAndRealSDFExports() throws {
        let cases: [(String, PhotoWallpaper.Effects, String)] = [
            ("Snow_Emitters-snow", .init(particles: .snow), "CAEmitterLayer"),
            ("Autumn_Horizon-original-leaf", .init(particles: .leaves), "CAEmitterLayer"),
            ("Snow_Emitters-original-star", .init(particles: .stars), "CAEmitterLayer"),
            ("Spinning_Squares", .init(spin: true), "CAKeyframeAnimation"),
            ("Zoro-gradient", .init(gradient: true), "CAGradientLayer"),
            ("WatchOS_Reflect-replicator", .init(replicate: true), "CAReplicatorLayer"),
            ("WatchOS_Reflect-screen", .init(blend: .screen), "compositingFilter"),
            ("WatchOS_Reflect-overlay", .init(blend: .overlay), "compositingFilter"),
            ("WatchOS_Reflect-blur", .init(blur: true), "CAFilter"),
            ("Minecraft_Liquid_Glass__beta_", .init(liquidGlass: true), "CASDFGlassDisplacementEffect")
        ]
        for (reference, effects, expected) in cases {
            let url = try PhotoWallpaper.makeArchive(layers: [.init(image: photo())], screenAspect: 0.5, effects: effects)
            defer { try? FileManager.default.removeItem(at: url) }
            let files = try unpack(url); let nodes = try referenceNodes(files)
            XCTAssertTrue(nodes.contains { $0.name == expected || $0.attributes["type"] == expected }, reference)
            if effects.particles != .none {
                let cells = nodes.filter { $0.name == "CAEmitterCell" }
                XCTAssertEqual(cells.count, 1)
                XCTAssertEqual(cells[0].attributes["yAcceleration"], "200")
                let bitmap = try file("/assets/mirsa-particle.png", in: files)
                XCTAssertNotNil(UIImage(data: bitmap))
                XCTAssertEqual(files.filter { $0.key.hasSuffix("/assets/mirsa-particle.png") }.count, 1)
            }
            if effects.spin {
                XCTAssertTrue(nodes.contains { $0.name == "animation" && $0.attributes["keyPath"] == "transform.rotation.z" &&
                    $0.attributes["repeatCount"] == "inf" })
            }
            if effects.liquidGlass {
                XCTAssertTrue(nodes.contains { $0.name == "CABackdropLayer" })
                XCTAssertTrue(nodes.contains { $0.name == "CAFilter" && $0.attributes["filter"] == "displacementMap" })
                XCTAssertTrue(nodes.contains { $0.name == "CASDFElementLayer" })
                XCTAssertFalse(nodes.contains { $0.attributes["filter"] == "gaussianBlur" })
            }
            try recordEvidence(url, name: reference)
        }
    }

    func testUnsupportedDepthGyroAndInvalidSceneOffsetsFailRatherThanSilentlyDropping() throws {
        let layer = WallpaperPhotoLayer(image: photo())
        XCTAssertThrowsError(try PhotoWallpaper.makeArchive(layers: [layer], screenAspect: 0.5, depth: true,
                                                            effects: .init(gyro: true)))
        for invalid in [Double.nan, .infinity, 1.001, -1.001] {
            var broken = layer; broken.homeOffsetX = invalid
            XCTAssertThrowsError(try PhotoWallpaper.makeArchive(layers: [broken], screenAspect: 0.5))
        }
    }

    func testReferenceA7XLightDarkDistinctBindingsWithoutInventedClockOrGyro() throws {
        var light = WallpaperPhotoLayer(image: photo(.blue)); light.appearance = .light
        var dark = WallpaperPhotoLayer(image: photo(.red)); dark.appearance = .dark
        let url = try PhotoWallpaper.makeArchive(layers: [light, dark], screenAspect: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let files = try unpack(url)
        let plist = try PropertyListSerialization.propertyList(from: file("/Wallpaper.plist", in: files), format: nil) as! [String: Any]
        XCTAssertEqual(plist["appearanceAware"] as? Bool, true)
        let bytes = try file(PhotoWallpaper.backgroundName + "/main.caml", in: files)
        let nodes = try ReferenceXML.read(bytes)
        let states = nodes.filter { $0.name == "LKState" }
        XCTAssertEqual(Set(states.compactMap { $0.attributes["name"] }),
                       ["Locked Light", "Unlock Light", "Sleep Light", "Locked Dark", "Unlock Dark", "Sleep Dark"])
        for state in states {
            let isLight = try XCTUnwrap(state.attributes["name"]).hasSuffix(" Light")
            for (target, visible) in [("state-0", isLight), ("state-1", !isLight)] {
                let assignment = try XCTUnwrap(state.all.first { $0.name == "LKStateSetValue" &&
                    $0.attributes["targetId"] == target && $0.attributes["keyPath"] == "opacity" })
                let value = Double(try XCTUnwrap(assignment.children.first?.attributes["value"]))
                XCTAssertEqual(value, visible ? 1 : 0)
            }
        }
        XCTAssertThrowsError(try PhotoWallpaper.makeArchive(layers: [light, dark], screenAspect: 0.5,
                                                            effects: .init(gyro: true)))
        _ = try referenceNodes(files)
        try recordEvidence(url, name: "A7X-light-dark-original-colours-no-clock")
    }

    func testReferenceRisingMrKrabsEmitterHasBottomOriginAndNegativeAcceleration() throws {
        let url = try PhotoWallpaper.makeArchive(layers: [.init(image: photo())], screenAspect: 0.5,
                                                 effects: .init(particles: .stars, particleDirection: .rising))
        defer { try? FileManager.default.removeItem(at: url) }
        let files = try unpack(url); let nodes = try referenceNodes(files)
        let emitter = try XCTUnwrap(nodes.first { $0.name == "CAEmitterLayer" })
        XCTAssertEqual(emitter.attributes["geometryFlipped"], "0")
        XCTAssertEqual(emitter.attributes["emitterPosition"], "195 840")
        let cell = try XCTUnwrap(nodes.first { $0.name == "CAEmitterCell" })
        XCTAssertEqual(cell.attributes["yAcceleration"], "-100")
        XCTAssertEqual(cell.attributes["xAcceleration"], "0")
        try recordEvidence(url, name: "Mr-krabs-rising-original-star")
    }

}

extension WallpaperMakerTests {
    func testRealVisionForegroundFixtureWhenDeviceModelAvailable() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Real Vision foreground model is not provided by this simulator. Alpha/export tests are separate, not segmentation proof.")
        #else
        let url = try XCTUnwrap(Bundle(for: WallpaperMakerTests.self).url(forResource: "nasa-eileen-collins", withExtension: "jpg"))
        let original = try PhotoWallpaper.loadImage(url)
        let outcome = try WallpaperForeground.process(original)
        switch outcome {
        case .unavailable: throw XCTSkip("Foreground model unavailable on this device.")
        case .noSubject: XCTFail("NASA portrait should yield a subject.")
        case .masked(let mask):
            XCTAssertTrue(WallpaperForeground.hasTransparency(try XCTUnwrap(mask.cgImage)))
            XCTAssertEqual(mask.size, original.size)
            XCTAssertFalse(WallpaperForeground.hasTransparency(try XCTUnwrap(original.cgImage)))
        }
        #endif
    }
    func testEmptyDescriptorSearchNeverPretendsAnArbitraryDirectoryIsWallpaper() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertTrue(TendiesEngine.shared.findDescriptorsWithExtensions(in: folder, defaultExt: "com.apple.WallpaperKit.CollectionsPoster").isEmpty)
    }
    func testTwoPhotosDefaultToBackgroundAndForeground() {
        XCTAssertEqual(PhotoWallpaper.defaultRoles(existing: 0, adding: 2), [.background, .foreground])
        XCTAssertEqual(PhotoWallpaper.defaultRoles(existing: 1, adding: 1), [.foreground])
    }
    func testLocalCutoutPreservesAlphaAndToggleRestoresOpaqueOriginal() throws {
        let original = photo(.red), alpha = photo(.red, transparent: true)
        guard case .masked(let mask) = try WallpaperForeground.process(alpha) else {
            return XCTFail("Existing alpha must be preserved without Vision")
        }
        XCTAssertTrue(WallpaperForeground.hasTransparency(try XCTUnwrap(mask.cgImage)))
        var layer = WallpaperPhotoLayer(image: original, role: .foreground)
        XCTAssertTrue(layer.cutoutEnabled)
        layer.cutoutImage = mask; layer.cutoutStatus = .ready
        for enabled in [true, false] {
            layer.cutoutEnabled = enabled
            let archive = try PhotoWallpaper.makeArchive(layers: [WallpaperPhotoLayer(image: photo(.blue)), layer], screenAspect: 0.5, depth: true)
            defer { try? FileManager.default.removeItem(at: archive) }
            let files = try unpack(archive)
            let png = try file(PhotoWallpaper.foregroundName + "/assets/\(layer.id.uuidString).png", in: files)
            XCTAssertEqual(WallpaperForeground.hasTransparency(try XCTUnwrap(UIImage(data: png)?.cgImage)), enabled)
            XCTAssertEqual(files.keys.filter { $0.hasSuffix(".png") }.count, 2)
            _ = try checkBundle(PhotoWallpaper.foregroundName, count: 1, files: files)
            try recordEvidence(archive, name: enabled ? "foreground-cutout-enabled" : "foreground-original-restored")
        }
        XCTAssertFalse(WallpaperForeground.hasTransparency(try XCTUnwrap(layer.image.cgImage)))
        layer.cutoutImage = nil
        XCTAssertTrue(layer.renderedImage === original, "A failed mask must fall back to the original")
    }
    func testGeneratedMotionHasBothDirectionsAndNonfinalStateAssignments() throws {
        let archive = try PhotoWallpaper.makeArchive(layers: [.init(image: photo())], screenAspect: 0.5,
                                                      effects: .init(floating: true))
        defer { try? FileManager.default.removeItem(at: archive) }
        let files = try unpack(archive)
        let caml = try checkBundle(PhotoWallpaper.backgroundName, count: 1, files: files)
        for state in ["Locked", "Unlock", "Sleep"] {
            XCTAssertTrue(caml.contains("fromState=\"*\" toState=\"\(state)\""))
            XCTAssertTrue(caml.contains("fromState=\"\(state)\" toState=\"*\""))
        }
        XCTAssertTrue(caml.contains("final=\"false\""))
    }
    func testOnlyRecognizedConnectionTimeoutGetsFriendlyHint() {
        XCTAssertTrue(TendiesConnectionHint.matches("MIRSA_CONNECTION: RSD connection timed out"))
        XCTAssertTrue(TendiesConnectionHint.matches("lockdown tunnel timeout"))
        XCTAssertTrue(TendiesConnectionHint.matches("RemoteXPC connection timed out"))
        XCTAssertFalse(TendiesConnectionHint.matches("RemoteXPC permission denied"))
        XCTAssertFalse(TendiesConnectionHint.matches("download timeout"))
        XCTAssertFalse(TendiesConnectionHint.matches("MIRSA_CONNECTION: permission denied"))
        for key in [WallpaperMakerStrings.Key.cutout, .cutoutHelp, .cutoutReady, .cutoutNoSubject, .cutoutUnavailable, .cutoutPreparing, .connectionHint, .containerUnavailable, .copyVerified, .applyFailed] {
            XCTAssertEqual(WallpaperMakerStrings.values[key]?.count, 5)
            XCTAssertTrue(WallpaperMakerStrings.values[key]?.allSatisfy { !$0.isEmpty } == true)
        }
    }
    func testArchiveContainmentNormalizesDirectorySlashesAndRejectsEqualSiblingTraversal() throws {
        let root = URL(fileURLWithPath: "/tmp/mirsa-archive-root", isDirectory: true)
        let slashRoot = URL(fileURLWithPath: root.path + "/", isDirectory: true)
        let child = root.appendingPathComponent("nested/file")
        for base in [root, slashRoot] {
            XCTAssertTrue(TendiesEngine.archiveDestination(child, isStrictlyInside: base))
            XCTAssertFalse(TendiesEngine.archiveDestination(root, isStrictlyInside: base))
            XCTAssertFalse(TendiesEngine.archiveDestination(
                URL(fileURLWithPath: root.path + "-sibling/file"), isStrictlyInside: base))
            XCTAssertFalse(TendiesEngine.archiveDestination(
                URL(fileURLWithPath: root.path + "/../escape"), isStrictlyInside: base))
        }
    }

    func testArchiveContainmentResolvesAliasAndRejectsSymlinkEscape() throws {
        let fm = FileManager.default
        let fixture = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fixture) }
        let root = fixture.appendingPathComponent("root", isDirectory: true)
        let alias = fixture.appendingPathComponent("alias", isDirectory: true)
        let outside = fixture.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: alias, withDestinationURL: root)
        try fm.createSymbolicLink(at: root.appendingPathComponent("redirect"), withDestinationURL: outside)
        XCTAssertTrue(TendiesEngine.archiveDestination(root.appendingPathComponent("new/file"), isStrictlyInside: alias))
        XCTAssertTrue(TendiesEngine.archiveDestination(alias.appendingPathComponent("new/file"), isStrictlyInside: root))
        XCTAssertFalse(TendiesEngine.archiveDestination(root.appendingPathComponent("redirect/file"), isStrictlyInside: root))
        try fm.createSymbolicLink(at: root.appendingPathComponent("dangling"),
                                  withDestinationURL: fixture.appendingPathComponent("nonexistent"))
        XCTAssertFalse(TendiesEngine.archiveDestination(root.appendingPathComponent("dangling/file"), isStrictlyInside: root))
        XCTAssertFalse(TendiesEngine.archiveDestination(root.appendingPathComponent("redirect/missing/deeper/file"), isStrictlyInside: root))
    }

    func testArchiveContainmentResolvesActualVarPrivateVarAlias() throws {
        let alias = URL(fileURLWithPath: "/var", isDirectory: true)
        let canonical = URL(fileURLWithPath: "/private/var", isDirectory: true)
        XCTAssertEqual(alias.resolvingSymlinksInPath().pathComponents,
                       canonical.resolvingSymlinksInPath().pathComponents)
        XCTAssertTrue(TendiesEngine.archiveDestination(canonical.appendingPathComponent("tmp/new"),
                                                       isStrictlyInside: alias))
        XCTAssertTrue(TendiesEngine.archiveDestination(alias.appendingPathComponent("tmp/new"),
                                                       isStrictlyInside: canonical))
        XCTAssertFalse(TendiesEngine.archiveDestination(alias, isStrictlyInside: canonical))
    }

    func testValidatedArchiveExtractsWithDirectoryURLAndTrailingSlash() throws {
        let fm = FileManager.default
        let fixture = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fixture) }
        let zip = fixture.appendingPathComponent("fixture.zip")
        let bytes = Data("archive containment fixture".utf8)
        do {
            let archive = try Archive(url: zip, accessMode: .create)
            try archive.addEntry(with: "nested/", type: .directory, uncompressedSize: Int64(0)) { _, _ in Data() }
            try archive.addEntry(with: "nested/file", type: .file, uncompressedSize: Int64(bytes.count)) { offset, count in
                bytes.subdata(in: Int(offset)..<(Int(offset) + count))
            }
        }
        for name in ["plain", "trailing/"] {
            let destination = fixture.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            try TendiesEngine.shared.extractValidatedArchive(zip, to: destination)
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("nested/file")), bytes)
        }
    }

    func testValidatedArchiveRejectsTraversalBeforeAnyWriteAndSymlinkRoot() throws {
        let fm = FileManager.default
        let fixture = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fixture) }
        let destination = fixture.appendingPathComponent("root", isDirectory: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let zip = fixture.appendingPathComponent("bad.zip")
        do {
            let archive = try Archive(url: zip, accessMode: .create)
            try archive.addEntry(with: "../escaped", type: .file, uncompressedSize: Int64(1)) { _, _ in Data([1]) }
        }
        XCTAssertThrowsError(try TendiesEngine.shared.extractValidatedArchive(zip, to: destination))
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: destination.path).isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: fixture.appendingPathComponent("escaped").path))
        let alias = fixture.appendingPathComponent("alias", isDirectory: true)
        try fm.createSymbolicLink(at: alias, withDestinationURL: destination)
        let safeZip = fixture.appendingPathComponent("safe.zip")
        do {
            let archive = try Archive(url: safeZip, accessMode: .create)
            try archive.addEntry(with: "file", type: .file, uncompressedSize: Int64(1)) { _, _ in Data([1]) }
        }
        XCTAssertThrowsError(try TendiesEngine.shared.extractValidatedArchive(safeZip, to: alias))
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

    /// Local filesystem evidence only, not proof of device grants or picker registration.
    func testExclusiveWholeRootCopyReadbackPreservesAttributesAndNeverMutatesPreferences() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("mirsa-pb-test-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let nested = source.appendingPathComponent("versions/1/contents")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try fm.createDirectory(at: source.appendingPathComponent("empty"), withIntermediateDirectories: true)
        try Data("fixture metadata".utf8).write(to: source.appendingPathComponent("metadata"))
        try Data([0, 1, 2, 255]).write(to: nested.appendingPathComponent("asset"))
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        // Include the root, nested directories and an empty directory in metadata verification.
        let paths = try MirsaPosterCopy.relativePaths(source).union([""])
        for path in paths {
            let url = source.appendingPathComponent(path)
            let directory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            try fm.setAttributes([.posixPermissions: directory ? 0o750 : 0o640, .modificationDate: old], ofItemAtPath: url.path)
        }
        let prefs = root.appendingPathComponent("com.apple.PosterBoard.unprotectedUserDefaults.plist")
        let previous = try PropertyListSerialization.data(fromPropertyList:
            ["unrelated": "keep", "PersistedPosterContainerBundleIdentifiers": ["com.apple.Existing"]],
            format: .binary, options: 0)
        try previous.write(to: prefs)
        let expected = try PosterBoardStore.manifest(source)
        let target = root.appendingPathComponent(UUID().uuidString)
        try MirsaPosterCopy.copyExclusive(source: source, target: target, expected: expected, log: { _ in })
        XCTAssertEqual(try PosterBoardStore.manifest(target), expected)
        XCTAssertEqual(try MirsaPosterCopy.relativePaths(target), try MirsaPosterCopy.relativePaths(source))
        try MirsaPosterCopy.verifyCopyAttributes(source: source, target: target)
        for path in paths {
            let attrs = try fm.attributesOfItem(atPath: target.appendingPathComponent(path).path)
            let original = try fm.attributesOfItem(atPath: source.appendingPathComponent(path).path)
            XCTAssertEqual(attrs[.posixPermissions] as? NSNumber, original[.posixPermissions] as? NSNumber)
            XCTAssertEqual(try XCTUnwrap(attrs[.modificationDate] as? Date).timeIntervalSince1970,
                           old.timeIntervalSince1970, accuracy: 0.001)
        }
        XCTAssertEqual(try Data(contentsOf: prefs), previous)
        XCTAssertThrowsError(try MirsaPosterCopy.copyExclusive(source: source, target: target, expected: expected, log: { _ in }))
        XCTAssertEqual(try PosterBoardStore.manifest(target), expected)
        // A different source cannot overwrite an existing destination either.
        try Data("changed source".utf8).write(to: source.appendingPathComponent("metadata"))
        XCTAssertThrowsError(try MirsaPosterCopy.copyExclusive(source: source, target: target,
            expected: PosterBoardStore.manifest(source), log: { _ in }))
        XCTAssertEqual(try PosterBoardStore.manifest(target), expected)
        XCTAssertEqual(try Data(contentsOf: prefs), previous)
    }
    func testCollectionsUseOnlyCanonicalProviderEvenWhenLegacyExists() throws {
        let canonical = "com.apple.WallpaperKit.CollectionsPoster"
        let legacy = "com.apple.Posters.CollectionsPosterApp"
        for importedProvider in [canonical, legacy] {
            XCTAssertEqual(try PosterBoardStore.providers(for: importedProvider, available: [canonical, legacy]), [canonical])
            XCTAssertEqual(try PosterBoardStore.providers(for: importedProvider, available: [canonical]), [canonical])
            XCTAssertThrowsError(try PosterBoardStore.providers(for: importedProvider, available: [legacy]))
        }
    }

    func testPosterStoreRejectsInvalidPathsUnknownProvidersAndSymlinkSource() throws {
        XCTAssertThrowsError(try PosterBoardStore.canonicalContainer("/var/mobile/Library"))
        XCTAssertThrowsError(try PosterBoardStore.canonicalContainer("/var/mobile/Containers/Data/Application/../" + UUID().uuidString))
        XCTAssertThrowsError(try PosterBoardStore.providers(for: "com.apple.Unknown", available: ["com.apple.Existing"]))
        let fm = FileManager.default, root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        XCTAssertThrowsError(try PosterBoardStore.manifest(root))
    }
}


#if DEBUG && targetEnvironment(simulator)
@_silgen_name("mirsa_pb_test_allowed")
private func posterAccessAllowed(_ path: UnsafePointer<CChar>) -> Int32
@_silgen_name("mirsa_pb_test_restore")
private func posterAccessRestore(_ caches: UnsafePointer<CChar>, _ backup: UnsafePointer<CChar>,
                                 _ existed: Int32, _ target: UnsafePointer<CChar>) -> Int32

final class PosterBoardAccessSafetyTests: XCTestCase {
    func testIdentityRejectsBareDatastoreAndContradictoryReadableMetadata() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root.appendingPathComponent("Library/Application Support/PRBPosterExtensionDataStore"),
                               withIntermediateDirectories: true)
        XCTAssertThrowsError(try PosterBoardStore.validateIdentity(root))
        let dotted = root.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
        let plain = root.appendingPathComponent("com.apple.mobile_container_manager.metadata.plist")
        func metadata(_ value: String, at url: URL) throws {
            try PropertyListSerialization.data(fromPropertyList: ["MCMMetadataIdentifier": value],
                                               format: .binary, options: 0).write(to: url)
        }
        try metadata("other.app", at: dotted)
        XCTAssertThrowsError(try PosterBoardStore.validateIdentity(root))
        try metadata("com.apple.PosterBoard", at: dotted)
        XCTAssertNoThrow(try PosterBoardStore.validateIdentity(root))
        try metadata("other.app", at: plain)
        XCTAssertThrowsError(try PosterBoardStore.validateIdentity(root), "A valid first identity must not hide contradictory second metadata")
        try metadata("com.apple.PosterBoard", at: plain)
        try Data("not a plist".utf8).write(to: dotted)
        XCTAssertThrowsError(try PosterBoardStore.validateIdentity(root), "Malformed readable metadata must fail closed")
    }

    func testClass7AliasRequiresExactTargetAndRejectsNestedLinks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent("PosterBoard")
        let alias = root.appendingPathComponent("Caches")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let metadata = ".com.apple.mobile_container_manager.metadata.plist"
        let store = target.appendingPathComponent("Library/Application Support/PRBPosterExtensionDataStore")
        try fm.createDirectory(at: store, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["MCMMetadataIdentifier": "com.apple.PosterBoard"],
            format: .binary, options: 0)
        try data.write(to: target.appendingPathComponent(metadata))
        try fm.createSymbolicLink(at: alias, withDestinationURL: target)
        XCTAssertTrue(PosterBoardStore.permitsLeasePath(alias.appendingPathComponent(metadata), effective: alias, target: target))
        XCTAssertFalse(PosterBoardStore.permitsLeasePath(alias.appendingPathComponent(metadata), effective: alias, target: root))
        XCTAssertFalse(PosterBoardStore.permitsLeasePath(root.appendingPathComponent("Caches-other"), effective: alias, target: target))
        try fm.createSymbolicLink(at: target.appendingPathComponent("redirect"), withDestinationURL: root)
        XCTAssertFalse(PosterBoardStore.permitsLeasePath(alias.appendingPathComponent("redirect/file"), effective: alias, target: target))
        try PosterBoardStore.validateIdentity(target)
        try PropertyListSerialization.data(fromPropertyList: ["MCMMetadataIdentifier": "other.app"],
                                           format: .binary, options: 0).write(to: target.appendingPathComponent(metadata))
        XCTAssertThrowsError(try PosterBoardStore.validateIdentity(target))
    }

    func testOnlyDataRootsOrUUIDChildrenAllowed() {
        let root = "/var/mobile/Containers/Data/Application"
        for path in [root, root + "/" + UUID().uuidString] {
            XCTAssertEqual(path.withCString { posterAccessAllowed($0) }, 1)
        }
        for path in ["/var/mobile/Library", root + "/../Library", root + "/not-a-uuid", root + "/" + UUID().uuidString + "/Library"] {
            XCTAssertEqual(path.withCString { posterAccessAllowed($0) }, 0)
        }
    }
    func testRestoreKeepsOriginalCachesAndNeverDeletesConflictingReplacement() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("mirsa-access-fixture-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let caches = root.appendingPathComponent("Caches"), backup = root.appendingPathComponent("Caches.mirsa-pb-backup")
        let target = root.appendingPathComponent("target")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        let marker = Data("keep the original cache".utf8)
        try marker.write(to: backup.appendingPathComponent("original"))
        try Data("do not touch target".utf8).write(to: target.appendingPathComponent("target-marker"))
        func restore() -> Int32 {
            caches.path.withCString { c in backup.path.withCString { b in target.path.withCString { t in
                posterAccessRestore(c, b, 1, t)
            } } }
        }
        try fm.createSymbolicLink(at: caches, withDestinationURL: target)
        XCTAssertEqual(restore(), 1)
        XCTAssertEqual(try Data(contentsOf: caches.appendingPathComponent("original")), marker)
        XCTAssertTrue(fm.fileExists(atPath: target.appendingPathComponent("target-marker").path))
        // Recreate an interrupted session, with a new real Caches from someone else.
        try fm.moveItem(at: caches, to: backup)
        try fm.createDirectory(at: caches, withIntermediateDirectories: true)
        try Data("replacement".utf8).write(to: caches.appendingPathComponent("new"))
        XCTAssertEqual(restore(), 0)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("original")), marker)
        XCTAssertTrue(fm.fileExists(atPath: caches.appendingPathComponent("new").path))
        XCTAssertTrue(fm.fileExists(atPath: target.appendingPathComponent("target-marker").path))
    }
    func testLocalizedLabelsDoNotChangeSerializedProviderValues() {
        XCTAssertEqual(TendiePosterType.suggestedPhotos.rawValue, "Suggested Photos")
        XCTAssertEqual(TendiePosterType.collections.rawValue, "Collections")
        XCTAssertEqual(WallpaperMakerStrings.text(.suggestedPhotosType, language: .arabic), "صور مقترحة")
        XCTAssertEqual(WallpaperMakerStrings.text(.deselectAll, language: .arabic), "شيل تحديد الكل")
        XCTAssertFalse(TendiesConnectionHint.matches("Direct PosterBoard access unavailable (lease -106)."))
    }

}
#endif
