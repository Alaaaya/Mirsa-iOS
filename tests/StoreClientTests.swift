import Foundation
import XCTest
import ApplePackage
import ZIPFoundation
#if canImport(MirsaStoreKit)
@testable import MirsaStoreKit
#else
@testable import Mirsa
#endif

private final class StoreTestVault: MirsaStoreVault {
    var data: [String: Data] = [:]
    var failWrite = false
    var failDeleteAccount = false
    var removed: [String] = []
    func read(_ key: String) throws -> Data? { data[key] }
    func write(_ data: Data, key: String) throws {
        if failWrite { throw MirsaStoreError.keychain(-1) }
        self.data[key] = data
    }
    func remove(_ key: String) throws {
        removed.append(key)
        if key == "account" && failDeleteAccount { throw MirsaStoreError.keychain(-1) }
        data[key] = nil
    }
}

private func testOwner() -> Account {
    Account(email: "owner@example.invalid", password: "fixture-password", appleId: "1", store: "143443",
            firstName: "Owner", lastName: "", passwordToken: "fixture-token",
            directoryServicesIdentifier: "123", cookie: [])
}
private func testSoftware(price: Double? = 0, id: Int64 = 42) -> Software {
    Software(id: id, bundleID: "com.example.fixture", name: "Fixture", version: "1.0", price: price,
             artistName: "", sellerName: "", description: "", averageUserRating: 0, userRatingCount: 0,
             artworkUrl: "", screenshotUrls: [], minimumOsVersion: "18.0", releaseDate: "", primaryGenreName: "")
}
private final class StoreTestAuth: MirsaStoreAuthentication {
    var calls: [String] = []
    var passwords: [String] = []
    var twoFactor = false
    var diagnostic: MirsaStoreAuthDiagnostic?
    var paused: CheckedContinuation<Account, Error>?
    var pause = false
    func authenticate(email: String, password: String, code: String) async throws -> Account {
        calls.append(code)
        passwords.append(password)
        if let diagnostic { throw diagnostic }
        if pause { return try await withCheckedThrowingContinuation { paused = $0 } }
        if twoFactor && code != "123456" { throw AuthenticationError.verificationCodeRequired }
        return testOwner()
    }
}
private final class StoreTestEngine: MirsaStoreEngine {
    let auth = StoreTestAuth()
    var authCreations = 0
    var failSetup = false
    var guids: [String] = []
    var app = testSoftware()
    var lookupCountries: [String] = []
    var acquisitions = 0
    var manifests = 0
    var seenVersion: String?
    var failManifest = false
    var versionApps: [Software] = []
    var versionsResult = ["123", "456"]
    var output: DownloadOutput {
        get throws {
            let metadata: [String: Any] = ["itemId": 42, "softwareVersionBundleId": "com.example.fixture",
                                            "softwareVersionExternalIdentifier": seenVersion ?? "999"]
            return DownloadOutput(downloadURL: "https://apps.mzstatic.com/fixture.ipa",
                                  sinfs: [Sinf(id: 0, sinf: Data([1, 2, 3]))],
                                  bundleShortVersionString: "1.0", bundleVersion: "1",
                                  iTunesMetadata: try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0))
        }
    }
    func configure(guid: String) { guids.append(guid) }
    func authentication() async throws -> any MirsaStoreAuthentication {
        authCreations += 1
        if failSetup { throw MirsaStoreError.serviceUnavailable }
        return auth
    }
    func search(term: String, country: String, limit: Int) async throws -> [Software] { [app] }
    func lookup(bundleID: String, country: String) async throws -> Software { lookupCountries.append(country); return app }
    func acquire(account: inout Account, app: Software) async throws { acquisitions += 1 }
    func manifest(account: inout Account, app: Software, version: String?) async throws -> DownloadOutput {
        manifests += 1; seenVersion = version
        if failManifest { throw ApplePackageError.licenseRequired }
        return try output
    }
    func versions(account: inout Account, app: Software) async throws -> [String] { versionApps.append(app); return versionsResult }
}
private final class StoreTestPackages: MirsaStorePackages {
    var calls = 0
    var cancellations = 0
    func cancel() { cancellations += 1 }
    func fetch(output: DownloadOutput, bundleID: String) async throws -> URL {
        calls += 1
        return URL(fileURLWithPath: "/tmp/MirsaStore-test/App.ipa")
    }
}

private actor StoreAccountGatePause {
    private var continuation: CheckedContinuation<Bool, Never>?
    private(set) var entered = false
    func wait() async -> Bool {
        entered = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func resume() { continuation?.resume(returning: true); continuation = nil }
}

final class MirsaStoreClientTests: XCTestCase {
    func testAccountVaultNamespacesNeverOverlapAndLegacySessionRemainsInPlace() throws {
        let base = StoreTestVault()
        let legacy = MirsaStoreAccountVault(base: base, id: "legacy")
        let other = MirsaStoreAccountVault(base: base, id: UUID().uuidString)
        for key in ["account", "machine", "challenge"] {
            try legacy.write(Data("old".utf8), key: key)
            try other.write(Data("new".utf8), key: key)
            XCTAssertEqual(try legacy.read(key), Data("old".utf8))
            XCTAssertEqual(try other.read(key), Data("new".utf8))
            try other.remove(key)
            XCTAssertEqual(try legacy.read(key), Data("old".utf8))
        }
        XCTAssertEqual(base.data["native.account"], Data("old".utf8))
    }

    func testAccountSwitchDuringAuthorizationKeepsCapturedAccountAndGUID() async throws {
        let base = StoreTestVault(), pause = StoreAccountGatePause()
        let engineA = StoreTestEngine(), engineB = StoreTestEngine()
        let vaultA = MirsaStoreAccountVault(base: base, id: "legacy")
        try vaultA.write(try JSONEncoder().encode(testOwner()), key: "account")
        let clientA = MirsaStoreClient(vault: vaultA, engine: engineA, packages: StoreTestPackages())
        let clientB = MirsaStoreClient(vault: StoreTestVault(), engine: engineB, packages: StoreTestPackages())
        let client = MirsaStoreOnDeviceClient(gate: { await pause.wait() }, vault: base,
            factory: { $0 == "legacy" ? clientA : clientB })
        let pending = Task { try await client.currentAccount() }
        while !(await pause.entered) { await Task.yield() }
        let secondID = try await client.beginAddAccount()
        await pause.resume()
        let captured = try await pending.value
        XCTAssertEqual(captured?.email, "owner@example.invalid")
        let selected = try await client.selectedAccountID()
        XCTAssertEqual(selected, secondID)
        XCTAssertEqual(engineA.guids.count, 1)
        XCTAssertTrue(engineB.guids.isEmpty)
        try await client.selectAccount(id: "legacy")
        XCTAssertEqual(base.removed.filter { $0 == "native.account" }.count, 0)
    }

    func testSeparateSavedClientsKeepIndependentSessionsAndStableGUIDs() async throws {
        let base = StoreTestVault()
        let id = UUID().uuidString
        let firstVault = MirsaStoreAccountVault(base: base, id: "legacy")
        let secondVault = MirsaStoreAccountVault(base: base, id: id)
        var secondOwner = testOwner()
        secondOwner.passwordToken = "second-fixture-token"
        secondOwner.directoryServicesIdentifier = "456"
        secondOwner.store = "143480"
        try firstVault.write(try JSONEncoder().encode(testOwner()), key: "account")
        try secondVault.write(try JSONEncoder().encode(secondOwner), key: "account")
        try firstVault.write(Data("AABBCCDDEEFF".utf8), key: "machine")
        try secondVault.write(Data("112233445566".utf8), key: "machine")
        let engineA = StoreTestEngine(), engineB = StoreTestEngine()
        let first = MirsaStoreClient(vault: firstVault, engine: engineA, packages: StoreTestPackages())
        let second = MirsaStoreClient(vault: secondVault, engine: engineB, packages: StoreTestPackages())
        _ = try await first.currentAccount()
        _ = try await second.currentAccount()
        XCTAssertEqual(engineA.guids, ["AABBCCDDEEFF"])
        XCTAssertEqual(engineB.guids, ["112233445566"])
        try await second.signOut()
        let retained = try await first.currentAccount()
        let removed = try await second.currentAccount()
        XCTAssertNotNil(retained)
        XCTAssertNil(removed)
        let owner = try JSONDecoder().decode(Account.self, from: firstVault.read("account")!)
        XCTAssertEqual(owner.passwordToken, "fixture-token")
        XCTAssertEqual(owner.directoryServicesIdentifier, "123")
        XCTAssertEqual(owner.store, "143443")
    }

    func testExpectedAccountMismatchFailsBeforeAuthorizationOrAppleRequest() async throws {
        let base = StoreTestVault(), engine = StoreTestEngine()
        let local = MirsaStoreClient(vault: StoreTestVault(), engine: engine, packages: StoreTestPackages())
        // A false gate would throw staging_denied if reached. Mismatch must win before that await.
        let client = MirsaStoreOnDeviceClient(local: local, gate: { false }, vault: base)
        let app = MirsaStoreApp(testSoftware())
        _ = try await client.beginAddAccount()
        do {
            _ = try await client.downloadOwnedApp(app, expectedAccountID: "legacy")
            XCTFail("Cross-account download accepted")
        } catch { XCTAssertEqual(error as? MirsaStoreError, .operationCancelled) }
        do {
            _ = try await client.acquireFreeAppAndDownload(app, expectedAccountID: "legacy")
            XCTFail("Cross-account acquisition accepted")
        } catch { XCTAssertEqual(error as? MirsaStoreError, .operationCancelled) }
        do {
            _ = try await client.currentAccount(expectedAccountID: "legacy")
            XCTFail("Cross-account summary accepted")
        } catch { XCTAssertEqual(error as? MirsaStoreError, .operationCancelled) }
        XCTAssertEqual(engine.manifests, 0)
        XCTAssertEqual(engine.acquisitions, 0)
        XCTAssertTrue(engine.guids.isEmpty)
    }

    func testAccountSelectionSurvivesClientRecreationWithoutSigningOut() async throws {
        let base = StoreTestVault()
        let first = MirsaStoreOnDeviceClient(gate: { true }, vault: base)
        let id = try await first.beginAddAccount()
        let second = MirsaStoreOnDeviceClient(gate: { true }, vault: base)
        let selected = try await second.selectedAccountID()
        XCTAssertEqual(selected, id)
        try await second.selectAccount(id: "legacy")
        let third = MirsaStoreOnDeviceClient(gate: { true }, vault: base)
        let restored = try await third.selectedAccountID()
        XCTAssertEqual(restored, "legacy")
        XCTAssertTrue(base.removed.isEmpty)
    }

    func testVersionListUsesSelectedAppWithoutIPhoneLookupPrecheck() async throws {
        let engine = StoreTestEngine()
        let client = MirsaStoreClient(vault: StoreTestVault(), engine: engine, packages: StoreTestPackages())
        _ = try await client.signIn(email: "owner@example.invalid", password: "fixture-password")
        let selected = MirsaStoreApp(testSoftware())
        // A redundant lookup would return a different app and block this valid selection.
        engine.app = testSoftware(id: 999)
        let versions = try await client.availableVersions(selected)
        XCTAssertEqual(versions, ["123", "456"])
        XCTAssertTrue(engine.lookupCountries.isEmpty)
        XCTAssertEqual(engine.versionApps.map(\.id), [selected.id])
        XCTAssertEqual(engine.versionApps.map(\.bundleID), [selected.bundleID])
        XCTAssertEqual(engine.acquisitions, 0)
    }

    func testSafeAuthDiagnosticReachesUIAndClearsFailedChallenge() async throws {
        let vault = StoreTestVault(), engine = StoreTestEngine()
        engine.auth.diagnostic = MirsaStoreAuthDiagnostic(.init(stage: .authentication,
            httpStatus: 403, appleCode: "-5000", message: "An explicit safe Apple rejection"))
        let client = MirsaStoreClient(vault: vault, engine: engine, packages: StoreTestPackages())
        do {
            _ = try await client.signIn(email: "owner@example.invalid", password: "fixture-password")
            XCTFail("Failed auth was accepted")
        } catch let safe as MirsaStoreAuthDiagnostic {
            XCTAssertEqual(safe.stage, .authentication)
            XCTAssertEqual(safe.httpStatus, 403)
            XCTAssertEqual(safe.appleCode, "-5000")
            XCTAssertTrue(safe.localizedDescription.contains("An explicit safe Apple rejection"))
        }
        XCTAssertNil(vault.data["challenge"])
        XCTAssertNil(vault.data["account"])
        XCTAssertEqual(engine.auth.calls.count, 1)
    }

    func testTwoFactorDiagnosticAlertKeepsSafeExactResponseFields() {
        let error = MirsaStoreAuthDiagnostic(.init(stage: .authentication, httpStatus: 200,
            loginPhase: .verificationCode, responseMessage: .configurator, failureState: .empty))
        let text = error.localizedDescription
        XCTAssertTrue(text.contains("[authentication]"))
        XCTAssertTrue(text.contains("HTTP 200"))
        XCTAssertTrue(text.contains("Phase 2FA"))
        XCTAssertTrue(text.contains("failureType empty"))
        XCTAssertTrue(text.contains("customerMessage MZFinance.BadLogin.Configurator_message"))
        XCTAssertTrue(text.contains("latest code"))
        XCTAssertFalse(text.contains("code was rejected"))
    }

    func testSignoutAttemptsBothSecretsAndCancelsDownloadEvenOnKeychainFailure() async throws {
        let vault = StoreTestVault(), packages = StoreTestPackages()
        let client = MirsaStoreClient(vault: vault, engine: StoreTestEngine(), packages: packages)
        _ = try await client.currentAccount()
        vault.data["challenge"] = Data("fixture".utf8)
        vault.failDeleteAccount = true
        do { try await client.signOut(); XCTFail("delete failure swallowed") } catch {}
        XCTAssertNil(vault.data["challenge"])
        XCTAssertTrue(vault.removed.contains("account"))
        XCTAssertEqual(packages.cancellations, 1)
    }

    func testSAPSetupFailureFailsClosedBeforePasswordIsStored() async throws {
        let vault = StoreTestVault(), engine = StoreTestEngine()
        engine.failSetup = true
        let client = MirsaStoreClient(vault: vault, engine: engine, packages: StoreTestPackages())
        do { _ = try await client.signIn(email: "owner@example.invalid", password: "fixture-password"); XCTFail("unsigned fallback") }
        catch { XCTAssertEqual(error as? MirsaStoreError, .serviceUnavailable) }
        XCTAssertTrue(engine.auth.calls.isEmpty)
        XCTAssertNil(vault.data["challenge"])
        XCTAssertNil(vault.data["account"])
    }

    func testPolicyRejectsPaidUnknownAndInvalidPrices() throws {
        try MirsaStorePolicy.requireFree(0)
        for price in [nil, 1.0, -1, Double.nan, Double.infinity] as [Double?] {
            XCTAssertThrowsError(try MirsaStorePolicy.requireFree(price))
        }
    }
    func testURLAllowlistAndCredentialRejection() throws {
        for text in ["https://apps.mzstatic.com/a", "https://apple.com/a", "https://cdn-apple.com/a"] {
            try MirsaStorePolicy.downloadURL(URL(string: text)!)
        }
        for text in ["http://apps.mzstatic.com/a", "https://mzstatic.com.evil.test/a", "https://evilapple.com/a",
                     "https://owner:secret@apple.com/a", "https://apple.com:8443/a", "file:///tmp/a"] {
            XCTAssertThrowsError(try MirsaStorePolicy.downloadURL(URL(string: text)!))
        }
    }
    func testInputAndArchiveTraversalPolicy() throws {
        XCTAssertEqual(try MirsaStorePolicy.country("de"), "DE")
        XCTAssertThrowsError(try MirsaStorePolicy.country("D1"))
        XCTAssertEqual(try MirsaStorePolicy.version("123"), "123")
        for version in ["-1", "0", "../123", "1.5", "18446744073709551616"] {
            XCTAssertThrowsError(try MirsaStorePolicy.version(version))
        }
        for path in ["../file", "/Payload/a", "Payload/../a", "Payload/./a", "Payload\\a", "a\0b"] {
            XCTAssertThrowsError(try MirsaStorePolicy.archivePath(path))
        }
    }
    func testLoginSavedOnlyInInjectedVaultAndRestoresMachineIdentity() async throws {
        let vault = StoreTestVault(), engine = StoreTestEngine()
        let client = MirsaStoreClient(vault: vault, engine: engine, packages: StoreTestPackages())
        let result = try await client.signIn(email: "owner@example.invalid", password: "fixture-password")
        guard case .signedIn(let summary) = result else { return XCTFail("login missing") }
        XCTAssertEqual(summary.country, "DE")
        XCTAssertNotNil(vault.data["account"])
        XCTAssertEqual(try JSONDecoder().decode(Account.self, from: vault.data["account"]!).password, "")
        XCTAssertFalse(String(data: vault.data["account"]!, encoding: .utf8)!.contains("fixture-password"))
        XCTAssertEqual(engine.guids.first?.count, 12)
        let restored = MirsaStoreClient(vault: vault, engine: engine, packages: StoreTestPackages())
        let current = try await restored.currentAccount()
        XCTAssertEqual(current, summary)
        XCTAssertEqual(engine.guids.count, 2)
        XCTAssertEqual(engine.guids[0], engine.guids[1])
        try await restored.signOut()
        XCTAssertNil(vault.data["account"])
        XCTAssertNotNil(vault.data["machine"])
    }
    func testTwoFactorReusesOneSAPSession() async throws {
        let engine = StoreTestEngine()
        engine.auth.twoFactor = true
        let vault = StoreTestVault()
        let client = MirsaStoreClient(vault: vault, engine: engine, packages: StoreTestPackages())
        let first = try await client.signIn(email: "owner@example.invalid", password: "fixture-password")
        XCTAssertEqual(first, .verificationRequired)
        XCTAssertNil(vault.data["challenge"])
        do { _ = try await client.verify(code: "123"); XCTFail("Malformed code accepted") }
        catch { XCTAssertEqual(error as? MirsaStoreError, .invalidVerificationCode) }
        XCTAssertEqual(engine.auth.calls, [""])
        let second = try await client.verify(code: "123456")
        guard case .signedIn = second else { return XCTFail("verification missing") }
        XCTAssertEqual(engine.auth.passwords, ["fixture-password", "fixture-password"])
        XCTAssertEqual(engine.authCreations, 1)
        XCTAssertEqual(engine.auth.calls, ["", "123456"])
    }
    func testChangedPasswordAndDuplicateCodeNeverReachSession() async throws {
        let engine = StoreTestEngine()
        engine.auth.twoFactor = true
        let vault = StoreTestVault()
        let client = MirsaStoreClient(vault: vault, engine: engine, packages: StoreTestPackages())
        _ = try await client.signIn(email: "owner@example.invalid", password: "fixture-password")
        do { _ = try await client.verify(code: "123456", password: "changed-password"); XCTFail() }
        catch { XCTAssertEqual(error as? MirsaStoreError, .verificationPasswordChanged) }
        XCTAssertEqual(engine.auth.calls, [""])
        do { _ = try await client.verify(code: "999999", password: "fixture-password"); XCTFail() } catch {}
        do { _ = try await client.verify(code: " 999999 ", password: "fixture-password"); XCTFail() }
        catch { XCTAssertEqual(error as? MirsaStoreError, .duplicateVerificationCode) }
        XCTAssertEqual(engine.auth.calls, ["", "999999"])
        _ = try await client.verify(code: "123456", password: "fixture-password")
        XCTAssertEqual(engine.auth.passwords, Array(repeating: "fixture-password", count: 3))
        XCTAssertNil(vault.data["challenge"])
    }

    func test5020TerminatesChallengeWithoutAnotherAppleRequest() async throws {
        let engine = StoreTestEngine(), vault = StoreTestVault()
        engine.auth.twoFactor = true
        let client = MirsaStoreClient(vault: vault, engine: engine, packages: StoreTestPackages())
        _ = try await client.signIn(email: "owner@example.invalid", password: "fixture-password")
        engine.auth.diagnostic = MirsaStoreAuthDiagnostic(.init(stage: .authentication,
            httpStatus: 200, appleCode: "5020", loginPhase: .verificationCode))
        do { _ = try await client.verify(code: "123456", password: "fixture-password"); XCTFail() }
        catch let error as MirsaStoreAuthDiagnostic { XCTAssertEqual(error.appleCode, "5020") }
        engine.auth.diagnostic = nil
        do { _ = try await client.verify(code: "654321", password: "fixture-password"); XCTFail() }
        catch { XCTAssertEqual(error as? MirsaStoreError, .signedOut) }
        XCTAssertEqual(engine.auth.calls, ["", "123456"])
        XCTAssertNil(vault.data["challenge"])
        XCTAssertNil(vault.data["account"])
    }

    func testNativeOwnerGateDeniesBeforeAppleAuthentication() async throws {
        let engine = StoreTestEngine(), vault = StoreTestVault()
        let local = MirsaStoreClient(vault: vault, engine: engine, packages: StoreTestPackages())
        let client = MirsaStoreOnDeviceClient(local: local, gate: { false }, vault: vault)
        do {
            _ = try await client.signIn(email: "owner@example.invalid", password: "fixture-password")
            XCTFail("Owner restriction bypassed")
        } catch { XCTAssertEqual(error as? MirsaStoreServerError, .code("staging_denied")) }
        XCTAssertEqual(engine.authCreations, 0)
        XCTAssertTrue(vault.data.isEmpty)
    }
    func testNativeOwnerGateUsesLocalSessionForLatinVerification() async throws {
        let engine = StoreTestEngine(), vault = StoreTestVault()
        engine.auth.twoFactor = true
        let local = MirsaStoreClient(vault: vault, engine: engine, packages: StoreTestPackages())
        let client = MirsaStoreOnDeviceClient(local: local, gate: { true }, vault: vault)
        let first = try await client.signIn(email: "owner@example.invalid", password: "fixture-password")
        XCTAssertEqual(first, .verificationRequired)
        XCTAssertNil(vault.data["challenge"])
        do {
            _ = try await client.verify(code: "182737", password: "")
            XCTFail("Changed verification password accepted")
        } catch { XCTAssertEqual(error as? MirsaStoreError, .verificationPasswordChanged) }
        // The UI sends only the code; use the original memory-only challenge password.
        let second = try await client.verify(code: "123456")
        guard case .signedIn = second else { return XCTFail("No local session") }
        XCTAssertEqual(engine.authCreations, 1)
        XCTAssertEqual(engine.auth.calls, ["", "123456"])
        XCTAssertNil(vault.data["challenge"])
        XCTAssertEqual(try JSONDecoder().decode(Account.self, from: vault.data["account"]!).password, "")
    }

    func testTwoFactorSubmissionLimitAndSignoutClearsChallenge() async throws {
        let engine = StoreTestEngine()
        engine.auth.twoFactor = true
        let client = MirsaStoreClient(vault: StoreTestVault(), engine: engine, packages: StoreTestPackages())
        _ = try await client.signIn(email: "owner@example.invalid", password: "fixture-password")
        for code in ["999999", "888888", "777777"] {
            do { _ = try await client.verify(code: code, password: "fixture-password"); XCTFail("wrong code accepted") } catch {}
        }
        do { _ = try await client.verify(code: "123456", password: "fixture-password"); XCTFail("expired challenge accepted") } catch {}
        XCTAssertEqual(engine.auth.calls.count, 4)
        try await client.signOut()
        do { _ = try await client.verify(code: "123456", password: "fixture-password"); XCTFail("signed out challenge accepted") } catch {}
    }
    func testAcquisitionUsesFreshAccountRegionAndRejectsUnknownOrPaidPrice() async throws {
        let engine = StoreTestEngine()
        let client = MirsaStoreClient(vault: StoreTestVault(), engine: engine, packages: StoreTestPackages())
        _ = try await client.signIn(email: "owner@example.invalid", password: "fixture-password")
        let advertised = MirsaStoreApp(testSoftware())
        for price in [nil, 1.0] as [Double?] {
            engine.app = testSoftware(price: price)
            do { try await client.acquireFreeApp(advertised); XCTFail("not free") } catch {}
        }
        XCTAssertEqual(engine.acquisitions, 0)
        engine.app = testSoftware()
        try await client.acquireFreeApp(advertised)
        XCTAssertEqual(engine.acquisitions, 1)
        XCTAssertEqual(engine.lookupCountries, ["DE", "DE", "DE"])
    }
    func testOwnedDownloadNeverAcquiresAndPreservesSelectedVersion() async throws {
        let engine = StoreTestEngine(), packages = StoreTestPackages()
        let client = MirsaStoreClient(vault: StoreTestVault(), engine: engine, packages: packages)
        _ = try await client.signIn(email: "owner@example.invalid", password: "fixture-password")
        _ = try await client.downloadOwnedApp(MirsaStoreApp(testSoftware()), externalVersionID: "123")
        XCTAssertEqual(engine.seenVersion, "123")
        XCTAssertEqual(packages.calls, 1)
        XCTAssertEqual(engine.acquisitions, 0)
        engine.failManifest = true
        do { _ = try await client.downloadOwnedApp(MirsaStoreApp(testSoftware())); XCTFail("no license") }
        catch { XCTAssertEqual(error as? MirsaStoreError, .licenseRequired) }
        XCTAssertEqual(engine.acquisitions, 0)
    }
    func testInvalidVersionDoesNotSendAnyDownload() async throws {
        let engine = StoreTestEngine()
        let client = MirsaStoreClient(vault: StoreTestVault(), engine: engine, packages: StoreTestPackages())
        _ = try await client.signIn(email: "owner@example.invalid", password: "fixture-password")
        do { _ = try await client.downloadOwnedApp(MirsaStoreApp(testSoftware()), externalVersionID: "../1"); XCTFail("bad version") } catch {}
        XCTAssertEqual(engine.manifests, 0)
    }
    func testVaultFailureDoesNotClaimSuccessfulLogin() async throws {
        let vault = StoreTestVault(), engine = StoreTestEngine()
        let client = MirsaStoreClient(vault: vault, engine: engine, packages: StoreTestPackages())
        _ = try await client.currentAccount()
        vault.failWrite = true
        do { _ = try await client.signIn(email: "owner@example.invalid", password: "fixture-password"); XCTFail("failed persistence accepted") } catch {}
        let current = try await client.currentAccount()
        XCTAssertNil(current)
    }
    func testSignoutDuringInFlightLoginCannotResurrectAccount() async throws {
        let vault = StoreTestVault(), engine = StoreTestEngine()
        engine.auth.pause = true
        let client = MirsaStoreClient(vault: vault, engine: engine, packages: StoreTestPackages())
        let login = Task { try await client.signIn(email: "owner@example.invalid", password: "fixture-password") }
        for _ in 0..<1000 {
            if engine.auth.paused != nil { break }
            await Task.yield()
        }
        guard let paused = engine.auth.paused else { login.cancel(); return XCTFail("did not suspend") }
        do { _ = try await client.search(term: "x", country: "DE"); XCTFail("concurrent request") }
        catch { XCTAssertEqual(error as? MirsaStoreError, .busy) }
        try await client.signOut()
        paused.resume(returning: testOwner())
        do { _ = try await login.value; XCTFail("account resurrected") } catch {}
        XCTAssertNil(vault.data["account"])
    }
}

final class MirsaStorePackageTests: XCTestCase {
    private func fixture(bundleID: String = "com.example.fixture") throws -> (URL, DownloadOutput, Data) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("App.ipa")
        let archive = try Archive(url: url, accessMode: .create)
        let info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleExecutable": "Fixture",
                                  "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"]
        let executable = Data([0xcf, 0xfa, 0xed, 0xfe, 0x99, 0xaa, 0xbb])
        try add(try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0),
                path: "Payload/Fixture.app/Info.plist", archive: archive)
        try add(executable, path: "Payload/Fixture.app/Fixture", archive: archive)
        let output = try StoreTestEngine().output
        return (url, output, executable)
    }
    private func add(_ data: Data, path: String, archive: Archive) throws {
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { offset, count in
            data.subdata(in: Int(offset)..<(Int(offset) + count))
        }
    }
    func testPackageAddsOriginalSINFAndMetadataWithoutChangingExecutable() throws {
        let (url, output, executable) = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try AppleStorePackages.assemble(url, output: output, bundleID: "com.example.fixture")
        let archive = try Archive(url: url, accessMode: .read)
        for (path, expected) in [
            ("Payload/Fixture.app/Fixture", executable),
            ("Payload/Fixture.app/SC_Info/Fixture.sinf", output.sinfs[0].sinf),
            ("iTunesMetadata.plist", output.iTunesMetadata)
        ] {
            var bytes = Data()
            _ = try archive.extract(try XCTUnwrap(archive[path])) { bytes.append($0) }
            XCTAssertEqual(bytes, expected)
        }
    }
    func testMismatchedBundleCannotBePackaged() throws {
        let (url, output, _) = try fixture(bundleID: "com.wrong.fixture")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertThrowsError(try AppleStorePackages.assemble(url, output: output, bundleID: "com.example.fixture"))
    }
    func testTraversalManifestIsRejected() throws {
        let (url, output, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            let archive = try Archive(url: url, accessMode: .update)
            let manifest = try PropertyListSerialization.data(fromPropertyList: ["SinfPaths": ["../Fixture"]], format: .binary, options: 0)
            try add(manifest, path: "Payload/Fixture.app/SC_Info/Manifest.plist", archive: archive)
        }
        XCTAssertThrowsError(try AppleStorePackages.assemble(url, output: output, bundleID: "com.example.fixture"))
    }
}

final class StoreLibraryPolicyTests: XCTestCase {
    private func catalog(price: Double? = 0, currency: String? = "EUR", country: String = "de", id: Int64 = 42, bundle: String = "com.example.fixture") -> StoreCatalogItem {
        StoreCatalogItem(app: MirsaStoreApp(id: id, bundleID: bundle, name: "Fixture", version: "2.0", price: price, artworkURL: ""), country: country, currency: currency, releaseNotes: "Latest only", minimumOSVersion: "28.0", screenshots: [], rating: nil, ratingCount: nil, sizeBytes: nil)
    }
    func testNumericMarketingVersionsAndUnknowns() {
        XCTAssertEqual(StoreVersionPolicy.newer("1.10", than: "1.9"), true)
        XCTAssertEqual(StoreVersionPolicy.newer("10.0", than: "9.99"), true)
        XCTAssertEqual(StoreVersionPolicy.newer("1.0.0", than: "01"), false)
        XCTAssertEqual(StoreVersionPolicy.newer("1.0", than: "1.0.1"), false)
        XCTAssertEqual(StoreVersionPolicy.newer("27.0.1", than: "27.0"), true)
        for invalid in ["", "1..2", "1-beta", " 1", "1.", "1,2"] {
            XCTAssertNil(StoreVersionPolicy.newer(invalid, than: "1"))
            XCTAssertNil(StoreVersionPolicy.newer("1", than: invalid))
        }
    }
    func testPriceTransitionRequiresMatchingIdentityStoreAndCurrency() {
        var wish = StoreWishItem(appID: 42, bundleID: "com.example.fixture", name: "Fixture", country: "de", currency: "EUR", price: 2.99)
        XCTAssertFalse(wish.observe(catalog(currency: "USD")))
        XCTAssertFalse(wish.observe(catalog(country: "us")))
        XCTAssertFalse(wish.observe(catalog(id: 43)))
        XCTAssertFalse(wish.observe(catalog(bundle: "com.wrong")))
        XCTAssertFalse(wish.observe(catalog(price: nil)))
        XCTAssertEqual(wish.price, 2.99)
        XCTAssertTrue(wish.observe(catalog()))
        wish.notified = true
        XCTAssertFalse(wish.observe(catalog()))
        XCTAssertFalse(wish.observe(catalog(price: 1.99)))
        XCTAssertTrue(wish.observe(catalog()))
    }
    func testFreeAtFirstObservationDoesNotNotifyAndInvalidPriceIsNotFree() {
        var wish = StoreWishItem(appID: 42, bundleID: "com.example.fixture", name: "Fixture", country: "de", currency: "EUR", price: 0)
        XCTAssertFalse(wish.observe(catalog()))
        XCTAssertFalse(wish.observe(catalog(price: -.infinity)))
        XCTAssertFalse(wish.observe(catalog(price: -1)))
        XCTAssertFalse(wish.observe(catalog(price: .nan)))
    }
    func testLatestMetadataNeverAssignedToOlderExternalID() {
        let item = catalog()
        XCTAssertEqual(item.notes(forVersion: nil), "Latest only")
        XCTAssertEqual(item.minimumOS(forVersion: nil), "28.0")
        XCTAssertNil(item.notes(forVersion: "123"))
        XCTAssertNil(item.minimumOS(forVersion: "123"))
    }
    func testLookupUnknownAndMismatchedResultFailClosed() throws {
        let valid = Data(#"{"results":[{"trackId":42,"bundleId":"com.example.fixture","trackName":"Fixture","version":"2.0","price":0,"currency":"EUR","screenshotUrls":["https://is1-ssl.mzstatic.com/image.jpg","https://evil.invalid/image.jpg","http://is1-ssl.mzstatic.com/image.jpg"]}]}"#.utf8)
        let item = try StoreCatalog.decode(valid, appID: 42, bundleID: "com.example.fixture", country: "DE")
        XCTAssertEqual(item.country, "de")
        XCTAssertEqual(item.screenshots.count, 1)
        XCTAssertThrowsError(try StoreCatalog.decode(valid, appID: 43, bundleID: nil, country: "de"))
        XCTAssertThrowsError(try StoreCatalog.decode(Data(#"{"results":[]}"#.utf8), appID: 42, bundleID: nil, country: "de"))
        XCTAssertThrowsError(try StoreCatalog.decode(Data(#"{"error":"quota"}"#.utf8), appID: 42, bundleID: nil, country: "de"))
        XCTAssertThrowsError(try StoreCatalog.decode(valid, appID: 42, bundleID: nil, country: "unknown"))
    }
    func testCleanupDefaultUnconfirmedSavedActiveAndPinnedAlwaysPreserved() {
        XCTAssertTrue(StoreIPACleanupPolicy.mayDelete(enabled: true, confirmed: true, saved: false, active: false, pinned: false))
        XCTAssertFalse(StoreIPACleanupPolicy.mayDelete(enabled: false, confirmed: true, saved: false, active: false, pinned: false))
        XCTAssertFalse(StoreIPACleanupPolicy.mayDelete(enabled: true, confirmed: false, saved: false, active: false, pinned: false))
        XCTAssertFalse(StoreIPACleanupPolicy.mayDelete(enabled: true, confirmed: true, saved: true, active: false, pinned: false))
        XCTAssertFalse(StoreIPACleanupPolicy.mayDelete(enabled: true, confirmed: true, saved: false, active: true, pinned: false))
        XCTAssertFalse(StoreIPACleanupPolicy.mayDelete(enabled: true, confirmed: true, saved: false, active: false, pinned: true))
    }
}
