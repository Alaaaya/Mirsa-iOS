import XCTest
@testable import Mirsa

@MainActor final class ForgeEntryDeleteTests: XCTestCase {
    func testPickNamePrefersDisplayName() {
        XCTAssertEqual(ForgeStore.pickName(["CFBundleDisplayName": "Lyfta", "CFBundleName": "Old"]), "Lyfta")
        XCTAssertEqual(ForgeStore.pickName(["CFBundleDisplayName": " ", "CFBundleName": "Name"]), "Name")
        XCTAssertNil(ForgeStore.pickName([:]))
    }
    func testDeleteRemovesFolderAndEntry() throws {
        let store = ForgeStore.shared
        let id = try makeProject(store)
        let folder = ForgeStore.root.appendingPathComponent(id.uuidString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        try store.delete(id)
        XCTAssertNil(store.project(id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        let data = try Data(contentsOf: ForgeStore.root.appendingPathComponent("projects.json"))
        XCTAssertFalse(try JSONDecoder().decode([ForgeProject].self, from: data).contains { $0.id == id })
    }
    func testDeleteFailureKeepsEntry() throws {
        let store = ForgeStore.shared
        let id = try makeProject(store)
        let folder = ForgeStore.root.appendingPathComponent(id.uuidString)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: ForgeStore.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ForgeStore.root.path); try? store.delete(id) }
        XCTAssertThrowsError(try store.delete(id))
        XCTAssertNotNil(store.project(id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }
    func testResolveNamePrefersLiveMetadataOverSnapshot() {
        let n = ForgeStore.resolveName(bundleID: "a.b", drafts: [("a.b", "Draft")], library: [("a.b", "Lib")], managed: [("a.b", "Mgd")], downloads: [])
        XCTAssertEqual(n, "Draft")
        XCTAssertEqual(ForgeStore.resolveName(bundleID: "a.b", drafts: [("a.b", " ")], library: [("x", "No")], managed: [("a.b", "Mgd")], downloads: []), "Mgd")
        XCTAssertNil(ForgeStore.resolveName(bundleID: "a.b", drafts: [], library: [], managed: [], downloads: []))
    }
    func testConfirmationTextsAllLanguages() {
        XCTAssertFalse(forgeDeleteFailed("X").isEmpty)
        XCTAssertTrue(forgeDeleteMessage("X").contains("X"))
        XCTAssertFalse(forgeDeleteTitle.isEmpty)
    }
    private func makeProject(_ store: ForgeStore) throws -> UUID {
        let ipa = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        try Data([1, 2, 3]).write(to: ipa)
        let info = ForgeStore.TargetInfo(name: "T", bundleID: "com.test.x", appName: "T", version: "1", executable: "T", classes: ["A"])
        return try store.create(ipa: ipa, info: info)
    }
}
