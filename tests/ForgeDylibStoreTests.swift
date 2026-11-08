import XCTest
@testable import Mirsa

@MainActor final class ForgeDylibStoreTests: XCTestCase {
    private func info(_ n: Int = 1) -> ForgeDylibInfo {
        ForgeDylibInfo(arch: "arm64", size: 10, linked: [], classes: ["A"], selectors: [], summary: String(repeating: "x", count: 9000))
    }
    private func project() -> (ForgeStore, UUID) {
        let s = ForgeStore.shared; let id = UUID()
        var p = ForgeProject(id: id, name: "D" + id.uuidString.prefix(4), bundleID: "x.y", appName: "D", appVersion: "1", executable: "D", classes: [])
        let orig = ForgeVersion(prompt: "orig", code: "c", settings: [], explain: ""); p.versions = [orig]; p.current = orig.id
        s.projects.append(p); return (s, id)
    }
    private func tmp() throws -> URL { let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dylib"); try Data("d".utf8).write(to: u); return u }
    func testImportKeepsOriginalAndIsDisabled() throws {
        let (s, id) = project()
        try s.importDylib(id, dylib: try tmp(), info: info(), name: "N")
        let p = s.project(id)!
        XCTAssertEqual(p.versions.count, 2); XCTAssertEqual(p.versions[0].code, "c")
        XCTAssertEqual(p.versions[1].importEnabled, false)
        XCTAssertTrue(ForgeStore.enabledImported(p).isEmpty)
    }
    func testEnableAndOrderAndDisabledExclusion() throws {
        let (s, id) = project()
        for n in ["A", "B", "C"] { try s.importDylib(id, dylib: try tmp(), info: info(), name: n) }
        var p = s.project(id)!
        let ids = p.versions.filter { $0.importedInfo != nil }.map { $0.id }
        s.setImportedEnabled(id, ids[0], true); s.setImportedEnabled(id, ids[2], true)
        XCTAssertEqual(ForgeStore.enabledImported(s.project(id)!).compactMap { $0.title }, ["A", "C"])
        s.moveImported(id, ids[2], by: -2)
        p = s.project(id)!
        XCTAssertEqual(ForgeStore.enabledImported(p).compactMap { $0.title }, ["C", "A"])
        s.moveImported(id, ids[2], by: -1) // already first: no change
        XCTAssertEqual(ForgeStore.enabledImported(s.project(id)!).compactMap { $0.title }, ["C", "A"])
    }
}
