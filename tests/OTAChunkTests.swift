import XCTest
@testable import Mirsa

final class OTAChunkTests: XCTestCase {
    func testInstallerLinkHasEmptyAuthorityAndRoundTripsSignedQuery() throws {
        let manifest = URL(string: "https://mirsa-app.mooo.com/ota/download/abc?token=a.b&kind=manifest")!
        let target = try OTAInstallLink.make(manifestURL: manifest)
        XCTAssertTrue(target.absoluteString.hasPrefix("itms-services://?action=download-manifest&url=https%3A%2F%2F"))
        let items = try XCTUnwrap(URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first(where: { $0.name == "url" })?.value, manifest.absoluteString)
        XCTAssertEqual(items.first(where: { $0.name == "action" })?.value, "download-manifest")
    }
    func testInstallerLinkPreservesLegacyEscapesAndPlus() throws {
        let manifest = URL(string: "https://example.com/manifest?token=a+b%2Fc%3D&kind=manifest")!
        let target = try OTAInstallLink.make(manifestURL: manifest)
        XCTAssertTrue(target.absoluteString.contains("%2B"))
        XCTAssertTrue(target.absoluteString.contains("%252F"))
        XCTAssertEqual(URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems?.last?.value, manifest.absoluteString)
    }
    func testInstallerLinkRejectsInsecureAndCredentialURLs() {
        for raw in ["http://example.com/m", "https://user:pass@example.com/m", "https://example.com/m#fragment"] {
            XCTAssertThrowsError(try OTAInstallLink.make(manifestURL: URL(string: raw)!))
        }
    }
    func testPlanCoversFileExactly() throws {
        let p = try OTAChunkPlan(total: 20, chunkSize: 8)
        XCTAssertEqual(p.count, 3)
        XCTAssertEqual(p.range(0), 0..<8); XCTAssertEqual(p.range(2), 16..<20)
    }
    func testPlanLimits() {
        XCTAssertThrowsError(try OTAChunkPlan(total: 0))
        XCTAssertThrowsError(try OTAChunkPlan(total: OTAChunkPlan.maxBytes + 1))
        XCTAssertNoThrow(try OTAChunkPlan(total: OTAChunkPlan.maxBytes))
    }
    func testHostAllowlist() {
        XCTAssertTrue(OTAHostPolicy.accepts(URL(string: "https://mirsa-app.mooo.com/x")!))
        XCTAssertFalse(OTAHostPolicy.accepts(URL(string: "http://mirsa-app.mooo.com/x")!))
        XCTAssertFalse(OTAHostPolicy.accepts(URL(string: "https://evil.com/x")!))
        XCTAssertFalse(OTAHostPolicy.accepts(URL(string: "https://mirsa-app.mooo.com@evil.com/x")!))
        XCTAssertFalse(OTAHostPolicy.accepts(URL(string: "https://mirsa-app.mooo.com.evil.com/")!))
    }
    func testErrorsLocalized() {
        XCTAssertNotNil(OTAChunkError.tooLarge.errorDescription)
        XCTAssertNotNil(OTAChunkError.server(500).errorDescription)
    }
    func testSessionWireValidation() throws {
        let ok = #"{"uploadURL":"https://mirsa-app.mooo.com/ota/sessions/abc","uploadToken":"t","maxChunkBytes":99999999999}"#.data(using: .utf8)!
        let s = try OTAOracleWire.session(from: ok)
        XCTAssertEqual(s.maxChunk, 8 * 1024 * 1024)
        for bad in [#"{"uploadURL":"https://evil.com/ota/sessions/a","uploadToken":"t"}"#,
                    #"{"uploadURL":"https://mirsa-app.mooo.com/other","uploadToken":"t"}"#,
                    #"{"uploadURL":"https://mirsa-app.mooo.com/ota/sessions/a","uploadToken":""}"#] {
            XCTAssertThrowsError(try OTAOracleWire.session(from: bad.data(using: .utf8)!))
        }
    }
    func testOffsetParse() {
        XCTAssertEqual(OTAOracleWire.offset(from: #"{"offset":8388608,"total":9}"#.data(using: .utf8)!), 8388608)
        XCTAssertNil(OTAOracleWire.offset(from: Data("x".utf8)))
    }
}
