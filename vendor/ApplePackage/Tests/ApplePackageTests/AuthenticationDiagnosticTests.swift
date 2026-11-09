@testable import ApplePackage
import XCTest

final class AuthenticationDiagnosticTests: XCTestCase {
    func testHTTPRejectionPreservesOnlyExplicitSafeFields() {
        let error = Authenticator.rejection([
            "failureType": "-5000",
            "dialog": ["explanation": "Apple rejected owner@example.invalid secret-password 123456"],
            "passwordToken": "do-not-export",
            "dsPersonId": "never-show"
        ], status: 403, secrets: ["owner@example.invalid", "secret-password", "123456"])
        XCTAssertEqual(error.stage, .authentication)
        XCTAssertEqual(error.httpStatus, 403)
        XCTAssertEqual(error.appleCode, "-5000")
        XCTAssertEqual(error.message, "Apple rejected [redacted] [redacted] [redacted]")
    }

    func testUntrustedCodeAndPayloadAreNeverDiagnosticCode() {
        let error = AuthenticationServiceError(stage: .sapSetup, appleCode: "token-secret",
            message: "password=bad token=bad cookie=bad https://example.invalid/?auth=secret a@b.example 12345678")
        XCTAssertNil(error.appleCode)
        XCTAssertFalse(error.message!.contains("bad"))
        XCTAssertFalse(error.message!.contains("secret"))
        XCTAssertFalse(error.message!.contains("12345678"))
    }

    func testOversizedMessageDroppedRatherThanTruncatedSecret() {
        XCTAssertNil(AuthenticationServiceError(stage: .authentication,
            message: String(repeating: "x", count: 4097)).message)
    }

    func testWrappingNeverExposesArbitraryErrorDescription() {
        let inner = NSError(domain: NSURLErrorDomain, code: -1009,
                            userInfo: [NSLocalizedDescriptionKey: "password secret token"])
        let error = AuthenticationServiceError.wrapping(inner, stage: .sapCertificate)
        XCTAssertEqual(error.stage, .sapCertificate)
        XCTAssertEqual(error.networkCode, -1009)
        XCTAssertNil(error.message)
        XCTAssertNil(error.httpStatus)
    }

    func testNestedStructuredErrorPreservesStage() {
        let initial = AuthenticationServiceError(stage: .sapSetup, httpStatus: 503)
        let outer = AuthenticationServiceError.wrapping(initial, stage: .sapValidation)
        XCTAssertEqual(outer.stage, .sapSetup)
        XCTAssertEqual(outer.httpStatus, 503)
    }

    func testCredentialFreeLiveSAPPreflight() async throws {
        guard ProcessInfo.processInfo.environment["MIRSA_AUTH_PREFLIGHT"] == "1" else {
            throw XCTSkip("Explicit opt-in credential-free Apple SAP transport probe")
        }
        Configuration.deviceIdentifier = "012345ABCDEF"
        APLogger.verbose = false
        // No Authenticator.authenticate call, no login, no invented account.
        do {
            let bag = try await Bag.fetchBag(redirectConfiguration: .disallow)
            XCTAssertNotNil(bag.authEndpoint.host)
            _ = try await SAPSigner.connect()
            print("MIRSA_PREFLIGHT bag=ok sap=ok accountLogin=NOT_ATTEMPTED")
        } catch {
            let safe = AuthenticationServiceError.wrapping(error, stage: .sapValidation)
            print("MIRSA_PREFLIGHT stage=\(safe.stage.rawValue) http=\(safe.httpStatus ?? 0) network=\(safe.networkCode ?? 0) accountLogin=NOT_ATTEMPTED")
            throw safe
        }
    }
}
