import XCTest
@testable import Mirsa

final class RuntimeStagingSession25Tests: XCTestCase {
    private let ep = "https://willingly-dejectedly-superb-neanderthal.kitten.space/runtime-translate-634f43ff16d0315cd0f4d44f"
    private func jwt(iss: String = RuntimeStagingSession.issuer, aud: String = RuntimeStagingSession.audience, exp: Date) -> String {
        func b(_ o: [String: Any]) -> String {
            Data(try! JSONSerialization.data(withJSONObject: o)).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return "\(b(["alg": "HS256"])).\(b(["iss": iss, "aud": aud, "exp": exp.timeIntervalSince1970])).sig"
    }
    func testAcceptsStagingSessionInBothFormats() throws {
        let t = jwt(exp: Date().addingTimeInterval(3000))
        XCTAssertEqual(try RuntimeStagingSession.parse("\(ep) \(t)").token, t)
        XCTAssertEqual(try RuntimeStagingSession.parse("{\"endpoint\":\"\(ep)\",\"accessToken\":\"\(t)\"}").endpoint, ep)
    }
    func testRejectsForeignHostHttpExpiredWrongIssuerAndLongLived() {
        let ok = jwt(exp: Date().addingTimeInterval(3000))
        XCTAssertThrowsError(try RuntimeStagingSession.parse("https://evil.example.com/runtime-translate-634f43ff16d0315cd0f4d44f \(ok)"))
        XCTAssertThrowsError(try RuntimeStagingSession.parse("http://willingly-dejectedly-superb-neanderthal.kitten.space/runtime-translate-634f43ff16d0315cd0f4d44f \(ok)"))
        XCTAssertThrowsError(try RuntimeStagingSession.parse("\(ep) \(jwt(exp: Date().addingTimeInterval(-5)))"))
        XCTAssertThrowsError(try RuntimeStagingSession.parse("\(ep) \(jwt(iss: "https://prod.supabase.co/auth/v1", exp: Date().addingTimeInterval(3000)))"))
        XCTAssertThrowsError(try RuntimeStagingSession.parse("\(ep) \(jwt(aud: "authenticated", exp: Date().addingTimeInterval(3000)))"))
        XCTAssertThrowsError(try RuntimeStagingSession.parse("\(ep) \(jwt(exp: Date().addingTimeInterval(86400)))"))
        XCTAssertThrowsError(try RuntimeStagingSession.parse("\(ep) \(jwt(exp: Date().addingTimeInterval(3700)))"))
        XCTAssertThrowsError(try RuntimeStagingSession.parse("\(ep)?x=1 \(ok)"))
    }
    func testStoreRoundTripAndExpiry() throws {
        let s = try RuntimeStagingSession.parse("\(ep) \(jwt(exp: Date().addingTimeInterval(3000)))")
        RuntimeStagingSessionStore.save(s)
        XCTAssertEqual(RuntimeStagingSessionStore.load()?.endpoint, ep)
        XCTAssertNil(RuntimeStagingSessionStore.load(now: Date().addingTimeInterval(4000)))
        RuntimeStagingSessionStore.save(nil)
        XCTAssertNil(RuntimeStagingSessionStore.load())
    }
}
