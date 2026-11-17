import XCTest
import Foundation
@testable import Mirsa

final class MirsaDiagnosticPrivacyTests: XCTestCase {
    // Synthetic canaries only. Never use live account/session/device information in tests.
    private let secret = "FixtureSecret_OnlyForRegression_924681"
    private let device = "01020304-0506-4708-890a-0b0c0d0e0f10"
    private var raw: [String] {
        ["COPY VERIFIED files=25 errno=0 uuid=\(device)",
         "INSTALL ERROR code=403 deviceToken=\(secret) count=2",
         "Authorization: Bearer \(secret)",
         "cookie=session=\(secret); private=true",
         "user_id=\(device) code=401",
         "accountName=Fixture Person code=403 count=2",
         "path=\"/private/var/mobile/Containers/Data/Application/\(device)/Documents/Fixture Person/key\" errno=2 files=25",
         "email=fixture-person@example.invalid code=403",
         "source https://example.invalid/private?token=\(secret)",
         "deviceID=\(device) code=2",
         "accountId=123456789012345 code=404",
         "credential \(secret)",
         "escaped %2Fvar%2Fmobile%2FContainers%2FFixturePrivate code=2",
         #"escaped \u002Fvar\u002Fmobile\u002FFixturePrivate code=2"#,
         #"escaped \/var\/mobile\/FixturePrivate code=2"#,
         "PRIVATE KEY: -----BEGIN PRIVATE KEY-----\nSHORTFIXTUREKEY\n-----END PRIVATE KEY-----",
         "address 192.168.50.42 code=2"]
    }
    private func assertSafe(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        for forbidden in [secret, device, "Fixture Person", "fixture-person@example.invalid", "FixturePrivate", "123456789012345", "SHORTFIXTUREKEY", "192.168.50.42", "/var/mobile", "/private/var", "example.invalid/private"] {
            XCTAssertFalse(text.contains(forbidden), "Synthetic privacy canary leaked", file: file, line: line)
        }
    }
    func testDisplayCopyAndExportUseIdenticalSanitizedFormatting() throws {
        let display = MirsaDiagnosticPrivacy.lines(raw).joined(separator: "\n")
        var clipboard = ""
        MirsaDiagnosticPrivacy.copy(raw) { clipboard = $0 }
        let export = try XCTUnwrap(String(data: MirsaDiagnosticPrivacy.export(raw), encoding: .utf8))
        for text in [display, clipboard, export] { assertSafe(text) }
        XCTAssertEqual(display, clipboard)
        XCTAssertEqual(display, export)
        for useful in ["COPY VERIFIED", "INSTALL ERROR", "files=25", "errno=2", "code=403", "count=2"] {
            XCTAssertTrue(display.contains(useful), "Nonsensitive event/code/count must survive")
        }
        XCTAssertEqual(MirsaDiagnosticPrivacy.formatted(MirsaDiagnosticPrivacy.lines(raw)), display)
    }
    func testControlAndPercentEncodingCannotHideFields() {
        for input in ["token=\(secret)", "tok\u{200B}en=\(secret)", "token%3D\(secret)",
                      "token%253D\(secret)", "token=\u{1B}[31m\(secret)\u{1B}[0m"] {
            assertSafe(MirsaDiagnosticPrivacy.line(input))
        }
        XCTAssertEqual(MirsaDiagnosticPrivacy.line(String(repeating: "x", count: 70_000)), "[oversized diagnostic omitted]")
        XCTAssertTrue(MirsaDiagnosticPrivacy.line(String(repeating: "word ", count: 1000)).count <= 2048)
        let splitPEM = ["-----BEGIN PRIVATE KEY-----", "SHORTFIXTUREKEY", "-----END PRIVATE KEY-----", "COPY VERIFIED files=25"]
        assertSafe(MirsaDiagnosticPrivacy.formatted(splitPEM))
        XCTAssertTrue(MirsaDiagnosticPrivacy.formatted(splitPEM).contains("COPY VERIFIED files=25"))
        let stream = MirsaDiagnosticPrivacy.Stream()
        assertSafe(splitPEM.map { stream.line($0) }.joined(separator: "\n"))
        var incremental: [String] = []
        for raw in splitPEM { incremental = MirsaDiagnosticPrivacy.lines(incremental + [raw]) }
        assertSafe(incremental.joined(separator: "\n"))
    }
    func testHistoricalEvidenceIsSanitizedAndRewrittenAndNewAppendNeverPersistsRaw() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("history.json")
        try JSONEncoder().encode(raw).write(to: file)
        let restored = try MirsaWallpaperEvidence.restore(at: file)
        assertSafe(MirsaDiagnosticPrivacy.formatted(restored))
        assertSafe(try String(contentsOf: file, encoding: .utf8))
        try MirsaWallpaperEvidence.append("INSTALL ERROR code=403 token=\(secret) files=25", at: file)
        for part in ["-----BEGIN PRIVATE KEY-----", "SHORTFIXTUREKEY", "-----END PRIVATE KEY-----"] {
            try MirsaWallpaperEvidence.append(part, at: file)
        }
        let persisted = try String(contentsOf: file, encoding: .utf8)
        assertSafe(persisted)
        XCTAssertTrue(persisted.contains("files=25"))
        XCTAssertTrue(try MirsaWallpaperEvidence.read(at: file).allSatisfy { $0.count <= 2048 })
    }
    func testLegacyInstallBreadcrumbsAreRemovedNotPublishedAsError() throws {
        let suite = "mirsa.synthetic.privacy." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("INSTALL token=\(secret)", forKey: "mirsa.install.stage")
        defaults.set(raw.joined(separator: "\n"), forKey: "mirsa.install.lastLog")
        assertSafe(MirsaDiagnosticPrivacy.formatted(MirsaDiagnosticPrivacy.migrateInstallBreadcrumbs(defaults)))
        XCTAssertNil(defaults.object(forKey: "mirsa.install.stage"))
        XCTAssertNil(defaults.object(forKey: "mirsa.install.lastLog"))
    }
}

@MainActor final class MirsaDiagnosticAccessTests: XCTestCase {
    func testUnauthenticatedAndNonownerCannotPerformAnyDiagnosticAction() async {
        var verifications = 0, actions = 0
        let unauthenticated = MirsaDiagnosticAccess(identity: { nil }, verify: { verifications += 1; return true })
        XCTAssertFalse(unauthenticated.allowed)
        await unauthenticated.perform { actions += 1 }
        XCTAssertFalse(unauthenticated.allowed)
        XCTAssertEqual(verifications, 0)
        let ordinary = MirsaDiagnosticAccess(identity: { "synthetic-session" }, verify: { false })
        await ordinary.perform { actions += 1 }
        XCTAssertFalse(ordinary.allowed)
        XCTAssertEqual(actions, 0)
    }
    func testOnlyVerifiedAdminMayCopyAndRevocationRechecksAction() async {
        var granted = true, actions = 0
        let access = MirsaDiagnosticAccess(identity: { "synthetic-session" }, verify: { granted })
        var clipboard = ""
        await access.perform {
            actions += 1
            MirsaDiagnosticPrivacy.copy(["COPY VERIFIED files=25 token=fixture-private-value code=403"]) { clipboard = $0 }
        }
        XCTAssertTrue(access.allowed)
        XCTAssertEqual(actions, 1)
        XCTAssertFalse(clipboard.contains("fixture-private-value"))
        granted = false
        await access.perform { actions += 1 }
        XCTAssertFalse(access.allowed)
        XCTAssertEqual(actions, 1)
    }
    func testLoadingCredentialChangeAndBackgroundFailClosed() async {
        var identity: String? = "synthetic-A"
        var continuation: CheckedContinuation<Bool, Never>?
        let access = MirsaDiagnosticAccess(identity: { identity }, verify: {
            await withCheckedContinuation { continuation = $0 }
        })
        let pending = Task { await access.refresh() }
        while continuation == nil { await Task.yield() }
        XCTAssertFalse(access.allowed, "Loading must expose no diagnostic content")
        identity = "synthetic-B"
        continuation?.resume(returning: true)
        let staleResult = await pending.value
        XCTAssertFalse(staleResult)
        XCTAssertFalse(access.allowed, "Old identity response is not authority")
        let owner = MirsaDiagnosticAccess(identity: { identity }, verify: { true })
        let result = await owner.refresh()
        XCTAssertTrue(result)
        owner.revoke() // scene background/disappearance
        XCTAssertFalse(owner.allowed)
        let second = await owner.refresh()
        XCTAssertTrue(second)
        identity = nil
        owner.invalidateIfIdentityChanged()
        XCTAssertFalse(owner.allowed)
    }
    func testExplicitRevokeInvalidatesInFlightServerResponse() async {
        var continuation: CheckedContinuation<Bool, Never>?
        let access = MirsaDiagnosticAccess(identity: { "synthetic-session" }, verify: {
            await withCheckedContinuation { continuation = $0 }
        })
        let task = Task { await access.refresh() }
        while continuation == nil { await Task.yield() }
        access.revoke()
        continuation?.resume(returning: true)
        let result = await task.value
        XCTAssertFalse(result)
        XCTAssertFalse(access.allowed)
    }
}
