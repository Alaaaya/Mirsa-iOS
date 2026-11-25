import XCTest
import Foundation
#if canImport(DiscoveryKit)
@testable import DiscoveryKit
#else
@testable import Mirsa
#endif

private final class MemStore: DiscoverySessionStore {
    var s: DiscoverySession?
    func load() -> DiscoverySession? { s }
    func save(_ s: DiscoverySession?) { self.s = s }
}

private final class FakeAuthHTTP: DiscoveryAuthHTTP {
    var calls: [String] = []
    var headers: [[String: String]] = []
    var replies: [(Int, String)]
    init(_ r: [(Int, String)]) { replies = r }
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        calls.append(url.path + (url.query.map { "?" + $0 } ?? ""))
        self.headers.append(headers)
        let r = replies.isEmpty ? (500, "") : replies.removeFirst()
        return (Data(r.1.utf8), r.0)
    }
}

private func sess(_ a: String, _ r: String, life: Int = 3600) -> String {
    #"{"access_token":"\#(a)","refresh_token":"\#(r)","expires_in":\#(life)}"#
}

private final class FakeGet: DiscoveryHTTP {
    var replies: [(Int, String)]
    var seen: [String] = []
    init(_ r: [(Int, String)]) { replies = r }
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        seen.append(headers["Authorization"] ?? "")
        let r = replies.isEmpty ? (500, "") : replies.removeFirst()
        return (Data(r.1.utf8), r.0)
    }
}

private struct StubAuth: DiscoveryTokenProvider {
    var forced: Box
    final class Box { var tokens: [String]; var forces: [Bool] = []; init(_ t: [String]) { tokens = t } }
    func token(forceRefresh: Bool) async throws -> String { forced.forces.append(forceRefresh); return forced.tokens.removeFirst() }
}

final class DiscoveryAuthTests: XCTestCase {
    private let project = URL(string: "https://abc.supabase.co")!
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testTranslationExistingOnlyNeverSignsUpForMissingOrRejectedSession() async throws {
        for existing in [false, true] {
            let store = MemStore(), http = FakeAuthHTTP([(400, "{}")])
            if existing { store.s = DiscoverySession(accessToken: "expired", refreshToken: "dead", expiresAt: t0) }
            let auth = DiscoveryAuthClient(projectURL: project, publishableKey: "public", store: store,
                                           http: http, now: { self.t0 }, existingOnly: true)
            do { _ = try await auth.token(forceRefresh: false); XCTFail("Missing account must fail") } catch {}
            XCTAssertEqual(http.calls.count, existing ? 1 : 0)
            XCTAssertFalse(http.calls.contains { $0.contains("signup") })
        }
    }
    func testTranslationExistingOnlyRefreshKeepsAccountAndRejectsSwitch() async throws {
        func jwt(_ sub: String, marker: String) -> String {
            let data = Data(("{\"sub\":\"" + sub + "\",\"role\":\"authenticated\",\"marker\":\"" + marker + "\"}").utf8)
            return "header." + data.base64EncodedString().replacingOccurrences(of: "=", with: "") + ".signature"
        }
        let id = "11111111-1111-4111-8111-111111111111"
        for same in [true, false] {
            let store = MemStore(); store.s = DiscoverySession(accessToken: jwt(id, marker: "old"), refreshToken: "refresh", expiresAt: t0)
            let next = jwt(same ? id : "22222222-2222-4222-8222-222222222222", marker: "fresh")
            let http = FakeAuthHTTP([(200, sess(next, "new-refresh"))])
            let auth = DiscoveryAuthClient(projectURL: project, publishableKey: "public", store: store,
                                           http: http, now: { self.t0 }, existingOnly: true)
            do { let token = try await auth.token(forceRefresh: false); XCTAssertTrue(same); XCTAssertEqual(token, next) }
            catch { XCTAssertFalse(same) }
            XCTAssertEqual(http.calls, ["/auth/v1/token?grant_type=refresh_token"])
        }
    }
    func testFirstUseSignsUpAnonymouslyAndStoresSession() async throws {
        let st = MemStore(), h = FakeAuthHTTP([(200, sess("A1", "R1"))])
        let c = DiscoveryAuthClient(projectURL: project, publishableKey: "pub", store: st, http: h, now: { self.t0 })
        let t = try await c.token(forceRefresh: false)
        XCTAssertEqual(t, "A1"); XCTAssertEqual(h.calls, ["/auth/v1/signup"]); XCTAssertEqual(st.s?.refreshToken, "R1")
        XCTAssertEqual(h.headers[0]["apikey"], "pub")
    }

    func testValidTokenIsReusedWithoutNetwork() async throws {
        let st = MemStore(); st.s = DiscoverySession(accessToken: "A", refreshToken: "R", expiresAt: t0.addingTimeInterval(600))
        let h = FakeAuthHTTP([])
        let c = DiscoveryAuthClient(projectURL: project, publishableKey: "pub", store: st, http: h, now: { self.t0 })
        let t = try await c.token(forceRefresh: false)
        XCTAssertEqual(t, "A"); XCTAssertTrue(h.calls.isEmpty)
    }

    func testExpiredTokenRefreshesExactlyOnce() async throws {
        let st = MemStore(); st.s = DiscoverySession(accessToken: "old", refreshToken: "R", expiresAt: t0.addingTimeInterval(30))
        let h = FakeAuthHTTP([(200, sess("new", "R2"))])
        let c = DiscoveryAuthClient(projectURL: project, publishableKey: "pub", store: st, http: h, now: { self.t0 })
        let t = try await c.token(forceRefresh: false)
        XCTAssertEqual(t, "new"); XCTAssertEqual(h.calls, ["/auth/v1/token?grant_type=refresh_token"]); XCTAssertEqual(st.s?.refreshToken, "R2")
    }

    func testRejectedRefreshTokenFallsBackToOneSignUp() async throws {
        let st = MemStore(); st.s = DiscoverySession(accessToken: "old", refreshToken: "dead", expiresAt: t0)
        let h = FakeAuthHTTP([(400, "{}"), (200, sess("fresh", "R3"))])
        let c = DiscoveryAuthClient(projectURL: project, publishableKey: "pub", store: st, http: h, now: { self.t0 })
        let t = try await c.token(forceRefresh: false)
        XCTAssertEqual(t, "fresh"); XCTAssertEqual(h.calls.count, 2)
    }

    func testServerErrorDuringRefreshDoesNotSignUpAgainOrLoop() async {
        let st = MemStore(); st.s = DiscoverySession(accessToken: "old", refreshToken: "R", expiresAt: t0)
        let h = FakeAuthHTTP([(503, "")])
        let c = DiscoveryAuthClient(projectURL: project, publishableKey: "pub", store: st, http: h, now: { self.t0 })
        do { _ = try await c.token(forceRefresh: false); XCTFail("should throw") } catch {}
        XCTAssertEqual(h.calls.count, 1); XCTAssertEqual(st.s?.refreshToken, "R", "session kept for a later retry")
    }

    func testAnonymousDisabledGivesClearError() async {
        let h = FakeAuthHTTP([(422, "{}")])
        let c = DiscoveryAuthClient(projectURL: project, publishableKey: "pub", store: MemStore(), http: h, now: { self.t0 })
        do { _ = try await c.token(forceRefresh: false); XCTFail() } catch { XCTAssertTrue(error.localizedDescription.contains("not enabled")) }
    }

    func testBackendRetriesOnceAfter401WithForcedRefresh() async {
        let cfg = WebBackendConfig(projectURL: project, publishableKey: "pub")
        let a = StubAuth(forced: .init(["t1", "t2"]))
        let g = FakeGet([(401, ""), (200, #"{"results":[{"name":"P","bundleId":"u.x.com","downloadURL":"https://example.com/p.ipa"}]}"#)])
        let r = await WebBackendProvider.search(cfg, name: "x", bundleID: nil, auth: a, http: g)
        XCTAssertEqual(g.seen, ["Bearer t1", "Bearer t2"]); XCTAssertEqual(a.forced.forces, [false, true])
        // Auth retry uses an allowed IPA-shaped fixture, not a blocked social page.
        XCTAssertEqual(r.candidates.count, 1)
        XCTAssertEqual(r.candidates.first?.downloadURL?.absoluteString, "https://example.com/p.ipa")
        if case .ok(let n) = r.report.status { XCTAssertEqual(n, 1) } else { XCTFail() }
    }

    func testBackendNeverRetriesOn429OrSecond401() async {
        let cfg = WebBackendConfig(projectURL: project, publishableKey: "pub")
        let g1 = FakeGet([(429, "")]); _ = await WebBackendProvider.search(cfg, name: "x", bundleID: nil, auth: StubAuth(forced: .init(["a", "b"])), http: g1)
        XCTAssertEqual(g1.seen.count, 1)
        let g2 = FakeGet([(401, ""), (401, "")]); _ = await WebBackendProvider.search(cfg, name: "x", bundleID: nil, auth: StubAuth(forced: .init(["a", "b", "c"])), http: g2)
        XCTAssertEqual(g2.seen.count, 2)
        let g3 = FakeGet([(503, "")]); _ = await WebBackendProvider.search(cfg, name: "x", bundleID: nil, auth: StubAuth(forced: .init(["a", "b"])), http: g3)
        XCTAssertEqual(g3.seen.count, 1)
    }

    func testNotConfiguredIsExplicitAndMakesNoRequest() async {
        let g = FakeGet([])
        let r = await WebBackendProvider.search(WebBackendConfig(projectURL: nil, publishableKey: nil), name: "x", bundleID: nil, auth: nil, http: g)
        XCTAssertTrue(g.seen.isEmpty)
        if case .unavailable(let m) = r.report.status { XCTAssertTrue(m.hasPrefix("Not configured")) } else { XCTFail() }
    }

    func testSecretKeysAreRejected() {
        XCTAssertTrue(WebBackendConfig.looksSecret("sb_secret_abc"))
        func jwt(_ role: String) -> String {
            let p = Data(#"{"role":"\#(role)"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
            return "aaaa." + p + ".bbbb"
        }
        XCTAssertTrue(WebBackendConfig.looksSecret(jwt("service_role")))
        XCTAssertFalse(WebBackendConfig.looksSecret(jwt("anon")))
        XCTAssertFalse(WebBackendConfig.looksSecret("sb_publishable_abc"))
        XCTAssertFalse(WebBackendConfig(projectURL: project, publishableKey: "sb_secret_abc").isConfigured)
        XCTAssertTrue(WebBackendConfig(projectURL: project, publishableKey: "sb_publishable_abc").isConfigured)
        XCTAssertEqual(WebBackendConfig(projectURL: project, publishableKey: "k").endpoint?.absoluteString, "https://abc.supabase.co/functions/v1/discovery-search")
    }
}

final class DiscoveryDefaultsTests: XCTestCase {
    func testShippedDefaultsAreConfiguredAndPublicOnly() {
        let d = UserDefaults(suiteName: "disc-test-" + UUID().uuidString)!
        let c = WebBackendConfig.load(defaults: d)
        XCTAssertTrue(c.isConfigured)
        XCTAssertFalse(WebBackendConfig.looksSecret(c.publishableKey ?? ""))
        XCTAssertTrue((c.publishableKey ?? "").hasPrefix("sb_publishable_"))
    }
}
