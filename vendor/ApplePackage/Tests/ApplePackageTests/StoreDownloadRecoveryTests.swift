@testable import ApplePackage
import Foundation
import AsyncHTTPClient
import Testing

struct StoreDownloadRecoveryTests {
    private var fixtureSoftware: Software {
        Software(id: 123, bundleID: "example.app", name: "Fixture", version: "1.0", price: 0,
                 artistName: "", sellerName: "", description: "", averageUserRating: 0,
                 userRatingCount: 0, artworkUrl: "", screenshotUrls: [], minimumOsVersion: "15.0",
                 releaseDate: "", primaryGenreName: "")
    }

    @Test
    func `full Turkish storefront survives persistence and every download retry request`() throws {
        var account = fixtureAccount
        // Synthetic fixture, not a guessed production storefront suffix.
        account.storeFront = "143480-7,29 t:fixture"
        account.pod = "25"
        account.cookie = [Cookie(name: "session", value: "fixture-cookie", path: "/", domain: ".itunes.apple.com", httpOnly: true, secure: true)]
        let saved = try JSONEncoder().encode(account)
        let restored = try JSONDecoder().decode(Account.self, from: saved)
        #expect(restored.storeFront == account.storeFront)
        #expect(Configuration.countryCode(for: restored.store) == "TR")
        for endpoint in [StoreDownloadEndpoint.volumeStore, .redownload, .update] {
            let original = try endpoint.url(pod: restored.pod, deviceIdentifier: "001122334455")
            let redirect = try #require(URL(string: "https://p37-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct?guid=001122334455"))
            for url in [original, original, redirect] {
                let request = try endpoint.makeRequest(account: restored, app: fixtureSoftware, url: url,
                    guid: "001122334455", externalVersionID: "1234", amdHeaders: ["X-Apple-AMD": "fixture-proof"])
                #expect(request.headers.first(name: "X-Apple-Store-Front") == account.storeFront)
                #expect(request.headers.first(name: "X-Token") == account.passwordToken)
                #expect(request.headers.first(name: "X-Dsid") == account.directoryServicesIdentifier)
                #expect(request.headers.first(name: "Cookie") == "session=fixture-cookie")
                #expect(request.headers.first(name: "X-Apple-AMD") == "fixture-proof")
                #expect(request.url == url)
            }
        }
        let purchase = try Purchase.makeRequest(account: restored, app: fixtureSoftware, guid: "001122334455", pricingParameters: "STDQ")
        #expect(purchase.headers.first(name: "X-Apple-Store-Front") == account.storeFront)
        #expect(purchase.url.host == "p25-buy.itunes.apple.com")
        // Earlier cached sessions decode safely but cannot fabricate the original header.
        var old = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        old.removeValue(forKey: "storeFront")
        let legacy = try JSONDecoder().decode(Account.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(legacy.storeFront == nil)
        #expect(throws: StorefrontMetadataMissing.self) { try legacy.commerceStoreFront() }
        for bad in ["TR", "143441-1", "143480-1\r\nX-Token: secret",
                    "143480-1\rInjected", "143480-1\nInjected", "143480-1\u{0}Injected",
                    "143480-1\tInjected", "143480-1\u{2028}Injected"] {
            var invalid = account; invalid.storeFront = bad
            #expect(throws: StorefrontMetadataMissing.self) { try invalid.commerceStoreFront() }
        }
    }

    private var fixtureAccount: Account {
        Account(email: "owner@example.invalid", password: "private-password", appleId: "private-owner-id",
                store: "143480", firstName: "PrivateFirst", lastName: "PrivateLast", passwordToken: "private-token",
                directoryServicesIdentifier: "private-dsid", cookie: [])
    }

    @Test
    func `download diagnostics expose bounded response fields and redact account secrets`() {
        let fields: [String: Any] = ["failureType": 5002,
            "customerMessage": "Rejected owner@example.invalid private-password private-token private-owner-id private-dsid PrivateFirst PrivateLast https://private.invalid/path?token=secret",
            "dialog": "NEVER EXPOSE DIALOG", "passwordToken": "NEVER EXPOSE BODY"]
        for endpoint in [StoreDownloadEndpoint.volumeStore, .redownload, .update] {
            let error = StoreProductDiagnostic(endpoint: endpoint, status: 403, fields: fields, account: fixtureAccount)
            let text = error.localizedDescription
            #expect(error.httpStatus == 403)
            #expect(error.failureType == "5002")
            #expect(text.contains("HTTP 403"))
            #expect(text.contains("customerMessage"))
            for secret in ["owner@example.invalid", "private-password", "private-token", "private-owner-id", "private-dsid", "PrivateFirst", "PrivateLast", "https://", "NEVER EXPOSE"] {
                #expect(!text.contains(secret))
            }
            #expect((error.customerMessage?.count ?? 0) <= 320)
        }
        for code in ["<private>", "123456789", "token-value"] {
            let error = StoreProductDiagnostic(endpoint: .volumeStore, status: 500,
                fields: ["failureType": code, "customerMessage": String(repeating: "secret", count: 1000)], account: fixtureAccount)
            #expect(error.failureType == nil)
            #expect(error.customerMessage == nil)
        }
    }

    @Test
    func `download request credentials never reach external hosts or unapproved routes`() throws {
        let path = "/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct"
        let forbidden = [
            "https://api.timbrd.com/apple/app-version", "https://apis.bilin.eu.org/history/123",
            "https://cdn.apple.com" + path, "https://p25-buy.itunes.apple.com.evil.invalid" + path,
            "http://p25-buy.itunes.apple.com" + path, "https://user:pass@buy.itunes.apple.com" + path,
            "https://buy.itunes.apple.com:8443" + path, "https://buy.itunes.apple.com" + path + "/extra",
            "https://downloaddispatch.itunes.apple.com/r/redownload/extra",
            "https://p25-buy.itunes.apple.com/other",
        ]
        for raw in forbidden {
            let url = try #require(URL(string: raw))
            #expect(throws: (any Error).self) { try StoreDownloadEndpoint.validatedURL(url) }
            #expect(throws: (any Error).self) {
                try StoreDownloadEndpoint.volumeStore.makeRequest(account: fixtureAccount, app: fixtureSoftware, url: url,
                    guid: "001122334455", externalVersionID: "", amdHeaders: ["X-Apple-AMD": "proof"])
            }
            var headers: [(String, String)] = []
            try StoreAMDHeaderScope.append(["X-Apple-AMD": "proof", "X-Apple-AMD-M": "machine"], to: &headers, url: url)
            #expect(headers.isEmpty)
        }
    }

    @Test
    func `download endpoints survive missing authentication endpoint`() throws {
        let endpoints = [
            "redownloadProduct": "https://downloaddispatch.itunes.apple.com/r/redownload",
            "updateProduct": "https://downloaddispatch.itunes.apple.com/up/updateProduct",
        ]
        let bags: [[String: Any]] = [endpoints, ["urlBag": endpoints]]
        for contents in bags {
            let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
            let bag = Bag.parse(data)
            #expect(bag.redownloadEndpoint?.absoluteString == endpoints["redownloadProduct"])
            #expect(bag.updateEndpoint?.absoluteString == endpoints["updateProduct"])
        }
    }

    @Test
    func `rejects unapproved download endpoints`() throws {
        for endpoint in [
            "http://downloaddispatch.itunes.apple.com/up/updateProduct",
            "https://downloaddispatch.itunes.apple.com.example.invalid/up/updateProduct",
            "https://user:password@downloaddispatch.itunes.apple.com/up/updateProduct",
            "https://downloaddispatch.itunes.apple.com/up/updateProduct?redirect=other",
            "https://downloaddispatch.itunes.apple.com/r/redownload",
        ] {
            let data = try PropertyListSerialization.data(fromPropertyList: ["urlBag": ["updateProduct": endpoint]], format: .xml, options: 0)
            #expect(Bag.parse(data).updateEndpoint == nil)
        }
    }

    @Test
    func `recovers empty responses but preserves explicit failures`() {
        let recoverable: [[String: Any]] = [[:], ["songList": [], "status": 0], ["failureType": 5002]]
        for response in recoverable {
            #expect(StoreDownloadEndpoint.requiresRedownload(response))
        }
        let failures: [[String: Any]] = [
            ["failureType": "9610"], ["status": -1], ["customerMessage": "Rejected"],
            ["dialog": [:]], ["songList": "invalid"], ["songList": [["metadata": [:]]]],
        ]
        for response in failures {
            #expect(!StoreDownloadEndpoint.requiresRedownload(response))
        }
    }

    @Test
    func `recovery must match the requested package`() throws {
        let app = Software(id: 123, bundleID: "example.app", name: "Fixture", version: "1.0",
                           artistName: "", sellerName: "", description: "", averageUserRating: 0,
                           userRatingCount: 0, artworkUrl: "", screenshotUrls: [], minimumOsVersion: "15.0",
                           releaseDate: "", primaryGenreName: "")
        let metadata: [String: Any] = ["itemId": 123, "softwareVersionExternalIdentifier": 456, "softwareVersionBundleId": "example.app"]
        let response: [String: Any] = ["songList": [["metadata": metadata]]]
        _ = try StoreDownloadEndpoint.validateRecoveryResponse(response, app: app, version: "456")
        for field in metadata.keys {
            var mismatched = metadata
            mismatched[field] = "wrong"
            #expect(throws: (any Error).self) {
                try StoreDownloadEndpoint.validateRecoveryResponse(["songList": [["metadata": mismatched]]], app: app, version: "456")
            }
        }
    }
}
