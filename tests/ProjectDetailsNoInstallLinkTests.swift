import XCTest
@testable import Mirsa

final class ProjectDetailsNoInstallLinkTests: XCTestCase {
    private func src(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("ios-app/Apps/" + name), encoding: .utf8)
    }
    func testDetailsDoesNotRenderInstallLinkCardInAnyLocale() throws {
        let s = try src("PersonalProjectDetailView.swift")
        XCTAssertFalse(s.contains("MirsaProjectInstallLink"))
        XCTAssertFalse(s.contains("رابط تثبيت"))
        XCTAssertFalse(s.lowercased().contains("48-hour install"))
        XCTAssertFalse(s.contains("QR"))
    }
    func testDetailsUsesSharedIconResolver() throws {
        let s = try src("PersonalProjectDetailView.swift")
        XCTAssertTrue(s.contains("library.icon(for: app)"))
        XCTAssertTrue(s.contains("library.ensureIcon(for: app)"))
        XCTAssertFalse(s.contains("UIImage(named"))
    }
}
