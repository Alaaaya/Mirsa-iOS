import XCTest
import ImageIO
import CoreGraphics
@testable import Mirsa

final class PersonalLibraryIconTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func png() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
            bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let output = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(output, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(output))
        return data as Data
    }
    func testCatalogOnlyAndMissingIconsReturnPlaceholder() throws {
        let bundle = try directory()
        try Data("not a real catalog".utf8).write(to: bundle.appendingPathComponent("Assets.car"))
        XCTAssertNil(PersonalAppsLibrary.iconPNG(bundle: bundle,
            info: ["CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconName": "AppIcon"]]]))
    }
    func testLoosePNGWithoutInfoAndCorruptCandidateFallback() throws {
        let bundle = try directory()
        try Data(repeating: 0, count: 2048).write(to: bundle.appendingPathComponent("AppIconBad.png"))
        try png().write(to: bundle.appendingPathComponent("AppIcon60@3x.png"))
        let result = try XCTUnwrap(PersonalAppsLibrary.iconPNG(bundle: bundle, info: [:]))
        XCTAssertNotNil(CGImageSourceCreateWithData(result as CFData, nil))
    }
    func testNamedPNGAndBackgroundDecode() async throws {
        let bundle = try directory()
        try png().write(to: bundle.appendingPathComponent("Custom60@3x.png"))
        let result = await Task.detached {
            PersonalAppsLibrary.iconPNG(bundle: bundle, info: ["CFBundleIconFiles": ["Custom60"]])
        }.value
        XCTAssertNotNil(result)
    }
    func testActualLiveContainerPrimaryIconExtractedFromIPA() throws {
        let bundle = try directory()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LiveContainer-primary-CgBI.png")
        let bytes = try Data(contentsOf: fixture)
        try bytes.write(to: bundle.appendingPathComponent("AppIcon60x60@2x.png"))
        // A generic or alternate icon must not replace the declared primary.
        try png().write(to: bundle.appendingPathComponent("DefaultIcon.png"))
        try png().write(to: bundle.appendingPathComponent("AppIconGrey60x60@2x.png"))
        let info: [String: Any] = ["CFBundleIcons": ["CFBundlePrimaryIcon":
            ["CFBundleIconFiles": ["AppIcon60x60"], "CFBundleIconName": "AppIcon"]]]
        let result = try XCTUnwrap(PersonalAppsLibrary.iconPNG(bundle: bundle, info: info))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 120)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 120)
    }

    func testDeclaredIconNameAndNestedPrimaryPNG() throws {
        let bundle = try directory()
        let folder = bundle.appendingPathComponent("Artwork")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png().write(to: folder.appendingPathComponent("Primary@3x.png"))
        XCTAssertNotNil(PersonalAppsLibrary.iconPNG(bundle: bundle, info: ["CFBundleIconName": "Artwork/Primary"]))
        XCTAssertNil(PersonalAppsLibrary.iconPNG(bundle: bundle, info: ["CFBundleIconName": "../Primary"]))
    }

    func testGenericAppIconDoesNotSelectAlternateGreyIcon() throws {
        let bundle = try directory()
        try png().write(to: bundle.appendingPathComponent("AppIconGrey60@3x.png"))
        XCTAssertNil(PersonalAppsLibrary.iconPNG(bundle: bundle, info: ["CFBundleIconName": "AppIcon"]))
    }

    func testMalformedAndCrushedPNGsFailClosed() throws {
        XCTAssertNil(PersonalAppsLibrary.validatedIconPNG(Data()))
        XCTAssertNil(PersonalAppsLibrary.validatedIconPNG(Data(repeating: 0, count: 100)))
        let valid = try png()
        XCTAssertNotNil(PersonalAppsLibrary.validatedIconPNG(valid))
        XCTAssertNil(PersonalAppsLibrary.validatedIconPNG(Data(valid.dropLast())))
        var crushed = Data([137,80,78,71,13,10,26,10,0,0,0,4])
        crushed.append(Data("CgBI".utf8))
        crushed.append(Data(repeating: 0, count: 8))
        crushed.append(valid.dropFirst(8))
        XCTAssertNil(PersonalAppsLibrary.validatedIconPNG(crushed))
    }
    func testSymlinkIconOutsideBundleRejected() throws {
        let bundle = try directory(), outside = try directory().appendingPathComponent("outside.png")
        try png().write(to: outside)
        try FileManager.default.createSymbolicLink(at: bundle.appendingPathComponent("AppIcon.png"), withDestinationURL: outside)
        XCTAssertNil(PersonalAppsLibrary.iconPNG(bundle: bundle, info: [:]))
    }
}
