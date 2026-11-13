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
}
