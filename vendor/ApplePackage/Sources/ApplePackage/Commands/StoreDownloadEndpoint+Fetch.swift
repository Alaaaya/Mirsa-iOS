//
//  StoreDownloadEndpoint+Fetch.swift
//  ApplePackage
//
//  Created on 2026/6/12.
//

import CStoreAMD
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
        let dict = try await StoreDownloadEndpoint.volumeStore.fetchProduct(
            client: client,
            account: &account,
            app: app,
            deviceIdentifier: deviceIdentifier,
            externalVersionID: externalVersionID,
        )

        guard requiresRedownload(dict) else { return dict }
        APLogger.debug("store: volumeStore returned no package, trying redownload")
        var version = externalVersionID
        if version.isEmpty {
            guard let country = Configuration.countryCode(for: account.store) else {
                try ensureFailed(Strings.unsupportedStoreIdentifier(account.store))
            }
            version = try await PlatformVersionLookup.lookup(appID: app.id, countryCode: country, entityType: entityType).externalVersionID
        }
        // Use the account/device-bound dispatch protocol before the legacy redownload.
        // The caller's exact selected ID is retained; latest lookup happens only when unpinned.
        var entitlementError: StoreProductDiagnostic?
        do {
            let response = try await StoreDownloadEndpoint.entitlement.fetchProduct(
                client: client, account: &account, app: app, deviceIdentifier: deviceIdentifier,
                externalVersionID: version)
            return try validateRecoveryResponse(response, app: app, version: version)
        } catch let error as StoreProductDiagnostic {
            // Explicit expired-session or licence responses must not trigger another action.
            if error.requiresReauthentication || error.requiresLicense { throw error }
            entitlementError = error
        } catch {
            // Local native generation/transport unavailability may use the original bounded chain.
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
            return try validateRecoveryResponse(response, app: app, version: version)
        } catch let error as StoreProductDiagnostic {
            guard error.httpStatus == 500, error.emptyBody, !version.isEmpty,
                  let updateEndpoint = bag?.updateEndpoint
            else { throw entitlementError ?? error }
            APLogger.debug("store: redownload returned an empty HTTP 500, trying updateProduct")
            let response = try await StoreDownloadEndpoint.update.fetchProduct(
                client: client, account: &account, app: app, deviceIdentifier: deviceIdentifier,
                externalVersionID: version, endpointURL: updateEndpoint,
            )
            return try validateRecoveryResponse(response, app: app, version: version)
        }
    }

    static func validateRecoveryResponse(_ response: [String: Any], app: Software, version: String) throws -> [String: Any] {
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
        else { try ensureFailed(Strings.invalidResponse) }
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
        let kbSync = self == .entitlement ? try Self.kbSync(dsid: account.directoryServicesIdentifier, guid: deviceIdentifier) : nil
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
                kbSync: kbSync,
            )
            let response = try await client.execute(request: request,
                delegate: ResponseAccumulator(request: request, maxBodySize: 2 * 1024 * 1024)).futureResult.get()

            APLogger.logResponse(
                status: response.status.code,
                headers: response.headers.map { ($0.name, $0.value) },
                bodySize: response.body?.readableBytes,
            )

            account.cookie.mergeCookies(response.cookies)

            // Every retry uses the same account, device, version and fresh native kbSync packet.
            if try await handshake.respond(to: response) { continue }

            if [301, 302, 303, 307, 308].contains(response.status.code) {
                guard let location = response.headers.first(name: "location"),
                      let newURL = URL(string: location, relativeTo: currentURL)?.absoluteURL,
                      redirectAttempt < maxRedirects
                else {
                    try ensureFailed(Strings.failedToRetrieveRedirect)
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
                throw StoreProductDiagnostic(endpoint: self, status: finalResponse.status.code, fields: responseFields, account: account, emptyBody: true, app: app, externalVersionID: externalVersionID, requestURL: currentURL, responseHeaders: finalResponse.headers.map { ($0.name, $0.value) })
            }
            throw StoreProductDiagnostic(endpoint: self, status: finalResponse.status.code, fields: responseFields, account: account, app: app, externalVersionID: externalVersionID, requestURL: currentURL, responseHeaders: finalResponse.headers.map { ($0.name, $0.value) })
        }
        if (!failure.isEmpty && failure != Self.retryableFailureType && failure != "9610") ||
            (failure.isEmpty && !message.isEmpty) {
            throw StoreProductDiagnostic(endpoint: self, status: finalResponse.status.code, fields: responseFields, account: account, app: app, externalVersionID: externalVersionID, requestURL: currentURL, responseHeaders: finalResponse.headers.map { ($0.name, $0.value) })
        }

        guard var body = finalResponse.body,
              let data = body.readData(length: body.readableBytes)
        else {
            throw StoreProductDiagnostic(endpoint: self, status: finalResponse.status.code, fields: responseFields, account: account, emptyBody: true, app: app, externalVersionID: externalVersionID, requestURL: currentURL, responseHeaders: finalResponse.headers.map { ($0.name, $0.value) })
        }

        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil,
        ) as? [String: Any]
        guard var dict = plist else { try ensureFailed(Strings.invalidResponse) }

        // Apple may encode the same failure code as an integer or string.
        // Downstream Download/VersionFinder use the documented string codes.
        if let code = dict["failureType"] as? NSNumber {
            dict["failureType"] = code.stringValue
        }
        return dict
    }

    static func hardware(_ guid: String) -> Data? {
        guard guid.utf8.count == 12, guid.range(of: "^[0-9A-Fa-f]{12}$", options: .regularExpression) != nil else { return nil }
        var result = Data()
        var i = guid.startIndex
        for _ in 0..<6 {
            let end = guid.index(i, offsetBy: 2)
            guard let value = UInt8(guid[i..<end], radix: 16) else { return nil }
            result.append(value); i = end
        }
        return result
    }

    static func kbSync(dsid: String, guid: String) throws -> String {
        guard let accountID = UInt64(dsid), accountID != 0, let hardware = hardware(guid) else { throw StoreAMDError(.device) }
        let bytes = [UInt8](hardware)
        var output = [UInt8](repeating: 0, count: 212)
        var written = 0
        let status = bytes.withUnsafeBufferPointer { buffer in
            output.withUnsafeMutableBufferPointer { out in
                mirsa_store_kbsync(accountID, buffer.baseAddress, buffer.count, out.baseAddress, out.count, &written)
            }
        }
        guard status == 1, written == 212 else { throw StoreAMDError(.request) }
        return Data(output).base64EncodedString()
    }

    func makeRequest(
        account: Account,
        app: Software,
        url: URL,
        guid: String,
        externalVersionID: String,
        amdHeaders: [String: String] = [:],
        kbSync: String? = nil,
    ) throws -> HTTPClient.Request {
        // Validate before constructing any credential-bearing request, including test callers.
        _ = try Self.validatedURL(url)
        var payload: [String: Any] = [
            "creditDisplay": "",
            "guid": guid,
            "salableAdamId": app.id,
            "serialNumber": "0",
        ]

        if self == .entitlement {
            guard let kbSync, let bytes = Data(base64Encoded: kbSync), bytes.count == 212,
                  let hardware = Self.hardware(guid) else { throw StoreAMDError(.device) }
            payload["kbsync"] = kbSync
            payload["salableAdamId"] = String(app.id)
            payload["serialNumber"] = (Data([0x54, 0xc8, 0xb0, 0xa9, 0x88]) + hardware.suffix(4)).base64EncodedString()
        }
        if !externalVersionID.isEmpty {
            payload[externalVersionIDKey] = externalVersionID
        }

        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)

        var headers: [(String, String)] = [
            ("Content-Type", self == .entitlement ? "application/x-www-form-urlencoded; charset=utf-8" : "application/x-apple-plist"),
            ("User-Agent", Configuration.userAgent),
            ("iCloud-DSID", account.directoryServicesIdentifier),
            ("X-Dsid", account.directoryServicesIdentifier),
            ("X-Apple-Store-Front", try account.commerceStoreFront()),
            ("X-Token", account.passwordToken),
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

/// Bounded response fields and explicitly allowlisted transport context. Never dumps credentials.
public struct StoreProductDiagnostic: Error, LocalizedError, Sendable {
    public let stage: String
    public let httpStatus: UInt
    let emptyBody: Bool
    public let failureType: String?
    public let customerMessage: String?
    public let requestedAppID: Int?
    public let requestedBundleID: String?
    public let requestedVersionID: String?
    public let accountStore: String?
    public let requestHost: String?
    public let requestPath: String?
    public let responseContext: [String: String]

    init(endpoint: StoreDownloadEndpoint, status: UInt, fields: [String: Any], account: Account, emptyBody: Bool = false, app: Software? = nil, externalVersionID: String = "", requestURL: URL? = nil, responseHeaders: [(String, String)] = []) {
        let stage: String
        switch endpoint {
        case .entitlement: stage = "ent/download"
        case .volumeStore: stage = "volumeStore"
        case .redownload: stage = "redownload"
        case .update: stage = "updateProduct"
        }
        self.init(stage: stage, status: status, fields: fields, account: account, emptyBody: emptyBody,
                  app: app, externalVersionID: externalVersionID, requestURL: requestURL, responseHeaders: responseHeaders)
    }

    init(stage: String, status: UInt, fields: [String: Any], account: Account, emptyBody: Bool = false, app: Software? = nil, externalVersionID: String = "", requestURL: URL? = nil, responseHeaders: [(String, String)] = []) {
        self.stage = stage
        requestedAppID = app.map { Int($0.id) }
        requestedBundleID = (app?.bundleID).flatMap {
            $0.count <= 255 && $0.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil ? $0 : nil
        }
        requestedVersionID = externalVersionID.isEmpty ? "latest" :
            (externalVersionID.range(of: "^[0-9]{1,20}$", options: .regularExpression) != nil ? externalVersionID : nil)
        accountStore = account.store.range(of: "^[0-9]{6}$", options: .regularExpression) != nil ? account.store : nil
        httpStatus = status
        self.emptyBody = emptyBody
        let secrets = [account.email, account.password, account.appleId, account.passwordToken,
                       account.directoryServicesIdentifier, account.firstName, account.lastName,
                       Configuration.deviceIdentifier] + account.cookie.map(\.value)
        let knownPaths = ["/WebObjects/MZFinance.woa/wa/buyProduct",
                          "/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct",
                          "/WebObjects/MZFinance.woa/wa/redownloadProduct",
                          "/WebObjects/MZFinance.woa/wa/updateProduct",
                          "/r/redownload", "/up/updateProduct", "/WebObjects/DownloadDispatch.woa/wa/ent/download"]
        if let url = requestURL, (StoreAMDHeaderScope.permits(url) || (try? StoreDownloadEndpoint.validatedURL(url)) != nil), knownPaths.contains(url.path) {
            requestHost = url.host?.lowercased()
            requestPath = url.path
        } else {
            requestHost = nil; requestPath = nil
        }
        // No Set-Cookie, Location, auth, token, DSID, device or session header.
        let allowed = ["content-type", "server", "x-request-id", "x-apple-request-uuid"]
        var context: [String: String] = [:]
        for (name, value) in responseHeaders {
            let key = name.lowercased()
            guard allowed.contains(key), context[key] == nil, value.count <= 160,
                  value.range(of: "^[A-Za-z0-9 /;=._:+-]+$", options: .regularExpression) != nil,
                  let clean = AuthenticationServiceError.redact(value, secrets: secrets) else { continue }
            context[key] = clean
        }
        responseContext = context
        let code = (fields["failureType"] as? String) ?? (fields["failureType"] as? NSNumber)?.stringValue
        failureType = code.flatMap { $0.range(of: "^-?[0-9]{1,8}$", options: .regularExpression) != nil ? $0 : nil }
        customerMessage = AuthenticationServiceError.redact(fields["customerMessage"] as? String, secrets: secrets)
    }

    /// Only Apple's explicit licence code is ownership evidence, never HTTP 403 alone.
    public var requiresLicense: Bool { failureType == "9610" }

    /// A commerce token rejection asks for sign-in again without deleting the shared account.
    /// A bare 403 is never proof that the session expired or the licence is missing.
    public var requiresReauthentication: Bool {
        failureType == "2034" || failureType == "2042" ||
            customerMessage?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "sign in to the itunes store"
    }

    public var errorDescription: String? {
        var parts = ["Apple [" + stage + "]", "HTTP " + String(httpStatus), "failureType " + (failureType ?? "missing")]
        if let requestedAppID { parts.append("appID " + String(requestedAppID)) }
        if let requestedBundleID { parts.append("bundle " + requestedBundleID) }
        if let accountStore { parts.append("accountStore " + accountStore) }
        if let requestedVersionID { parts.append("versionID " + requestedVersionID) }
        if let requestHost { parts.append("host " + requestHost) }
        if let requestPath { parts.append("path " + requestPath) }
        for name in responseContext.keys.sorted() { parts.append(name + " " + (responseContext[name] ?? "")) }
        if let customerMessage { parts.append("customerMessage " + customerMessage) }
        return parts.joined(separator: " · ")
    }
}
