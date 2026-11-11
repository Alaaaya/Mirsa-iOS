//
//  Bag.swift
//  ApplePackage
//
//  Created on 2026/2/20.
//

import AsyncHTTPClient
import Foundation

public enum Bag {
    public struct BagOutput {
        public var authEndpoint: URL
        public var redownloadEndpoint: URL?
        public var updateEndpoint: URL?
        // Authentication must validate the live protocol instead of silently using a default.
        var sapVersion: String?
        var sapSetupEndpoint: String?
        var sapCertificateEndpoint: String?
        var advertisedAuthEndpoint: Bool = false
        /// Apple's HTTP `Date`, used to correct the machine OTP clock.
        var serverDate: Date?

        func requireSupportedAuthentication() throws {
            guard advertisedAuthEndpoint, sapVersion == "200",
                  sapSetupEndpoint == "https://fpinit.itunes.apple.com/v1/signSapSetup/legacy",
                  sapCertificateEndpoint == "https://s.mzstatic.com/sap/setupCert.plist" else {
                throw AuthenticationServiceError(stage: .bag)
            }
            _ = try Authenticator.approvedEndpoint(authEndpoint)
        }
    }

    private static let defaultAuthEndpoint = "https://auth.itunes.apple.com/auth/v1/native/fast/"

    public static func fetchBag(
        redirectConfiguration: HTTPClient.Configuration.RedirectConfiguration = .follow(max: 8, allowCycles: false),
    ) async throws -> BagOutput {
        let deviceIdentifier = Configuration.deviceIdentifier

        let client = Configuration.makeHTTPClient(redirectConfiguration: redirectConfiguration)
        defer { _ = client.shutdown() }

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "init.itunes.apple.com"
        comps.path = "/bag.xml"
        comps.queryItems = [URLQueryItem(name: "guid", value: deviceIdentifier)]
        guard let url = comps.url else {
            APLogger.debug("bag: failed to construct URL, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        let headers: [(String, String)] = [
            ("User-Agent", Configuration.userAgent),
            ("Accept", "application/xml"),
        ]

        APLogger.logRequest(method: "GET", url: url.absoluteString, headers: headers)

        // Bag routing can move between Apple pods. Resolve a bounded, Apple-only
        // chain explicitly even when the caller correctly disables automatic redirects.
        var target = url
        var finalResponse: HTTPClient.Response?
        for hop in 0...3 {
            _ = try Authenticator.approvedEndpoint(target)
            let request = try HTTPClient.Request(url: target.absoluteString, method: .GET,
                                                 headers: .init(headers), body: .none)
            let response: HTTPClient.Response
            do {
                let accumulator = ResponseAccumulator(request: request, maxBodySize: 2 * 1024 * 1024)
                response = try await client.execute(request: request, delegate: accumulator).futureResult.get()
            } catch { throw AuthenticationServiceError.wrapping(error, stage: .bag, transport: true) }
            if [301, 302, 303, 307, 308].contains(Int(response.status.code)) {
                guard hop < 3, let location = response.headers.first(name: "location"),
                      let next = URL(string: location, relativeTo: target)?.absoluteURL else {
                    throw AuthenticationServiceError(stage: .bag, httpStatus: Int(response.status.code))
                }
                target = try Authenticator.approvedEndpoint(next)
                continue
            }
            guard response.status == .ok else {
                throw AuthenticationServiceError(stage: .bag, httpStatus: Int(response.status.code))
            }
            finalResponse = response
            break
        }
        guard let response = finalResponse else { throw AuthenticationServiceError(stage: .bag) }

        APLogger.logResponse(
            status: response.status.code,
            headers: response.headers.map { ($0.name, $0.value) },
            bodySize: response.body?.readableBytes,
        )

        let serverDate = StoreAMDClock.serverDate(response.headers)
        guard var body = response.body,
              let data = body.readData(length: body.readableBytes)
        else {
            APLogger.debug("bag: empty response body, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!, serverDate: serverDate)
        }

        var output = parse(data)
        output.serverDate = serverDate
        return output
    }

    static func parse(_ data: Data) -> BagOutput {
        let plistData = extractPlistData(from: data)

        guard
            let plist = try? PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil,
            ) as? [String: Any]
        else {
            APLogger.debug("bag: failed to parse plist, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        // authenticateAccount used to live inside the nested urlBag dict,
        // newer bag responses move it to the plist root
        let urlBag = plist["urlBag"] as? [String: Any] ?? [:]
        let authURLString = (plist["authenticateAccount"] as? String) ?? (urlBag["authenticateAccount"] as? String)

        let authURL = authURLString.flatMap(normalizedAuthEndpoint) ?? URL(string: defaultAuthEndpoint)!
        if authURLString == nil {
            APLogger.debug("bag: no authenticateAccount in plist, using default auth endpoint")
        }

        APLogger.info("bag: auth endpoint resolved to \(APLogger.safeURL(authURL.absoluteString))")
        return BagOutput(
            authEndpoint: authURL,
            redownloadEndpoint: downloadEndpoint(plist["redownloadProduct"] ?? urlBag["redownloadProduct"], path: "/r/redownload"),
            updateEndpoint: downloadEndpoint(plist["updateProduct"] ?? urlBag["updateProduct"], path: "/up/updateProduct"),
            sapVersion: (plist["sign-sap-version"] ?? urlBag["sign-sap-version"]).map { String(describing: $0) },
            sapSetupEndpoint: (plist["sign-sap-setup"] ?? urlBag["sign-sap-setup"]) as? String,
            sapCertificateEndpoint: (plist["sign-sap-setup-cert"] ?? urlBag["sign-sap-setup-cert"]) as? String,
            advertisedAuthEndpoint: authURLString.flatMap(normalizedAuthEndpoint) != nil,
        )
    }

    private static func downloadEndpoint(_ value: Any?, path: String) -> URL? {
        guard let value = value as? String, let url = URL(string: value),
              url.scheme == "https", url.host == "downloaddispatch.itunes.apple.com",
              url.path == path, url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.query == nil, url.fragment == nil
        else { return nil }
        return url
    }

    /// Keep Apple's advertised native route verbatim. `/native` and
    /// `/native/fast/` are different services, not slash variants. Rewriting
    /// the former to the latter can reject an otherwise valid signed request.
    /// Only the legacy MZFinance route needs a trailing slash.
    static func normalizedAuthEndpoint(from urlString: String) -> URL? {
        guard var comps = URLComponents(string: urlString) else { return nil }
        if comps.scheme?.lowercased() == "https", let host = comps.host?.lowercased() {
            let legacyHost =
                host == "buy.itunes.apple.com" || host.range(of: "^p[0-9]+-buy[.]itunes[.]apple[.]com$", options: .regularExpression) != nil
            if legacyHost, comps.path == "/WebObjects/MZFinance.woa/wa/authenticate" {
                comps.path += "/"
            }
        }
        return comps.url
    }

    /// The bag XML response wraps the plist inside `<Document><Protocol><plist>...</plist>`.
    /// Extract the `<plist>...</plist>` portion so PropertyListSerialization can parse it.
    /// If the data is already a bare plist, return it as-is.
    private static func extractPlistData(from data: Data) -> Data {
        guard let xmlString = String(data: data, encoding: .utf8),
              let startRange = xmlString.range(of: "<plist"),
              let endRange = xmlString.range(of: "</plist>")
        else {
            return data
        }
        return Data(xmlString[startRange.lowerBound ..< endRange.upperBound].utf8)
    }
}
