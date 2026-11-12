//
//  Authenticate.swift
//  ApplePackage
//
//  Created by QAQ on 2023/10/4.
//

import AsyncHTTPClient
import Foundation
import NIOHTTP1

public actor Authenticator {
    private enum LoginResponse {
        case success(Account)
        case codeRequired
        case redirect(URL)
        case failure(AuthenticationServiceError)
    }

    private let signer: any SAPRequestSigning
    private let deviceIdentifier: String
    private let amd: any StoreAMDProviding
    private let executor: (@Sendable (HTTPClient.Request) async throws -> HTTPClient.Response)?
    private var endpoint: URL
    private var cookies: [Cookie]
    private var storeFront = ""
    private var pod: String?
    private var authenticating = false
    private var terminalRejection: AuthenticationServiceError?
    private var submittedCodes: Set<String> = []

    /// A fresh SAP exchange is mandatory. Reuse this instance when supplying a verification code.
    public init(cookies: [Cookie] = []) async throws {
        executor = nil
        deviceIdentifier = Configuration.deviceIdentifier
        amd = StoreAMDProof(deviceIdentifier: Configuration.deviceIdentifier)
        let bag: Bag.BagOutput
        do { bag = try await Bag.fetchBag(redirectConfiguration: .disallow) }
        catch { throw AuthenticationServiceError.wrapping(error, stage: .bag) }
        try bag.requireSupportedAuthentication()
        endpoint = try Self.createInitialRequestEndpoint(baseURL: bag.authEndpoint, deviceIdentifier: deviceIdentifier)
        do { signer = try await SAPSigner.connect() }
        catch { throw AuthenticationServiceError.wrapping(error, stage: .sapValidation) }
        self.cookies = cookies
    }

    // Offline tests exercise the same complete login loop, without SAP or network access.
    init(endpoint: URL, deviceIdentifier: String, signer: any SAPRequestSigning, amd: any StoreAMDProviding,
         executor: @escaping @Sendable (HTTPClient.Request) async throws -> HTTPClient.Response) throws {
        self.endpoint = try Self.approvedEndpoint(endpoint)
        self.deviceIdentifier = deviceIdentifier
        self.signer = signer
        self.amd = amd
        self.executor = executor
        cookies = []
    }

    public static func authenticate(email: String, password: String, code: String = "", cookies: [Cookie] = []) async throws -> Account {
        let session = try await Authenticator(cookies: cookies)
        return try await session.authenticate(email: email, password: password, code: code)
    }

    public func authenticate(email: String, password: String, code: String = "") async throws -> Account {
        let code = try Self.normalizedVerificationCode(code)
        if let terminalRejection { throw terminalRejection }
        guard !authenticating else { try ensureFailed("An authentication request is already in progress.") }
        if !code.isEmpty {
            guard submittedCodes.insert(code).inserted else { throw AuthenticationError.verificationCodeRejected }
        }
        authenticating = true
        defer { authenticating = false }
        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }
        var redirects = 0
        var handshake = StoreAMDHandshake(provider: amd)
        // Freeze the serialized password body for this attempt (including 2FA).
        // Every retry signs these exact bytes; only machine OTP headers refresh.
        let signedBody = try Self.authenticationBody(email: email, password: password, code: code, deviceIdentifier: deviceIdentifier)
        for _ in 0 ..< 8 {
            let request = try await Self.makeRequest(
                endpoint: endpoint, email: email, password: password, code: code, cookies: cookies, deviceIdentifier: deviceIdentifier,
                sapSigner: signer, serializedBody: signedBody, amdHeaders: try await amd.headers(),
            )
            let accumulator = ResponseAccumulator(request: request, maxBodySize: 2 * 1024 * 1024)
            let response: HTTPClient.Response
            do {
                if let executor { response = try await executor(request) }
                else { response = try await client.execute(request: request, delegate: accumulator).futureResult.get() }
            }
            catch { throw AuthenticationServiceError.wrapping(error, stage: .authentication, transport: true) }
            let data = response.body.map { Data($0.readableBytesView) } ?? Data()
            let fields = (try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
                ?? (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let action = response.headers.first(name: "X-Apple-AMD-Action")
            // Apple can challenge on any status, before redirects or login rejection.
            if let date = response.headers.first(name: "Date") {
                try await amd.synchronize(dateHeader: date)
            } else if try StoreAMDAction.parse(fields: fields, actionHeader: action,
                                               challenge: response.headers.first(name: "X-Apple-AMD-Data")) != nil {
                throw StoreAMDError(.clock)
            }
            if try await handshake.respond(fields: fields, action: action,
                                           challenge: response.headers.first(name: "X-Apple-AMD-Data")) {
                cookies.mergeCookies(response.cookies)
                continue
            }
            let result = try parseResponse(response, email: email, password: password, code: code)
            switch result {
            case let .success(account): return account
            case let .redirect(url):
                guard redirects < 3 else { try ensureFailed("Authentication redirect limit exceeded.") }
                guard let resolved = URL(string: url.relativeString, relativeTo: endpoint)?.absoluteURL else {
                    try ensureFailed(Strings.failedToRetrieveRedirect)
                }
                endpoint = try Self.approvedEndpoint(Bag.normalizedAuthEndpoint(from: resolved.absoluteString) ?? resolved)
                redirects += 1
            case .codeRequired: throw AuthenticationError.verificationCodeRequired
            case let .failure(diagnostic):
                // Never retry this session after Apple's repeated-password rejection.
                // Preserve the diagnostic without asserting that the account is locked.
                if diagnostic.appleCode == "5020" { terminalRejection = diagnostic }
                throw diagnostic
            }
        }
        try ensureFailed("Authentication redirect limit exceeded.")
    }

    public static func rotatePasswordToken(for account: inout Account) async throws {
        account = try await authenticate(email: account.email, password: account.password, cookies: account.cookie)
    }

    static func approvedEndpoint(_ url: URL) throws -> URL {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), host == "apple.com" || host.hasSuffix(".apple.com"),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443
        else { try ensureFailed("Authentication requires an Apple HTTPS endpoint.") }
        return url
    }

    static func createInitialRequestEndpoint(baseURL: URL, deviceIdentifier: String) throws -> URL {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            try ensureFailed("\(Strings.invalidAuthEndpoint): \(baseURL)")
        }
        // Native auth consumes GUID in the signed plist. Keep the advertised
        // URL verbatim, including its query, just like the on-device protocol.
        // Only the legacy MZFinance service needs the GUID query suffix.
        if comps.host?.lowercased() == "auth.itunes.apple.com" {
            return try approvedEndpoint(baseURL)
        }
        var query = comps.queryItems ?? []
        query.removeAll { $0.name == "guid" }
        query.append(URLQueryItem(name: "guid", value: deviceIdentifier))
        comps.queryItems = query
        return try approvedEndpoint(comps.url.get())
    }

    static func authenticationBody(email: String, password: String, code: String, deviceIdentifier: String) throws -> Data {
        let code = try normalizedVerificationCode(code)
        return try PropertyListSerialization.data(fromPropertyList: [
            "appleId": email, "attempt": code.isEmpty ? "1" : "2", "guid": deviceIdentifier,
            "password": password + code, "rmp": "0", "why": "signIn",
        ], format: .xml, options: 0)
    }

    static func makeRequest(
        endpoint: URL, email: String, password: String, code: String, cookies: [Cookie], deviceIdentifier: String,
        sapSigner: any SAPRequestSigning, serializedBody: Data? = nil, amdHeaders: [String: String] = [:],
    ) async throws -> HTTPClient.Request {
        let data = try serializedBody ?? authenticationBody(email: email, password: password, code: code, deviceIdentifier: deviceIdentifier)
        var headers: [(String, String)] = [("User-Agent", Configuration.userAgent), ("Content-Type", "application/x-apple-plist")]
        for item in cookies.buildCookieHeader(endpoint) {
            headers.append(item)
        }
        _ = try approvedEndpoint(endpoint)
        let signature: Data
        do { signature = try await sapSigner.sign(data) }
        catch { throw AuthenticationServiceError.wrapping(error, stage: .signing) }
        headers.append(("X-Apple-ActionSignature", signature.base64EncodedString()))
        try StoreAMDHeaderScope.append(amdHeaders, to: &headers, url: endpoint)
        APLogger.logRequest(method: "POST", url: endpoint.absoluteString, headers: headers)
        return try .init(url: endpoint.absoluteString, method: .POST, headers: .init(headers), body: .data(data))
    }

    static func normalizedVerificationCode(_ input: String) throws -> String {
        let code = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.isEmpty || (code.utf8.count == 6 && code.utf8.allSatisfy({ (48...57).contains($0) })) else {
            throw AuthenticationError.verificationCodeRejected
        }
        return code
    }

    static func requiresVerificationCode(_ fields: [String: Any], submittedCode: Bool) -> Bool {
        !submittedCode && (fields["failureType"] as? String) == ""
            && (fields["customerMessage"] as? String) == "MZFinance.BadLogin.Configurator_message"
    }

    static func rejection(_ fields: [String: Any], status: Int, secrets: [String],
                          submittedCode: Bool = false) -> AuthenticationServiceError {
        let rawMessage = fields["customerMessage"]
        let message: AuthenticationServiceError.ResponseMessage
        if rawMessage == nil { message = .missing }
        else if let text = rawMessage as? String {
            if text.isEmpty { message = .empty }
            else {
                // Metadata stays finite; the separately redacted display message is not metadata.
                switch text.trimmingCharacters(in: .whitespacesAndNewlines) {
                case "MZFinance.BadLogin.Configurator_message": message = .configurator
                case "AMD-Action::SP": message = .amdSP
                case "AMD-Action::RP": message = .amdRP
                default: message = .unrecognized
                }
            }
        } else { message = .unrecognized }
        let code = fields["failureType"]
        let safeCode = AuthenticationServiceError(stage: .authentication, appleCode: code).appleCode
        let failure: AuthenticationServiceError.FailureState
        if code == nil { failure = .missing }
        else if (code as? String) == "" { failure = .empty }
        else if safeCode != nil { failure = .numeric }
        else { failure = .unrecognized }
        // Display only the bounded, redacted customerMessage, never the body or dialog.
        // Malformed device challenge payloads remain private rather than looking
        // like a password/code error; the handshake reports its own safe step.
        let displayMessage = (rawMessage as? String).flatMap { text -> String? in
            text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("AMD-Action") ? nil : text
        }
        return .init(stage: .authentication, httpStatus: status, appleCode: safeCode,
                     message: displayMessage, secrets: secrets,
                     loginPhase: submittedCode ? .verificationCode : .password,
                     responseMessage: message, failureState: failure)
    }

    private func parseResponse(_ response: HTTPClient.Response, email: String, password: String, code: String) throws -> LoginResponse {
        APLogger.logResponse(
            status: response.status.code, headers: response.headers.map { ($0.name, $0.value) }, bodySize: response.body?.readableBytes,
        )

        cookies.mergeCookies(response.cookies)

        let readStoreFrontValue = response.headers["x-set-apple-store-front"].filter { !$0.isEmpty }.compactMap {
            $0.components(separatedBy: "-").first
        }.filter { !$0.isEmpty }
        assert(readStoreFrontValue.count <= 1)
        if let first = readStoreFrontValue.first {
            storeFront = first
        }

        if let podValue = response.headers.first(name: "pod"), !podValue.isEmpty {
            pod = podValue
        }

        let redirectStatuses: [HTTPResponseStatus] = [.movedPermanently, .found, .seeOther, .temporaryRedirect, .permanentRedirect]
        if redirectStatuses.contains(response.status) {
            guard let location = response.headers.first(name: "location"), let url = URL(string: location) else {
                return .failure(.init(stage: .authentication, httpStatus: Int(response.status.code)))
            }
            return .redirect(url)
        }

        // Preserve Apple's explicit error fields even on non-200 responses.
        let responseData = response.body.map { Data($0.readableBytesView) } ?? Data()
        let fields = (try? PropertyListSerialization.propertyList(from: responseData, format: nil) as? [String: Any])
            ?? (try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]) ?? [:]
        let diagnostic = Self.rejection(fields, status: Int(response.status.code), secrets: [email, password + code, password, code], submittedCode: !code.isEmpty)
        guard response.status == .ok else { return .failure(diagnostic) }
        guard var body = response.body, body.readableBytes <= 2 * 1024 * 1024, let data = body.readData(length: body.readableBytes) else {
            return .failure(diagnostic)
        }

        guard let dic = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return .failure(diagnostic)
        }

        // A code submission can fail for account, transport or device reasons too.
        // Keep Apple's bounded diagnostic instead of asserting the code was wrong.
        if !code.isEmpty, dic["accountInfo"] == nil {
            return .failure(diagnostic)
        }

        if Self.requiresVerificationCode(dic, submittedCode: !code.isEmpty) {
            return .codeRequired
        }

        if let failureType = dic["failureType"] as? String, failureType == "-5000" {
            return .failure(diagnostic)
        }

        if let failureType = dic["failureType"] as? String, failureType == "5005" {
            return .failure(diagnostic)
        }

        guard let accountInfoDic = dic["accountInfo"] as? [String: Any],
              let addressInfoDic = accountInfoDic["address"] as? [String: Any] else { return .failure(diagnostic) }

        let account = try Account(
            email: email, password: password, appleId: accountInfoDic["appleId"] as? String, store: storeFront,
            firstName: addressInfoDic["firstName"] as? String, lastName: addressInfoDic["lastName"] as? String,
            passwordToken: dic["passwordToken"] as? String, directoryServicesIdentifier: dic["dsPersonId"] as? String, cookie: cookies,
            pod: pod,
        )
        return .success(account)
    }
}
