@testable import ApplePackage
import AsyncHTTPClient
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import XCTest

/// Offline only: builds the product download / version-list request and checks it byte by byte against ipatool
/// (pkg/appstore/appstore_download_product.go `downloadProductRequest`, appstore_list_versions.go). No request is sent.
/// Also checks the secret-free `[dl:...]` tag. The class name contains `SAPAuthenticationRequestTests` so the CI filter runs it.
final class DownloadSAPAuthenticationRequestTests: XCTestCase {
    private enum FakeError: Error { case unexpectedBodyChunk }

    private static let token = "FIXTURE-password-token-AAAABBBBCCCCDDDDEEEEFFFF0000"
    private static let dsid = "8123456789"
    private static let guid = "A1B2C3D4E5F6"

    private static func account(store: String = "143441", token: String = token) -> Account {
        Account(email: "owner@example.invalid", password: "", appleId: "owner@example.invalid", store: store,
                firstName: "F", lastName: "L", passwordToken: token, directoryServicesIdentifier: dsid,
                cookie: [Cookie(name: "mz_at0", value: "fixture-cookie", path: "/", domain: ".apple.com", httpOnly: true, secure: true)],
                pod: "25")
    }

    private static var app: Software { Software(id: 1_234_567_890, bundleID: "example.app", name: "Fixture", version: "1.0",
                                      artistName: "", sellerName: "", description: "", averageUserRating: 0,
                                      userRatingCount: 0, artworkUrl: "", screenshotUrls: [], minimumOsVersion: "15.0",
                                      releaseDate: "", primaryGenreName: "") }

    private static func bodyData(_ request: HTTPClient.Request) throws -> Data {
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

    private func request(_ endpoint: StoreDownloadEndpoint, version: String, amd: [String: String] = [:]) throws -> HTTPClient.Request {
        let url = try endpoint.url(pod: "25", deviceIdentifier: Self.guid)
        return try endpoint.makeRequest(account: Self.account(), app: Self.app, url: url, guid: Self.guid,
                                        externalVersionID: version, amdHeaders: amd)
    }

    // MARK: - Request shape vs ipatool downloadProductRequest

    func testVolumeStoreRequestHeadersMatchIpatool() throws {
        let request = try request(.volumeStore, version: "", amd: ["X-Apple-AMD": "AMD1", "X-Apple-AMD-M": "AMDM"])
        XCTAssertEqual(request.method, .POST)
        XCTAssertEqual(request.url.absoluteString,
                       "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct?guid=\(Self.guid)")
        let h = request.headers
        XCTAssertEqual(h["Content-Type"], ["application/x-apple-plist"])
        XCTAssertEqual(h["User-Agent"], [Configuration.userAgent])
        XCTAssertEqual(h["iCloud-DSID"], [Self.dsid])
        XCTAssertEqual(h["X-Dsid"], [Self.dsid])
        // Missing before this change; ipatool sends both on every commerce download request.
        XCTAssertEqual(h["X-Apple-Store-Front"], ["143441-1"])
        XCTAssertEqual(h["X-Token"], [Self.token])
        XCTAssertEqual(h["X-Apple-AMD"], ["AMD1"])
        XCTAssertEqual(h["X-Apple-AMD-M"], ["AMDM"])
        XCTAssertEqual(h["Cookie"], ["mz_at0=fixture-cookie"])
        // No GUID header (ipatool sends guid in the query and the body only).
        XCTAssertTrue(h["GUID"].isEmpty)
    }

    func testRedownloadAndUpdateCarrySameSessionHeaders() throws {
        for endpoint in [StoreDownloadEndpoint.redownload, .update] {
            let h = try request(endpoint, version: "870000001").headers
            XCTAssertEqual(h["X-Apple-Store-Front"], ["143441-1"], "\(endpoint)")
            XCTAssertEqual(h["X-Token"], [Self.token], "\(endpoint)")
            XCTAssertEqual(h["X-Dsid"], [Self.dsid], "\(endpoint)")
            XCTAssertEqual(h["iCloud-DSID"], [Self.dsid], "\(endpoint)")
        }
    }

    func testBodyBytesMatchIpatoolPayload() throws {
        // Unpinned (ipatool ListVersions for iPhone/iPad and Download without -external-version-id).
        let unpinned = try Self.bodyData(request(.volumeStore, version: ""))
        let expectedUnpinned: [String: Any] = ["creditDisplay": "", "guid": Self.guid, "salableAdamId": Self.app.id, "serialNumber": "0"]
        XCTAssertEqual(unpinned, try PropertyListSerialization.data(fromPropertyList: expectedUnpinned, format: .xml, options: 0))
        let parsed = try XCTUnwrap(PropertyListSerialization.propertyList(from: unpinned, format: nil) as? [String: Any])
        XCTAssertEqual(Set(parsed.keys), ["creditDisplay", "guid", "salableAdamId", "serialNumber"])
        XCTAssertTrue(String(decoding: unpinned, as: UTF8.self).contains("<key>salableAdamId</key>\n\t<integer>1234567890</integer>"))

        // Pinned: volumeStore uses externalVersionId, dispatch endpoints use appExtVrsId (string), as ipatool.
        let pins: [(StoreDownloadEndpoint, String)] = [(.volumeStore, "externalVersionId"), (.redownload, "appExtVrsId"), (.update, "appExtVrsId")]
        for (endpoint, key) in pins {
            let data = try Self.bodyData(request(endpoint, version: "870000001"))
            var expected = expectedUnpinned
            expected[key] = "870000001"
            XCTAssertEqual(data, try PropertyListSerialization.data(fromPropertyList: expected, format: .xml, options: 0), "\(endpoint)")
        }
    }

    func testSessionHeadersRefuseControlBytesAndSkipEmptyOrInvalid() throws {
        XCTAssertThrowsError(try StoreDownloadEndpoint.sessionHeaders(Self.account(token: "abc\r\nX-Evil: 1")))
        XCTAssertThrowsError(try StoreDownloadEndpoint.sessionHeaders(Self.account(token: "abc\u{0}")))
        let empty = try StoreDownloadEndpoint.sessionHeaders(Self.account(token: ""))
        XCTAssertEqual(empty.map { $0.0 }, ["X-Apple-Store-Front"])
        let badStore = try StoreDownloadEndpoint.sessionHeaders(Self.account(store: "143441\r\nX: y"))
        XCTAssertEqual(badStore.map { $0.0 }, ["X-Token"])
        // Same value form as the working buyProduct request.
        XCTAssertEqual(try StoreDownloadEndpoint.sessionHeaders(Self.account()).first?.1, "143441-1")
    }

    // MARK: - Secret-free tag

    func testTagCarriesAppleCodesButNoSecrets() {
        let response: [String: Any] = [
            "failureType": "2042",
            "customerMessage": "Hello owner@example.invalid, dsid \(Self.dsid) token \(Self.token)",
            "metrics": ["messageCode": 2042, "dsid": Self.dsid] as [String: Any],
            "dialog": ["message": "x", "explanation": "y"],
        ]
        let tag = StoreDownloadTag(operation: .download, endpoint: .volume, response: response, httpStatus: 200, stop: .failure)
        XCTAssertEqual(tag.text, "[dl:download at=volume ft=2042 mc=2042 msg=other http=200 dlg=1 items=0 stop=failure]")
        for secret in ["owner@example.invalid", Self.dsid, Self.token, Self.guid, "fixture-cookie"] {
            XCTAssertFalse(tag.text.contains(secret), secret)
        }
    }

    func testTagMapsKnownAppleTextsAndKeys() {
        let cases: [(String, String)] = [
            ("Sign In to the iTunes Store", "sign-in"),
            ("  Sign-In   Required ", "sign-in"),
            ("Your password has changed.", "password-changed"),
            ("This app is No Longer Available", "no-longer-available"),
            ("Redownload Unavailable with This Apple Account", "redownload-unavailable"),
            ("Subscription Required", "subscription-required"),
            ("Your account is disabled.", "account-disabled"),
            ("This item is temporarily unavailable.", "temporarily-unavailable"),
            ("MZCommerce.SoftwareNotAvailable", "MZCommerce.SoftwareNotAvailable"),
            ("Please contact support about owner@example.invalid", "other"),
        ]
        for (text, slug) in cases {
            XCTAssertEqual(StoreDownloadTag.message(text), slug, text)
        }
        XCTAssertEqual(StoreDownloadTag.message(nil), "none")
        // dialog.message is read when customerMessage is absent.
        let tag = StoreDownloadTag(endpoint: .redownload, response: ["dialog": ["message": "Redownload Unavailable with This Apple Account"]],
                                   httpStatus: 200, stop: .failure)
        XCTAssertEqual(tag.message, "redownload-unavailable")
        XCTAssertTrue(tag.dialog)
    }

    func testHTTPErrorBecomesTaggedFailureWithOperation() throws {
        let plain = StoreDownloadFailure.map(StoreDownloadHTTPError(statusCode: 500, emptyBody: true), .versions)
        XCTAssertEqual((plain as? StoreDownloadFailure)?.tag.text,
                       "[dl:versions at=none ft=none mc=none msg=none http=500 dlg=0 items=0 stop=http]")
        let withBody = StoreDownloadHTTPError(statusCode: 403, emptyBody: false,
                                              tag: .init(endpoint: .redownload, response: ["failureType": "1008"], httpStatus: 403, stop: .http))
        let mapped = try XCTUnwrap(StoreDownloadFailure.map(withBody, .download) as? StoreDownloadFailure)
        XCTAssertEqual(mapped.tag.text, "[dl:download at=redownload ft=1008 mc=none msg=none http=403 dlg=0 items=0 stop=http]")
    }

    func testMapLeavesDistinctErrorsUntouched() {
        XCTAssertTrue(StoreDownloadFailure.map(StoreAMDError(.parse), .download) is StoreAMDError)
        XCTAssertTrue(StoreDownloadFailure.map(CancellationError(), .download) is CancellationError)
        if case ApplePackageError.licenseRequired = StoreDownloadFailure.map(ApplePackageError.licenseRequired, .versions) {} else {
            XCTFail("license required must stay distinct")
        }
    }

    func testRecoveryMismatchIsTaggedWithEndpoint() {
        let metadata: [String: Any] = ["itemId": 1, "softwareVersionExternalIdentifier": 2, "softwareVersionBundleId": "other.app"]
        let response: [String: Any] = ["songList": [["metadata": metadata]]]
        XCTAssertThrowsError(try StoreDownloadEndpoint.validateRecoveryResponse(response, app: Self.app, version: "2", endpoint: .update)) { error in
            XCTAssertEqual((error as? StoreDownloadFailure)?.tag.text,
                           "[dl:download at=update ft=none mc=none msg=none http=200 dlg=0 items=1 stop=recovery]")
        }
        XCTAssertThrowsError(try StoreDownloadEndpoint.validateRecoveryResponse(["customerMessage": "No Longer Available"],
                                                                                app: Self.app, version: "2")) { error in
            XCTAssertEqual((error as? StoreDownloadFailure)?.tag.stop, .failure)
            XCTAssertEqual((error as? StoreDownloadFailure)?.tag.message, "no-longer-available")
        }
    }

    func testFailureDescriptionHasNoAppleFreeText() {
        let failure = StoreDownloadFailure.answer(.download, .volume, ["failureType": "5000", "customerMessage": "secret owner@example.invalid"],
                                                  .failure, reason: Strings.downloadFailed + ": 5000")
        let text = failure.localizedDescription
        XCTAssertFalse(text.contains("owner@example.invalid"), text)
        XCTAssertTrue(text.hasSuffix("[dl:download at=volume ft=5000 mc=none msg=other http=200 dlg=0 items=0 stop=failure]"), text)
    }
}
