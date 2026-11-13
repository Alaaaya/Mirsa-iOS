//
//  Purchase.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import AsyncHTTPClient
import Foundation

public enum Purchase {
    public static func purchase(
        account: inout Account,
        app: Software,
    ) async throws {
        let deviceIdentifier = Configuration.deviceIdentifier

        if app.price != 0 {
            try ensureFailed(Strings.paidAppsNotSupported)
        }

        do {
            try await purchaseWithParams(account: &account, app: app, guid: deviceIdentifier, pricingParameters: "STDQ")
        } catch let error as StoreProductDiagnostic {
            // Existing Arcade fallback only. 2059 never means already purchased.
            if error.failureType == "2059" {
                try await purchaseWithParams(account: &account, app: app, guid: deviceIdentifier, pricingParameters: "GAME")
            } else {
                throw error
            }
        }
    }

    static func failureCode(_ fields: [String: Any]) -> String? {
        (fields["failureType"] as? String) ?? (fields["failureType"] as? NSNumber)?.stringValue
    }

    static func confirmsExistingLicense(_ fields: [String: Any]) -> Bool {
        failureCode(fields) == "5002"
    }

    private static func purchaseWithParams(
        account: inout Account,
        app: Software,
        guid: String,
        pricingParameters: String,
    ) async throws {
        APLogger.debug("purchase: using pricing parameters: \(pricingParameters)")

        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }

        let amd = StoreAMDProof(deviceIdentifier: guid)
        var handshake = StoreAMDHandshake(provider: amd)
        var finalResponse: HTTPClient.Response?
        var currentURL = try Self.purchaseURL(pod: account.pod)
        var redirectCount = 0
        for _ in 0..<8 {
            let request = try makeRequest(
                account: account, app: app, guid: guid, pricingParameters: pricingParameters,
                amdHeaders: try await amd.headers(), endpointURL: currentURL
            )
            let response = try await client.execute(request: request,
                delegate: ResponseAccumulator(request: request, maxBodySize: 2 * 1024 * 1024)).futureResult.get()
            account.cookie.mergeCookies(response.cookies)
            if try await handshake.respond(to: response) { continue }
            if [301, 302, 303, 307, 308].contains(response.status.code) {
                guard redirectCount < 3, let location = response.headers.first(name: "location"),
                      let target = URL(string: location, relativeTo: currentURL)?.absoluteURL else {
                    throw StoreProductDiagnostic(stage: "licence/" + pricingParameters, status: response.status.code,
                        fields: [:], account: account, app: app, requestURL: currentURL)
                }
                currentURL = try Self.validatedPurchaseURL(target)
                redirectCount += 1
                continue // Rebuild scoped cookies/proof and replay the original POST, never GET.
            }
            finalResponse = response
            break
        }
        guard let response = finalResponse else { throw StoreAMDError(.budget) }

        APLogger.logResponse(
            status: response.status.code,
            headers: response.headers.map { ($0.name, $0.value) },
            bodySize: response.body?.readableBytes,
        )

        account.cookie.mergeCookies(response.cookies)

        let data = response.body.map { Data($0.readableBytesView) } ?? Data()
        let fields = (try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            ?? (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let diagnostic = StoreProductDiagnostic(stage: "licence/" + pricingParameters,
            status: response.status.code, fields: fields, account: account, emptyBody: data.isEmpty,
            app: app, requestURL: currentURL, responseHeaders: response.headers.map { ($0.name, $0.value) })
        // Only a successful transport plus Apple's explicit 5002 entitlement
        // response is positive evidence. Neither HTTP 500 nor 2059 qualifies.
        guard response.status == .ok else { throw diagnostic }
        if Self.confirmsExistingLicense(fields) { return }
        if Self.failureCode(fields) != nil || fields["action"] != nil ||
            !(fields["customerMessage"] as? String ?? "").isEmpty { throw diagnostic }
        guard fields["jingleDocType"] as? String == "purchaseSuccess",
              (fields["status"] as? NSNumber)?.intValue == 0 else { throw diagnostic }
    }

    static func purchaseURL(pod: String?) throws -> URL {
        let host = Configuration.purchaseAPIHost(pod: pod)
        let urlString = "https://\(host)/WebObjects/MZFinance.woa/wa/buyProduct"
        guard let url = URL(string: urlString) else { try ensureFailed(Strings.failedToRetrieveRedirect) }
        return try validatedPurchaseURL(url)
    }

    static func validatedPurchaseURL(_ url: URL) throws -> URL {
        // The AMD scope is also the strict Apple host/path credential boundary.
        try ensure(StoreAMDHeaderScope.permits(url) &&
                   url.path == "/WebObjects/MZFinance.woa/wa/buyProduct",
                   Strings.failedToRetrieveRedirect)
        return url
    }

    static func makeRequest(
        account: Account,
        app: Software,
        guid: String,
        pricingParameters: String,
        amdHeaders: [String: String] = [:],
        endpointURL: URL? = nil,
    ) throws -> HTTPClient.Request {
        let payload: [String: Any] = [
            "appExtVrsId": "0",
            "hasAskedToFulfillPreorder": "true",
            "buyWithoutAuthorization": "true",
            "hasDoneAgeCheck": "true",
            "guid": guid,
            "needDiv": "0",
            "origPage": "Software-\(app.id)",
            "origPageLocation": "Buy",
            "price": "0",
            "pricingParameters": pricingParameters,
            "productType": "C",
            "salableAdamId": app.id,
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)

        var headers: [(String, String)] = [
            ("Content-Type", "application/x-apple-plist"),
            ("User-Agent", Configuration.userAgent),
            ("iCloud-DSID", account.directoryServicesIdentifier),
            ("X-Dsid", account.directoryServicesIdentifier),
            ("X-Apple-Store-Front", try account.commerceStoreFront()),
            ("X-Token", account.passwordToken),
        ]

        let url = try Self.validatedPurchaseURL(endpointURL ?? Self.purchaseURL(pod: account.pod))
        let urlString = url.absoluteString

        for item in account.cookie.buildCookieHeader(url) {
            headers.append(item)
        }

        try StoreAMDHeaderScope.append(amdHeaders, to: &headers, url: url)
        APLogger.logRequest(method: "POST", url: urlString, headers: headers)

        return try .init(
            url: urlString,
            method: .POST,
            headers: .init(headers),
            body: .data(data),
        )
    }
}
