import XCTest
@testable import Mirsa

final class DeviceConnectionPolicyTests: XCTestCase {
    func testCertificateOTAPredicate() {
        XCTAssertTrue(CertificateInstall.shouldUseOTA(ownCertificateMode: true, wifi: true))
        XCTAssertTrue(CertificateInstall.shouldUseOTA(ownCertificateMode: true, wifi: false))
        XCTAssertTrue(CertificateInstall.shouldUseOTA(ownCertificateMode: false, wifi: false))
        XCTAssertTrue(CertificateInstall.shouldUseOTA(ownCertificateMode: false, wifi: true))
    }
    func testAppleIDRealAppGuardIsScoped() {
        XCTAssertFalse(DeviceConnectionPolicy.mayInstallRealApp(wifi: false, tunnelRoute: true, hasPairing: true))
        XCTAssertTrue(DeviceConnectionPolicy.mayInstallRealApp(wifi: true, tunnelRoute: true, hasPairing: true))
        XCTAssertFalse(DeviceConnectionPolicy.mayInstallRealApp(wifi: true, tunnelRoute: false, hasPairing: true))
    }
    func testCellularVPNCanAttemptWithoutWifi() {
        XCTAssertTrue(DeviceConnectionPolicy.mayAttempt(tunnelRoute: true, hasPairing: true))
    }
    func testWifiVPNUsesSamePolicy() {
        XCTAssertTrue(DeviceConnectionPolicy.mayAttempt(tunnelRoute: true, hasPairing: true))
    }
    func testNoVPNAndMissingPairingCannotAttempt() {
        XCTAssertFalse(DeviceConnectionPolicy.mayAttempt(tunnelRoute: false, hasPairing: true))
        XCTAssertFalse(DeviceConnectionPolicy.mayAttempt(tunnelRoute: true, hasPairing: false))
    }
    func testTypedTimeoutNotInvalidPairing() {
        let failure = DeviceConnectionFailure("MIRSA_CONNECTION|connect|timeout|transport|unknown|unreported")
        XCTAssertEqual(failure?.kind, "timeout")
        XCTAssertTrue(failure!.message(arabic: false).contains("does not prove"))
        XCTAssertFalse(failure!.message(arabic: true).isEmpty)
    }
    func testPairingPermissionAndHeartbeat() {
        for kind in ["pairing_rejected", "permission", "heartbeat", "route_unreachable"] {
            let failure = DeviceConnectionFailure("MIRSA_CONNECTION|connect|\(kind)|POSIX|54|172.16.0.1:49152")
            XCTAssertEqual(failure?.kind, kind)
            XCTAssertTrue(failure!.message(arabic: false).contains("[connect / \(kind) / POSIX / 54 / 172.16.0.1:49152]"))
        }
    }
    func testDoesNotDisplayUntrustedFields() {
        for raw in ["MIRSA_CONNECTION|connect|secret|POSIX|54|172.16.0.1:49152", "MIRSA_CONNECTION|connect|timeout|secret|54",
                    "MIRSA_CONNECTION|connect|timeout|POSIX|54 token=private",
                    "MIRSA_CONNECTION|secret|timeout|POSIX|54|172.16.0.1:49152"] {
            XCTAssertNil(DeviceConnectionFailure(raw))
        }
    }
}
