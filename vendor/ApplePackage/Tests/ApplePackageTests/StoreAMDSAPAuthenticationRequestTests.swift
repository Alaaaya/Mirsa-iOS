@testable import ApplePackage
import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1
import XCTest

/// Offline sign-in loop: fake transport, fake signer, fake device-registration provider.
/// The class name contains `SAPAuthenticationRequestTests` so the CI filter runs it.
@MainActor
final class StoreAMDSAPAuthenticationRequestTests: XCTestCase {
    private enum FakeError: Error { case exhausted }

    private struct Sent: Sendable {
        let url: String
        let amd: String?
        let machine: String?
        let body: Data
    }

    private actor ScriptedTransport: StoreHTTPTransport {
        private var replies: [HTTPClient.Response]
        private var sent: [Sent] = []
        init(_ replies: [HTTPClient.Response]) { self.replies = replies }
        func execute(_ request: HTTPClient.Request, maxBodySize _: Int) throws -> HTTPClient.Response {
            sent.append(Sent(url: request.url.absoluteString, amd: request.headers.first(name: "X-Apple-AMD"),
                             machine: request.headers.first(name: "X-Apple-AMD-M"), body: Data()))
            guard !replies.isEmpty else { throw FakeError.exhausted }
            return replies.removeFirst()
        }
        func requests() -> [Sent] { sent }
        func remaining() -> Int { replies.count }
    }

    private actor CountingSigner: SAPRequestSigning {
        private(set) var bodies: [Data] = []
        func sign(_ body: Data) -> Data { bodies.append(body); return Data([0x5A, UInt8(bodies.count)]) }
        func signed() -> [Data] { bodies }
    }

    private actor FakeAMD: StoreAMDProviding {
        private var generation = 0
        private(set) var provisions = 0
        private(set) var resets = 0
        private(set) var dates: [Date] = []
        init(provisioned: Bool = false) { generation = provisioned ? 1 : 0 }
        func headers() -> [String: String] {
            generation == 0 ? [:] : ["X-Apple-AMD": "otp-\(generation)", "X-Apple-AMD-M": "machine-\(generation)"]
        }
        func provision(_: Data) { provisions += 1; generation += 1 }
        func reset() { resets += 1; generation = 0 }
        func hasProfile() -> Bool { generation > 0 }
        func observeServerDate(_ date: Date) { dates.append(date) }
        func counts() -> [Int] { [provisions, resets] }
        func seenDates() -> [Date] { dates }
    }

    private static let endpoint = URL(string: "https://auth.itunes.apple.com/auth/v1/native?pod=25")!
    private static let device = "001122334455"

    private static func response(status: HTTPResponseStatus = .ok, headers: [(String, String)] = [],
                                 fields: [String: Any]? = nil) -> HTTPClient.Response {
        var body: ByteBuffer?
        if let fields, let data = try? PropertyListSerialization.data(fromPropertyList: fields, format: .xml, options: 0) {
            body = ByteBuffer(bytes: data)
        }
        return HTTPClient.Response(host: "auth.itunes.apple.com", status: status, version: .http1_1,
                                   headers: HTTPHeaders(headers), body: body)
    }

    private static func spChallenge(status: HTTPResponseStatus = .ok, header: String = "SP") -> HTTPClient.Response {
        response(status: status, headers: [("X-Apple-AMD-Action", header), ("X-Apple-AMD-Data", "AQID")],
                 fields: ["customerMessage": "AMD-Action::SP"])
    }

    private static var codeRequired: HTTPClient.Response {
        response(fields: ["failureType": "", "customerMessage": "MZFinance.BadLogin.Configurator_message"])
    }

    private static var success: HTTPClient.Response {
        response(headers: [("x-set-apple-store-front", "143441-1,29"), ("Date", "Wed, 11 Nov 2026 22:00:00 GMT")], fields: [
            "accountInfo": ["appleId": "offline@example.invalid", "address": ["firstName": "Off", "lastName": "Line"]],
            "passwordToken": "fixture-token", "dsPersonId": "1",
        ])
    }

    private func authenticator(_ transport: ScriptedTransport, amd: FakeAMD, signer: CountingSigner = CountingSigner()) -> Authenticator {
        Authenticator(endpoint: Self.endpoint, deviceIdentifier: Self.device, signer: signer, amd: amd, transport: transport)
    }

    // (a) SP -> provision -> retry -> success
    func testFullLoopProvisionsThenSignsIn() async throws {
        let transport = ScriptedTransport([Self.spChallenge(), Self.success])
        let amd = FakeAMD()
        let signer = CountingSigner()
        let account = try await authenticator(transport, amd: amd, signer: signer)
            .authenticate(email: "offline@example.invalid", password: "fixture")
        XCTAssertEqual(account.firstName, "Off")
        let counts = await amd.counts()
        XCTAssertEqual(counts, [1, 0])
        let sent = await transport.requests()
        XCTAssertEqual(sent.count, 2)
        XCTAssertNil(sent[0].amd)
        XCTAssertEqual(sent[1].amd, "otp-1")
        XCTAssertEqual(sent[1].machine, "machine-1")
        XCTAssertEqual(sent.map(\.url), [Self.endpoint.absoluteString, Self.endpoint.absoluteString])
        let bodies = await signer.signed()
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies[0], bodies[1])
        let dates = await amd.seenDates()
        XCTAssertEqual(dates.count, 1)
    }

    // (b) SP -> provision -> retry -> code required -> same Authenticator, code -> success
    func testFullLoopWithVerificationCodeOnSameAuthenticator() async throws {
        let transport = ScriptedTransport([Self.spChallenge(), Self.codeRequired, Self.success])
        let amd = FakeAMD()
        let session = authenticator(transport, amd: amd)
        do {
            _ = try await session.authenticate(email: "offline@example.invalid", password: "fixture")
            XCTFail("Expected a verification code request")
        } catch let error as AuthenticationError {
            XCTAssertEqual(error, .verificationCodeRequired)
        }
        let account = try await session.authenticate(email: "offline@example.invalid", password: "fixture", code: " 123456 ")
        XCTAssertEqual(account.lastName, "Line")
        let counts = await amd.counts()
        XCTAssertEqual(counts, [1, 0])
        let sent = await transport.requests()
        XCTAssertEqual(sent.map(\.amd), [nil, "otp-1", "otp-1"])
        let remaining = await transport.remaining()
        XCTAssertEqual(remaining, 0)
    }

    func testSPOnNonOKStatusIsHandled() async throws {
        let transport = ScriptedTransport([Self.spChallenge(status: .forbidden, header: "  sp\t"), Self.success])
        let amd = FakeAMD()
        _ = try await authenticator(transport, amd: amd).authenticate(email: "offline@example.invalid", password: "fixture")
        let counts = await amd.counts()
        XCTAssertEqual(counts, [1, 0])
    }

    func testWrongCodeIsCodeRejected() async throws {
        let transport = ScriptedTransport([Self.codeRequired])
        let session = authenticator(transport, amd: FakeAMD(provisioned: true))
        do {
            _ = try await session.authenticate(email: "offline@example.invalid", password: "fixture", code: "000000")
            XCTFail("Expected rejection")
        } catch let error as AuthenticationError {
            XCTAssertEqual(error, .codeRejected)
        }
    }

    func testCodeMustBeSixASCIIDigitsBeforeSending() async throws {
        for bad in ["12345", "1234567", "12a456", "١٢٣٤٥٦", "123 456"] {
            let transport = ScriptedTransport([Self.success])
            do {
                _ = try await authenticator(transport, amd: FakeAMD()).authenticate(email: "offline@example.invalid", password: "fixture", code: bad)
                XCTFail("Accepted \(bad)")
            } catch let error as AuthenticationError {
                XCTAssertEqual(error, .invalidVerificationCode)
            }
            let sent = await transport.requests()
            XCTAssertTrue(sent.isEmpty)
        }
        XCTAssertEqual(try Authenticator.validatedCode("\t654321\n"), "654321")
        XCTAssertEqual(try Authenticator.validatedCode(""), "")
    }

    func testUnresolvedAMDMessageIsLocalizedDeviceRegistrationError() async throws {
        let transport = ScriptedTransport([Self.response(status: .forbidden, fields: [
            "failureType": "", "dialog": ["explanation": "AMD-Action:: "],
        ])])
        do {
            _ = try await authenticator(transport, amd: FakeAMD()).authenticate(email: "offline@example.invalid", password: "fixture")
            XCTFail("Expected device registration error")
        } catch let error as StoreAMDError {
            XCTAssertEqual(error.stage, .parse)
            XCTAssertFalse(error.localizedDescription.contains("AMD-Action"))
        }
        XCTAssertTrue(Authenticator.isUnresolvedDeviceRegistration(["dialog": ["explanation": " AMD-Action::XY"]]))
        XCTAssertFalse(Authenticator.isUnresolvedDeviceRegistration(["customerMessage": "Your account is disabled."]))
    }

    // Parser

    func testActionParserHeaderCaseAndWhitespace() throws {
        XCTAssertEqual(try StoreAMDAction.parse(fields: [:], actionHeader: " sp\t", challenge: "AQ=="), StoreAMDAction.provision(Data([1])))
        XCTAssertEqual(try StoreAMDAction.parse(fields: [:], actionHeader: "\nrP ", challenge: nil), StoreAMDAction.reset)
        XCTAssertNil(try StoreAMDAction.parse(fields: [:], actionHeader: "   ", challenge: nil))
        XCTAssertNil(try StoreAMDAction.parse(fields: ["customerMessage": "Something else"], actionHeader: nil, challenge: nil))
        XCTAssertThrowsError(try StoreAMDAction.parse(fields: [:], actionHeader: "XX", challenge: "AQ=="))
    }

    func testActionParserMessageSingleAndDoubleColon() throws {
        XCTAssertEqual(try StoreAMDAction.parse(fields: ["customerMessage": "AMD-Action::SP"], actionHeader: nil, challenge: "AQ=="), StoreAMDAction.provision(Data([1])))
        XCTAssertEqual(try StoreAMDAction.parse(fields: ["customerMessage": "AMD-Action:SP"], actionHeader: nil, challenge: "AQ=="), StoreAMDAction.provision(Data([1])))
        XCTAssertEqual(try StoreAMDAction.parse(fields: ["customerMessage": "  AMD-Action: rp "], actionHeader: nil, challenge: nil), StoreAMDAction.reset)
        XCTAssertEqual(try StoreAMDAction.parse(fields: ["customerMessage": "AMD-Action::SP"], actionHeader: "", challenge: "AQ=="), StoreAMDAction.provision(Data([1])))
        XCTAssertThrowsError(try StoreAMDAction.parse(fields: ["customerMessage": "AMD-Action"], actionHeader: nil, challenge: nil))
        XCTAssertThrowsError(try StoreAMDAction.parse(fields: ["customerMessage": "AMD-Action::SP"], actionHeader: nil, challenge: nil))
    }

    func testActionFieldsFromPlistOrJSONOnAnyStatus() async throws {
        let json = Data(#"{"customerMessage":"AMD-Action::RP"}"#.utf8)
        XCTAssertEqual(StoreAMDAction.fields(from: json)["customerMessage"] as? String, "AMD-Action::RP")
        let amd = FakeAMD(provisioned: true)
        var handshake = StoreAMDHandshake(provider: amd)
        let handled = try await handshake.respond(to: Self.response(status: .internalServerError, headers: [("X-Apple-AMD-Action", "RP")]))
        XCTAssertTrue(handled)
        let counts = await amd.counts()
        XCTAssertEqual(counts, [0, 1])
    }

    func testRPWithoutProfileIsIgnoredOnceAndNotCounted() async throws {
        let amd = FakeAMD()
        var handshake = StoreAMDHandshake(provider: amd)
        let first = try await handshake.respond(fields: [:], action: "RP", challenge: nil)
        XCTAssertTrue(first)
        var counts = await amd.counts()
        XCTAssertEqual(counts, [0, 0])
        do { _ = try await handshake.respond(fields: [:], action: "RP", challenge: nil); XCTFail("Unbounded RP") }
        catch let error as StoreAMDError { XCTAssertEqual(error.stage, .parse) }
        // The ignored RP did not consume the real reset budget.
        _ = try await handshake.respond(fields: [:], action: "SP", challenge: "AQ==")
        _ = try await handshake.respond(fields: [:], action: "RP", challenge: nil)
        counts = await amd.counts()
        XCTAssertEqual(counts, [1, 1])
    }

    // Header path restriction

    func testAMDHeadersOnlyOnNativeAuthAndStorePaths() throws {
        let amd = ["X-Apple-AMD": "otp", "X-Apple-AMD-M": "machine"]
        for allowed in [
            "https://auth.itunes.apple.com/auth/v1/native", "https://auth.itunes.apple.com/auth/v1/native/",
            "https://auth.itunes.apple.com/auth/v1/native/fast", "https://auth.itunes.apple.com/auth/v1/native/fast/?guid=1",
            "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/buyProduct",
            "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct?guid=1",
            "https://downloaddispatch.itunes.apple.com/r/redownload", "https://downloaddispatch.itunes.apple.com/up/updateProduct",
        ] {
            let url = try XCTUnwrap(URL(string: allowed))
            XCTAssertTrue(StoreAMDHeaderPolicy.allows(url), allowed)
            XCTAssertEqual(try StoreAMDHeaderPolicy.headers(amd, for: url).map { $0.0 }, ["X-Apple-AMD", "X-Apple-AMD-M"])
        }
        for denied in [
            "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/",
            "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate",
            "https://auth.itunes.apple.com/auth/v1/other", "https://auth.itunes.apple.com/auth/v1/native/fastx",
            "http://auth.itunes.apple.com/auth/v1/native", "https://evil.example/auth/v1/native",
            "https://auth.itunes.apple.com:8443/auth/v1/native", "https://init.itunes.apple.com/bag.xml",
        ] {
            let url = try XCTUnwrap(URL(string: denied))
            XCTAssertFalse(StoreAMDHeaderPolicy.allows(url), denied)
            XCTAssertTrue(try StoreAMDHeaderPolicy.headers(amd, for: url).isEmpty)
        }
        XCTAssertThrowsError(try StoreAMDHeaderPolicy.headers(["X-Apple-AMD": "a\r\nb"], for: Self.endpoint))
    }

    func testLegacyRedirectStripsAMDHeaders() async throws {
        let signer = CountingSigner()
        let request = try await Authenticator.makeRequest(
            endpoint: XCTUnwrap(URL(string: "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/")),
            email: "offline@example.invalid", password: "fixture", code: "", cookies: [], deviceIdentifier: Self.device,
            sapSigner: signer, amdHeaders: ["X-Apple-AMD": "otp", "X-Apple-AMD-M": "machine"])
        XCTAssertNil(request.headers.first(name: "X-Apple-AMD"))
        XCTAssertNil(request.headers.first(name: "X-Apple-AMD-M"))
        XCTAssertNotNil(request.headers.first(name: "X-Apple-ActionSignature"))
    }

    // Clock skew

    func testServerDateOffsetIsBounded() throws {
        let server = try XCTUnwrap(StoreAMDClock.parse("Wed, 11 Nov 2026 22:00:00 GMT"))
        let local = server.addingTimeInterval(-120)
        XCTAssertEqual(StoreAMDClock.offset(server: server, local: local), 120)
        XCTAssertNil(StoreAMDClock.offset(server: server, local: server.addingTimeInterval(-StoreAMDClock.maximumOffset - 1)))
        XCTAssertEqual(try StoreAMDClock.seconds(now: local, offset: 120), UInt32(server.timeIntervalSince1970))
        XCTAssertNil(StoreAMDClock.parse("not a date"))
    }

    func testErrorStageIsSecretFree() {
        XCTAssertEqual(StoreAMDError(.http(503)).diagnostic, "amd:http-503")
        XCTAssertEqual(StoreAMDError(.keychain(-25300)).diagnostic, "amd:keychain--25300")
        for stage: StoreAMDError.Stage in [.begin, .request, .finish, .export, .headers, .parse] {
            XCTAssertTrue(StoreAMDError(stage).localizedDescription.hasPrefix("Device registration didn't finish"))
        }
    }
}
