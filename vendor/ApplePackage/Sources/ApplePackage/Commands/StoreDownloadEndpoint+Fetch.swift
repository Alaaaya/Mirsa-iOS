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
    /// Failures inside the chain are thrown as `StoreDownloadFailure` (secret-free tag) or `StoreDownloadHTTPError`.
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
        } catch let error as StoreDownloadHTTPError {
            guard error.statusCode == 500, error.emptyBody, !version.isEmpty,
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
        let amd = StoreAMDProof.shared(deviceIdentifier: deviceIdentifier)
        var handshake = StoreAMDHandshake(provider: amd)
        var amdRetries = 0

        while redirectAttempt <= maxRedirects {
            currentURL = try Self.validatedURL(currentURL)
            // A missing profile or unusable identifier must not block a download; Apple asks with SP.
            var amdHeaders: [String: String] = [:]
            if StoreAMDHeaderPolicy.allows(currentURL) { amdHeaders = (try? await amd.headers()) ?? [:] }
            let request = try makeRequest(
                account: account,
                app: app,
                url: currentURL,
                guid: deviceIdentifier,
                externalVersionID: externalVersionID,
                amdHeaders: amdHeaders,
            )
            let response = try await client.execute(request: request).get()
            defer { finalResponse = response }

            APLogger.logResponse(
                status: response.status.code,
                headers: response.headers.map { ($0.name, $0.value) },
                bodySize: response.body?.readableBytes,
            )

            account.cookie.mergeCookies(response.cookies)

            // Device registration, bounded by the handshake budget and a hard cap.
            if amdRetries < 4, try await handshake.respond(to: response) {
                amdRetries += 1
                continue
            }

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
            break
        }

        guard let finalResponse else { try ensureFailed(Strings.noResponseReceived) }

        guard finalResponse.status == .ok else {
            let errorBody = finalResponse.body.map { Data($0.readableBytesView) } ?? Data()
            throw StoreDownloadHTTPError(statusCode: finalResponse.status.code, emptyBody: errorBody.isEmpty,
                                         tag: .init(endpoint: tagEndpoint, response: StoreAMDAction.fields(from: errorBody),
                                                    httpStatus: Int(finalResponse.status.code), stop: .http))
        }

        guard var body = finalResponse.body,
              let data = body.readData(length: body.readableBytes)
        else {
            try ensureFailed(Strings.responseBodyEmpty)
        }

        let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil,
        ) as? [String: Any]
        guard let dict = plist else {
            throw StoreDownloadFailure(.init(endpoint: tagEndpoint, httpStatus: 200, stop: .parse), reason: Strings.invalidResponse)
        }
        if StoreAMDAction.isActionMessage(dict["customerMessage"] as? String) { throw StoreAMDError(.parse) }

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
        ]
        // ipatool downloadProductRequest sends X-Apple-Store-Front and X-Token on volumeStore, redownload and
        // updateProduct alike. Mirsa's working buyProduct already sends both in this exact form.
        headers.append(contentsOf: try Self.sessionHeaders(account))

        for item in account.cookie.buildCookieHeader(url) {
            headers.append(item)
        }
        headers.append(contentsOf: try StoreAMDHeaderPolicy.headers(amdHeaders, for: url))

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
    /// `X-Apple-Store-Front: <store>-1` and `X-Token: <passwordToken>`, same values as Purchase.makeRequest.
    /// Values with CR/LF/NUL are refused at byte level; an empty token or store is not sent.
    static func sessionHeaders(_ account: Account) throws -> [(String, String)] {
        var result: [(String, String)] = []
        let store = account.store.trimmingCharacters(in: .whitespaces)
        if !store.isEmpty, store.utf8.count <= 12, store.utf8.allSatisfy({ (48...57).contains($0) }) {
            result.append(("X-Apple-Store-Front", "\(store)-1"))
        }
        let token = account.passwordToken
        if !token.isEmpty {
            try ensure(token.utf8.count <= 8192 && !token.utf8.contains(where: { $0 == 13 || $0 == 10 || $0 == 0 }),
                       Strings.unableToReadPasswordToken)
            result.append(("X-Token", token))
        }
        return result
    }
}

struct StoreDownloadHTTPError: LocalizedError {
    let statusCode: UInt
    let emptyBody: Bool
    /// Secret-free reason (endpoint, failureType, key-like message) of the non-200 answer.
    var tag: StoreDownloadTag? = nil

    var errorDescription: String? {
        Strings.requestFailed(status: statusCode)
    }
}
