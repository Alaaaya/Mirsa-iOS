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
        XCTAssertNil(error.message)
        XCTAssertEqual(error.responseMessage, .missing)
        XCTAssertEqual(error.failureState, .numeric)
        XCTAssertEqual(error.loginPhase, .password)
    }

    func testResponseMetadataIsFiniteAllowlistNotArbitraryAppleText() {
        let cases: [(Any?, AuthenticationServiceError.ResponseMessage)] = [
            (nil, .missing), ("", .empty),
            ("MZFinance.BadLogin.Configurator_message", .configurator),
            (" AMD-Action::SP\n", .amdSP), ("AMD-Action::RP", .amdRP),
            ("MZFinance.BadLogin.Configurator_message owner", .unrecognized),
            ("AMD-Action::SP secret", .unrecognized),
            ("Alaa Nasser", .unrecognized), ("MH-AA 1909", .unrecognized),
            ("password=hidden cookie=hidden", .unrecognized),
            ("<script>secret</script>", .unrecognized), (["token": "secret"], .unrecognized),
            (String(repeating: "x", count: 5000), .unrecognized)
        ]
        for (raw, expected) in cases {
            var fields: [String: Any] = ["dialog": ["explanation": "Private name and address"]]
            fields["customerMessage"] = raw
            let error = Authenticator.rejection(fields, status: 403, secrets: [], submittedCode: true)
            XCTAssertEqual(error.responseMessage, expected)
            XCTAssertEqual(error.loginPhase, .verificationCode)
            XCTAssertEqual(error.failureState, .missing)
            XCTAssertEqual(error.message, AuthenticationServiceError.redact(raw as? String, secrets: []))
            let wrapped = AuthenticationServiceError.wrapping(error, stage: .signing)
            XCTAssertEqual(wrapped.responseMessage, expected)
            XCTAssertEqual(wrapped.loginPhase, .verificationCode)
        }
    }

    func testApple5020CustomerMessagePreservedWithSecretsRedacted() {
        let error = Authenticator.rejection([
            "failureType": "5020",
            "customerMessage": "The password was entered incorrectly. owner@example.invalid secret-password 123456",
            "passwordToken": "never-export"
        ], status: 200, secrets: ["owner@example.invalid", "secret-password", "123456"], submittedCode: true)
        XCTAssertEqual(error.appleCode, "5020")
        XCTAssertEqual(error.loginPhase, .verificationCode)
        XCTAssertTrue(error.message?.contains("The password was entered incorrectly.") == true)
        for secret in ["owner@example.invalid", "secret-password", "123456", "never-export"] {
            XCTAssertFalse(error.message?.contains(secret) == true)
        }
    }

    func testFailureStateDistinguishesAbsentEmptyNumericAndUntrustedValues() {
        let cases: [(Any?, AuthenticationServiceError.FailureState, String?)] = [
            (nil, .missing, nil), ("", .empty, nil), ("-5000", .numeric, "-5000"),
            (NSNumber(value: 5005), .numeric, "5005"), ("token=private", .unrecognized, nil),
            ("123456789", .unrecognized, nil), (["secret": "x"], .unrecognized, nil)
        ]
        for (raw, state, code) in cases {
            var fields: [String: Any] = [:]; fields["failureType"] = raw
            let error = Authenticator.rejection(fields, status: 429, secrets: [], submittedCode: true)
            XCTAssertEqual(error.failureState, state)
            XCTAssertEqual(error.appleCode, code)
            XCTAssertEqual(error.httpStatus, 429)
            XCTAssertNil(error.message)
        }
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
