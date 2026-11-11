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

    private let signer: SAPSigner
    private let deviceIdentifier: String
    private var endpoint: URL
    private var cookies: [Cookie]
    private var storeFront = ""
    private var pod: String?
    private var authenticating = false

    /// A fresh SAP exchange is mandatory. Reuse this instance when supplying a verification code.
    public init(cookies: [Cookie] = []) async throws {
        deviceIdentifier = Configuration.deviceIdentifier
        let bag: Bag.BagOutput
        do { bag = try await Bag.fetchBag(redirectConfiguration: .disallow) }
        catch { throw AuthenticationServiceError.wrapping(error, stage: .bag) }
        try bag.requireSupportedAuthentication()
        endpoint = try Self.createInitialRequestEndpoint(baseURL: bag.authEndpoint, deviceIdentifier: deviceIdentifier)
        do { signer = try await SAPSigner.connect() }
        catch { throw AuthenticationServiceError.wrapping(error, stage: .sapValidation) }
        self.cookies = cookies
    }

    public static func authenticate(email: String, password: String, code: String = "", cookies: [Cookie] = []) async throws -> Account {
        let session = try await Authenticator(cookies: cookies)
        return try await session.authenticate(email: email, password: password, code: code)
    }

    public func authenticate(email: String, password: String, code: String = "") async throws -> Account {
        guard !authenticating else { try ensureFailed("An authentication request is already in progress.") }
        authenticating = true
        defer { authenticating = false }
        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }
        var redirects = 0
        for _ in 0 ..< 5 {
            let request = try await Self.makeRequest(
                endpoint: endpoint, email: email, password: password, code: code, cookies: cookies, deviceIdentifier: deviceIdentifier,
                sapSigner: signer,
            )
            let accumulator = ResponseAccumulator(request: request, maxBodySize: 2 * 1024 * 1024)
            let response: HTTPClient.Response
            do { response = try await client.execute(request: request, delegate: accumulator).futureResult.get() }
            catch { throw AuthenticationServiceError.wrapping(error, stage: .authentication, transport: true) }
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
            case let .failure(diagnostic): throw diagnostic
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

    static func makeRequest(
        endpoint: URL, email: String, password: String, code: String, cookies: [Cookie], deviceIdentifier: String,
        sapSigner: any SAPRequestSigning,
    ) async throws -> HTTPClient.Request {
        let parameters: [String: String] = [
            "appleId": email, "attempt": "\(code.isEmpty ? "1" : "2")", "guid": deviceIdentifier, "password": "\(password)\(code)",
            "rmp": "0", "why": "signIn",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: parameters, format: .xml, options: 0)
        var headers: [(String, String)] = [("User-Agent", Configuration.userAgent), ("Content-Type", "application/x-apple-plist")]
        for item in cookies.buildCookieHeader(endpoint) {
            headers.append(item)
        }
        _ = try approvedEndpoint(endpoint)
        let signature: Data
        do { signature = try await sapSigner.sign(data) }
        catch { throw AuthenticationServiceError.wrapping(error, stage: .signing) }
        headers.append(("X-Apple-ActionSignature", signature.base64EncodedString()))
        APLogger.logRequest(method: "POST", url: endpoint.absoluteString, headers: headers)
        return try .init(url: endpoint.absoluteString, method: .POST, headers: .init(headers), body: .data(data))
    }

    static func rejection(_ fields: [String: Any], status: Int, secrets: [String]) -> AuthenticationServiceError {
        let knownSecrets = ["passwordToken", "dsPersonId", "appleId", "password", "token", "cookie"].compactMap { fields[$0] as? String }
        return .init(stage: .authentication, httpStatus: status, appleCode: fields["failureType"],
              message: (fields["dialog"] as? [String: Any])?["explanation"] as? String
                ?? fields["customerMessage"] as? String, secrets: secrets + knownSecrets)
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
        let diagnostic = Self.rejection(fields, status: Int(response.status.code), secrets: [email, password + code, password, code])
        guard response.status == .ok else { return .failure(diagnostic) }
        guard var body = response.body, body.readableBytes <= 2 * 1024 * 1024, let data = body.readData(length: body.readableBytes) else {
            return .failure(diagnostic)
        }

        guard let dic = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return .failure(diagnostic)
        }

        if let failureType = dic["failureType"] as? String, failureType.isEmpty, code.isEmpty,
           let customerMessage = dic["customerMessage"] as? String, customerMessage == "MZFinance.BadLogin.Configurator_message"
        {
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
