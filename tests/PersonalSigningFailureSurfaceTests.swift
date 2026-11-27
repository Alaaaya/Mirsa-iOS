import XCTest
@testable import Mirsa

@MainActor
final class PersonalSigningFailureSurfaceTests: XCTestCase {
    /// Pre-sign failure (missing IPA, no pairing) must end the operation with a visible typed error,
    /// never a silent reset, and must not report success.
    func testPreSignFailureSurfacesErrorAndNeverSucceeds() async throws {
        let op = PersonalSigningOperation.shared
        let pid = UUID()
        let missing = URL(fileURLWithPath: "/nonexistent/mirsa-\(UUID().uuidString).ipa")
        let material = PersonalIdentityVault.Material(p12: Data([1, 2, 3]), password: "x", profile: Data([4]))
        op.start(projectID: pid, title: "T", input: missing, material: material,
                 pairingPath: "/nonexistent/pairing.plist", options: PersonalProjectOptions())
        XCTAssertEqual(op.state?.projectID, pid)
        for _ in 0..<200 where op.state?.running == true { try await Task.sleep(nanoseconds: 50_000_000) }
        let state = try XCTUnwrap(op.state)
        XCTAssertFalse(state.running)
        XCTAssertEqual(state.stage, .failed)
        XCTAssertNil(state.result)
        let message = try XCTUnwrap(state.error)
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(message.contains("/Users/runner"))
    }
    func testDuplicateStartWhileRunningIsIgnoredAndNewAttemptClearsOldError() async throws {
        let op = PersonalSigningOperation.shared
        let material = PersonalIdentityVault.Material(p12: Data([1]), password: "x", profile: Data([4]))
        let missing = URL(fileURLWithPath: "/nonexistent/a.ipa")
        var draft = PersonalProjectDraft()
        draft.translateArabic = true
        var options = PersonalProjectOptions()
        options.applyTranslationChoice(from: draft)
        op.start(projectID: UUID(), title: "A", input: missing, material: material, pairingPath: "", options: options)
        XCTAssertEqual(op.state?.requestedTranslateToArabic, true)
        XCTAssertTrue(op.state?.log.contains { $0.text == "Arabic translation requested: ON" } == true)
        XCTAssertTrue(op.state?.log.contains { $0.text.hasPrefix("Mirsa ") } == true)
        draft.translateArabic = false
        options.applyTranslationChoice(from: draft)
        XCTAssertEqual(op.state?.requestedTranslateToArabic, true)
        let first = op.state?.id
        op.start(projectID: UUID(), title: "B", input: missing, material: material, pairingPath: "", options: PersonalProjectOptions())
        XCTAssertEqual(op.state?.id, first)
        XCTAssertEqual(op.state?.requestedTranslateToArabic, true)
        for _ in 0..<200 where op.state?.running == true { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertNotNil(op.state?.error)
        op.start(projectID: UUID(), title: "C", input: missing, material: material, pairingPath: "", options: PersonalProjectOptions())
        XCTAssertNil(op.state?.error)
        XCTAssertNotEqual(op.state?.id, first)
        XCTAssertEqual(op.state?.requestedTranslateToArabic, false)
        XCTAssertTrue(op.state?.log.contains { $0.text == "Arabic translation requested: OFF" } == true)
        XCTAssertFalse(op.state?.log.contains { $0.text == "Arabic translation requested: ON" } == true)
        for _ in 0..<200 where op.state?.running == true { try await Task.sleep(nanoseconds: 50_000_000) }
    }
}
