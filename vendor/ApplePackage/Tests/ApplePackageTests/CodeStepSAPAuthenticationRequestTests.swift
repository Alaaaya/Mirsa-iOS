@testable import ApplePackage
import AsyncHTTPClient
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix
import XCTest

/// Offline only: scripted transport, fake signer, fake device registration. No request reaches Apple.
/// The 2FA code step compared with ipatool (pkg/appstore/appstore_login.go, appstore_native_login.go):
/// - an AMD action on the code step is handled before "code rejected" (ipatool checks X-Apple-AMD-Action first),
///   then the same password+code is re-sent (ipatool's nativeLogin calls legacyLogin again with the same AuthCode);
/// - a pod redirect keeps the payload and the AMD headers, destination used verbatim;
/// - every stop carries a secret-free tag.
/// The class name contains `SAPAuthenticationRequestTests` so the CI filter runs it.
@MainActor
final class CodeStepSAPAuthenticationRequestTests: XCTestCase {
    private enum FakeError: Error { case exhausted, unexpectedBodyChunk }

    private struct Sent: Sendable {
        let url: String
        let cookie: String?
        let amd: String?
        let machine: String?
        let body: Data
    }

    nonisolated private static func bodyData(_ request: HTTPClient.Request) throws -> Data {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let eventLoop = group.next()
        let captured = NIOLockedValueBox(Data())
        guard let body = request.body else { return Data() }
        try body.stream(
            .init { part in
                guard case let .byteBuffer(buffer) = part else { return eventLoop.makeFailedFuture(FakeError.unexpectedBodyChunk) }
                captured.withLockedValue { $0.append(contentsOf: buffer.readableBytesView) }
                return eventLoop.makeSucceededFuture(())
            },
        ).wait()
        return captured.withLockedValue { $0 }
    }

    private actor ScriptedTransport: StoreHTTPTransport {
        private var replies: [HTTPClient.Response]
        private var sent: [Sent] = []
        init(_ replies: [HTTPClient.Response]) { self.replies = replies }
        func execute(_ request: HTTPClient.Request, maxBodySize _: Int) throws -> HTTPClient.Response {
            sent.append(Sent(url: request.url.absoluteString, cookie: request.headers.first(name: "Cookie"),
                             amd: request.headers.first(name: "X-Apple-AMD"), machine: request.headers.first(name: "X-Apple-AMD-M"),
                             body: try CodeStepSAPAuthenticationRequestTests.bodyData(request)))
            guard !replies.isEmpty else { throw FakeError.exhausted }
            return replies.removeFirst()
        }
        func requests() -> [Sent] { sent }
        func remaining() -> Int { replies.count }
    }

    private actor CountingSigner: SAPRequestSigning {
        private var bodies: [Data] = []
        func sign(_ body: Data) -> Data { bodies.append(body); return Data([0x5A, UInt8(bodies.count)]) }
        func signed() -> [Data] { bodies }
    }

    private actor FakeAMD: StoreAMDProviding {
        private var generation = 0
        private var provisions = 0
        private var resets = 0
        private var challenges: [Data] = []
        init(provisioned: Bool = false) { generation = provisioned ? 1 : 0 }
        func headers() -> [String: String] {
            generation == 0 ? [:] : ["X-Apple-AMD": "fixture-otp-\(generation)", "X-Apple-AMD-M": "fixture-machine-\(generation)"]
        }
        func provision(_ challenge: Data) { provisions += 1; generation += 1; challenges.append(challenge) }
        func reset() { resets += 1; generation = 0 }
        func hasProfile() -> Bool { generation > 0 }
        func observeServerDate(_: Date) {}
        func counts() -> [Int] { [provisions, resets] }
    }

    private static let endpoint = URL(string: "https://auth.itunes.apple.com/auth/v1/native?pod=25")!
    private static let pod = "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate"
    private static let device = "001122334455"
    private static let email = "offline.owner@example.invalid"
    private static let password = "fixture-Pa55word!"
    private static let code = "482916"
    private static let configurator = "MZFinance.BadLogin.Configurator_message"
    /// Base64 of the bytes 0x01 0x02 0x03; stands in for Apple's SP challenge.
    private static let challenge = "AQID"
    private static let spHeaders = [("X-Apple-AMD-Action", "SP"), ("X-Apple-AMD-Data", challenge)]

    private static func response(status: HTTPResponseStatus = .ok, headers: [(String, String)] = [],
                                 fields: [String: Any]? = nil) -> HTTPClient.Response {
        var body: ByteBuffer?
        if let fields, let data = try? PropertyListSerialization.data(fromPropertyList: fields, format: .xml, options: 0) {
            body = ByteBuffer(bytes: data)
        }
        return HTTPClient.Response(host: "auth.itunes.apple.com", status: status, version: .http1_1,
                                   headers: HTTPHeaders(headers), body: body)
    }

    private static func codeRequired(headers: [(String, String)] = []) -> HTTPClient.Response {
        response(headers: headers, fields: ["failureType": "", "customerMessage": configurator])
    }

    private static var success: HTTPClient.Response {
        response(headers: [("x-set-apple-store-front", "143441-1,29"), ("pod", "25"),
                           ("Set-Cookie", "mz_at_ssl-1=fixture-at; Path=/; Secure; HttpOnly")], fields: [
            "accountInfo": ["appleId": email, "address": ["firstName": "Off", "lastName": "Line"]],
            "passwordToken": "fixture-password-token", "dsPersonId": "1",
        ])
    }

    private func authenticator(_ transport: ScriptedTransport, amd: FakeAMD, signer: CountingSigner = CountingSigner()) -> Authenticator {
        Authenticator(endpoint: Self.endpoint, deviceIdentifier: Self.device, signer: signer, amd: amd, transport: transport)
    }

    /// Step 1 up to "code required", on a fresh session.
    private func passwordStep(_ session: Authenticator) async throws {
        do { _ = try await session.authenticate(email: Self.email, password: Self.password); XCTFail("code step skipped") }
        catch let error as AuthenticationError { XCTAssertEqual(error, .verificationCodeRequired) }
        let tag = await session.lastFailureTag
        XCTAssertNil(tag, "code required is not a failure")
    }

    private func expectedBody(code: String) throws -> Data {
        try Authenticator.authenticationBody(email: Self.email, password: Self.password, code: code, deviceIdentifier: Self.device)
    }

    // MARK: Valid code with pod redirect

    func testValidCodeFollowsPodRedirectVerbatimWithSameBytesHeadersAndCookies() async throws {
        let redirect = Self.response(status: .found, headers: [
            ("Location", Self.pod), ("Set-Cookie", "itspod=25; Path=/; Domain=.apple.com; Secure"),
        ])
        let transport = ScriptedTransport([
            Self.codeRequired(headers: [("Set-Cookie", "mzsession=fixture-session; Path=/; Domain=.apple.com; Secure; HttpOnly"),
                                        ("Set-Cookie", "hostonly=fixture-host; Path=/; Secure")]),
            redirect, Self.success,
        ])
        let signer = CountingSigner()
        let session = authenticator(transport, amd: FakeAMD(provisioned: true), signer: signer)
        try await passwordStep(session)
        let account = try await session.authenticate(email: Self.email, password: Self.password, code: Self.code)
        XCTAssertEqual(account.firstName, "Off")
        XCTAssertEqual(account.pod, "25")
        let tag = await session.lastFailureTag
        XCTAssertNil(tag)

        let sent = await transport.requests()
        XCTAssertEqual(sent.map(\.url), [Self.endpoint.absoluteString, Self.endpoint.absoluteString, Self.pod])
        // Same password+code bytes at the advertised route and at the pod, attempt "1" both times.
        let stepTwo = try expectedBody(code: Self.code)
        XCTAssertEqual(sent[1].body, stepTwo)
        XCTAssertEqual(sent[2].body, stepTwo)
        let fields = try XCTUnwrap(PropertyListSerialization.propertyList(from: stepTwo, format: nil) as? [String: String])
        XCTAssertEqual(fields["attempt"], "1")
        XCTAssertEqual(fields["password"], Self.password + Self.code)
        XCTAssertEqual(fields["guid"], Self.device)
        // The machine OTP travels to the pod as well (ipatool keeps the headers on a redirect).
        XCTAssertEqual(sent.map(\.amd), ["fixture-otp-1", "fixture-otp-1", "fixture-otp-1"])
        XCTAssertEqual(sent[2].machine, "fixture-machine-1")
        // Cookies from step 1 and from the redirect reach the pod request.
        let podCookies = Set((sent[2].cookie ?? "").components(separatedBy: "; "))
        XCTAssertTrue(podCookies.isSuperset(of: ["mzsession=fixture-session", "itspod=25"]), "\(podCookies)")
        // A host-only cookie from auth.itunes.apple.com stays on that host (as in a Go cookiejar).
        XCTAssertFalse(podCookies.contains("hostonly=fixture-host"), "\(podCookies)")
        XCTAssertTrue((sent[1].cookie ?? "").contains("hostonly=fixture-host"))
        // Every request is signed again over its exact body.
        let signed = await signer.signed()
        XCTAssertEqual(signed, sent.map(\.body))
    }

    // MARK: Code rejected, with tag

    func testConfiguratorMessageAfterCodeIsRejectedOnceWithTag() async throws {
        let transport = ScriptedTransport([Self.codeRequired(), Self.codeRequired(), Self.success])
        let amd = FakeAMD(provisioned: true)
        let session = authenticator(transport, amd: amd)
        try await passwordStep(session)
        do { _ = try await session.authenticate(email: Self.email, password: Self.password, code: Self.code); XCTFail("accepted") }
        catch let error as AuthenticationError { XCTAssertEqual(error, .codeRejected) }
        let lastTag = await session.lastFailureTag
        let tag = try XCTUnwrap(lastTag)
        XCTAssertEqual(tag.text, "[auth:code ft=none msg=MZFinance.BadLogin.Configurator_message http=200 amd=none step=2 stop=classify]")
        let sent = await transport.requests()
        XCTAssertEqual(sent.count, 2, "a rejected code is never re-sent automatically")
        let remaining = await transport.remaining()
        XCTAssertEqual(remaining, 1)
        let counts = await amd.counts()
        XCTAssertEqual(counts, [0, 0])
    }

    func testFailureType5005AfterCodeIsTagged() async throws {
        let transport = ScriptedTransport([Self.codeRequired(),
                                           Self.response(fields: ["failureType": "5005", "customerMessage": "Your code is not correct, fixture."])])
        let session = authenticator(transport, amd: FakeAMD(provisioned: true))
        try await passwordStep(session)
        do { _ = try await session.authenticate(email: Self.email, password: Self.password, code: Self.code); XCTFail("accepted") }
        catch let error as AuthenticationError { XCTAssertEqual(error, .codeRejected) }
        let lastTag = await session.lastFailureTag
        let tag = try XCTUnwrap(lastTag)
        // Human text is never copied into the tag.
        XCTAssertEqual(tag.text, "[auth:code ft=5005 msg=other http=200 amd=none step=2 stop=classify]")
    }

    // MARK: SP on the code step

    func testSPOnCodeStepProvisionsOnceThenResendsSameCodeOnce() async throws {
        let transport = ScriptedTransport([Self.codeRequired(), Self.codeRequired(headers: Self.spHeaders), Self.success])
        let amd = FakeAMD()
        let signer = CountingSigner()
        let session = authenticator(transport, amd: amd, signer: signer)
        try await passwordStep(session)
        let account = try await session.authenticate(email: Self.email, password: Self.password, code: Self.code)
        XCTAssertEqual(account.lastName, "Line")
        let counts = await amd.counts()
        XCTAssertEqual(counts, [1, 0])
        let sent = await transport.requests()
        XCTAssertEqual(sent.count, 3)
        // Before provisioning no proof exists; the one re-send carries the fresh proof and the same code.
        XCTAssertEqual(sent.map(\.amd), [nil, nil, "fixture-otp-1"])
        XCTAssertEqual(sent[1].body, try expectedBody(code: Self.code))
        XCTAssertEqual(sent[2].body, sent[1].body)
        XCTAssertEqual(sent.map(\.url), Array(repeating: Self.endpoint.absoluteString, count: 3))
        let tag = await session.lastFailureTag
        XCTAssertNil(tag)
    }

    func testSecondSPOnCodeStepStopsWithoutSecondProvisionOrThirdCodeSend() async throws {
        let transport = ScriptedTransport([
            Self.codeRequired(), Self.codeRequired(headers: Self.spHeaders), Self.codeRequired(headers: Self.spHeaders), Self.success,
        ])
        let amd = FakeAMD()
        let session = authenticator(transport, amd: amd)
        try await passwordStep(session)
        do { _ = try await session.authenticate(email: Self.email, password: Self.password, code: Self.code); XCTFail("accepted") }
        catch let error as StoreAMDError { XCTAssertEqual(error.stage, .parse) }
        let counts = await amd.counts()
        XCTAssertEqual(counts, [1, 0])
        let sent = await transport.requests()
        XCTAssertEqual(sent.count, 3, "the code is sent at most twice in one step")
        let lastTag = await session.lastFailureTag
        let tag = try XCTUnwrap(lastTag)
        XCTAssertEqual(tag.text, "[auth:amd ft=none msg=MZFinance.BadLogin.Configurator_message http=200 amd=SP step=2 stop=amd-action]")
    }

    func testCredentialRejectionWithSPOnCodeStepIsStillTerminal() async throws {
        let transport = ScriptedTransport([Self.codeRequired(),
                                           Self.response(headers: Self.spHeaders, fields: ["failureType": "-5000", "customerMessage": "MZFinance.BadLogin"]),
                                           Self.success])
        let amd = FakeAMD()
        let session = authenticator(transport, amd: amd)
        try await passwordStep(session)
        do { _ = try await session.authenticate(email: Self.email, password: Self.password, code: Self.code); XCTFail("accepted") }
        catch let error as AuthenticationError { XCTAssertEqual(error, .passwordRejected("-5000")) }
        let counts = await amd.counts()
        XCTAssertEqual(counts, [0, 0])
        let sent = await transport.requests()
        XCTAssertEqual(sent.count, 2)
        let lastTag = await session.lastFailureTag
        let tag = try XCTUnwrap(lastTag)
        XCTAssertEqual(tag.text, "[auth:password ft=-5000 msg=MZFinance.BadLogin http=200 amd=SP step=2 stop=classify]")
    }

    func testOtherFailureTypeWithSPOnPasswordStepStaysTerminal() async throws {
        let transport = ScriptedTransport([Self.response(headers: Self.spHeaders, fields: ["failureType": "2002"]), Self.success])
        let amd = FakeAMD()
        let session = authenticator(transport, amd: amd)
        do { _ = try await session.authenticate(email: Self.email, password: Self.password); XCTFail("accepted") }
        catch is AuthenticationServiceError {}
        let counts = await amd.counts()
        XCTAssertEqual(counts, [0, 0])
        let lastTag = await session.lastFailureTag
        let tag = try XCTUnwrap(lastTag)
        XCTAssertEqual(tag.text, "[auth:rejected ft=2002 msg=none http=200 amd=SP step=1 stop=classify]")
    }

    // MARK: Tag is secret-free

    func testTagNeverContainsSecrets() async throws {
        let echo = "Wrong code \(Self.code) for \(Self.email) token=fixture-password-token \(Self.password)"
        let transport = ScriptedTransport([
            Self.codeRequired(headers: [("Set-Cookie", "mzsession=fixture-session; Path=/; Secure")]),
            Self.response(status: .forbidden, headers: [("X-Apple-AMD-Action", "SP"), ("X-Apple-AMD-Data", "@@not-base64@@")],
                          fields: ["failureType": "fixture-\(Self.code)", "customerMessage": echo,
                                   "passwordToken": "fixture-password-token", "dsPersonId": "987654321"]),
        ])
        let session = authenticator(transport, amd: FakeAMD(provisioned: true))
        try await passwordStep(session)
        do { _ = try await session.authenticate(email: Self.email, password: Self.password, code: Self.code); XCTFail("accepted") }
        catch {}
        let lastTag = await session.lastFailureTag
        let text = try XCTUnwrap(lastTag).text
        for secret in [Self.code, Self.email, Self.password, "fixture-password-token", "987654321", "fixture-session",
                       "fixture-otp", "fixture-machine", "not-base64", Self.challenge, "Wrong code"] {
            XCTAssertFalse(text.contains(secret), "tag leaked \(secret): \(text)")
        }
        XCTAssertTrue(text.hasPrefix("[auth:"))
        XCTAssertTrue(text.contains("ft=other"))
        XCTAssertTrue(text.contains("msg=other"))
        XCTAssertTrue(text.contains("http=403"))
        XCTAssertTrue(text.contains("step=2"))
    }

    func testTagFieldFilters() {
        XCTAssertEqual(AuthenticationTag.keyLike("MZFinance.BadLogin.Configurator_message"), "MZFinance.BadLogin.Configurator_message")
        XCTAssertEqual(AuthenticationTag.keyLike(" AMD-Action::SP "), "AMD-Action::SP")
        XCTAssertEqual(AuthenticationTag.keyLike("AMD-Action:RP"), "AMD-Action:RP")
        XCTAssertEqual(AuthenticationTag.keyLike(""), "none")
        XCTAssertEqual(AuthenticationTag.keyLike(nil), "none")
        XCTAssertEqual(AuthenticationTag.keyLike("MZFinance.BadLogin owner@example.invalid"), "other")
        XCTAssertEqual(AuthenticationTag.keyLike("Your Apple Account has been locked."), "other")
        XCTAssertEqual(AuthenticationTag.failureCode("5005"), "5005")
        XCTAssertEqual(AuthenticationTag.failureCode(NSNumber(value: -5000)), "-5000")
        XCTAssertEqual(AuthenticationTag.failureCode(""), "none")
        XCTAssertEqual(AuthenticationTag.failureCode("482916x"), "other")
        XCTAssertEqual(AuthenticationTag.action(" sp "), "SP")
        XCTAssertEqual(AuthenticationTag.action("XY"), "other")
        XCTAssertEqual(AuthenticationTag.action(nil), "none")
    }
}
