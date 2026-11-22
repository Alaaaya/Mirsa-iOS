import XCTest
@testable import Mirsa

final class LocalDevVPNRouteTests: XCTestCase {
    func testMainAlwaysUsesUnambiguousSchemeEvenWithLegacySetupInstalled() {
        for mainInstalled in [true, false] {
            XCTAssertEqual(LocalDevVPNRoute.enableURL(isSetup: false, mainInstalled: mainInstalled).absoluteString,
                           "localdevvpn://enable?scheme=mirsa-container")
        }
    }

    func testSetupOnlyReturnsToItselfIfMainIsAbsent() {
        XCTAssertEqual(LocalDevVPNRoute.enableURL(isSetup: true, mainInstalled: true).absoluteString,
                       "localdevvpn://enable?scheme=mirsa-container")
        XCTAssertEqual(LocalDevVPNRoute.enableURL(isSetup: true, mainInstalled: false).absoluteString,
                       "localdevvpn://enable?scheme=mirsa")
    }

    func testSetupSelfInstallRestoresMainSchemeWithoutDroppingHandlers() {
        let setup = [["CFBundleURLName": "legacy", "CFBundleURLSchemes": ["mirsa"]]] as [[String: Any]]
        let main = LocalDevVPNRoute.mainURLTypes(setup)
        XCTAssertEqual(main.first?["CFBundleURLName"] as? String, "legacy")
        XCTAssertTrue(main.contains { ($0["CFBundleURLSchemes"] as? [String]) == ["mirsa-container"] })
        XCTAssertEqual(LocalDevVPNRoute.mainURLTypes(main).count, main.count)
        XCTAssertEqual(LocalDevVPNRoute.mainURLTypes([]).count, 1)
    }
}
