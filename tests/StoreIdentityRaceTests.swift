import Foundation
import XCTest
#if canImport(MirsaStoreKit)
@testable import MirsaStoreKit
#else
@testable import Mirsa
#endif

final class StoreIdentityRaceTests: XCTestCase {
    private func denied() -> MirsaStoreServerError { MirsaStoreServerError(code: "staging_denied") }

    func testIdentityAppearingAfterLaunchIsAccepted() async throws {
        var reads = 0
        var sleeps = 0
        let value: String = try await MirsaStoreIdentityLoader.load(attempts: 5, sleep: { _ in sleeps += 1 }, read: {
            reads += 1
            if reads < 3 { throw self.denied() }
            return "ready"
        })
        XCTAssertEqual(value, "ready")
        XCTAssertEqual(reads, 3)
        XCTAssertEqual(sleeps, 2)
    }

    func testGenuinelyMissingIdentityStaysDeniedAndIsBounded() async {
        var reads = 0
        do {
            let _: String = try await MirsaStoreIdentityLoader.load(attempts: 4, sleep: { _ in }, read: { reads += 1; throw self.denied() })
            XCTFail("must stay denied")
        } catch let error as MirsaStoreServerError {
            guard case .code(let code) = error else { return XCTFail("wrong error") }
            XCTAssertEqual(code, "staging_denied")
        } catch { XCTFail("wrong error type") }
        XCTAssertEqual(reads, 4)
    }

    func testOtherErrorsAreNotRetried() async {
        var reads = 0
        do {
            let _: String = try await MirsaStoreIdentityLoader.load(attempts: 4, sleep: { _ in }, read: { reads += 1; throw MirsaStoreServerError(code: "unauthorized") })
            XCTFail("must throw")
        } catch {}
        XCTAssertEqual(reads, 1)
    }

    func testImmediateIdentityDoesNotWait() async throws {
        var sleeps = 0
        let v: Int = try await MirsaStoreIdentityLoader.load(sleep: { _ in sleeps += 1 }, read: { 7 })
        XCTAssertEqual(v, 7)
        XCTAssertEqual(sleeps, 0)
    }

    func testRefreshRunsThenIdentityReadsOnce() async throws {
        var ready = false, refreshes = 0
        let v: String = try await MirsaStoreIdentityLoader.loadRefreshing(refresh: { refreshes += 1; ready = true }, read: {
            if !ready { throw self.denied() }
            return "ok"
        })
        XCTAssertEqual(v, "ok"); XCTAssertEqual(refreshes, 1)
    }

    func testRefreshFailureIsTransientNotDenial() async {
        do {
            let _: String = try await MirsaStoreIdentityLoader.loadRefreshing(refresh: { throw MirsaStoreServerError(code: "upstream_unavailable") }, read: { throw self.denied() })
            XCTFail("must throw")
        } catch let e as MirsaStoreServerError { XCTAssertEqual(e, .code("upstream_unavailable")) } catch { XCTFail("type") }
    }

    func testMissingAfterSuccessfulRefreshIsDefinitiveDenial() async {
        do {
            let _: String = try await MirsaStoreIdentityLoader.loadRefreshing(refresh: {}, read: { throw self.denied() })
            XCTFail("must throw")
        } catch let e as MirsaStoreServerError { XCTAssertEqual(e, .code("staging_denied")) } catch { XCTFail("type") }
    }

    func testPresentIdentityNeverRefreshes() async throws {
        var refreshes = 0
        let _: Int = try await MirsaStoreIdentityLoader.loadRefreshing(refresh: { refreshes += 1 }, read: { 1 })
        XCTAssertEqual(refreshes, 0)
    }

    func testUnauthorizedIsNotRefreshed() async {
        var refreshes = 0
        do {
            let _: Int = try await MirsaStoreIdentityLoader.loadRefreshing(refresh: { refreshes += 1 }, read: { throw MirsaStoreServerError(code: "unauthorized") })
            XCTFail("must throw")
        } catch {}
        XCTAssertEqual(refreshes, 0)
    }

    // Real MirsaStoreServerClient path with a controllable, delayed identity and a real /account round trip.
    private func client(_ outcome: @escaping () async throws -> MirsaStoreServerIdentity,
                        http: @escaping MirsaStoreServerClient.HTTP) -> MirsaStoreServerClient {
        MirsaStoreServerClient(identity: outcome, vault: RaceVault(), http: http)
    }
    private func identity() -> MirsaStoreServerIdentity {
        .init(bearer: "b", userID: UUID(), forgeDeviceID: "91f71c66-b727-450e-8de2-244a1cf85915",
              forgeDeviceToken: String(repeating: "a", count: 64))
    }
    private func ok(_ req: URLRequest) -> (Data, Int) {
        req.url!.path.hasSuffix("/devices")
            ? (Data(#"{"deviceToken":"\#(String(repeating: "D", count: 43))"}"#.utf8), 200)
            : (Data(#"{"status":"signed_out"}"#.utf8), 200)
    }

    func testGateStateAuthorizedWhenIdentityReady() async {
        let c = client({ self.identity() }, http: { self.ok($0) })
        let s = await c.gateState()
        XCTAssertEqual(s, .authorized)
    }

    func testGateStateDefinitiveDenialsAndUnknown() async {
        for (code, expected) in [("staging_denied", MirsaStoreGateState.denied), ("unauthorized", .denied),
                                 ("upstream_unavailable", .unknown), ("rate_limited", .unknown)] {
            let c = client({ throw MirsaStoreServerError(code: code) }, http: { self.ok($0) })
            let s = await c.gateState()
            XCTAssertEqual(s, expected, code)
        }
        let net = client({ self.identity() }, http: { _ in throw URLError(.timedOut) })
        let timeout = await net.gateState()
        XCTAssertEqual(timeout, .unknown)
    }

    func testDelayedIdentityFirstCallUnknownNotDenialThenAuthorized() async {
        let box = Flag()
        let c = client({
            if !box.value { throw MirsaStoreServerError(code: "upstream_unavailable") }
            return self.identity()
        }, http: { self.ok($0) })
        let first = await c.gateState()
        XCTAssertEqual(first, .unknown)
        box.value = true
        let second = await c.gateState()
        XCTAssertEqual(second, .authorized)
    }

    func testOnDeviceClientMapsStatesWithoutIdentityDenialForUnknown() async {
        for (state, expected) in [(MirsaStoreGateState.unknown, "upstream_unavailable"), (.denied, "staging_denied")] {
            let c = MirsaStoreOnDeviceClient(gate: { false }, stateGate: { state }, vault: RaceVault())
            do { _ = try await c.search(term: "1632106976", country: "TR"); XCTFail("must throw") }
            catch let e as MirsaStoreServerError { XCTAssertEqual(e, .code(expected)) }
            catch let e as MirsaStoreError { XCTAssertEqual(e, .signedOut) } // no saved account: gate order not under test
            catch { XCTFail("type") }
        }
    }
}

final class Flag { var value = false }
final class RegCounter: @unchecked Sendable { private let l = NSLock(); private var n = 0; func set() { l.lock(); n += 1; l.unlock() }; var count: Int { l.lock(); defer { l.unlock() }; return n } }
private final class RaceVault: MirsaStoreVault {
    var items: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { items[key] }
    func write(_ data: Data, key: String) throws { items[key] = data }
    func remove(_ key: String) throws { items[key] = nil }

    func testRegistrationSharedAndNeverTrustsLocalRead() async throws {
        let reg = MirsaStoreRegistration()
        let user = UUID()
        let counter = RegCounter()
        let jwt = StoreIdentityRaceTests.jwt(user)
        let op: @Sendable () async throws -> ForgeFixCredentials = {
            counter.set()
            try await Task.sleep(nanoseconds: 50_000_000)
            return ForgeFixCredentials(accessToken: jwt, deviceID: "D", deviceToken: String(repeating: "a", count: 64))
        }
        async let a = reg.credentials(user: user, register: op)
        async let b = reg.credentials(user: user, register: op)
        _ = try await (a, b)
        _ = try await reg.credentials(user: user, register: op)
        XCTAssertEqual(counter.count, 1)
    }

    func testRegistrationTransientAndWrongUserAreUnknown() async {
        let reg = MirsaStoreRegistration()
        let user = UUID()
        for op: @Sendable () async throws -> ForgeFixCredentials in [
            { throw URLError(.notConnectedToInternet) },
            { ForgeFixCredentials(accessToken: StoreIdentityRaceTests.jwt(UUID()), deviceID: "D", deviceToken: "t") }] {
            do { _ = try await reg.credentials(user: user, register: op); XCTFail("must throw") }
            catch let e as MirsaStoreServerError { XCTAssertEqual(e, MirsaStoreServerError(code: "upstream_unavailable")) }
            catch { XCTFail("wrong error") }
        }
    }

    static func jwt(_ user: UUID) -> String {
        func b(_ s: String) -> String { Data(s.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_") }
        return b("{}") + "." + b("{\"sub\":\"" + user.uuidString.lowercased() + "\",\"role\":\"authenticated\"}") + ".sig"
    }
}
