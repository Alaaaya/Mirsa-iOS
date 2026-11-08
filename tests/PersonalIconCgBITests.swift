import XCTest
import Compression
import ImageIO
@testable import Mirsa

final class PersonalIconCgBITests: XCTestCase {
    private func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
        var out = [UInt8](); let n = body.count
        out += [UInt8(n >> 24 & 255), UInt8(n >> 16 & 255), UInt8(n >> 8 & 255), UInt8(n & 255)]
        out += Array(type.utf8) + body + [0, 0, 0, 0]; return out
    }
    private func cgbi(width: Int = 4, height: Int = 4, color: UInt8 = 6) -> Data {
        var raw = [UInt8]()
        for _ in 0..<height { raw.append(0); for _ in 0..<width { raw += [0, 0, 200, 255] } } // BGRA red
        var comp = [UInt8](repeating: 0, count: raw.count + 64)
        let n = compression_encode_buffer(&comp, comp.count, raw, raw.count, nil, COMPRESSION_ZLIB)
        var ihdr = [UInt8](); for v in [width, height] { ihdr += [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }
        ihdr += [8, color, 0, 0, 0]
        var png: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        png += chunk("CgBI", [0, 0, 0, 0]) + chunk("IHDR", ihdr) + chunk("IDAT", Array(comp[0..<n])) + chunk("IEND", [])
        return Data(png)
    }
    func testCgBIConvertsToDecodablePNG() throws {
        let out = try XCTUnwrap(PersonalAppsLibrary.cgbiIconPNG(cgbi()))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(out as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(src), 1)
        XCTAssertNotNil(PersonalAppsLibrary.validatedIconPNG(cgbi()))
    }
    func testMalformedCgBIReturnsNil() {
        XCTAssertNil(PersonalAppsLibrary.cgbiIconPNG(Data([1, 2, 3])))
        XCTAssertNil(PersonalAppsLibrary.cgbiIconPNG(cgbi(color: 2)))
        var d = cgbi(); d.removeLast(20)
        XCTAssertNil(PersonalAppsLibrary.cgbiIconPNG(d))
        XCTAssertNil(PersonalAppsLibrary.validatedIconPNG(Data()))
    }
    func testIconPathVariantsAndMissing() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("icontest-" + UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? fm.removeItem(at: dir) }
        XCTAssertNil(PersonalAppsLibrary.iconPNG(bundle: dir, info: [:]))
        try cgbi().write(to: dir.appendingPathComponent("AppIcon60x60@2x.png"))
        let info: [String: Any] = ["CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["AppIcon60x60"]]]]
        XCTAssertNotNil(PersonalAppsLibrary.iconPNG(bundle: dir, info: info))
        XCTAssertNotNil(PersonalAppsLibrary.iconPNG(bundle: dir, info: ["CFBundleIconFiles": ["AppIcon60x60.png"]]))
        XCTAssertNotNil(PersonalAppsLibrary.iconPNG(bundle: dir, info: ["CFBundleIconFile": "AppIcon60x60"]))
        try Data("junk".utf8).write(to: dir.appendingPathComponent("AppIcon76x76.png"))
        XCTAssertNotNil(PersonalAppsLibrary.iconPNG(bundle: dir, info: [:]))
    }
    func testNoForeignBundleLookupInSource() throws {
        let src = try String(contentsOfFile: #filePath.replacingOccurrences(of: "tests/PersonalIconCgBITests.swift", with: "ios-app/Apps/PersonalAppsLibrary.swift"))
        XCTAssertFalse(src.contains("UIImage(named"))
        XCTAssertFalse(src.contains("imageNamed"))
    }
    func testStampChangesWithFile() throws {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("stamp-" + UUID().uuidString)
        try Data("a".utf8).write(to: u); defer { try? FileManager.default.removeItem(at: u) }
        let a = PersonalAppsLibrary.stamp(u); try Data("bb".utf8).write(to: u)
        XCTAssertNotEqual(a, PersonalAppsLibrary.stamp(u))
    }
}
