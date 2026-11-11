@testable import ApplePackage
import AsyncHTTPClient
import CStoreAMD
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import XCTest

@MainActor
final class SAPAuthenticationRequestTests: XCTestCase {
    private actor RecordingSigner: SAPRequestSigning {
        private var bodies: [Data] = []

        func sign(_ body: Data) throws -> Data {
            bodies.append(body)
            return Data([0xA5, UInt8(bodies.count)])
        }

        func recordedBodies() -> [Data] {
            bodies
        }
    }

    private actor FailingSigner: SAPRequestSigning { func sign(_: Data) throws -> Data {
        throw TestError.signingFailed
    } }

    private enum TestError: Error {
        case signingFailed
        case unexpectedBodyChunk
    }

    /// Run the actual AsyncHTTPClient body producer without opening a socket.
    private func bodyData(_ request: HTTPClient.Request) throws -> Data {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let eventLoop = group.next()
        let captured = NIOLockedValueBox(Data())
        let body = try XCTUnwrap(request.body)
        try body.stream(
            .init { part in
                guard case let .byteBuffer(buffer) = part else { return eventLoop.makeFailedFuture(TestError.unexpectedBodyChunk) }
                captured.withLockedValue { $0.append(contentsOf: buffer.readableBytesView) }
                return eventLoop.makeSucceededFuture(())
            },
        ).wait()
        return captured.withLockedValue { $0 }
    }

    private func makeRequest(
        endpoint: String = "https://auth.itunes.apple.com/login", code: String = "", signer: any SAPRequestSigning = RecordingSigner(),
    ) async throws -> HTTPClient.Request {
        try await Authenticator.makeRequest(
            endpoint: XCTUnwrap(URL(string: endpoint)), email: "reader+ä@example.invalid", password: "test<&password", code: code,
            cookies: [], deviceIdentifier: "001122334455", sapSigner: signer,
        )
    }

    func testSignatureCoversExactSerializedHTTPBody() async throws {
        let signer = RecordingSigner()
        let request = try await makeRequest(code: "123456", signer: signer)
        let sentBody = try bodyData(request)
        let signedBodies = await signer.recordedBodies()
        XCTAssertEqual(signedBodies, [sentBody])
        XCTAssertEqual(request.method.rawValue, "POST")
        XCTAssertEqual(request.headers.first(name: "Content-Type"), "application/x-apple-plist")
        let signature = try XCTUnwrap(request.headers.first(name: "X-Apple-ActionSignature"))
        XCTAssertEqual(Data(base64Encoded: signature), Data([0xA5, 1]))
        let parameters = try XCTUnwrap(PropertyListSerialization.propertyList(from: sentBody, format: nil) as? [String: String])
        XCTAssertEqual(parameters["appleId"], "reader+ä@example.invalid")
        XCTAssertEqual(parameters["password"], "test<&password123456")
        XCTAssertEqual(parameters["attempt"], "2")
        XCTAssertEqual(parameters["guid"], "001122334455")
        XCTAssertEqual(parameters["rmp"], "0")
        XCTAssertEqual(parameters["why"], "signIn")
    }

    func testRetryRedirectAndVerificationReuseSignerState() async throws {
        let signer = RecordingSigner()
        let first = try await makeRequest(signer: signer)
        let retry = try await makeRequest(signer: signer)
        let redirect = try await makeRequest(endpoint: "https://p25-buy.itunes.apple.com/login", signer: signer)
        let verification = try await makeRequest(endpoint: "https://p25-buy.itunes.apple.com/login", code: "654321", signer: signer)
        let requests = [first, retry, redirect, verification]
        let sentBodies = try requests.map(bodyData)
        let signedBodies = await signer.recordedBodies()
        XCTAssertEqual(signedBodies, sentBodies)
        let initial = try XCTUnwrap(PropertyListSerialization.propertyList(from: sentBodies[0], format: nil) as? [String: String])
        XCTAssertEqual(initial["attempt"], "1")
        XCTAssertEqual(sentBodies[0], sentBodies[1])
        XCTAssertEqual(sentBodies[0], sentBodies[2])
        XCTAssertNotEqual(sentBodies[2], sentBodies[3])
        for (index, request) in requests.enumerated() {
            let header = try XCTUnwrap(request.headers.first(name: "X-Apple-ActionSignature"))
            XCTAssertEqual(Data(base64Encoded: header), Data([0xA5, UInt8(index + 1)]))
        }
    }

    func testUnapprovedEndpointNeverReachesSigner() async throws {
        let signer = RecordingSigner()
        do {
            _ = try await makeRequest(endpoint: "http://auth.itunes.apple.com/login", signer: signer)
            XCTFail("Expected unapproved endpoint rejection")
        } catch {
            let bodies = await signer.recordedBodies()
            XCTAssertTrue(bodies.isEmpty)
        }
    }

    func testSigningFailurePreventsRequestConstruction() async throws {
        do {
            _ = try await makeRequest(signer: FailingSigner())
            XCTFail("Expected signing failure")
        } catch let diagnostic as AuthenticationServiceError {
            XCTAssertEqual(diagnostic.stage, .signing)
            XCTAssertNil(diagnostic.message)
            XCTAssertNil(diagnostic.httpStatus)
            // No request is returned to the HTTP client.
        }
    }

    func testSignatureHeaderIsRedactedCaseInsensitively() {
        XCTAssertEqual(APLogger.safeHeaderValue(name: "X-Apple-ActionSignature", value: "sensitive-blob"), "<redacted>")
        XCTAssertEqual(APLogger.safeHeaderValue(name: "x-apple-actionsignature", value: "sensitive-blob"), "<redacted>")
        XCTAssertEqual(APLogger.safeHeaderValue(name: "X-Token", value: "secret"), "<redacted>")
        XCTAssertEqual(APLogger.safeHeaderValue(name: "Content-Type", value: "application/x-apple-plist"), "application/x-apple-plist")
        for header in ["Cookie", "Set-Cookie", "Authorization", "X-Apple-DSID", "Location", "X-Unknown"] {
            XCTAssertEqual(APLogger.safeHeaderValue(name: header, value: "private-value"), "<redacted>")
        }
        XCTAssertEqual(APLogger.safeURL("https://user:pass@apple.com/auth?guid=private#fragment"), "https://apple.com/auth")
    }

    func testLegacyAuthenticationEndpointRequiresTrailingSlash() throws {
        let path = "/WebObjects/MZFinance.woa/wa/authenticate"
        for host in ["buy.itunes.apple.com", "p25-buy.itunes.apple.com", "p123-buy.itunes.apple.com"] {
            let original = "https://\(host)\(path)?guid=A%2FB&value=1"
            let normalized = try XCTUnwrap(Bag.normalizedAuthEndpoint(from: original))
            XCTAssertEqual(normalized.absoluteString, "https://\(host)\(path)/?guid=A%2FB&value=1")
            XCTAssertEqual(Bag.normalizedAuthEndpoint(from: normalized.absoluteString), normalized)
        }
        for original in [
            "http://buy.itunes.apple.com\(path)", "https://example.invalid\(path)", "https://evilbuy.itunes.apple.com\(path)",
            "https://pfoo-buy.itunes.apple.com\(path)", "https://p25-buy.itunes.apple.com.example.invalid\(path)",
            "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/other",
        ] {
            XCTAssertEqual(Bag.normalizedAuthEndpoint(from: original)?.absoluteString, original)
        }
    }

    func testNativeAuthenticationEndpointNormalizationIsPreserved() {
        for path in ["/auth/v1/native", "/auth/v1/native/", "/auth/v1/native/fast", "/auth/v1/native/fast/"] {
            let original = "https://auth.itunes.apple.com\(path)?guid=example"
            XCTAssertEqual(
                Bag.normalizedAuthEndpoint(from: original)?.absoluteString,
                original,
            )
        }
    }
    func testLiveBagNativeRouteIsNotRewrittenToFast() async throws {
        let advertised = "https://auth.itunes.apple.com/auth/v1/native"
        let xml = try PropertyListSerialization.data(fromPropertyList: [
            "authenticateAccount": advertised,
            "sign-sap-version": "200",
            "sign-sap-setup": "https://fpinit.itunes.apple.com/v1/signSapSetup/legacy",
            "sign-sap-setup-cert": "https://s.mzstatic.com/sap/setupCert.plist"
        ], format: .xml, options: 0)
        let bag = Bag.parse(xml)
        try bag.requireSupportedAuthentication()
        XCTAssertEqual(bag.authEndpoint.absoluteString, advertised)
        let signer = RecordingSigner()
        let request = try await makeRequest(endpoint: bag.authEndpoint.absoluteString, code: "123456", signer: signer)
        XCTAssertEqual(request.url.absoluteString, advertised)
        let recorded = await signer.recordedBodies()
        XCTAssertEqual(try bodyData(request), recorded.first)
    }

    func testInitialNativeRequestMatchesAdvertisedOnDeviceProtocol() async throws {
        let advertised = try XCTUnwrap(URL(string: "https://auth.itunes.apple.com/auth/v1/native?pod=25"))
        let endpoint = try Authenticator.createInitialRequestEndpoint(baseURL: advertised, deviceIdentifier: "001122334455")
        XCTAssertEqual(endpoint, advertised)
        let request = try await makeRequest(endpoint: endpoint.absoluteString, code: "123456")
        XCTAssertEqual(request.url, advertised)
        XCTAssertEqual(request.method.rawValue, "POST")
        XCTAssertEqual(request.headers.first(name: "User-Agent"), Configuration.userAgent)
        XCTAssertTrue(Configuration.userAgent.hasPrefix("Configurator/2.21 "))
        XCTAssertEqual(request.headers.first(name: "Content-Type"), "application/x-apple-plist")
        let fields = try XCTUnwrap(PropertyListSerialization.propertyList(from: bodyData(request), format: nil) as? [String: String])
        XCTAssertEqual(fields, ["appleId": "reader+ä@example.invalid", "attempt": "2", "guid": "001122334455",
                               "password": "test<&password123456", "rmp": "0", "why": "signIn"])
    }

    func testInitialLegacyRequestRetainsGuidSuffixAndPod() throws {
        let base = try XCTUnwrap(Bag.normalizedAuthEndpoint(from: "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate?Pod=25"))
        let endpoint = try Authenticator.createInitialRequestEndpoint(baseURL: base, deviceIdentifier: "001122334455")
        XCTAssertEqual(endpoint.absoluteString, "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/?Pod=25&guid=001122334455")
    }

    private actor OfflineAMD: StoreAMDProviding {
        private var generation = 0
        private var provisionCalls = 0
        private var resetCalls = 0
        func headers() -> [String: String] {
            generation == 0 ? [:] : ["X-Apple-AMD": "otp-\(generation)", "X-Apple-AMD-M": "machine-\(generation)"]
        }
        func provision(_ challenge: Data) { provisionCalls += 1; generation += 1 }
        func reset() { resetCalls += 1; generation = 0 }
        func hasProfile() -> Bool { generation > 0 }
        func observeServerDate(_: Date) {}
        func snapshot() -> [Int] { [provisionCalls, resetCalls] }
    }

    func testSPRetriesAdvertisedURLWithSameSignedBodyAndFreshProof() async throws {
        let proof = OfflineAMD()
        var handshake = StoreAMDHandshake(provider: proof)
        let signer = RecordingSigner()
        let endpoint = try XCTUnwrap(URL(string: "https://auth.itunes.apple.com/auth/v1/native?pod=25"))
        let body = try Authenticator.authenticationBody(email: "offline@example.invalid", password: "fixture", code: "", deviceIdentifier: "001122334455")
        var requests: [HTTPClient.Request] = []
        for index in 0..<2 {
            requests.append(try await Authenticator.makeRequest(endpoint: endpoint, email: "offline@example.invalid", password: "fixture", code: "",
                cookies: [], deviceIdentifier: "001122334455", sapSigner: signer, serializedBody: body, amdHeaders: try await proof.headers()))
            if index == 0 {
                let handled = try await handshake.respond(fields: ["customerMessage": "AMD-Action::SP"], action: nil,
                                                           challenge: Data([1,2,3]).base64EncodedString())
                XCTAssertTrue(handled)
            }
        }
        XCTAssertEqual(requests.map(\.url), [endpoint, endpoint])
        XCTAssertEqual(try requests.map(bodyData), [body, body])
        let recorded = await signer.recordedBodies()
        XCTAssertEqual(recorded, [body, body])
        XCTAssertNil(requests[0].headers.first(name: "X-Apple-AMD"))
        XCTAssertEqual(requests[1].headers.first(name: "X-Apple-AMD"), "otp-1")
        XCTAssertEqual(requests[1].headers.first(name: "X-Apple-AMD-M"), "machine-1")
        for request in requests { XCTAssertNotNil(request.headers.first(name: "X-Apple-ActionSignature")) }
        XCTAssertEqual(APLogger.safeHeaderValue(name: "X-Apple-AMD", value: "otp-1"), "<redacted>")
        XCTAssertEqual(APLogger.safeHeaderValue(name: "X-Apple-AMD-Data", value: "challenge"), "<redacted>")
    }

    func testRPDiscardsProofAndAllowsExactlyOneReprovision() async throws {
        let proof = OfflineAMD()
        var handshake = StoreAMDHandshake(provider: proof)
        let challenge = Data([1]).base64EncodedString()
        _ = try await handshake.respond(fields: [:], action: "SP", challenge: challenge)
        _ = try await handshake.respond(fields: [:], action: "RP", challenge: nil)
        let empty = try await proof.headers()
        XCTAssertTrue(empty.isEmpty)
        _ = try await handshake.respond(fields: [:], action: "SP", challenge: challenge)
        for action in ["SP", "RP"] {
            do { _ = try await handshake.respond(fields: [:], action: action, challenge: challenge); XCTFail("Unbounded machine challenge retry") }
            catch is StoreAMDError { }
        }
        let counts = await proof.snapshot()
        XCTAssertEqual(counts, [2, 1])
    }

    func testRepeatedSPStopsBeforeSecondProvision() async throws {
        let proof = OfflineAMD()
        var handshake = StoreAMDHandshake(provider: proof)
        _ = try await handshake.respond(fields: [:], action: "SP", challenge: "AQ==")
        do { _ = try await handshake.respond(fields: [:], action: "SP", challenge: "AQ=="); XCTFail("Repeated SP") }
        catch is StoreAMDError { }
        let counts = await proof.snapshot()
        XCTAssertEqual(counts, [1, 0])
    }

    func testMalformedSPNeverReachesProvisionerAndIsNotTwoFactor() async throws {
        for malformed in ["", "!", "AQ", "AR==", "AQ==\n", String(repeating: "A", count: 16388)] {
            let proof = OfflineAMD()
            var handshake = StoreAMDHandshake(provider: proof)
            do {
                _ = try await handshake.respond(fields: ["customerMessage": "AMD-Action::SP"], action: nil, challenge: malformed)
                XCTFail("Accepted invalid challenge")
            } catch is StoreAMDError { }
            let counts = await proof.snapshot()
            XCTAssertEqual(counts, [0, 0])
        }
        XCTAssertThrowsError(try StoreAMDAction.parse(fields: [:], actionHeader: "SP", challenge: nil))
        XCTAssertFalse(Authenticator.requiresVerificationCode(["failureType": "", "customerMessage": "AMD-Action::SP"], submittedCode: false))
    }

    func testConfiguratorTwoFactorIsSeparateFromMachineProvisioning() async throws {
        let fields = ["failureType": "", "customerMessage": "MZFinance.BadLogin.Configurator_message"]
        XCTAssertTrue(Authenticator.requiresVerificationCode(fields, submittedCode: false))
        XCTAssertFalse(Authenticator.requiresVerificationCode(fields, submittedCode: true))
        XCTAssertFalse(Authenticator.requiresVerificationCode(["failureType": "5005", "customerMessage": fields["customerMessage"]!], submittedCode: false))
        let proof = OfflineAMD()
        var handshake = StoreAMDHandshake(provider: proof)
        let handled = try await handshake.respond(fields: fields, action: nil, challenge: nil)
        XCTAssertFalse(handled)
        let before = try await makeRequest()
        let after = try await makeRequest(code: "654321")
        let a = try XCTUnwrap(PropertyListSerialization.propertyList(from: bodyData(before), format: nil) as? [String: String])
        let b = try XCTUnwrap(PropertyListSerialization.propertyList(from: bodyData(after), format: nil) as? [String: String])
        XCTAssertEqual(b["password"], a["password"]! + "654321")
        XCTAssertEqual(b["attempt"], "2")
    }

    func testNativeEngineRejectsMalformedChallengeWithoutNetwork() {
        let hardware = [UInt8](repeating: 1, count: 20)
        let challenge: [UInt8] = [1,2,3]
        let session = mirsa_store_begin(challenge, challenge.count, hardware, 1700000000)
        XCTAssertNil(session)
        if let session { mirsa_store_session_free(session) }
    }

}
