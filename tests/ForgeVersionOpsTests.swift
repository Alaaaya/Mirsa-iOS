import XCTest
@testable import Mirsa

@MainActor final class ForgeVersionOpsTests: XCTestCase {
    private func make(_ n: Int) throws -> (ForgeStore, UUID, [UUID]) {
        let store = ForgeStore.shared
        let id = UUID()
        var p = ForgeProject(id: id, name: "T" + id.uuidString.prefix(4), bundleID: "x.y", appName: "T", appVersion: "1", executable: "T", classes: [])
        var ids: [UUID] = []
        for i in 0..<n { let v = ForgeVersion(prompt: "p\(i)", code: "c\(i)", settings: [], explain: ""); p.versions.append(v); ids.append(v.id) }
        p.current = ids.last
        store.projects.append(p)
        for v in p.versions { try? Data("x".utf8).write(to: store.dylibURL(p, v)) }
        return (store, id, ids)
    }
    func testActiveDeleteFallsBackToPrevious() throws {
        let (s, id, ids) = try make(3)
        try s.deleteVersion(id, ids[2])
        XCTAssertEqual(s.project(id)?.current, ids[1]); XCTAssertEqual(s.project(id)?.versions.count, 2)
    }
    func testFirstActiveFallsBackToNext() throws {
        let (s, id, ids) = try make(2); s.revert(id, to: ids[0])
        try s.deleteVersion(id, ids[0]); XCTAssertEqual(s.project(id)?.current, ids[1])
    }
    func testLastVersionKeepsProject() throws {
        let (s, id, ids) = try make(1)
        try s.deleteVersion(id, ids[0])
        XCTAssertNotNil(s.project(id)); XCTAssertTrue(s.project(id)!.versions.isEmpty); XCTAssertNil(s.project(id)?.currentVersion)
    }
    func testDeleteRemovesOnlyOwnFile() throws {
        let (s, id, ids) = try make(2); let p = s.project(id)!
        try s.deleteVersion(id, ids[0])
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.dylibURL(p, p.versions[0]).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.dylibURL(p, p.versions[1]).path))
    }
    func testNonActiveDeleteKeepsCurrentAndMissingIDIsNoop() throws {
        let (s, id, ids) = try make(3)
        try s.deleteVersion(id, ids[0]); XCTAssertEqual(s.project(id)?.current, ids[2])
        try s.deleteVersion(id, UUID()); XCTAssertEqual(s.project(id)?.versions.count, 2)
    }
    func testEditCodeCreatesNewVersionKeepsOriginal() throws {
        let (s, id, ids) = try make(1)
        s.editVersionCode(id, ids[0], code: "new")
        let p = s.project(id)!
        XCTAssertEqual(p.versions.count, 2); XCTAssertEqual(p.versions[0].code, "c0"); XCTAssertEqual(p.currentVersion?.code, "new")
    }
    func testRename() throws {
        let (s, id, ids) = try make(1)
        s.renameVersion(id, ids[0], to: " Hi "); XCTAssertEqual(s.project(id)?.versions[0].title, "Hi")
        s.renameVersion(id, ids[0], to: " "); XCTAssertNil(s.project(id)?.versions[0].title)
    }
}
