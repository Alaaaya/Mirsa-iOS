import XCTest
import SwiftUI
@testable import Mirsa

final class SignedAppsFolder24Tests: XCTestCase {
    func testMissingEmptyUnsignedAndSymlinkInputsAreExcluded() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertTrue(try SignedAppsCatalog.load(root: root).isEmpty)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("unsigned-import.ipa"))
        let dir = root.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent("empty.ipa"))
        let outside = root.appendingPathComponent("unsigned-import.ipa")
        try fm.createSymbolicLink(at: dir.appendingPathComponent("link.ipa"), withDestinationURL: outside)
        XCTAssertTrue(try SignedAppsCatalog.load(root: root).isEmpty)
        XCTAssertFalse(SignedAppsCatalog.available(outside, root: root))
    }

    /// This fixture is a real own-code arm64 Mach-O ad-hoc signed by codesign in CI.
    /// It proves retention/export bytes, not certificate provisioning or installation.
    @MainActor func testSignedOutputRetentionSurvivesTempCleanupAndSharesExactIPA() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SignedFolder24Fixture", withExtension: "ipa"))
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let source = tmp.appendingPathComponent("SignedFolder24Fixture.ipa")
        let bytes = try Data(contentsOf: fixture)
        try bytes.write(to: source)
        let metadata = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleDisplayName": "CI Signing Fixture", "CFBundleShortVersionString": "1.0"
        ], format: .binary, options: 0)
        let retained = try CertificateInstall.retain(source, signedInfoPlist: metadata)
        defer { try? fm.removeItem(at: retained.deletingLastPathComponent()) }
        try? fm.removeItem(at: tmp)
        XCTAssertFalse(fm.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: retained), bytes)
        let row = try XCTUnwrap(try SignedAppsCatalog.load().first { $0.url == retained })
        XCTAssertEqual(row.name, "CI Signing Fixture")
        XCTAssertEqual(row.version, "1.0")
        XCTAssertEqual(row.bytes, Int64(bytes.count))
        XCTAssertTrue(SignedAppsCatalog.available(row.url))
        let host = UIHostingController(rootView: PersonalSignedShare(url: row.url))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let original = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; original?.makeKey() }
        host.loadViewIfNeeded()
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(host.children.contains { $0 is UIActivityViewController },
                      "Production share representable must create a real system share controller")
        XCTAssertEqual(try Data(contentsOf: row.url), bytes)
        try fm.removeItem(at: retained)
        XCTAssertFalse(SignedAppsCatalog.available(row.url))
        XCTAssertFalse(try SignedAppsCatalog.load().contains { $0.id == row.id })
    }

    func testLegacyRetainedFilesUseFilenameWithoutInventingMetadata() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = root.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let url = dir.appendingPathComponent("Legacy-signed.ipa")
        try Data([80, 75, 3, 4]).write(to: url)
        let row = try XCTUnwrap(try SignedAppsCatalog.load(root: root).first)
        XCTAssertEqual(row.name, "Legacy-signed")
        XCTAssertEqual(row.version, "")
        XCTAssertEqual(row.url, url)
    }

    // MARK: Real icon extraction from the retained SIGNED IPA

    private func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
    private func le32(_ v: UInt32) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]) }

    /// Minimal stored-zip builder so tests control names, bytes and unix modes exactly.
    private func zip(_ files: [(String, Data, UInt32)]) -> Data {
        var out = Data(), central = Data()
        for (name, bytes, mode) in files {
            let n = Data(name.utf8), crc = CRC32.update(0, bytes), offset = UInt32(out.count)
            out += le32(0x04034b50) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + le32(crc)
                + le32(UInt32(bytes.count)) + le32(UInt32(bytes.count)) + le16(n.count) + le16(0) + n + bytes
            central += le32(0x02014b50) + le16(0x031E) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + le32(crc)
                + le32(UInt32(bytes.count)) + le32(UInt32(bytes.count)) + le16(n.count) + le16(0) + le16(0)
                + le16(0) + le16(0) + le32(mode << 16) + le32(offset) + n
        }
        let cdOffset = UInt32(out.count)
        return out + central + le32(0x06054b50) + le16(0) + le16(0) + le16(files.count) + le16(files.count)
            + le32(UInt32(central.count)) + le32(cdOffset) + le16(0)
    }

    private func png(_ side: Int, red: CGFloat) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side),
                                               format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return renderer.pngData { ctx in
            UIColor(red: red, green: 0.1, blue: 0.9, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private func plist(_ d: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: d, format: .binary, options: 0)
    }

    private func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        try data.write(to: url)
        return url
    }

    private func dominantRed(_ png: Data) throws -> CGFloat {
        let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return CGFloat(ctx.data!.load(as: UInt8.self)) / 255
    }

    func testRealFixtureIconIsExtractedFromSignedIPA() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SignedFolder24Fixture", withExtension: "ipa"))
        let png = try XCTUnwrap(SignedIPAIcon.thumbnailPNG(in: fixture))
        let image = try XCTUnwrap(UIImage(data: png))
        XCTAssertGreaterThanOrEqual(image.size.width, 16)
        XCTAssertGreaterThan(try dominantRed(png), 0.9, "Distinct magenta/yellow fixture art, not a generic symbol")
    }

    func testFixtureWithoutIconFallsBack() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SignedFolder24NoIcon", withExtension: "ipa"))
        XCTAssertNil(SignedIPAIcon.thumbnailPNG(in: fixture))
    }

    func testIconPrecedencePrimaryBeforeTopLevelAndLargestWins() throws {
        let info = try plist(["CFBundleIdentifier": "x.y", "CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["Primary"]]],
                              "CFBundleIconFiles": ["Top"]])
        let url = try write(zip([
            ("Payload/A.app/Info.plist", info, 0o100644),
            ("Payload/A.app/Top60x60@2x.png", png(120, red: 0.0), 0o100644),
            ("Payload/A.app/Primary29x29.png", png(29, red: 1.0), 0o100644),
            ("Payload/A.app/Primary60x60@2x.png", png(120, red: 1.0), 0o100644)]))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertGreaterThan(try dominantRed(try XCTUnwrap(SignedIPAIcon.thumbnailPNG(in: url))), 0.9)
        XCTAssertEqual(SignedIPAIcon.iconNames(["CFBundleIconFile": "Legacy", "CFBundleIconFiles": ["Top"]]), ["Top", "Legacy", "AppIcon"])
    }

    func testMalformedMissingAndAmbiguousArchivesYieldNoIcon() throws {
        let info = try plist(["CFBundleIconFiles": ["Icon"]])
        let cases: [Data] = [
            Data([1, 2, 3]),
            zip([("Payload/A.app/Info.plist", info, 0o100644)]),
            zip([("Payload/A.app/Info.plist", Data([0, 1]), 0o100644), ("Payload/A.app/Icon.png", png(64, red: 1), 0o100644)]),
            zip([("Payload/A.app/Info.plist", info, 0o100644), ("Payload/A.app/Icon.png", Data("not a png".utf8), 0o100644)]),
            zip([("Payload/A.app/Info.plist", info, 0o100644), ("Payload/B.app/Info.plist", info, 0o100644),
                 ("Payload/A.app/Icon.png", png(64, red: 1), 0o100644)]),
            zip([("Payload/A.app/Info.plist", info, 0o100644), ("Payload/A.app/Frameworks/Icon.png", png(64, red: 1), 0o100644)]),
            zip([("Payload/A.app/Info.plist", info, 0o100644), ("Payload/A.app/Icon.png", png(8, red: 1), 0o100644)])
        ]
        for data in cases {
            let url = try write(data)
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertNil(SignedIPAIcon.thumbnailPNG(in: url))
        }
    }

    func testUnsafePathsSymlinksAndOversizeAreRejected() throws {
        let info = try plist(["CFBundleIconFiles": ["Icon"]])
        let good = png(64, red: 1)
        let traversal = try write(zip([("Payload/A.app/Info.plist", info, 0o100644), ("Payload/A.app/../Icon.png", good, 0o100644)]))
        let symlink = try write(zip([("Payload/A.app/Info.plist", info, 0o100644), ("Payload/A.app/Icon.png", good, 0o120777)]))
        let huge = try write(zip([("Payload/A.app/Info.plist", info, 0o100644),
                                  ("Payload/A.app/Icon.png", Data(count: Int(SignedIPAIcon.maxEntryBytes) + 1), 0o100644)]))
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        let target = try write(zip([("Payload/A.app/Info.plist", info, 0o100644), ("Payload/A.app/Icon.png", good, 0o100644)]))
        try FileManager.default.createSymbolicLink(at: outside, withDestinationURL: target)
        defer { for u in [traversal, symlink, huge, outside, target] { try? FileManager.default.removeItem(at: u) } }
        XCTAssertNil(SignedIPAIcon.thumbnailPNG(in: traversal))
        XCTAssertNil(SignedIPAIcon.thumbnailPNG(in: symlink))
        XCTAssertNil(SignedIPAIcon.thumbnailPNG(in: huge))
        XCTAssertNil(SignedIPAIcon.thumbnailPNG(in: outside), "A symlinked IPA must never be read")
        XCTAssertNotNil(SignedIPAIcon.thumbnailPNG(in: target))
    }

    func testCatalogRowCarriesIconOnlyWhenSignedIPAHasOne() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let withIcon = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SignedFolder24Fixture", withExtension: "ipa"))
        let noIcon = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SignedFolder24NoIcon", withExtension: "ipa"))
        for (name, src) in [("A.ipa", withIcon), ("B.ipa", noIcon)] {
            let dir = root.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.copyItem(at: src, to: dir.appendingPathComponent(name))
        }
        let rows = try SignedAppsCatalog.load(root: root)
        XCTAssertEqual(rows.count, 2)
        XCTAssertNotNil(rows.first { $0.url.lastPathComponent == "A.ipa" }?.iconPNG)
        XCTAssertNil(rows.first { $0.url.lastPathComponent == "B.ipa" }?.iconPNG)
    }
}
