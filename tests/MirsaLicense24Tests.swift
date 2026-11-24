import XCTest
import CryptoKit
@testable import Mirsa

final class MirsaLicense24Tests: XCTestCase {
    func testUpstreamMITNoticeIsCompleteAndUnchanged() {
        // SHA-256 of the freshly verified Mak5er/AirCard-iOS LICENSE, including its final newline.
        let digest = SHA256.hash(data: Data(LicensesView.upstreamMITNotice.utf8))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "65a15cb14444f04e048d81c4efdc176cb597c2bbd5846dcbdce6e2f742945581")
        XCTAssertTrue(LicensesView.upstreamMITNotice.contains("Copyright (c) 2026 Johnny Franks"))
        XCTAssertTrue(LicensesView.upstreamMITNotice.hasSuffix("SOFTWARE.\n"))
    }
}
