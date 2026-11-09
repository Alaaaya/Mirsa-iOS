import XCTest
@testable import Mirsa

final class CertificateInstallTests: XCTestCase {
    func testStageRejectsMissingAndNonIPA() {
        let dir = FileManager.default.temporaryDirectory
        XCTAssertThrowsError(try CertificateInstall.stageSignedApp(ipa: dir.appendingPathComponent("none.ipa"), in: dir))
        let txt = dir.appendingPathComponent("x-\(UUID().uuidString).txt")
        try? Data("x".utf8).write(to: txt)
        defer { try? FileManager.default.removeItem(at: txt) }
        XCTAssertThrowsError(try CertificateInstall.stageSignedApp(ipa: txt, in: dir))
    }

    func testRetainedMessageNamesFile() {
        let url = URL(fileURLWithPath: "/tmp/App-signed.ipa")
        let m = CertificateInstall.retainedMessage(SideloadError.message("boom"), url)
        XCTAssertTrue(m.contains("boom"))
        XCTAssertTrue(m.contains("App-signed.ipa"))
    }

    func testRetainedFailureCarriesURL() {
        let url = URL(fileURLWithPath: "/tmp/a.ipa")
        if case CertificateInstall.Failure.retained(_, let u) = CertificateInstall.Failure.retained("m", signedURL: url) {
            XCTAssertEqual(u, url)
        } else { XCTFail() }
    }
}

extension CertificateInstallTests {
    func testSigningResultPreservesRealDeviceAuthorizationAndDroppedGroups() {
        let parsed = PersonalProfileVerification.parse([
            "profile_verification": "verified", "device_authorization": "checked",
            "warnings": [["code": "entitlements_dropped", "message": "com.apple.security.application-groups",
                          "bundle_id": "com.kdt.livecontainer"]]
        ])
        XCTAssertEqual(parsed.device_authorization, "checked")
        XCTAssertTrue(parsed.warningText.contains("com.kdt.livecontainer"))
        XCTAssertTrue(parsed.warningText.contains("com.apple.security.application-groups"))
    }
    func testUnknownDeviceIsNotReportedChecked() {
        let parsed = PersonalProfileVerification.parse([
            "profile_verification": "verified", "device_authorization": "not_checked", "warnings": []
        ])
        XCTAssertEqual(parsed.device_authorization, "not_checked")
    }
}

extension CertificateInstallTests {
    func testArchiveInputUsesOriginalBytesWithoutExtractionOrRepacking() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.IPA")
        // Input selection does not parse or trust bytes; the signer must do that.
        let bytes = Data([0x50, 0x4b, 0x03, 0x04, 42])
        try bytes.write(to: original)
        let unusedStage = root.appendingPathComponent("must-not-be-created")
        let input = try CertificateOTA.prepareSigningInput(source: original, sourceIsArchive: true,
                                                           stage: unusedStage, control: PersonalSigningControl())
        XCTAssertEqual(input, original)
        XCTAssertEqual(try Data(contentsOf: input), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: unusedStage.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["original.IPA"])
    }

    func testCancelledPreparationDoesNotReadOrCreateArchive() throws {
        let control = PersonalSigningControl()
        control.cancel()
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try CertificateOTA.prepareSigningInput(source: missing, sourceIsArchive: true,
                                                                   stage: missing, control: control))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testArchiveInputRejectsDirectoriesAndRemoteURLs() throws {
        let temp = FileManager.default.temporaryDirectory
        XCTAssertThrowsError(try CertificateInstall.validateIPA(temp))
        XCTAssertThrowsError(try CertificateInstall.validateIPA(URL(string: "https://example.invalid/app.ipa")!))
    }
}

extension CertificateInstallTests {
    @MainActor
    func testInstallArchiveRetainsExactBytesAndDeduplicates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("signed.ipa")
        let bytes = Data(repeating: 42, count: 4096)
        try bytes.write(to: input)
        let archive = MirsaVersionArchive(root: root.appendingPathComponent("archive"))
        await archive.archiveForInstall(input, bundleID: "test.install", name: "Test", version: "1", signed: true)
        await archive.archiveForInstall(input, bundleID: "test.install", name: "Test", version: "1", signed: true)
        XCTAssertEqual(archive.items.count, 1)
        let item = try XCTUnwrap(archive.items.first)
        XCTAssertEqual(item.bytes, Int64(bytes.count))
        XCTAssertEqual(item.sha256, try MirsaVersionArchive.hash(input))
        XCTAssertEqual(try Data(contentsOf: archive.url(item)), bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
    }
}
