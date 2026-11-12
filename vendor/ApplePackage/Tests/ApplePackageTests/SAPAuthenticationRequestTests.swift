@testable import ApplePackage
import AsyncHTTPClient
import CStoreAMD
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import NIOHTTP1
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
        func synchronize(dateHeader: String?) throws { var clock = StoreAMDClock(); try clock.synchronize(dateHeader) }
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

    private actor ScriptedHTTP {
        private var responses: [HTTPClient.Response]
        private var requests: [HTTPClient.Request] = []
        init(_ responses: [HTTPClient.Response]) { self.responses = responses }
        func execute(_ request: HTTPClient.Request) throws -> HTTPClient.Response {
            requests.append(request)
            guard !responses.isEmpty else { throw TestError.unexpectedBodyChunk }
            return responses.removeFirst()
        }
        func recorded() -> [HTTPClient.Request] { requests }
    }

    private func response(status: HTTPResponseStatus = .ok, action: String? = nil,
                          fields: [String: Any] = [:], date: String? = "Wed, 11 Nov 2026 22:00:00 GMT") throws -> HTTPClient.Response {
        var headers = HTTPHeaders([("x-set-apple-store-front", "143441-1")])
        if let date { headers.add(name: "Date", value: date) }
        if let action {
            headers.add(name: "X-Apple-AMD-Action", value: action)
            headers.add(name: "X-Apple-AMD-Data", value: "AQ==")
        }
        let data = try PropertyListSerialization.data(fromPropertyList: fields, format: .xml, options: 0)
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        return .init(host: "auth.itunes.apple.com", status: status, version: .http1_1, headers: headers, body: buffer)
    }

    private var successFields: [String: Any] {
        ["accountInfo": ["appleId": "offline@example.invalid", "address": ["firstName": "Test", "lastName": "Reader"]],
         "passwordToken": "fixture-token", "dsPersonId": "fixture-person"]
    }

    private func session(_ http: ScriptedHTTP, proof: OfflineAMD, signer: RecordingSigner) throws -> Authenticator {
        try Authenticator(endpoint: XCTUnwrap(URL(string: "https://auth.itunes.apple.com/auth/v1/native")),
                          deviceIdentifier: "001122334455", signer: signer, amd: proof,
                          executor: { request in try await http.execute(request) })
    }

    func testCompleteLoopSPProvisionRetrySuccessOnAnyHTTPStatus() async throws {
        for status in [HTTPResponseStatus.ok, .forbidden, .internalServerError, .found] {
            let http = try ScriptedHTTP([response(status: status, action: "SP"), response(fields: successFields)])
            let proof = OfflineAMD()
            let signer = RecordingSigner()
            let auth = try session(http, proof: proof, signer: signer)
            let account = try await auth.authenticate(email: "offline@example.invalid", password: "fixture")
            XCTAssertEqual(account.email, "offline@example.invalid")
            let requests = await http.recorded()
            XCTAssertEqual(requests.count, 2)
            let bodies = try requests.map(bodyData)
            XCTAssertEqual(bodies[0], bodies[1])
            let signed = await signer.recordedBodies()
            XCTAssertEqual(signed, bodies)
            XCTAssertNil(requests[0].headers.first(name: "X-Apple-AMD"))
            XCTAssertEqual(requests[1].headers.first(name: "X-Apple-AMD"), "otp-1")
            let counts = await proof.snapshot()
            XCTAssertEqual(counts, [1, 0])
        }
    }

    func testCompleteLoopSPThenTwoFactorThenCodeUsesSameSession() async throws {
        let http = try ScriptedHTTP([
            response(status: .forbidden, action: "SP"),
            response(fields: ["failureType": "", "customerMessage": "MZFinance.BadLogin.Configurator_message"]),
            response(fields: successFields)
        ])
        let proof = OfflineAMD()
        let signer = RecordingSigner()
        let auth = try session(http, proof: proof, signer: signer)
        do {
            _ = try await auth.authenticate(email: "offline@example.invalid", password: "fixture")
            XCTFail("Expected verification code")
        } catch AuthenticationError.verificationCodeRequired { }
        _ = try await auth.authenticate(email: "offline@example.invalid", password: "fixture", code: "654321")
        let requests = await http.recorded()
        XCTAssertEqual(requests.count, 3)
        let bodies = try requests.map(bodyData)
        XCTAssertEqual(bodies[0], bodies[1])
        let fields = try XCTUnwrap(PropertyListSerialization.propertyList(from: bodies[2], format: nil) as? [String: String])
        XCTAssertEqual(fields["attempt"], "2")
        XCTAssertEqual(fields["password"], "fixture654321")
        XCTAssertEqual(requests[2].headers.first(name: "X-Apple-AMD"), "otp-1")
        let signed = await signer.recordedBodies()
        XCTAssertEqual(signed, bodies)
        let counts = await proof.snapshot()
        XCTAssertEqual(counts, [1, 0])
    }

    func testCompleteLoopRepeatedChallengeIsBounded() async throws {
        let http = try ScriptedHTTP([response(status: .forbidden, action: "SP"), response(status: .forbidden, action: "SP")])
        let proof = OfflineAMD()
        let auth = try session(http, proof: proof, signer: RecordingSigner())
        do {
            _ = try await auth.authenticate(email: "offline@example.invalid", password: "fixture")
            XCTFail("Expected budget error")
        } catch let error as StoreAMDError { XCTAssertEqual(error.step, .budget) }
        let counts = await proof.snapshot()
        XCTAssertEqual(counts, [1, 0])
    }

    func testCompleteLoopMissingOrInvalidDateGivesDistinctSafeError() async throws {
        for date in [nil, "private-challenge-not-a-date"] as [String?] {
            let http = try ScriptedHTTP([response(status: .forbidden, action: "SP", date: date)])
            let proof = OfflineAMD()
            let auth = try session(http, proof: proof, signer: RecordingSigner())
            do {
                _ = try await auth.authenticate(email: "offline@example.invalid", password: "fixture")
                XCTFail("Expected clock diagnostic")
            } catch let error as StoreAMDError {
                XCTAssertEqual(error.step, .clock)
                XCTAssertFalse(error.localizedDescription.contains("private-challenge"))
            }
            let counts = await proof.snapshot()
            XCTAssertEqual(counts, [0, 0])
        }
    }

    func testAppleDateOffsetCorrectsPositiveAndNegativeClockSkew() throws {
        let server = Date(timeIntervalSince1970: 1794434400) // Wed 11 Nov 2026 22:00 GMT
        for skew: TimeInterval in [-86400, 86400] {
            let local = server.addingTimeInterval(skew)
            var clock = StoreAMDClock()
            try clock.synchronize("Wed, 11 Nov 2026 22:00:00 GMT", now: local)
            XCTAssertEqual(try clock.seconds(now: local.addingTimeInterval(5)), UInt32(server.timeIntervalSince1970 + 5))
        }
        var clock = StoreAMDClock()
        XCTAssertThrowsError(try clock.synchronize(nil))
        XCTAssertThrowsError(try clock.synchronize("secret"))
    }

    func testSafeAMDDiagnosticsSurviveAuthenticationWrapping() {
        for step: StoreAMDError.Step in [.begin, .request, .finish, .http, .keychain, .clock] {
            let error = StoreAMDError(step, httpStatus: 503, keychainStatus: -25308)
            let diagnostic = AuthenticationServiceError.wrapping(error, stage: .authentication)
            XCTAssertEqual(diagnostic.httpStatus, 503)
            XCTAssertTrue(diagnostic.message?.contains("[AMD " + step.rawValue + "]") == true)
            XCTAssertTrue(diagnostic.message?.contains("Keychain -25308") == true)
        }
    }

    func testAMDParserNormalizesHeaderAndLastMessageComponent() throws {
        for action in [" sp ", "\tSp\n"] {
            XCTAssertEqual(try StoreAMDAction.parse(fields: [:], actionHeader: action, challenge: "AQ=="), .provision(Data([1])))
        }
        for message in ["AMD-Action::SP", "AMD-Action:extra: sp ", " AMD-Action::rp "] {
            let parsed = try StoreAMDAction.parse(fields: ["customerMessage": message], actionHeader: " ", challenge: "AQ==")
            XCTAssertEqual(parsed, message.contains("rp") ? .reset : .provision(Data([1])))
        }
        for message in ["AMD-Action", "AMD-Action::private-value"] {
            do {
                _ = try StoreAMDAction.parse(fields: ["customerMessage": message], actionHeader: nil, challenge: "private-challenge")
                XCTFail("Unresolved challenge")
            } catch let error as StoreAMDError {
                XCTAssertTrue(error.localizedDescription.contains("تسجيل الجهاز ما كمل"))
                XCTAssertTrue(error.localizedDescription.contains("header=false"))
                XCTAssertTrue(error.localizedDescription.contains("AMDDataLength=17"))
                XCTAssertFalse(error.localizedDescription.contains("private"))
            }
        }
        let diagnostic = Authenticator.rejection(["customerMessage": "AMD-Action::private"], status: 200, secrets: [])
        XCTAssertEqual(diagnostic.message, "تسجيل الجهاز ما كمل")
    }

    func testRPWithoutProfileDoesNotResetOrConsumeBudget() async throws {
        let proof = OfflineAMD()
        var handshake = StoreAMDHandshake(provider: proof)
        for _ in 0..<3 {
            let handled = try await handshake.respond(fields: [:], action: " rp ", challenge: nil)
            XCTAssertFalse(handled)
        }
        let counts = await proof.snapshot()
        XCTAssertEqual(counts, [0, 0])
        _ = try await handshake.respond(fields: [:], action: "SP", challenge: "AQ==")
        _ = try await handshake.respond(fields: [:], action: "RP", challenge: nil)
        let after = await proof.snapshot()
        XCTAssertEqual(after, [1, 1])
    }

    func testAMDHeadersAreScopedToNativeAndPurchaseOnly() async throws {
        let proof = ["X-Apple-AMD": "otp", "X-Apple-AMD-M": "machine"]
        for endpoint in [
            "https://auth.itunes.apple.com/auth/v1/native",
            "https://auth.itunes.apple.com/auth/v1/native/fast/",
            "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/buyProduct",
            "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/buyProduct",
        ] {
            var headers: [(String, String)] = []
            try StoreAMDHeaderScope.append(proof, to: &headers, url: XCTUnwrap(URL(string: endpoint)))
            XCTAssertEqual(headers.count, 2)
        }
        for endpoint in [
            "https://auth.itunes.apple.com/auth/v1/otp/1.5/finish",
            "https://auth.itunes.apple.com/login",
            "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct",
            "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate",
            "https://cdn.apple.com/WebObjects/MZFinance.woa/wa/buyProduct",
            "https://p25-buy.itunes.apple.com.evil.invalid/auth/v1/native",
            "http://auth.itunes.apple.com/auth/v1/native",
        ] {
            var headers: [(String, String)] = []
            try StoreAMDHeaderScope.append(proof, to: &headers, url: XCTUnwrap(URL(string: endpoint)))
            XCTAssertTrue(headers.isEmpty)
        }
        let request = try await Authenticator.makeRequest(endpoint: XCTUnwrap(URL(string: "https://auth.itunes.apple.com/login")),
            email: "offline@example.invalid", password: "fixture", code: "", cookies: [], deviceIdentifier: "001122334455",
            sapSigner: RecordingSigner(), amdHeaders: proof)
        XCTAssertNil(request.headers.first(name: "X-Apple-AMD"))
        XCTAssertNotNil(request.headers.first(name: "X-Apple-ActionSignature"))
    }

    func testDispatchChallengeUsesSharedBoundedHandlerWithoutProofHeaders() async throws {
        let proof = OfflineAMD()
        var handshake = StoreAMDHandshake(provider: proof)
        let handled = try await handshake.respond(to: response(status: .forbidden, action: " sp "))
        XCTAssertTrue(handled)
        do {
            _ = try await handshake.respond(to: response(status: .internalServerError, action: "SP"))
            XCTFail("Repeated dispatch challenge")
        } catch let error as StoreAMDError { XCTAssertEqual(error.step, .budget) }
        let counts = await proof.snapshot()
        XCTAssertEqual(counts, [1, 0])
    }

    func testVerificationCodeTrimmingAndSixASCIIDigitsOnly() throws {
        XCTAssertEqual(try Authenticator.normalizedVerificationCode(" 123456\n"), "123456")
        XCTAssertEqual(try Authenticator.normalizedVerificationCode(" "), "")
        for invalid in ["12345", "1234567", "12 3456", "١٢٣٤٥٦", "abcdef"] {
            XCTAssertThrowsError(try Authenticator.normalizedVerificationCode(invalid)) { error in
                XCTAssertEqual(error.localizedDescription, "الرمز مرفوض")
            }
        }
        XCTAssertEqual(AuthenticationServiceError.wrapping(AuthenticationError.verificationCodeRejected, stage: .authentication).message, "الرمز مرفوض")
    }

    func testSPDuringAttemptTwoPreservesCodeAndSameAuthenticator() async throws {
        let http = try ScriptedHTTP([
            response(fields: ["failureType": "", "customerMessage": "MZFinance.BadLogin.Configurator_message"]),
            response(status: .forbidden, action: "SP"),
            response(fields: successFields)
        ])
        let proof = OfflineAMD()
        let signer = RecordingSigner()
        let auth = try session(http, proof: proof, signer: signer)
        do {
            _ = try await auth.authenticate(email: "offline@example.invalid", password: "fixture")
            XCTFail("Expected code")
        } catch AuthenticationError.verificationCodeRequired { }
        _ = try await auth.authenticate(email: "offline@example.invalid", password: "fixture", code: " 654321\n")
        let requests = await http.recorded()
        XCTAssertEqual(requests.count, 3)
        let bodies = try requests.map(bodyData)
        XCTAssertEqual(bodies[1], bodies[2])
        let fields = try XCTUnwrap(PropertyListSerialization.propertyList(from: bodies[2], format: nil) as? [String: String])
        XCTAssertEqual(fields["attempt"], "2")
        XCTAssertEqual(fields["password"], "fixture654321")
        XCTAssertEqual(requests[2].headers.first(name: "X-Apple-AMD"), "otp-1")
        let signed = await signer.recordedBodies()
        XCTAssertEqual(signed, bodies)
    }

    func testRejectedCodeIsDistinctFromInitialCodeChallenge() async throws {
        let rejected: [String: Any] = ["failureType": "", "customerMessage": "MZFinance.BadLogin.Configurator_message"]
        let http = try ScriptedHTTP([response(fields: rejected), response(fields: rejected)])
        let auth = try session(http, proof: OfflineAMD(), signer: RecordingSigner())
        do {
            _ = try await auth.authenticate(email: "offline@example.invalid", password: "fixture")
            XCTFail("Expected code")
        } catch AuthenticationError.verificationCodeRequired { }
        do {
            _ = try await auth.authenticate(email: "offline@example.invalid", password: "fixture", code: "123456")
            XCTFail("Expected rejected code")
        } catch let diagnostic as AuthenticationServiceError {
            XCTAssertEqual(diagnostic.httpStatus, 200)
            XCTAssertEqual(diagnostic.loginPhase, .verificationCode)
            XCTAssertEqual(diagnostic.responseMessage, .configurator)
            XCTAssertEqual(diagnostic.failureState, .empty)
            XCTAssertNil(diagnostic.message)
        }
    }

    private actor RefreshingOTP: StoreAMDProviding {
        private var sequence = 0
        func headers() -> [String: String] {
            sequence += 1
            return ["X-Apple-AMD": "fresh-otp-\(sequence)", "X-Apple-AMD-M": "stable-machine"]
        }
        func provision(_ challenge: Data) { }
        func reset() { }
        func synchronize(dateHeader: String?) throws { }
    }

    func testRejectedTwoFactorRetryUsesNewCodeFreshOTPAndStableSessionIdentity() async throws {
        var challenge = try response(fields: ["failureType": "", "customerMessage": "MZFinance.BadLogin.Configurator_message"])
        challenge.headers.add(name: "Set-Cookie", value: "session=fixture-session; Domain=.itunes.apple.com; Path=/; Secure")
        let http = try ScriptedHTTP([challenge,
            response(fields: ["failureType": "5005", "customerMessage": "Private owner address"]),
            response(fields: successFields)])
        let signer = RecordingSigner()
        let auth = try Authenticator(endpoint: XCTUnwrap(URL(string: "https://auth.itunes.apple.com/auth/v1/native")),
            deviceIdentifier: "001122334455", signer: signer, amd: RefreshingOTP(),
            executor: { try await http.execute($0) })
        do {
            _ = try await auth.authenticate(email: "offline@example.invalid", password: "fixture")
            XCTFail("Expected initial code challenge")
        } catch AuthenticationError.verificationCodeRequired { }
        do {
            _ = try await auth.authenticate(email: "offline@example.invalid", password: "fixture", code: "123456")
            XCTFail("Expected explicit Apple rejection")
        } catch let error as AuthenticationServiceError {
            XCTAssertEqual(error.appleCode, "5005")
            XCTAssertEqual(error.loginPhase, .verificationCode)
            XCTAssertEqual(error.responseMessage, .unrecognized)
            XCTAssertNil(error.message)
        }
        _ = try await auth.authenticate(email: "offline@example.invalid", password: "fixture", code: "654321")
        let requests = await http.recorded()
        XCTAssertEqual(requests.count, 3)
        let bodies = try requests.map(bodyData)
        let signed = await signer.recordedBodies()
        XCTAssertEqual(signed, bodies)
        let passwords = ["fixture", "fixture123456", "fixture654321"]
        for index in requests.indices {
            let request = requests[index]
            XCTAssertEqual(request.url, requests[0].url)
            XCTAssertEqual(request.method, .POST)
            XCTAssertEqual(request.headers.first(name: "X-Apple-AMD"), "fresh-otp-\(index + 1)")
            XCTAssertEqual(request.headers.first(name: "X-Apple-AMD-M"), "stable-machine")
            if index > 0 { XCTAssertEqual(request.headers.first(name: "Cookie"), "session=fixture-session") }
            let fields = try XCTUnwrap(PropertyListSerialization.propertyList(from: bodies[index], format: nil) as? [String: String])
            XCTAssertEqual(fields["guid"], "001122334455")
            XCTAssertEqual(fields["password"], passwords[index])
            XCTAssertEqual(fields["attempt"], index == 0 ? "1" : "2")
            XCTAssertEqual(fields["why"], "signIn")
            XCTAssertEqual(fields["rmp"], "0")
        }
    }

    func testTwoFactorHTTPFailuresKeepStatusAndNeverBecomeWrongCode() async throws {
        for status: HTTPResponseStatus in [.forbidden, .tooManyRequests, .internalServerError] {
            let http = try ScriptedHTTP([response(status: status,
                fields: ["failureType": "-5000", "customerMessage": "A private owner name",
                         "dialog": ["explanation": "Do not export any of this"]])])
            let auth = try session(http, proof: OfflineAMD(), signer: RecordingSigner())
            do {
                _ = try await auth.authenticate(email: "offline@example.invalid", password: "fixture", code: "123456")
                XCTFail("Expected failure")
            } catch let error as AuthenticationServiceError {
                XCTAssertEqual(error.httpStatus, Int(status.code))
                XCTAssertEqual(error.appleCode, "-5000")
                XCTAssertEqual(error.loginPhase, .verificationCode)
                XCTAssertEqual(error.responseMessage, .unrecognized)
                XCTAssertNil(error.message)
            }
        }
    }

    func testAppleDomainCookieIsRetainedAcrossTwoFactorContinuation() async throws {
        var challenge = try response(fields: ["failureType": "", "customerMessage": "MZFinance.BadLogin.Configurator_message"])
        challenge.headers.add(name: "Set-Cookie", value: "session=fixture-session; Domain=.itunes.apple.com; Path=/; Secure; HttpOnly")
        let http = try ScriptedHTTP([challenge, response(fields: successFields)])
        let auth = try session(http, proof: OfflineAMD(), signer: RecordingSigner())
        do {
            _ = try await auth.authenticate(email: "offline@example.invalid", password: "fixture")
            XCTFail("Expected code")
        } catch AuthenticationError.verificationCodeRequired { }
        _ = try await auth.authenticate(email: "offline@example.invalid", password: "fixture", code: " 654321\n")
        let requests = await http.recorded()
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(requests[0].headers.first(name: "Cookie"))
        XCTAssertEqual(requests[1].headers.first(name: "Cookie"), "session=fixture-session")
        let fields = try XCTUnwrap(PropertyListSerialization.propertyList(from: bodyData(requests[1]), format: nil) as? [String: String])
        XCTAssertEqual(fields["password"], "fixture654321")
        XCTAssertEqual(fields["attempt"], "2")
    }

    func testLeadingDotCookieDomainRemainsBoundaryScoped() throws {
        for domain in [".itunes.apple.com", ".ITUNES.APPLE.COM", "itunes.apple.com"] {
            let cookies = [Cookie(name: "session", value: "fixture", path: "/", domain: domain, httpOnly: true, secure: true)]
            XCTAssertEqual(cookies.buildCookieHeader(try XCTUnwrap(URL(string: "https://auth.itunes.apple.com/auth/v1/native"))).count, 1)
            for url in ["https://evilitunes.apple.com/", "https://itunes.apple.com.evil.invalid/", "http://auth.itunes.apple.com/"] {
                XCTAssertTrue(cookies.buildCookieHeader(try XCTUnwrap(URL(string: url))).isEmpty)
            }
        }
    }

}
