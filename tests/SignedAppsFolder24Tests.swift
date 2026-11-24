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
}
