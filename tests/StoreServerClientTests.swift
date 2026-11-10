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
    func identity() -> MirsaStoreServerIdentity { .init(bearer: "fixture-bearer", userID: user) }
    func fail(_ value: String?) { errorCode = value }
    func rejectCodes() { invalidCode = true }
    func count(_ suffix: String) -> Int { paths.filter { $0.hasSuffix(suffix) }.count }
    func verifyBody() -> [String: String]? {
        bodies.last { $0["code"] != nil } as? [String: String]
    }
    func respond(_ request: URLRequest) throws -> (Data, Int) {
        XCTAssertEqual(request.url?.host, "mirsa-app.mooo.com")
        XCTAssertEqual(request.timeoutInterval, 180)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-bearer")
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
        XCTAssertEqual(MirsaStoreServerError(code: "invalid_code"), .code("invalid_code"))
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

    func testArtifactMetadataRejectsExfiltrationExpiryHashAndOversize() throws {
        let transport = try MirsaStoreServerTransport(origin: URL(string: "https://mirsa-app.mooo.com")!)
        func item(_ url: String = "https://mirsa-app.mooo.com/store/v1/artifacts/randomID",
                  size: Int64 = 10, hash: String = String(repeating: "a", count: 64),
                  offset: TimeInterval = 600) -> MirsaStoreServerClient.Artifact {
            .init(url: url, size: size, sha256: hash,
                  expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset)))
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
