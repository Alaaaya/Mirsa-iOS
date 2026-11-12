//
//  StoreDownloadEndpoint+Fetch.swift
//  ApplePackage
//
//  Created on 2026/6/12.
//

import AsyncHTTPClient
import Foundation

extension StoreDownloadEndpoint {
    /// Preserve the version across the bounded volumeStore, redownload, and update chain.
    static func fetchProductWithFallback(
        client: HTTPClient,
        account: inout Account,
        app: Software,
        deviceIdentifier: String,
        externalVersionID: String,
        entityType: EntityType = .iPhone,
    ) async throws -> [String: Any] {
        try await fetchProductTracked(client: client, account: &account, app: app, deviceIdentifier: deviceIdentifier,
                                      externalVersionID: externalVersionID, entityType: entityType).response
    }

    /// The tag's endpoint for this case.
    var tagEndpoint: StoreDownloadTag.Endpoint {
        switch self {
        case .volumeStore: .volume
        case .redownload: .redownload
        case .update: .update
        }
    }

    /// Same chain as `fetchProductWithFallback`, also naming the endpoint whose answer is returned.
    /// Apple's non-200 / failureType answers stay `StoreProductDiagnostic`; the other chain stops
    /// (redirect, parse, recovery mismatch, catalog lookup) are `StoreDownloadFailure` with a secret-free tag.
    static func fetchProductTracked(
        client: HTTPClient,
        account: inout Account,
        app: Software,
        deviceIdentifier: String,
        externalVersionID: String,
        entityType: EntityType = .iPhone,
    ) async throws -> (response: [String: Any], endpoint: StoreDownloadTag.Endpoint) {
        let dict = try await StoreDownloadEndpoint.volumeStore.fetchProduct(
            client: client,
            account: &account,
            app: app,
            deviceIdentifier: deviceIdentifier,
            externalVersionID: externalVersionID,
        )

        guard requiresRedownload(dict) else { return (dict, .volume) }
        APLogger.debug("store: volumeStore returned no package, trying redownload")
        var version = externalVersionID
        if version.isEmpty {
            guard let country = Configuration.countryCode(for: account.store) else {
                try ensureFailed(Strings.unsupportedStoreIdentifier(account.store))
            }
            do {
                version = try await PlatformVersionLookup.lookup(appID: app.id, countryCode: country, entityType: entityType).externalVersionID
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw StoreDownloadFailure(.init(endpoint: .volume, response: dict, httpStatus: 200, stop: .lookup),
                                           reason: Strings.missingVersionIdentifiers)
            }
        }
        let bag = try? await Bag.fetchBag()
        do {
            let response = try await StoreDownloadEndpoint.redownload.fetchProduct(
                client: client,
                account: &account,
                app: app,
                deviceIdentifier: deviceIdentifier,
                externalVersionID: version,
                endpointURL: bag?.redownloadEndpoint,
            )
            return (try validateRecoveryResponse(response, app: app, version: version, endpoint: .redownload), .redownload)
        } catch let error as StoreProductDiagnostic {
            guard error.httpStatus == 500, error.emptyBody, !version.isEmpty,
                  let updateEndpoint = bag?.updateEndpoint
            else { throw error }
            APLogger.debug("store: redownload returned an empty HTTP 500, trying updateProduct")
            let response = try await StoreDownloadEndpoint.update.fetchProduct(
                client: client, account: &account, app: app, deviceIdentifier: deviceIdentifier,
                externalVersionID: version, endpointURL: updateEndpoint,
            )
            return (try validateRecoveryResponse(response, app: app, version: version, endpoint: .update), .update)
        }
    }

    static func validateRecoveryResponse(_ response: [String: Any], app: Software, version: String,
                                         endpoint: StoreDownloadTag.Endpoint = .redownload) throws -> [String: Any] {
        if let failure = response["failureType"], !String(describing: failure).isEmpty {
            return response
        }
        guard (response["customerMessage"] as? String ?? "").isEmpty,
              response["dialog"] == nil, response["action"] == nil,
              let items = response["songList"] as? [[String: Any]], items.count == 1,
              let metadata = items.first?["metadata"] as? [String: Any],
              metadata["itemId"].map({ String(describing: $0) }) == String(app.id),
              metadata["softwareVersionExternalIdentifier"].map({ String(describing: $0) }) == version,
              metadata["softwareVersionBundleId"] as? String == app.bundleID
        else {
            let stop: StoreDownloadTag.Stop = (response["customerMessage"] as? String ?? "").isEmpty && response["dialog"] == nil
                && response["action"] == nil ? .recovery : .failure
            throw StoreDownloadFailure(.init(endpoint: endpoint, response: response, httpStatus: 200, stop: stop),
                                       reason: Strings.invalidResponse)
        }
        return response
    }

    static func requiresRedownload(_ response: [String: Any]) -> Bool {
        let failure = response["failureType"].map { String(describing: $0) } ?? ""
        if failure == retryableFailureType {
            return true
        }
        guard failure.isEmpty, (response["customerMessage"] as? String ?? "").isEmpty,
              response["dialog"] == nil, response["action"] == nil,
              response["status"] == nil || (response["status"] as? NSNumber)?.intValue == 0
        else { return false }
        if let items = response["songList"] as? [Any] {
            return items.isEmpty
        }
        return response["songList"] == nil
    }

    /// Runs the product request against this endpoint, following pod redirects,
    /// and returns the parsed plist response.
    func fetchProduct(
        client: HTTPClient,
        account: inout Account,
        app: Software,
        deviceIdentifier: String,
        externalVersionID: String,
        endpointURL: URL? = nil,
    ) async throws -> [String: Any] {
        var currentURL = try url(pod: account.pod, deviceIdentifier: deviceIdentifier)
        if let endpointURL, var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "guid", value: deviceIdentifier)]
            currentURL = try components.url.get()
        }
        var redirectAttempt = 0
        var finalResponse: HTTPClient.Response?
        let maxRedirects = 3
        let amd = StoreAMDProof(deviceIdentifier: deviceIdentifier)
        var handshake = StoreAMDHandshake(provider: amd)

        for _ in 0..<8 {
            currentURL = try Self.validatedURL(currentURL)
            let request = try makeRequest(
                account: account,
                app: app,
                url: currentURL,
                guid: deviceIdentifier,
                externalVersionID: externalVersionID,
                amdHeaders: try await amd.headers(),
            )
            let response = try await client.execute(request: request,
                delegate: ResponseAccumulator(request: request, maxBodySize: 2 * 1024 * 1024)).futureResult.get()

            APLogger.logResponse(
                status: response.status.code,
                headers: response.headers.map { ($0.name, $0.value) },
                bodySize: response.body?.readableBytes,
            )

            account.cookie.mergeCookies(response.cookies)

            // Dispatch handles challenges but deliberately sends NO AMD proof headers.
            if try await handshake.respond(to: response) { continue }

            if [301, 302, 303, 307, 308].contains(response.status.code) {
                guard let location = response.headers.first(name: "location"),
                      let newURL = URL(string: location, relativeTo: currentURL)?.absoluteURL,
                      redirectAttempt < maxRedirects
                else {
                    throw StoreDownloadFailure(.init(endpoint: tagEndpoint, httpStatus: Int(response.status.code), stop: .redirect),
                                               reason: Strings.failedToRetrieveRedirect)
                }
                currentURL = newURL
                redirectAttempt += 1
                continue
            }
            finalResponse = response
            break
        }

        guard let finalResponse else { throw StoreAMDError(.budget) }

        let responseData = finalResponse.body.map { Data($0.readableBytesView) } ?? Data()
        let responseFields = (try? PropertyListSerialization.propertyList(from: responseData, format: nil) as? [String: Any])
            ?? (try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]) ?? [:]
        let failure = responseFields["failureType"].map { String(describing: $0) } ?? ""
        let message = responseFields["customerMessage"] as? String ?? ""
        // Preserve the narrow empty-500 recovery path and licence acquisition.
        if finalResponse.status != .ok {
            if finalResponse.status.code == 500 && responseData.isEmpty {
                throw StoreProductDiagnostic(endpoint: self, status: finalResponse.status.code, fields: responseFields, account: account, emptyBody: true)
            }
            throw StoreProductDiagnostic(endpoint: self, status: finalResponse.status.code, fields: responseFields, account: account)
        }
        if (!failure.isEmpty && failure != Self.retryableFailureType && failure != "9610") ||
            (failure.isEmpty && !message.isEmpty) {
            throw StoreProductDiagnostic(endpoint: self, status: finalResponse.status.code, fields: responseFields, account: account)
        }

        guard var body = finalResponse.body,
              let data = body.readData(length: body.readableBytes)
        else {
            throw StoreProductDiagnostic(endpoint: self, status: finalResponse.status.code, fields: responseFields, account: account, emptyBody: true)
        }

        let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil,
        ) as? [String: Any]
        guard let dict = plist else {
            throw StoreDownloadFailure(.init(endpoint: tagEndpoint, httpStatus: 200, stop: .parse), reason: Strings.invalidResponse)
        }

        return dict
    }

    func makeRequest(
        account: Account,
        app: Software,
        url: URL,
        guid: String,
        externalVersionID: String,
        amdHeaders: [String: String] = [:],
    ) throws -> HTTPClient.Request {
        // Validate before constructing any credential-bearing request, including test callers.
        _ = try Self.validatedURL(url)
        var payload: [String: Any] = [
            "creditDisplay": "",
            "guid": guid,
            "salableAdamId": app.id,
            "serialNumber": "0",
        ]

        if !externalVersionID.isEmpty {
            payload[externalVersionIDKey] = externalVersionID
        }

        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)

        var headers: [(String, String)] = [
            ("Content-Type", "application/x-apple-plist"),
            ("User-Agent", Configuration.userAgent),
            ("iCloud-DSID", account.directoryServicesIdentifier),
            ("X-Dsid", account.directoryServicesIdentifier),
            ("X-Apple-Store-Front", try Self.headerValue(account.commerceStoreFront(), "invalid X-Apple-Store-Front value")),
            ("X-Token", try Self.headerValue(account.passwordToken, Strings.unableToReadPasswordToken)),
        ]

        for item in account.cookie.buildCookieHeader(url) {
            headers.append(item)
        }

        try StoreAMDHeaderScope.append(amdHeaders, to: &headers, url: url)

        APLogger.logRequest(method: "POST", url: url.absoluteString, headers: headers)

        return try .init(
            url: url,
            method: .POST,
            headers: .init(headers),
            body: .data(data),
        )
    }
}

extension StoreDownloadEndpoint {
    /// X-Token / X-Apple-Store-Front value guard: CR, LF and NUL are refused at byte level (no header injection),
    /// as are empty or oversized values. The value itself never reaches an error or log.
    static func headerValue(_ value: String, _ reason: String) throws -> String {
        try ensure(!value.isEmpty && value.utf8.count <= 8192 && !value.utf8.contains(where: { $0 == 13 || $0 == 10 || $0 == 0 }),
                   reason)
        return value
    }
}

/// Bounded response fields only. No headers, request, body, URL, or account dump.
public struct StoreProductDiagnostic: Error, LocalizedError, Sendable {
    public let stage: String
    public let httpStatus: UInt
    let emptyBody: Bool
    public let failureType: String?
    public let customerMessage: String?

    init(endpoint: StoreDownloadEndpoint, status: UInt, fields: [String: Any], account: Account, emptyBody: Bool = false) {
        switch endpoint {
        case .volumeStore: stage = "volumeStore"
        case .redownload: stage = "redownload"
        case .update: stage = "updateProduct"
        }
        httpStatus = status
        self.emptyBody = emptyBody
        let secrets = [account.email, account.password, account.appleId, account.passwordToken,
                       account.directoryServicesIdentifier, account.firstName, account.lastName,
                       Configuration.deviceIdentifier] + account.cookie.map(\.value)
        let code = (fields["failureType"] as? String) ?? (fields["failureType"] as? NSNumber)?.stringValue
        failureType = code.flatMap { $0.range(of: "^-?[0-9]{1,8}$", options: .regularExpression) != nil ? $0 : nil }
        customerMessage = AuthenticationServiceError.redact(fields["customerMessage"] as? String, secrets: secrets)
    }

    public var errorDescription: String? {
        var parts = ["Apple [" + stage + "]", "HTTP " + String(httpStatus), "failureType " + (failureType ?? "missing")]
        if let customerMessage { parts.append("customerMessage " + customerMessage) }
        return parts.joined(separator: " · ")
    }
}
