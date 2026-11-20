import XCTest
@testable import Mirsa

final class ProjectInstallLogTests: XCTestCase {
    func testLogRecordsOnlyRealStageChanges() {
        var state = PersonalSigningOperation.State(id: UUID(), projectID: UUID())
        XCTAssertEqual(state.log.count, 1)
        XCTAssertTrue(state.apply(.signing(completed: 1, total: 4)))
        let afterSign = state.log.count
        XCTAssertGreaterThan(afterSign, 1)
        XCTAssertFalse(state.apply(.signing(completed: 1, total: 4)))
        XCTAssertEqual(state.log.count, afterSign)
        XCTAssertTrue(state.apply(PersonalSigningEvent(stage: .packaging)))
        XCTAssertGreaterThan(state.log.count, afterSign)
        XCTAssertTrue(state.log.contains { $0.source == "Signer" })
    }
    func testOldThemePreferenceIsIgnored() {
        UserDefaults.standard.set("obsidianGold", forKey: "mirsa.projectDetailsTheme")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "mirsa.projectDetailsTheme"), "obsidianGold")
        UserDefaults.standard.removeObject(forKey: "mirsa.projectDetailsTheme")
    }
}
