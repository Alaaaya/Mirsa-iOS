import XCTest
import UIKit
import AssetCatalogWrapper
@testable import Mirsa

final class CertificateDarkIcon29Tests: XCTestCase {
    func testCatalogActuallyRewrittenAndOtherAssetsPreserved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Assets", withExtension: "car"))
        let catalogURL = root.appendingPathComponent("Assets.car")
        try FileManager.default.copyItem(at: fixture, to: catalogURL)
        let (_, original) = try AssetCatalogWrapper.shared.renditions(forCarArchive: catalogURL)
        let renditions = original.flatMap(\.renditions)
        func pixels(_ collection: [Rendition], excluding name: String) -> [String: Data] {
            var output: [String: Data] = [:]
            for r in collection where r.namedLookup.name != name {
                if let image = r.image, let data = UIImage(cgImage: image).pngData() {
                    output["\(PersonalDarkIconFixer.record(r))"] = data
                }
            }
            return output
        }
        let unrelatedBefore = pixels(renditions, excluding: "MirsaParityPrimary")
        XCTAssertFalse(unrelatedBefore.isEmpty)
        let beforeBytes = try Data(contentsOf: catalogURL)
        let removed = try PersonalDarkIconFixer.repair(app: root, info: ["CFBundleIconName": "MirsaParityPrimary"])
        XCTAssertGreaterThan(removed, 0, "Must execute a real CoreUI catalog mutation, not silently no-op")
        XCTAssertNotEqual(try Data(contentsOf: catalogURL), beforeBytes)
        let (_, after) = try AssetCatalogWrapper.shared.renditions(forCarArchive: catalogURL)
        let remaining = after.flatMap(\.renditions)
        XCTAssertEqual(unrelatedBefore, pixels(remaining, excluding: "MirsaParityPrimary"))
        XCTAssertFalse(remaining.contains { $0.namedLookup.name == "MirsaParityPrimary" && $0.namedLookup.key.themeAppearance == 1 })
        XCTAssertTrue(remaining.contains { $0.namedLookup.name == "MirsaParityPrimary" && $0.namedLookup.key.themeAppearance == 0 })
        XCTAssertEqual(try PersonalDarkIconFixer.repair(app: root, info: ["CFBundleIconName": "MirsaParityPrimary"]), 0)
        let beforeNoDefault = try Data(contentsOf: catalogURL)
        XCTAssertEqual(try PersonalDarkIconFixer.repair(app: root, info: ["CFBundleIconName": "MirsaParityNoDefault"]), 0)
        XCTAssertEqual(try Data(contentsOf: catalogURL), beforeNoDefault)
    }
    func testOnlyPrimaryIconNamesAndNoCatalogIsNotAnError() throws {
        XCTAssertEqual(PersonalDarkIconFixer.primaryNames([
            "CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconName": "Primary"],
                              "CFBundleAlternateIcons": ["Other": ["CFBundleIconName": "Alternate"]]]
        ]), ["Primary"])
        XCTAssertFalse(PersonalProjectOptions().fixDarkIcon)
        XCTAssertEqual(try PersonalDarkIconFixer.repair(app: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), info: [:]), 0)
    }
}
