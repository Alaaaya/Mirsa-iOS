import Foundation
import XCTest
#if canImport(MirsaStoreKit)
@testable import MirsaStoreKit
#else
@testable import Mirsa
#endif

private final class ServerFixtureVault: MirsaStoreVault {
    var items: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { items[key] }
    func write(_ data: Data, key: String) throws { items[key] = data }
    func remove(_ key: String) throws { items[key] = nil }
}

private actor ServerFixture {
    let user = UUID()
    let device = String(repeating: "D", count: 43)
    var paths: [String] = []
    var bodies: [[String: Any]] = []
    var invalidCode = false
    var authenticated = false
    var errorCode: String?
    var selection: String?
    var wrongMetadataApp = false
    func wrongMetadata() { wrongMetadataApp = true }
    var mismatchSelection = false
    func mismatch() { mismatchSelection = true }
    var holdDownload = false
    var held: CheckedContinuation<Void, Never>?
    var started: CheckedContinuation<Void, Never>?
    var didStart = false
    func hold() { holdDownload = true }
    func waitForDownload() async {
        if didStart { return }; await withCheckedContinuation { started = $0 }
    }
    func releaseDownload() { held?.resume(); held = nil }
    func identity() -> MirsaStoreServerIdentity { .init(bearer: "fixture-bearer", userID: user, forgeDeviceID: "91f71c66-b727-450e-8de2-244a1cf85915", forgeDeviceToken: String(repeating: "a", count: 64)) }
    func fail(_ value: String?) { errorCode = value }
    func rejectCodes() { invalidCode = true }
    func count(_ suffix: String) -> Int { paths.filter { $0.hasSuffix(suffix) }.count }
    func verifyBody() -> [String: String]? {
        bodies.last { $0["code"] != nil } as? [String: String]
    }
    func respond(_ request: URLRequest) async throws -> (Data, Int) {
        XCTAssertEqual(request.url?.host, "mirsa-app.mooo.com")
        XCTAssertEqual(request.timeoutInterval, 180)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-bearer")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-mirsa-device"), "91f71c66-b727-450e-8de2-244a1cf85915")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-mirsa-device-token"), String(repeating: "a", count: 64))
        let path = request.url!.path
        paths.append(path)
        let body = try request.httpBody.map { try JSONSerialization.jsonObject(with: $0) as! [String: Any] } ?? [:]
        bodies.append(body)
        if path.hasSuffix("/devices") {
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Mirsa-Store-Device"))
            return try reply(["deviceToken": device])
        }
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Mirsa-Store-Device"), device)
        if let errorCode { return try reply(["error": ["code": errorCode, "retryable": false]], 401) }
        if path.hasSuffix("/version-metadata") {
            XCTAssertEqual(body["externalVersionIDs"] as? [String], ["111", "222"])
            return try reply(["appID": wrongMetadataApp ? 999 : 42, "entries": [
                ["externalVersionID": "111", "status": "ready", "version": "1.2.3"],
                ["externalVersionID": "222", "status": "queued"],
                ["externalVersionID": "999", "status": "ready", "version": "unrequested"]]])
        }
        if path.hasSuffix("/versions") {
            return try reply(["appID": 42, "latestExternalVersionID": "999", "versions": ["111", "222", "999"]])
        }
        if path.hasSuffix("/downloads") {
            selection = body["externalVersionID"] as? String
            if holdDownload {
                didStart = true; started?.resume(); started = nil
                await withCheckedContinuation { held = $0 }
            }
            return try reply(["jobID": "fixture-job", "status": "queued", "appID": 42, "externalVersionID": selection.map { $0 as Any } ?? NSNull()], 202)
        }
        if path.hasSuffix("/downloads/fixture-job") {
            return try reply(["jobID": "fixture-job", "status": "running", "appID": mismatchSelection ? 999 : 42, "externalVersionID": selection.map { $0 as Any } ?? NSNull()])
        }
        if path.hasSuffix("/login") {
            XCTAssertEqual(body["password"] as? String, "login-fixture-secret")
            return try reply(["status": "challenge", "challengeID": "fixture-challenge",
                              "expiresAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(299)),
                              "passwordRequired": true])
        }
        if path.hasSuffix("/verify") {
            if invalidCode { return try reply(["error": ["code": "invalid_code", "retryable": false]], 400) }
            authenticated = true
            return try reply(["status": "authenticated", "account": ["email": "fixture@example.invalid", "name": "Fixture", "storefront": "DE"]])
        }
        if path.hasSuffix("/account") {
            return try reply(["status": "signed_out"])
        }
        if path.hasSuffix("/search") {
            XCTAssertEqual(body["term"] as? String, "fixture")
            return try reply(["apps": [["id": 42, "bundleID": "invalid.example.fixture", "name": "Fixture", "version": "1.0", "price": 0]]])
        }
        if path.hasSuffix("/logout") { authenticated = false; return try reply(["status": "signed_out"]) }
        return try reply(["status": "ok"])
    }
    private func reply(_ value: [String: Any], _ status: Int = 200) throws -> (Data, Int) {
        (try JSONSerialization.data(withJSONObject: value), status)
    }
}

final class StoreServerClientTests: XCTestCase {
    func testLoginAvailabilityRequiresSuccessfulServerAccountGate() async throws {
        let fixture = ServerFixture()
        let client = MirsaStoreServerClient(identity: { await fixture.identity() },
            vault: ServerFixtureVault(), http: { try await fixture.respond($0) })
        let allowed = await client.loginAvailable()
        XCTAssertTrue(allowed) // signed_out is an allowed owner, not an Apple login.
        let accounts = await fixture.count("/account")
        let logins = await fixture.count("/login")
        XCTAssertEqual(accounts, 1)
        XCTAssertEqual(logins, 0)
        await fixture.fail("staging_denied")
        let denied = await client.loginAvailable()
        XCTAssertFalse(denied)
    }

    func testLoginAvailabilityFailsClosedForNetworkAndMalformedAccount() async throws {
        let fixture = ServerFixture()
        let network = MirsaStoreServerClient(identity: { await fixture.identity() },
            vault: ServerFixtureVault(), http: { _ in throw URLError(.notConnectedToInternet) })
        let offline = await network.loginAvailable()
        XCTAssertFalse(offline)
        let malformed = MirsaStoreServerClient(identity: { await fixture.identity() },
            vault: ServerFixtureVault(), http: { request in
                if request.url?.path.hasSuffix("/devices") == true { return try await fixture.respond(request) }
                return (Data(#"{"status":"enabled"}"#.utf8), 200)
            })
        let invalid = await malformed.loginAvailable()
        XCTAssertFalse(invalid)
    }

    func testAllRoutesIncludingEnrollmentAndArtifactCarryExistingForgeBinding() async throws {
        let fixture = ServerFixture()
        let owner = await fixture.identity()
        let client = MirsaStoreServerClient(identity: { await fixture.identity() }, vault: ServerFixtureVault(),
                                           http: { try await fixture.respond($0) })
        for path in ["/devices", "/login", "/verify", "/account", "/search", "/purchase", "/versions",
                     "/version-metadata", "/downloads", "/downloads/fixture-job", "/artifacts/fixture-artifact", "/logout"] {
            let enrollment = path == "/devices"
            let request = try await client.request(path, owner: owner,
                device: enrollment ? nil : String(repeating: "D", count: 43))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-bearer", path)
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-mirsa-device"), owner.forgeDeviceID, path)
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-mirsa-device-token"), owner.forgeDeviceToken, path)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Mirsa-Store-Device"),
                           enrollment ? nil : String(repeating: "D", count: 43), path)
        }
    }

    func testMissingExistingForgeCredentialDeniesBeforeEnrollmentOrAppleBody() async throws {
        let fixture = ServerFixture()
        let user = UUID()
        let vault = ServerFixtureVault()
        let client = MirsaStoreServerClient(identity: {
            .init(bearer: "fixture-bearer", userID: user,
                  forgeDeviceID: "91f71c66-b727-450e-8de2-244a1cf85915", forgeDeviceToken: "")
        }, vault: vault, http: { try await fixture.respond($0) })
        do { _ = try await client.signIn(email: "fixture@example.invalid", password: "login-fixture-secret"); XCTFail() }
        catch { XCTAssertEqual(error as? MirsaStoreServerError, .code("staging_denied")) }
        let enrollment = await fixture.count("/devices")
        let login = await fixture.count("/login")
        XCTAssertEqual(enrollment, 0); XCTAssertEqual(login, 0)
        XCTAssertTrue(vault.items.isEmpty)
    }

    func testChallengeRequiresFreshPasswordAndPersistsOnlyOpaqueDeviceToken() async throws {
        let fixture = ServerFixture()
        let vault = ServerFixtureVault()
        let client = MirsaStoreServerClient(identity: { await fixture.identity() }, vault: vault,
                                           http: { try await fixture.respond($0) })
        let login = try await client.signIn(email: "fixture@example.invalid", password: "login-fixture-secret")
        XCTAssertEqual(login, .verificationRequired)
        XCTAssertEqual(vault.items.count, 1)
        XCTAssertFalse(vault.items.values.contains { String(data: $0, encoding: .utf8)?.contains("secret") == true })
        do { _ = try await client.verify(code: "123456", password: ""); XCTFail() }
        catch { XCTAssertEqual(error as? MirsaStoreError, .invalidInput) }
        let before = await fixture.count("/verify")
        XCTAssertEqual(before, 0)
        let result = try await client.verify(code: "123456", password: "fresh-fixture-secret")
        guard case .signedIn(let account) = result else { return XCTFail() }
        XCTAssertEqual(account.country, "DE")
        let body = await fixture.verifyBody()
        XCTAssertEqual(body?["password"], "fresh-fixture-secret")
        XCTAssertEqual(body?["challengeID"], "fixture-challenge")
        XCTAssertEqual(body?["code"], "123456")
        let devices = await fixture.count("/devices")
        XCTAssertEqual(devices, 1)
    }

    func testOnlyTwoVerificationAttemptsAndNoImplicitPasswordReplay() async throws {
        let fixture = ServerFixture()
        await fixture.rejectCodes()
        let client = MirsaStoreServerClient(identity: { await fixture.identity() }, vault: ServerFixtureVault(),
                                           http: { try await fixture.respond($0) })
        _ = try await client.signIn(email: "fixture@example.invalid", password: "login-fixture-secret")
        for _ in 0..<2 {
            do { _ = try await client.verify(code: "123456", password: "fresh"); XCTFail() }
            catch { XCTAssertEqual(error as? MirsaStoreServerError, .code("invalid_code")) }
        }
        do { _ = try await client.verify(code: "123456", password: "fresh"); XCTFail() }
        catch { XCTAssertEqual(error as? MirsaStoreServerError, .code("challenge_expired")) }
        let verifies = await fixture.count("/verify")
        let logins = await fixture.count("/login")
        XCTAssertEqual(verifies, 2); XCTAssertEqual(logins, 1)
    }

    func testSearchDecodesCatalogAndPaidPurchaseNeverHitsNetwork() async throws {
        let fixture = ServerFixture()
        let client = MirsaStoreServerClient(identity: { await fixture.identity() }, vault: ServerFixtureVault(),
                                           http: { try await fixture.respond($0) })
        let apps = try await client.search(term: "fixture")
        XCTAssertEqual(apps.first?.id, 42)
        let app = MirsaStoreApp(id: 43, bundleID: "invalid.paid", name: "Paid", version: "1", price: 1, artworkURL: "")
        do { try await client.acquireFreeApp(app); XCTFail() }
        catch { XCTAssertEqual(error as? MirsaStoreError, .freeAppsOnly) }
        let purchases = await fixture.count("/purchase")
        XCTAssertEqual(purchases, 0)
    }

    func testErrorAllowlistAndUnauthorizedDoesNotRetry() async throws {
        let fixture = ServerFixture()
        let client = MirsaStoreServerClient(identity: { await fixture.identity() }, vault: ServerFixtureVault(),
                                           http: { try await fixture.respond($0) })
        _ = try await client.currentAccount()
        await fixture.fail("raw Apple secret payload")
        do { _ = try await client.currentAccount(); XCTFail() }
        catch { XCTAssertEqual(error as? MirsaStoreServerError, .code("upstream_unavailable")) }
        let accounts = await fixture.count("/account")
        XCTAssertEqual(accounts, 2)
        for code in ["invalid_code", "device_limit", "invalid_version", "staging_denied"] {
            XCTAssertEqual(MirsaStoreServerError(code: code), .code(code))
        }
    }

    func testLogoutDeletesChallengeAndCallsServerOnce() async throws {
        let fixture = ServerFixture()
        let client = MirsaStoreServerClient(identity: { await fixture.identity() }, vault: ServerFixtureVault(),
                                           http: { try await fixture.respond($0) })
        _ = try await client.signIn(email: "fixture@example.invalid", password: "login-fixture-secret")
        try await client.signOut()
        do { _ = try await client.verify(code: "123456", password: "fresh"); XCTFail() }
        catch { XCTAssertEqual(error as? MirsaStoreServerError, .code("challenge_expired")) }
        let count = await fixture.count("/logout")
        XCTAssertEqual(count, 1)
    }

    func testDownloadPollingIsBoundedAndCancellationStopsBeforeImport() async throws {
        let fixture = ServerFixture()
        let app = MirsaStoreApp(id: 42, bundleID: "invalid.fixture", name: "Fixture", version: "1", price: 0, artworkURL: "")
        let client = MirsaStoreServerClient(identity: { await fixture.identity() }, vault: ServerFixtureVault(),
            http: { try await fixture.respond($0) }, pause: {})
        do { _ = try await client.downloadOwnedApp(app); XCTFail() }
        catch { XCTAssertEqual(error as? MirsaStoreServerError, .code("busy")) }
        let polls = await fixture.count("/downloads/fixture-job")
        XCTAssertEqual(polls, MirsaStoreServerClient.maximumPolls)
        let cancelled = MirsaStoreServerClient(identity: { await fixture.identity() }, vault: ServerFixtureVault(),
            http: { try await fixture.respond($0) }, pause: { throw CancellationError() })
        do { _ = try await cancelled.downloadOwnedApp(app); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        let after = await fixture.count("/downloads/fixture-job")
        XCTAssertEqual(after, polls)
    }

    func testLogoutInvalidatesInFlightDownloadBeforeLateJobCanImport() async throws {
        let fixture = ServerFixture()
        await fixture.hold()
        let client = MirsaStoreServerClient(identity: { await fixture.identity() }, vault: ServerFixtureVault(),
            http: { try await fixture.respond($0) }, pause: {})
        let app = MirsaStoreApp(id: 42, bundleID: "invalid.fixture", name: "Fixture", version: "1", price: 0, artworkURL: "")
        let download = Task { try await client.downloadOwnedApp(app) }
        await fixture.waitForDownload()
        try await client.signOut()
        await fixture.releaseDownload()
        do { _ = try await download.value; XCTFail("A late job must not reach the import callback") }
        catch { XCTAssertEqual(error as? MirsaStoreError, .operationCancelled) }
        let polls = await fixture.count("/downloads/fixture-job")
        XCTAssertEqual(polls, 0)
    }

    func testOfficialVersionListAndSelectedExternalIDStayBoundToJob() async throws {
        let fixture = ServerFixture()
        let client = MirsaStoreServerClient(identity: { await fixture.identity() }, vault: ServerFixtureVault(),
            http: { try await fixture.respond($0) }, pause: { throw CancellationError() })
        let app = MirsaStoreApp(id: 42, bundleID: "invalid.fixture", name: "Fixture", version: "1", price: 0, artworkURL: "")
        let versions = try await client.availableVersions(app)
        XCTAssertEqual(versions, ["111", "222", "999"])
        do { _ = try await client.downloadOwnedApp(app, externalVersionID: "222"); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        try MirsaStoreServerClient.verifySelection(appID: 42, externalVersionID: "222", expectedAppID: 42, expectedVersionID: "222")
        XCTAssertThrowsError(try MirsaStoreServerClient.verifySelection(appID: 42, externalVersionID: "111", expectedAppID: 42, expectedVersionID: "222"))
        XCTAssertThrowsError(try MirsaStoreServerClient.verifySelection(appID: 43, externalVersionID: "222", expectedAppID: 42, expectedVersionID: "222"))
        XCTAssertThrowsError(try MirsaStoreServerClient.verifySelection(appID: 42, externalVersionID: nil, expectedAppID: 42, expectedVersionID: "222"))
        XCTAssertThrowsError(try MirsaStoreServerClient.verifySelection(appID: 42, externalVersionID: "222", expectedAppID: 42, expectedVersionID: nil))
        XCTAssertFalse(MirsaStoreServerClient.numericVersion("22/2"))
    }

    func testChangedJobSelectionIsRejectedBeforeArtifactDownload() async throws {
        let fixture = ServerFixture()
        await fixture.mismatch()
        let client = MirsaStoreServerClient(identity: { await fixture.identity() }, vault: ServerFixtureVault(),
            http: { try await fixture.respond($0) }, pause: {})
        let app = MirsaStoreApp(id: 42, bundleID: "invalid.fixture", name: "Fixture", version: "1", price: 0, artworkURL: "")
        do { _ = try await client.downloadOwnedApp(app, externalVersionID: "222"); XCTFail() }
        catch { XCTAssertEqual(error as? MirsaStoreError, .invalidPackage) }
        let polls = await fixture.count("/downloads/fixture-job")
        XCTAssertEqual(polls, 1)
    }

    func testOfficialMetadataBindingAndTwentyIDLimit() async throws {
        let fixture = ServerFixture()
        let client = MirsaStoreServerClient(identity: { await fixture.identity() }, vault: ServerFixtureVault(),
            http: { try await fixture.respond($0) })
        let app = MirsaStoreApp(id: 42, bundleID: "invalid.fixture", name: "Fixture", version: "1", price: 0, artworkURL: "")
        let entries = try await client.versionMetadata(app, externalVersionIDs: ["111", "222"])
        XCTAssertEqual(entries.map(\.externalVersionID), ["111", "222"])
        XCTAssertEqual(entries.first?.version, "1.2.3")
        XCTAssertNil(entries.last?.version)
        for ids in [["111", "111"], ["bad"], (1...21).map(String.init)] {
            do { _ = try await client.versionMetadata(app, externalVersionIDs: ids); XCTFail() }
            catch { XCTAssertEqual(error as? MirsaStoreError, .invalidInput) }
        }
        await fixture.wrongMetadata()
        do { _ = try await client.versionMetadata(app, externalVersionIDs: ["111", "222"]); XCTFail() }
        catch { XCTAssertEqual(error as? MirsaStoreError, .invalidPackage) }
    }

    func testArtifactMetadataRejectsExfiltrationExpiryHashAndOversize() throws {
        let transport = try MirsaStoreServerTransport(origin: URL(string: "https://mirsa-app.mooo.com")!)
        func item(_ url: String = "https://mirsa-app.mooo.com/store/v1/artifacts/randomID",
                  size: Int64 = 10, hash: String = String(repeating: "a", count: 64),
                  offset: TimeInterval = 600) -> MirsaStoreServerClient.Artifact {
            .init(url: url, size: size, sha256: hash,
                  expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset)),
                  appID: 42, externalVersionID: nil)
        }
        XCTAssertNoThrow(try MirsaStoreServerClient.artifactURL(item(), transport: transport))
        for value in [item("https://evil.invalid/store/v1/artifacts/randomID"),
                      item("https://mirsa-app.mooo.com/another/randomID"),
                      item("https://mirsa-app.mooo.com/store/v1/artifacts/randomID?x=y"),
                      item(size: 2_147_483_649), item(hash: "bad"), item(offset: -10), item(offset: 2000)] {
            XCTAssertThrowsError(try MirsaStoreServerClient.artifactURL(value, transport: transport))
        }
    }
}
