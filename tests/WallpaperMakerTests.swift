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
        let url = try PhotoWallpaper.makeArchive(layers: [.init(image: photo())], screenAspect: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "tendies")
        let files = try unpack(url)
        XCTAssertTrue(files.keys.allSatisfy { $0.hasPrefix("Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors/") })
        XCTAssertNotNil(try file("providerInfo.plist", in: files))
        let caml = String(decoding: try file(PhotoWallpaper.backgroundName + "/main.caml", in: files), as: UTF8.self)
        XCTAssertTrue(caml.contains("layer-0-background"))
        let png = try file(PhotoWallpaper.backgroundName + "/assets/layer-0.png", in: files)
        XCTAssertNotNil(UIImage(data: png))
        XCTAssertTrue(caml.contains("assets/layer-0.png"))
        let index = try PropertyListSerialization.propertyList(from: file(PhotoWallpaper.backgroundName + "/index.xml", in: files), format: nil) as? [String: Any]
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
        let fg = String(decoding: try file(PhotoWallpaper.foregroundName + "/main.caml", in: files), as: UTF8.self)
        XCTAssertTrue(bg.contains("layer-0-background")); XCTAssertTrue(bg.contains("layer-1-middle"))
        XCTAssertFalse(bg.contains("layer-2-foreground")); XCTAssertTrue(fg.contains("layer-2-foreground"))
        XCTAssertEqual(files.keys.filter { $0.hasSuffix(".png") }.count, 3)
        let png = try file(PhotoWallpaper.foregroundName + "/assets/layer-2.png", in: files)
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
        XCTAssertEqual(spec["floatingAnimationFileNameKey"] as? String, PhotoWallpaper.foregroundName)
        XCTAssertEqual(spec["type"] as? String, "LayeredAnimation")
    }
    func testDepthDefaultOffKeepsEveryLayerInBackgroundInManualOrder() throws {
        let layers: [WallpaperPhotoLayer] = [.init(image: photo(), role: .foreground), .init(image: photo(.blue))]
        let url = try PhotoWallpaper.makeArchive(layers: layers, screenAspect: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let files = try unpack(url)
        let bg = String(decoding: try file(PhotoWallpaper.backgroundName + "/main.caml", in: files), as: UTF8.self)
        let fg = String(decoding: try file(PhotoWallpaper.foregroundName + "/main.caml", in: files), as: UTF8.self)
        XCTAssertTrue(bg.contains("layer-0-foreground")); XCTAssertTrue(bg.contains("layer-1-background"))
        XCTAssertFalse(fg.contains("assets/layer-"))
        XCTAssertEqual(PhotoWallpaper.ordered(layers, depth: false).map(\.id), layers.map(\.id))
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
                    memset(CVPixelBufferGetBaseAddress(pixel), frame * 12, CVPixelBufferGetDataSize(pixel))
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
        let caml = String(decoding: try file(PhotoWallpaper.backgroundName + "/main.caml", in: files), as: UTF8.self)
        XCTAssertTrue(caml.contains("CAKeyframeAnimation"))
        XCTAssertGreaterThan(files.keys.filter { $0.hasSuffix(".jpg") }.count, 1)
        XCTAssertNotNil(try file("providerInfo.plist", in: files))
    }
}
