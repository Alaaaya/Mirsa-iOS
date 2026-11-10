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

    func testAuthenticationRejectsAbsentOrChangedBagProtocol() throws {
        let valid: [String: Any] = [
            "authenticateAccount": "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate",
            "sign-sap-version": "200",
            "sign-sap-setup": "https://fpinit.itunes.apple.com/v1/signSapSetup/legacy",
            "sign-sap-setup-cert": "https://s.mzstatic.com/sap/setupCert.plist"
        ]
        func parsed(_ fields: [String: Any]) throws -> Bag.BagOutput {
            Bag.parse(try PropertyListSerialization.data(fromPropertyList: fields, format: .xml, options: 0))
        }
        XCTAssertNoThrow(try parsed(valid).requireSupportedAuthentication())
        for key in valid.keys {
            var changed = valid; changed.removeValue(forKey: key)
            XCTAssertThrowsError(try parsed(changed).requireSupportedAuthentication())
        }
        var changed = valid; changed["sign-sap-version"] = "201"
        XCTAssertThrowsError(try parsed(changed).requireSupportedAuthentication())
        changed = valid; changed["sign-sap-setup"] = "https://example.invalid/setup"
        XCTAssertThrowsError(try parsed(changed).requireSupportedAuthentication())
        XCTAssertThrowsError(try Bag.parse(Data("not a plist".utf8)).requireSupportedAuthentication())
    }

    func testChallengeMustBeExplicitAndNeverInferredFromEmpty204() {
        let explicit: [String: Any] = [
            "failureType": "", "customerMessage": "MZFinance.BadLogin.Configurator_message"
        ]
        XCTAssertTrue(Authenticator.requiresVerificationCode(fields: explicit, status: 200, submittedCode: ""))
        XCTAssertFalse(Authenticator.requiresVerificationCode(fields: [:], status: 204, submittedCode: ""))
        XCTAssertFalse(Authenticator.requiresVerificationCode(fields: explicit, status: 204, submittedCode: ""))
        XCTAssertFalse(Authenticator.requiresVerificationCode(fields: explicit, status: 200, submittedCode: "123456"))
        XCTAssertFalse(Authenticator.requiresVerificationCode(fields: [:], status: 200, submittedCode: ""))
        for failure in ["-5000", "5005"] {
            var wrongPassword = explicit; wrongPassword["failureType"] = failure
            XCTAssertFalse(Authenticator.requiresVerificationCode(fields: wrongPassword, status: 200, submittedCode: ""))
        }
    }

    func testNativeEndpointRequiresUnavailableProofBeforeCredentials() throws {
        let endpoint = "https://auth.itunes.apple.com/auth/v1/native"
        let fields: [String: Any] = [
            "authenticateAccount": endpoint, "sign-sap-version": "200",
            "sign-sap-setup": "https://fpinit.itunes.apple.com/v1/signSapSetup/legacy",
            "sign-sap-setup-cert": "https://s.mzstatic.com/sap/setupCert.plist"
        ]
        let bag = Bag.parse(try PropertyListSerialization.data(fromPropertyList: fields, format: .xml, options: 0))
        XCTAssertEqual(bag.authEndpoint.absoluteString, endpoint)
        XCTAssertThrowsError(try bag.requireSupportedAuthentication()) { error in
            let safe = error as? AuthenticationServiceError
            XCTAssertEqual(safe?.reason, .nativeDeviceProofUnavailable)
            XCTAssertEqual(safe?.stage, .bag)
            XCTAssertNil(safe?.message)
        }
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
            try bag.requireSupportedAuthentication()
            let signer = try await SAPSigner.connect()
            // Sign only public test bytes locally. Never POST to an account endpoint.
            let signature = try await signer.sign(Data("Mirsa credential-free preflight".utf8))
            XCTAssertFalse(signature.isEmpty)
            print("MIRSA_PREFLIGHT bag=ok sap=ok localSignature=ok accountLogin=NOT_ATTEMPTED")
        } catch {
            let safe = AuthenticationServiceError.wrapping(error, stage: .sapValidation)
            print("MIRSA_PREFLIGHT stage=\(safe.stage.rawValue) http=\(safe.httpStatus ?? 0) network=\(safe.networkCode ?? 0) accountLogin=NOT_ATTEMPTED")
            throw safe
        }
    }
}
