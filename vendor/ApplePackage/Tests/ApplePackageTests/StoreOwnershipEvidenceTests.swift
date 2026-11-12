@testable import ApplePackage
import Foundation
import Testing

struct StoreOwnershipEvidenceTests {
    private var account: Account {
        Account(email: "fixture@example.invalid", password: "secret-password", appleId: "fixture-id",
                store: "143480", firstName: "", lastName: "", passwordToken: "secret-token",
                directoryServicesIdentifier: "fixture-dsid", cookie: [])
    }

    @Test func onlyExplicitLicenseCodeMeansMissingLicense() {
        for endpoint in [StoreDownloadEndpoint.volumeStore, .redownload, .update] {
            for status in [UInt(200), 403, 500] {
                for fields in ([[:], ["failureType": "5002"], ["customerMessage": "Forbidden"]] as [[String: Any]]) {
                    let error = StoreProductDiagnostic(endpoint: endpoint, status: status, fields: fields, account: account)
                    #expect(!error.requiresLicense)
                }
                for code in (["9610", 9610] as [Any]) {
                    let error = StoreProductDiagnostic(endpoint: endpoint, status: status, fields: ["failureType": code], account: account)
                    #expect(error.requiresLicense)
                }
            }
        }
    }

    @Test func explicitAcquisitionAlreadyOwnedIsPositiveEvidenceOnlyFor5002() {
        #expect(Purchase.confirmsExistingLicense(["failureType": "5002"]))
        #expect(Purchase.confirmsExistingLicense(["failureType": 5002]))
        for fields in ([[:], ["status": 403], ["failureType": "9610"],
                        ["failureType": "2059"], ["customerMessage": "already purchased"]] as [[String: Any]]) {
            #expect(!Purchase.confirmsExistingLicense(fields))
        }
    }
    @Test func ownedWhatsAppDiagnosticKeepsRequestedIdentityAndVersionWithoutCredentialLeak() throws {
        // Offline selected-detail fixture, no ownership inference or provider request.
        let app = Software(id: 310633997, bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp",
                           version: "fixture", price: 0, artistName: "", sellerName: "",
                           description: "", averageUserRating: 0, userRatingCount: 0,
                           artworkUrl: "", screenshotUrls: [], minimumOsVersion: "15.0",
                           releaseDate: "", primaryGenreName: "")
        for version in ["", "880000004"] {
            let error = StoreProductDiagnostic(endpoint: .redownload, status: 403, fields: [:],
                                               account: account, app: app, externalVersionID: version)
            #expect(!error.requiresLicense)
            #expect(error.requestedAppID == 310633997)
            #expect(error.requestedBundleID == app.bundleID)
            #expect(error.accountStore == "143480")
            #expect(error.requestedVersionID == (version.isEmpty ? "latest" : version))
            #expect(!error.localizedDescription.contains(account.passwordToken))
            #expect(!error.localizedDescription.contains(account.directoryServicesIdentifier))
            #expect(!error.localizedDescription.contains(account.email))
        }
        let metadata: [String: Any] = ["itemId": app.id, "softwareVersionBundleId": app.bundleID,
                                      "softwareVersionExternalIdentifier": "880000004"]
        _ = try StoreDownloadEndpoint.validateRecoveryResponse(["songList": [["metadata": metadata]]],
                                                               app: app, version: "880000004")
    }

    @Test func licenceAndDownloadTransportContextIsAllowlistedAndRedacted() throws {
        let path = "/WebObjects/MZFinance.woa/wa/buyProduct"
        let url = try #require(URL(string: "https://p25-buy.itunes.apple.com" + path + "?guid=secret-guid&token=secret-token"))
        let error = StoreProductDiagnostic(stage: "licence/STDQ", status: 403,
            fields: ["failureType": 2059, "customerMessage": "Rejected secret-token fixture@example.invalid"],
            account: account, requestURL: url, responseHeaders: [
                ("Content-Type", "text/html"), ("Server", "Apple"), ("X-Request-ID", "safe-request-123"),
                ("Set-Cookie", "session=secret-session"), ("X-Token", "secret-token"),
                ("Location", "https://evil.invalid/private"), ("X-Dsid", "fixture-dsid"),
                ("X-Session-ID", "secret-session"), ("X-Apple-Request-UUID", "bad\r\nheader")
            ])
        #expect(error.httpStatus == 403)
        #expect(error.failureType == "2059")
        #expect(error.requestHost == "p25-buy.itunes.apple.com")
        #expect(error.requestPath == path)
        #expect(error.responseContext == ["content-type": "text/html", "server": "Apple", "x-request-id": "safe-request-123"])
        for secret in ["secret-token", "fixture@example.invalid", "secret-guid", "secret-session", "fixture-dsid", "evil.invalid"] {
            #expect(!error.localizedDescription.contains(secret))
        }
        #expect(error.localizedDescription.contains("licence/STDQ"))
        #expect(!error.requiresLicense)
        let unsafe = StoreProductDiagnostic(stage: "licence/STDQ", status: 500, fields: [:], account: account,
            requestURL: URL(string: "https://evil.invalid/" + account.passwordToken))
        #expect(unsafe.requestHost == nil && unsafe.requestPath == nil)
        #expect(!Purchase.confirmsExistingLicense(["failureType": "2059", "customerMessage": "Purchase couldn't be completed"]))
    }

}
