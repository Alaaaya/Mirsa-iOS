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
                                    "galleryRegistrationVerified": false, "realVisionSegmentation": false]
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
        for state in ["Locked", "Unlock", "Sleep"] { XCTAssertTrue(xml.contains("LKState name=\"\(state)\"")) }
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
                let url = try PhotoWallpaper.makeArchive(layers: [layer], screenAspect: 0.5, depth: depth, effects: effect)
                defer { try? FileManager.default.removeItem(at: url) }
                let files = try unpack(url)
                let caml = try checkBundle(depth ? PhotoWallpaper.floatingName : PhotoWallpaper.simpleName, count: 1, files: files)
                XCTAssertEqual(caml.contains("CASpringAnimation"), effect.unlock != .none)
                if effect.unlock != .none {
                    XCTAssertTrue(caml.contains("targetId=\"#1\"")); XCTAssertTrue(caml.contains("duration=\"0.8\""))
                    XCTAssertTrue(caml.contains("keyPath=\"\(effect.unlock == .slide ? "position" : "transform")\""))
                }
                XCTAssertEqual(caml.contains("CAKeyframeAnimation"), effect.floating)
                if effect.floating { XCTAssertTrue(caml.contains("duration=\"6\"")); XCTAssertTrue(caml.contains("repeatCount=\"inf\"")) }
                XCTAssertEqual(caml.contains("transform.translation.x"), effect.gyro)
                if effect.gyro { XCTAssertTrue(caml.contains("value=\"motion-0\"")); XCTAssertTrue(caml.contains("transform.translation.y")) }
                let plist = try PropertyListSerialization.propertyList(from: file("/Wallpaper.plist", in: files), format: nil) as! [String: Any]
                XCTAssertEqual(plist["wantsDeviceMotion"] as? Bool, effect.gyro)
            }
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
                                                     effects: .init(unlock: .zoom, gyro: true, floating: false))
            defer { try? FileManager.default.removeItem(at: url) }
            let files = try unpack(url)
            let pngs = files.keys.filter { $0.hasSuffix(".png") && $0.contains("/assets/") }
            XCTAssertEqual(pngs.count, n)
            var referenced = 0
            for name in [PhotoWallpaper.backgroundName, PhotoWallpaper.floatingName, PhotoWallpaper.foregroundName] {
                let xml = String(decoding: try file(name + "/main.caml", in: files), as: UTF8.self)
                referenced += xml.components(separatedBy: #"src="assets/"#).count - 1
                XCTAssertTrue(xml.contains("LKStateTransitionElement"))
            }
            XCTAssertEqual(referenced, n)
            let fg = String(decoding: try file(PhotoWallpaper.foregroundName + "/main.caml", in: files), as: UTF8.self)
            XCTAssertTrue(fg.contains(photos.last!.id.uuidString))
            let plist = try PropertyListSerialization.propertyList(from: file("/Wallpaper.plist", in: files), format: nil) as! [String: Any]
            XCTAssertEqual(plist["wantsDeviceMotion"] as? Bool, true)
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
                                                      effects: .init(unlock: .zoom, gyro: true, floating: true))
        defer { try? FileManager.default.removeItem(at: archive) }
        let files = try unpack(archive)
        let caml = try checkBundle(PhotoWallpaper.simpleName, count: 1, files: files)
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
    func testPosterStoreCopiesReadbacksPreservesMetadataAndUnrelatedPreferences() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("mirsa-pb-test-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let container = root.appendingPathComponent("container")
        let provider = "com.apple.WallpaperKit.CollectionsPoster"
        let target = container.appendingPathComponent("Library/Application Support/PRBPosterExtensionDataStore/73/Extensions/" + provider + "/descriptors")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let identity = try PropertyListSerialization.data(fromPropertyList: ["MCMMetadataIdentifier": "com.apple.PosterBoard"], format: .binary, options: 0)
        try identity.write(to: container.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist"))
        let prefs = container.appendingPathComponent("Library/Preferences/com.apple.PosterBoard.unprotectedUserDefaults.plist")
        try fm.createDirectory(at: prefs.deletingLastPathComponent(), withIntermediateDirectories: true)
        let previous = try PropertyListSerialization.data(fromPropertyList: ["unrelated": "keep", "PersistedPosterContainerBundleIdentifiers": ["com.apple.Existing"]], format: .binary, options: 0)
        try previous.write(to: prefs)
        let id = "5M800000-0000-0000-0000-5QU41R000000"
        let source = root.appendingPathComponent(id)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("fixture \(id)".utf8).write(to: source.appendingPathComponent("metadata"))
        let backup = root.appendingPathComponent("backups")
        let count = try PosterBoardStore.install([(url: source, ext: provider)], container: container, resetProtections: false, backupRoot: backup, log: { _ in })
        XCTAssertEqual(count, 1)
        XCTAssertEqual(try PosterBoardStore.manifest(source), try PosterBoardStore.manifest(target.appendingPathComponent(id)))
        let dict = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: prefs), format: nil) as? [String: Any])
        XCTAssertEqual(dict["unrelated"] as? String, "keep")
        XCTAssertEqual(dict["PBF_LOCALE_DID_CHANGE"] as? Bool, false)
        XCTAssertNil(dict["PBF_RESET_FILE_PROTECTIONS"])
        XCTAssertEqual(Set(dict["PersistedPosterContainerBundleIdentifiers"] as? [String] ?? []), Set([provider, "com.apple.Existing"]))
        let saved = try XCTUnwrap(try fm.contentsOfDirectory(at: backup, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: saved.appendingPathComponent("unprotectedUserDefaults.original.plist")), previous)
        let proof = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: saved.appendingPathComponent("verified-copy.json"))) as? [String: Any])
        XCTAssertEqual(proof["galleryRegistrationVerified"] as? Bool, false)
        XCTAssertEqual(proof["version"] as? String, "73")
        XCTAssertThrowsError(try PosterBoardStore.install([(url: source, ext: provider)], container: container, resetProtections: false, backupRoot: backup, log: { _ in }))
        XCTAssertEqual(try PosterBoardStore.manifest(source), try PosterBoardStore.manifest(target.appendingPathComponent(id)))
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
