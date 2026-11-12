@testable import ApplePackage
import AsyncHTTPClient
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix
import XCTest

/// Offline only: scripted transport, fake signer, fake device registration. No request reaches Apple.
/// Apple's 5020 ("password entered incorrectly more than once") and every other credential rejection
/// must end the call after exactly one request, even when the response also asks for an AMD action.
/// The class name contains `SAPAuthenticationRequestTests` so the CI filter runs it.
@MainActor
final class PasswordRejectionSAPAuthenticationRequestTests: XCTestCase {
    private enum FakeError: Error { case exhausted, unexpectedBodyChunk }

    private struct Sent: Sendable {
        let url: String
        let cookie: String?
        let amd: String?
        let body: Data
    }

    /// Reads the exact bytes AsyncHTTPClient would put on the wire, without opening a socket.
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
                             amd: request.headers.first(name: "X-Apple-AMD"), body: try PasswordRejectionSAPAuthenticationRequestTests.bodyData(request)))
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
        init(provisioned: Bool = false) { generation = provisioned ? 1 : 0 }
        func headers() -> [String: String] {
            generation == 0 ? [:] : ["X-Apple-AMD": "otp-\(generation)", "X-Apple-AMD-M": "machine-\(generation)"]
        }
        func provision(_: Data) { provisions += 1; generation += 1 }
        func reset() { resets += 1; generation = 0 }
        func hasProfile() -> Bool { generation > 0 }
        func observeServerDate(_: Date) {}
        func counts() -> [Int] { [provisions, resets] }
    }

    private static let endpoint = URL(string: "https://auth.itunes.apple.com/auth/v1/native?pod=25")!
    private static let device = "001122334455"
    private static let email = "offline@example.invalid"
    private static let lockMessage = "Your password was entered incorrectly more than once. Your Apple Account has been locked for security."

    private static func response(status: HTTPResponseStatus = .ok, headers: [(String, String)] = [],
                                 fields: [String: Any]? = nil) -> HTTPClient.Response {
        var body: ByteBuffer?
        if let fields, let data = try? PropertyListSerialization.data(fromPropertyList: fields, format: .xml, options: 0) {
            body = ByteBuffer(bytes: data)
        }
        return HTTPClient.Response(host: "auth.itunes.apple.com", status: status, version: .http1_1,
                                   headers: HTTPHeaders(headers), body: body)
    }

    private static let spHeaders = [("X-Apple-AMD-Action", "SP"), ("X-Apple-AMD-Data", "AQID")]

    private static func rejection(_ failureType: Any, status: HTTPResponseStatus = .ok, headers: [(String, String)] = [],
                                  message: String = lockMessage) -> HTTPClient.Response {
        response(status: status, headers: headers, fields: [
            "failureType": failureType, "customerMessage": message, "dialog": ["explanation": message],
        ])
    }

    private static var success: HTTPClient.Response {
        response(headers: [("x-set-apple-store-front", "143441-1,29")], fields: [
            "accountInfo": ["appleId": email, "address": ["firstName": "Off", "lastName": "Line"]],
            "passwordToken": "fixture-token", "dsPersonId": "1",
        ])
    }

    private static func codeRequired(headers: [(String, String)] = []) -> HTTPClient.Response {
        response(headers: headers, fields: ["failureType": "", "customerMessage": "MZFinance.BadLogin.Configurator_message"])
    }

    private func authenticator(_ transport: ScriptedTransport, amd: FakeAMD = FakeAMD(),
                               signer: CountingSigner = CountingSigner()) -> Authenticator {
        Authenticator(endpoint: Self.endpoint, deviceIdentifier: Self.device, signer: signer, amd: amd, transport: transport)
    }

    private func expectPasswordRejected(_ code: String, _ body: () async throws -> Void,
                                        file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("Credential rejection was not reported", file: file, line: line)
        } catch let error as AuthenticationError {
            XCTAssertEqual(error, .passwordRejected(code), file: file, line: line)
            XCTAssertNotEqual(error, .codeRejected, file: file, line: line)
            XCTAssertNotEqual(error, .verificationCodeRequired, file: file, line: line)
        } catch {
            XCTFail("Unexpected error \(type(of: error))", file: file, line: line)
        }
    }

    // MARK: 5020 is sent once and never again

    func test5020WithoutAMDHeaderSendsExactlyOneRequest() async throws {
        let transport = ScriptedTransport([Self.rejection("5020"), Self.success])
        let amd = FakeAMD()
        await expectPasswordRejected("5020") {
            _ = try await self.authenticator(transport, amd: amd).authenticate(email: Self.email, password: "fixture")
        }
        let sent = await transport.requests()
        XCTAssertEqual(sent.count, 1)
        let remaining = await transport.remaining()
        XCTAssertEqual(remaining, 1)
        let counts = await amd.counts()
        XCTAssertEqual(counts, [0, 0])
    }

    func test5020WithAMDActionHeaderIsNeverRetriedOrProvisioned() async throws {
        let variants: [HTTPClient.Response] = [
            Self.rejection("5020", headers: Self.spHeaders),
            Self.rejection("5020", headers: [("X-Apple-AMD-Action", "RP")]),
            Self.rejection("5020", status: .forbidden, headers: Self.spHeaders),
            Self.rejection(5020, headers: Self.spHeaders),
            Self.rejection("5020", headers: Self.spHeaders, message: "AMD-Action::SP"),
        ]
        for reply in variants {
            let transport = ScriptedTransport([reply, Self.success, Self.success])
            let amd = FakeAMD(provisioned: true)
            await expectPasswordRejected("5020") {
                _ = try await self.authenticator(transport, amd: amd).authenticate(email: Self.email, password: "fixture")
            }
            let sent = await transport.requests()
            XCTAssertEqual(sent.count, 1)
            let counts = await amd.counts()
            XCTAssertEqual(counts, [0, 0])
        }
    }

    func testOtherCredentialRejectionsStopImmediately() async throws {
        let cases: [(HTTPClient.Response, String)] = [
            (Self.rejection("-5000", headers: Self.spHeaders, message: "MZFinance.BadLogin"), "-5000"),
            (Self.rejection("", headers: Self.spHeaders, message: "MZFinance.BadLogin.Incorrect_message"), "BadLogin"),
            (Self.rejection("", message: "MZFinance.BadLogin"), "BadLogin"),
        ]
        for (reply, code) in cases {
            let transport = ScriptedTransport([reply, Self.success])
            let amd = FakeAMD()
            await expectPasswordRejected(code) {
                _ = try await self.authenticator(transport, amd: amd).authenticate(email: Self.email, password: "fixture")
            }
            let sent = await transport.requests()
            XCTAssertEqual(sent.count, 1)
            let counts = await amd.counts()
            XCTAssertEqual(counts, [0, 0])
        }
        XCTAssertNil(Authenticator.passwordRejection(["failureType": "", "customerMessage": "MZFinance.BadLogin.Configurator_message"]))
        XCTAssertNil(Authenticator.passwordRejection(["customerMessage": "AMD-Action::SP"]))
    }

    func testAnyOtherFailureTypeEndsBeforeAMDAndDoesNotResendPassword() async throws {
        let transport = ScriptedTransport([Self.rejection("2002", headers: Self.spHeaders, message: "Something else"), Self.success])
        let amd = FakeAMD()
        do {
            _ = try await authenticator(transport, amd: amd).authenticate(email: Self.email, password: "fixture")
            XCTFail("Rejected response accepted")
        } catch let diagnostic as AuthenticationServiceError {
            XCTAssertEqual(diagnostic.appleCode, "2002")
        }
        let sent = await transport.requests()
        XCTAssertEqual(sent.count, 1)
        let counts = await amd.counts()
        XCTAssertEqual(counts, [0, 0])
    }

    func test5020OnCodeStepIsOneRequestForThatStep() async throws {
        let transport = ScriptedTransport([Self.codeRequired(), Self.rejection("5020", headers: Self.spHeaders), Self.success])
        let session = authenticator(transport, amd: FakeAMD(provisioned: true))
        do { _ = try await session.authenticate(email: Self.email, password: "fixture"); XCTFail("code step skipped") }
        catch let error as AuthenticationError { XCTAssertEqual(error, .verificationCodeRequired) }
        await expectPasswordRejected("5020") {
            _ = try await session.authenticate(email: Self.email, password: "fixture", code: "123456")
        }
        let sent = await transport.requests()
        XCTAssertEqual(sent.count, 2)
        let remaining = await transport.remaining()
        XCTAssertEqual(remaining, 1)
    }

    func testAMDResendsAreBoundedBeforeProvisioning() async throws {
        let rp = Self.response(headers: [("X-Apple-AMD-Action", "RP")], fields: ["customerMessage": "AMD-Action:RP"])
        let sp = Self.response(headers: Self.spHeaders, fields: ["customerMessage": "AMD-Action::SP"])
        let transport = ScriptedTransport([sp, rp, sp, Self.success])
        let amd = FakeAMD()
        do {
            _ = try await authenticator(transport, amd: amd).authenticate(email: Self.email, password: "fixture")
            XCTFail("Unbounded AMD resend")
        } catch let error as StoreAMDError {
            XCTAssertEqual(error.stage, .parse)
        }
        let sent = await transport.requests()
        XCTAssertEqual(sent.count, 1 + Authenticator.maximumAMDResends)
        let counts = await amd.counts()
        // The third action is refused before a second provisioning round trip.
        XCTAssertEqual(counts, [1, 1])
    }

    // MARK: Body bytes, GUID, cookies and routing across the two steps

    func testPasswordStepBodyIsByteExact() async throws {
        let transport = ScriptedTransport([Self.success])
        let signer = CountingSigner()
        _ = try await authenticator(transport, signer: signer).authenticate(email: Self.email, password: "test<&password")
        let expected = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>appleId</key>
        \t<string>offline@example.invalid</string>
        \t<key>attempt</key>
        \t<string>1</string>
        \t<key>guid</key>
        \t<string>001122334455</string>
        \t<key>password</key>
        \t<string>test&lt;&amp;password</string>
        \t<key>rmp</key>
        \t<string>0</string>
        \t<key>why</key>
        \t<string>signIn</string>
        </dict>
        </plist>

        """
        let sent = await transport.requests()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(String(decoding: sent[0].body, as: UTF8.self), expected)
        XCTAssertEqual(sent[0].body, Data(expected.utf8))
        let signed = await signer.signed()
        XCTAssertEqual(signed, [sent[0].body])
    }

    func testCodeStepBodyDiffersOnlyByAppendedCodeAndKeepsGuidCookiesAndRoute() async throws {
        // Leading/trailing spaces, a tab, a combining accent (NFD) and non-Latin text: all must be sent verbatim.
        let password = " pa\u{0301}ss\tكلمة "
        let redirect = Self.response(status: .found, headers: [
            ("Location", "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate"),
            ("Set-Cookie", "mzroute=pod25; Path=/; Secure; HttpOnly"),
        ])
        let code = Self.codeRequired(headers: [("Set-Cookie", "mzsession=fixture-session; Path=/; Secure; HttpOnly")])
        let transport = ScriptedTransport([redirect, code, Self.success])
        let signer = CountingSigner()
        let session = authenticator(transport, amd: FakeAMD(provisioned: true), signer: signer)
        do { _ = try await session.authenticate(email: Self.email, password: password); XCTFail("code step skipped") }
        catch let error as AuthenticationError { XCTAssertEqual(error, .verificationCodeRequired) }
        let account = try await session.authenticate(email: Self.email, password: password, code: "654321")
        XCTAssertEqual(account.firstName, "Off")

        let sent = await transport.requests()
        XCTAssertEqual(sent.count, 3)
        // Step 2 starts again at the advertised route, like a fresh ipatool login with the same cookie jar.
        XCTAssertEqual(sent[0].url, Self.endpoint.absoluteString)
        XCTAssertEqual(sent[1].url, "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/")
        XCTAssertEqual(sent[2].url, Self.endpoint.absoluteString)
        XCTAssertFalse(sent[2].url.contains("guid="))
        // Cookies set during step 1 reach step 2.
        let stepTwoCookies = Set((sent[2].cookie ?? "").components(separatedBy: "; "))
        XCTAssertEqual(stepTwoCookies, ["mzroute=pod25", "mzsession=fixture-session"])

        let first = try XCTUnwrap(PropertyListSerialization.propertyList(from: sent[0].body, format: nil) as? [String: String])
        let second = try XCTUnwrap(PropertyListSerialization.propertyList(from: sent[2].body, format: nil) as? [String: String])
        XCTAssertEqual(first, ["appleId": Self.email, "attempt": "1", "guid": Self.device, "password": password, "rmp": "0", "why": "signIn"])
        XCTAssertEqual(second, ["appleId": Self.email, "attempt": "1", "guid": Self.device, "password": password + "654321", "rmp": "0", "why": "signIn"])
        // Unicode scalars are untouched (no NFC/NFKC, no trimming).
        XCTAssertEqual(Array(try XCTUnwrap(first["password"]).unicodeScalars), Array(password.unicodeScalars))
        XCTAssertEqual(Array(try XCTUnwrap(second["password"]).utf8), Array((password + "654321").utf8))
        // Byte level: step 2 is step 1 with the six digits appended inside the password string, nothing else.
        let marker = Data("</string>\n\t<key>rmp</key>".utf8)
        let range = try XCTUnwrap(sent[0].body.range(of: marker))
        var expectedSecond = sent[0].body
        expectedSecond.replaceSubrange(range.lowerBound ..< range.lowerBound, with: Data("654321".utf8))
        XCTAssertEqual(sent[2].body, expectedSecond)
        XCTAssertTrue(sent[0].body.range(of: Data(password.utf8)) != nil)
        // Redirect inside step 1 re-signed the same bytes.
        XCTAssertEqual(sent[0].body, sent[1].body)
        let signed = await signer.signed()
        XCTAssertEqual(signed, sent.map(\.body))
    }
}
