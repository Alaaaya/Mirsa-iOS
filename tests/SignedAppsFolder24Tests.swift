import XCTest
import SwiftUI
@testable import Mirsa

final class SignedAppsFolder24Tests: XCTestCase {
    func testDeleteRemovesWholeRetainedDirectoryAndLeavesOthers() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        var urls: [URL] = []
        for index in 0..<3 {
            let dir = root.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("App\(index).ipa")
            try Data([1, 2, 3]).write(to: url)
            try Data([4]).write(to: dir.appendingPathComponent("Info.plist"))
            urls.append(url)
        }
        try SignedAppsCatalog.delete([urls[0]], root: root)
        XCTAssertFalse(fm.fileExists(atPath: urls[0].deletingLastPathComponent().path))
        XCTAssertTrue(SignedAppsCatalog.available(urls[1], root: root))
        try SignedAppsCatalog.delete(Array(urls.dropFirst()), root: root)
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testDeleteRejectsOutsideAndSymlinkSelectionBeforeAnyRemoval() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: outside) }
        let dir = root.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        let good = dir.appendingPathComponent("good.ipa")
        let other = outside.appendingPathComponent("private.ipa")
        try Data([1]).write(to: good)
        try Data([2]).write(to: other)
        XCTAssertThrowsError(try SignedAppsCatalog.delete([good, other], root: root))
        XCTAssertTrue(fm.fileExists(atPath: good.path))
        let link = root.appendingPathComponent(UUID().uuidString)
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try SignedAppsCatalog.delete([link.appendingPathComponent("private.ipa")], root: root))
        XCTAssertTrue(fm.fileExists(atPath: other.path))
        try SignedAppsCatalog.delete([], root: root)
        XCTAssertTrue(fm.fileExists(atPath: good.path))
    }

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

    private func put(_ target: inout Data, _ parts: [Data]) {
        for part in parts { target.append(part) }
    }

    /// Minimal stored-zip builder so tests control names, bytes and unix modes exactly.
    /// Every append is a separate typed statement so the type checker never sees a long Data concatenation.
    private func zip(_ files: [(String, Data, UInt32)]) -> Data {
        var out = Data()
        var central = Data()
        for (name, bytes, mode) in files {
            let n = Data(name.utf8)
            let crc: UInt32 = CRC32.update(0, bytes)
            let offset = UInt32(out.count)
            let size = UInt32(bytes.count)
            let nameLength = n.count
            var local: [Data] = []
            local.append(le32(0x04034b50))
            local.append(le16(20))
            local.append(le16(0))
            local.append(le16(0))
            local.append(le16(0))
            local.append(le16(0))
            local.append(le32(crc))
            local.append(le32(size))
            local.append(le32(size))
            local.append(le16(nameLength))
            local.append(le16(0))
            local.append(n)
            local.append(bytes)
            put(&out, local)
            var entry: [Data] = []
            entry.append(le32(0x02014b50))
            entry.append(le16(0x031E))
            entry.append(le16(20))
            entry.append(le16(0))
            entry.append(le16(0))
            entry.append(le16(0))
            entry.append(le16(0))
            entry.append(le32(crc))
            entry.append(le32(size))
            entry.append(le32(size))
            entry.append(le16(nameLength))
            entry.append(le16(0))
            entry.append(le16(0))
            entry.append(le16(0))
            entry.append(le16(0))
            entry.append(le32(mode << 16))
            entry.append(le32(offset))
            entry.append(n)
            put(&central, entry)
        }
        let cdOffset = UInt32(out.count)
        let count = files.count
        var footer: [Data] = []
        footer.append(central)
        footer.append(le32(0x06054b50))
        footer.append(le16(0))
        footer.append(le16(0))
        footer.append(le16(count))
        footer.append(le16(count))
        footer.append(le32(UInt32(central.count)))
        footer.append(le32(cdOffset))
        footer.append(le16(0))
        put(&out, footer)
        return out
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

    /// Verify all three known colors in the own-code fixture, independently of image orientation.
    /// The cyan diagonals deliberately lower average red, so a solid-red assertion would be wrong.
    private func assertFixtureArtwork(_ png: Data) throws {
        let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
        let width = image.width
        let height = image.height
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                             bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var cyan = 0
        var magenta = 0
        var yellow = 0
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let r = pixels[index]
                let g = pixels[index + 1]
                let b = pixels[index + 2]
                if r < 30 && g > 150 && b > 180 { cyan += 1 }
                if r > 220 && g < 40 && b > 150 { magenta += 1 }
                if r > 220 && g > 180 && b < 40 { yellow += 1 }
            }
        }
        let minimum = width * height / 10
        XCTAssertGreaterThan(cyan, minimum, "Real artwork must retain its cyan diagonals")
        XCTAssertGreaterThan(magenta, minimum, "Real artwork must retain magenta patches")
        XCTAssertGreaterThan(yellow, minimum, "Real artwork must retain yellow patches")
    }

    func testRealFixtureIconIsExtractedFromSignedIPA() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SignedFolder24Fixture", withExtension: "ipa"))
        let png = try XCTUnwrap(SignedIPAIcon.thumbnailPNG(in: fixture))
        let image = try XCTUnwrap(UIImage(data: png))
        XCTAssertGreaterThanOrEqual(image.size.width, 16)
        try assertFixtureArtwork(png)
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
        let carIcon = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SignedFolder24CarIcon", withExtension: "ipa"))
        let sources: [(String, URL)] = [("A.ipa", withIcon), ("B.ipa", noIcon), ("C.ipa", carIcon)]
        for (name, src) in sources {
            let dir = root.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.copyItem(at: src, to: dir.appendingPathComponent(name))
        }
        let rows = try SignedAppsCatalog.load(root: root)
        XCTAssertEqual(rows.count, 3)
        XCTAssertNotNil(rows.first { $0.url.lastPathComponent == "A.ipa" }?.iconPNG)
        XCTAssertNil(rows.first { $0.url.lastPathComponent == "B.ipa" }?.iconPNG)
        XCTAssertNotNil(rows.first { $0.url.lastPathComponent == "C.ipa" }?.iconPNG, "Assets.car-only IPA must yield its real icon")
    }

    // MARK: Strict icon names, iPad metadata, compiled asset catalog

    private func runAdversarial(_ info: [String: Any], files: [(String, Data)]) throws -> Data? {
        var entries: [(String, Data, UInt32)] = [("Payload/A.app/Info.plist", try plist(info), 0o100644)]
        for (n, d) in files { entries.append(("Payload/A.app/" + n, d, 0o100644)) }
        let url = try write(zip(entries))
        defer { try? FileManager.default.removeItem(at: url) }
        return SignedIPAIcon.thumbnailPNG(in: url)
    }

    func testStrictSuffixMatchingRejectsUnrelatedPrefixes() throws {
        XCTAssertTrue(SignedIPAIcon.matches(file: "Icon.png", name: "Icon"))
        XCTAssertTrue(SignedIPAIcon.matches(file: "Icon.png", name: "Icon.png"))
        XCTAssertTrue(SignedIPAIcon.matches(file: "Icon60x60@2x.png", name: "Icon"))
        XCTAssertTrue(SignedIPAIcon.matches(file: "Icon83.5x83.5@2x~ipad.png", name: "Icon"))
        XCTAssertTrue(SignedIPAIcon.matches(file: "Icon@3x~iphone.png", name: "Icon"))
        XCTAssertTrue(SignedIPAIcon.matches(file: "Icon60x60@2x.png", name: "Icon60x60"))
        XCTAssertFalse(SignedIPAIcon.matches(file: "IconBanner.png", name: "Icon"))
        XCTAssertFalse(SignedIPAIcon.matches(file: "Icon60x60@2x\n.png", name: "Icon"))
        XCTAssertFalse(SignedIPAIcon.matches(file: "Icon\n", name: "Icon"))
        XCTAssertFalse(SignedIPAIcon.matches(file: "Icon-Large.png", name: "Icon"))
        XCTAssertFalse(SignedIPAIcon.matches(file: "Icon60x61@2x.png", name: "Icon"), "non-square size is not an icon")
        XCTAssertFalse(SignedIPAIcon.matches(file: "Icon60x60@4x.png", name: "Icon"))
        XCTAssertFalse(SignedIPAIcon.matches(file: "Icon60x60@2x~tv.png", name: "Icon"))
        XCTAssertFalse(SignedIPAIcon.matches(file: "Icon2000x2000.png", name: "Icon"))
        XCTAssertFalse(SignedIPAIcon.matches(file: "Icon.jpg", name: "Icon"))
        XCTAssertFalse(SignedIPAIcon.matches(file: "Icon.png", name: ""))
    }

    func testUnrelatedPrefixFileIsNotUsedAsIcon() throws {
        let result = try runAdversarial(["CFBundleIconFiles": ["Icon"]],
                                        files: [("IconBanner.png", png(64, red: 1)), ("Icon-extra@2x.png", png(64, red: 1))])
        XCTAssertNil(result)
    }

    func testIPadOnlyMetadataAndExactExtensions() throws {
        let padInfo: [String: Any] = ["CFBundleIcons~ipad": ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["PadIcon"]]]]
        XCTAssertTrue(SignedIPAIcon.iconNames(padInfo).contains("PadIcon"))
        XCTAssertEqual(SignedIPAIcon.iconNames(["CFBundleIconFiles~ipad": ["Top~"], "CFBundleIconFile": "Old"]), ["Top~", "Old", "AppIcon"])
        let found = try runAdversarial(padInfo, files: [("PadIcon76x76@2x~ipad.png", png(152, red: 1))])
        XCTAssertGreaterThan(try dominantRed(try XCTUnwrap(found)), 0.9)
        let pngName = try runAdversarial(["CFBundleIconFiles": ["Named.png"]], files: [("Named@2x.png", png(128, red: 1))])
        XCTAssertNotNil(pngName)
        let wrongExtension = try runAdversarial(["CFBundleIconFiles": ["Named"]], files: [("Named.jpg", png(128, red: 1)), ("Named.png.exe", png(128, red: 1))])
        XCTAssertNil(wrongExtension)
    }

    private func carBytes(from ipaName: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: ipaName, withExtension: "ipa"))
        var limits = IPALimits()
        limits.maxEntries = 20_000
        limits.rejectSymlinks = true
        let zipReader = try ZipReader(data: try Data(contentsOf: url), limits: limits)
        let entry = try XCTUnwrap(zipReader.entry("Payload/SignedFixture.app/Assets.car"))
        return try zipReader.read(entry, length: entry.uncompressedSize, limits: limits)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "SignedFolder24Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testAssetsCarOnlyFixtureHasNoLooseIconsAndYieldsRealIcon() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SignedFolder24CarIcon", withExtension: "ipa"))
        var limits = IPALimits()
        limits.maxEntries = 20_000
        let zipReader = try ZipReader(data: try Data(contentsOf: url), limits: limits)
        XCTAssertFalse(zipReader.entries.contains { $0.name.lowercased().hasSuffix(".png") }, "fixture must be compiled-asset only")
        XCTAssertNotNil(zipReader.entry("Payload/SignedFixture.app/Assets.car"))
        let png = try XCTUnwrap(SignedIPAIcon.thumbnailPNG(in: url))
        XCTAssertGreaterThan(try dominantRed(png), 0.9)
        let image = try XCTUnwrap(UIImage(data: png))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 180)
    }

    func testCarWithUnrelatedNamesYieldsNoIcon() throws {
        let car = try carBytes(from: "SignedFolder24CarIcon")
        XCTAssertNil(SignedIPAIcon.thumbnailPNG(carData: car, names: ["OtherIcon", "IconBanner"], defaults: isolatedDefaults()))
        XCTAssertNotNil(SignedIPAIcon.thumbnailPNG(carData: car, names: ["AppIcon"], defaults: isolatedDefaults()))
    }

    func testInvalidMissingAndOversizeCarFallBack() throws {
        let info: [String: Any] = ["CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconName": "AppIcon"]]]
        let defaults = isolatedDefaults()
        XCTAssertNil(SignedIPAIcon.thumbnailPNG(carData: Data(), names: ["AppIcon"], defaults: defaults))
        XCTAssertNil(SignedIPAIcon.thumbnailPNG(carData: Data(count: 4096), names: ["AppIcon"], defaults: defaults))
        var truncated = Data("BOMStore".utf8)
        truncated.append(Data(count: 600))
        XCTAssertFalse(SignedIPAIcon.isPlausibleBOMStore(truncated), "zero block counts and offsets are malformed")
        XCTAssertNil(SignedIPAIcon.thumbnailPNG(carData: truncated, names: ["AppIcon"], defaults: defaults))
        XCTAssertNil(try runAdversarial(info, files: []), "missing Assets.car")
        let junk = try runAdversarial(info, files: [("Assets.car", Data("not a car".utf8))])
        XCTAssertNil(junk)
        let oversize = try runAdversarial(info, files: [("Assets.car", Data(count: Int(SignedIPAIcon.maxCarBytes) + 1))])
        XCTAssertNil(oversize)
        XCTAssertTrue((defaults.stringArray(forKey: SignedIPAIcon.quarantineKey) ?? []).isEmpty)
    }

    func testCrashMarkerQuarantinesCarAndIsClearedAfterNormalParse() throws {
        let car = try carBytes(from: "SignedFolder24CarIcon")
        let digest = SignedIPAIcon.carDigest(car)
        let defaults = isolatedDefaults()
        XCTAssertFalse(SignedIPAIcon.isQuarantined(digest, defaults: defaults))
        XCTAssertNotNil(SignedIPAIcon.thumbnailPNG(carData: car, names: ["AppIcon"], defaults: defaults))
        XCTAssertFalse(SignedIPAIcon.isQuarantined(digest, defaults: defaults), "marker cleared after a normal return")
        // Simulate a previous launch that crashed mid-parse: the marker remains and the car is skipped.
        defaults.set([digest], forKey: SignedIPAIcon.quarantineKey)
        XCTAssertNil(SignedIPAIcon.thumbnailPNG(carData: car, names: ["AppIcon"], defaults: defaults))
        XCTAssertTrue(SignedIPAIcon.isQuarantined(digest, defaults: defaults))
    }
}
