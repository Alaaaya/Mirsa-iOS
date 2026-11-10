import XCTest
@testable import Mirsa

final class NoTranslatorFeatureTests: XCTestCase {
    private func read(_ rel: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
    }
    func testToolsHasApprovedSectionsAndNoTranslator() {
        XCTAssertEqual(ToolsTab.Section.allCases.map(\.rawValue), ["tweaks", "create", "device", "pairing"])
    }
    func testNoTranslatorEntrypointsOrCalls() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ios-app")
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("Apps/IPAStringsTranslator.swift").path))
        let e = fm.enumerator(at: root, includingPropertiesForKeys: nil)!
        for case let u as URL in e where u.pathExtension == "swift" {
            let s = try String(contentsOf: u, encoding: .utf8)
            XCTAssertFalse(s.contains("IPAStringsTranslator"), u.lastPathComponent)
            XCTAssertFalse(s.contains("ForgeTranslateView"), u.lastPathComponent)
            XCTAssertFalse(s.contains("\"action\": \"translate\""), u.lastPathComponent)
        }
    }
    func testAppUILanguagesRemain() {
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.rawValue)).count, 4)
    }
}
