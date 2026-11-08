import XCTest
@testable import Mirsa

@MainActor final class ForgeFixInboxTests: XCTestCase {
    private func fixture(tweak: UUID = UUID(), bundle: String = "com.test.app", fix: UUID = UUID()) throws -> (ForgeFixItem, Data, ForgeProject) {
        var bytes = Data([0xCF,0xFA,0xED,0xFE]); bytes.append(Data(repeating: 0x01, count: 2048))
        let code = "%hook UIView\n- (void)layoutSubviews { %orig; }\n%end"
        let obj: [String: Any] = ["id": fix.uuidString, "tweakID": tweak.uuidString, "bundleID": bundle,
            "name": "Test", "version": 1, "code": code, "settings": [],
            "sourceSHA256": ForgeFixItem.sha(Data(code.utf8)), "dylibSHA256": ForgeFixItem.sha(bytes),
            "dylibBytes": bytes.count, "createdAt": "2026-11-08T15:00:00Z", "requiresReview": true, "autoEnable": false]
        let item = try JSONDecoder().decode(ForgeFixItem.self, from: JSONSerialization.data(withJSONObject: obj))
        let original = ForgeVersion(id: tweak, prompt: "Original", code: "original", settings: [], explain: "")
        let project = ForgeProject(name: "Test", bundleID: bundle, appName: "Test", appVersion: "1", executable: "Test", classes: [], versions: [original], current: original.id, values: ["enabled": false])
        return (item, bytes, project)
    }
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    func testDurableImportPreservesSelectionOriginalAndValues() throws {
        let (item, bytes, project) = try fixture()
        let root = try root()
        let saved = try ForgeFixPersistence.commit(item, bytes: bytes, projects: [project], root: root)
        XCTAssertEqual(saved[0].versions.count, 2)
        XCTAssertEqual(saved[0].versions[0], project.versions[0])
        XCTAssertEqual(saved[0].current, project.current)
        XCTAssertEqual(saved[0].values, project.values)
        XCTAssertEqual(saved[0].versions[1].tweakID, item.tweakID)
        XCTAssertEqual(saved[0].versions[1].fixDylibSHA256, item.dylibSHA256)
        let disk = try JSONDecoder().decode([ForgeProject].self, from: Data(contentsOf: root.appendingPathComponent("projects.json")))
        XCTAssertEqual(disk[0].versions, saved[0].versions)
    }
    func testLegacyMissingOrStaleSelectionNeverSelectsImportedFix() throws {
        let (item, bytes, original) = try fixture()
        for selection in [nil, UUID()] as [UUID?] {
            var project = original
            project.current = selection
            let previous = project.currentVersion?.id
            let saved = try ForgeFixPersistence.commit(item, bytes: bytes, projects: [project], root: root())
            XCTAssertEqual(saved[0].current, selection)
            XCTAssertEqual(saved[0].currentVersion?.id, previous)
        }
    }
    func testReplayAfterRelaunchAndMissingFileRestoresWithoutDuplicate() throws {
        let (item, bytes, project) = try fixture()
        let root = try root()
        _ = try ForgeFixPersistence.commit(item, bytes: bytes, projects: [project], root: root)
        let disk = try JSONDecoder().decode([ForgeProject].self, from: Data(contentsOf: root.appendingPathComponent("projects.json")))
        let library = root.appendingPathComponent(project.id.uuidString).appendingPathComponent(project.name + "-" + item.id.uuidString.prefix(8) + ".dylib")
        try FileManager.default.removeItem(at: library)
        let retry = try ForgeFixPersistence.commit(item, bytes: bytes, projects: disk, root: root)
        XCTAssertEqual(retry[0].versions.count, 2)
        XCTAssertEqual(try Data(contentsOf: library), bytes)
    }
    func testOrphanLibraryBeforeIndexCommitIsRetrySafe() throws {
        let (item, bytes, project) = try fixture()
        let root = try root()
        let index = root.appendingPathComponent("projects.json")
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: true)
        XCTAssertThrowsError(try ForgeFixPersistence.commit(item, bytes: bytes, projects: [project], root: root))
        XCTAssertEqual(project.versions.count, 1)
        try FileManager.default.removeItem(at: index)
        let retry = try ForgeFixPersistence.commit(item, bytes: bytes, projects: [project], root: root)
        XCTAssertEqual(retry[0].versions.count, 2)
    }
    func testRejectsForeignTweakBundleAndAmbiguousProject() throws {
        let (item, bytes, project) = try fixture()
        let root = try root()
        var foreign = project
        foreign.bundleID = "com.wrong.app"
        XCTAssertThrowsError(try ForgeFixPersistence.commit(item, bytes: bytes, projects: [foreign], root: root))
        foreign = project
        foreign.versions[0].id = UUID()
        XCTAssertThrowsError(try ForgeFixPersistence.commit(item, bytes: bytes, projects: [foreign], root: root))
        foreign = project; foreign.id = UUID()
        XCTAssertThrowsError(try ForgeFixPersistence.commit(item, bytes: bytes, projects: [project, foreign], root: root))
    }
    func testTamperedBytesSourceMetadataAndConflictingReplayRejected() throws {
        let (item, bytes, project) = try fixture()
        var corrupt = bytes; corrupt[20] ^= 1
        XCTAssertThrowsError(try item.validateLibrary(corrupt))
        XCTAssertThrowsError(try item.validateLibrary(bytes.dropLast()))
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as! [String: Any]
        for change in [["code": "different source"] as [String: Any], ["autoEnable": true], ["requiresReview": false], ["dylibBytes": 0], ["sourceSHA256": "../evil"]] {
            let altered = obj.merging(change) { _, new in new }
            let bad = try JSONDecoder().decode(ForgeFixItem.self, from: JSONSerialization.data(withJSONObject: altered))
            XCTAssertThrowsError(try bad.validate())
        }
        obj["id"] = project.versions[0].id.uuidString
        let conflict = try JSONDecoder().decode(ForgeFixItem.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertThrowsError(try ForgeFixPersistence.commit(conflict, bytes: bytes, projects: [project], root: root()))
    }
    func testSanitizedReportCannotContainPrivatePayloadAndIsBounded() {
        let raw = "Bearer TOPSECRET\nerror: /private/var/mobile/user/secret.swift\nname@example.com\nUDID abcdef123456\nUIAlertView user text\ncrash memory layout recursion\n" + String(repeating: "secret", count: 50000)
        let clean = ForgeFixDiagnostic.sanitized(raw, kind: "crash")
        for secret in ["TOPSECRET", "/private", "example.com", "abcdef", "UIAlertView", "user text"] { XCTAssertFalse(clean.contains(secret)) }
        XCTAssertLessThan(clean.utf8.count, 512)
        XCTAssertTrue(clean.contains("memory"))
        XCTAssertTrue(clean.contains("layout"))
    }
    func testUserBindingRejectsAnonApiKeyAndMissingSubject() throws {
        XCTAssertThrowsError(try ForgeClient.fixUserID("public-anon-key"))
        func jwt(_ body: [String: String]) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: body)
            return "head." + data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") + ".signature"
        }
        XCTAssertThrowsError(try ForgeClient.fixUserID(jwt(["role": "anon"])))
        let user = UUID()
        XCTAssertEqual(try ForgeClient.fixUserID(jwt(["role": "authenticated", "sub": user.uuidString])), user)
    }
    final class FakeStore: ForgeFixSecretStore {
        var items: [String: Data] = [:]; var readError: Int32?; var addError: Int32?; var raceToken: Data?; var adds = 0
        func read(service: String, account: String) throws -> Data? {
            if let e = readError { throw ForgeFixStoreError(status: e) }
            return items[service + account]
        }
        func add(service: String, account: String, data: Data) throws -> Bool {
            if let e = addError { throw ForgeFixStoreError(status: e) }
            adds += 1
            if let race = raceToken { items[service + account] = race; return false }
            if items[service + account] != nil { return false }
            items[service + account] = data; return true
        }
    }
    func testKeychainProvisioningStableAcrossRetryAndScopedToUser() throws {
        let store = FakeStore(); let user = UUID(), device = UUID().uuidString.lowercased()
        let token = try ForgeFixKeychain.token(user: user, device: device, store: store)
        XCTAssertEqual(token.count, 64)
        XCTAssertEqual(try ForgeFixKeychain.token(user: user, device: device, store: store), token)
        XCTAssertEqual(store.adds, 1)
        XCTAssertNotEqual(try ForgeFixKeychain.token(user: UUID(), device: device, store: store), token)
    }
    func testKeychainConcurrentDuplicateCorruptAndUnavailableFailClosed() throws {
        let user = UUID(), device = "dev"
        let race = FakeStore(); race.raceToken = Data(String(repeating: "ab", count: 32).utf8)
        XCTAssertEqual(try ForgeFixKeychain.token(user: user, device: device, store: race), String(repeating: "ab", count: 32))
        let corrupt = FakeStore(); corrupt.items[ForgeFixKeychain.service + user.uuidString.lowercased() + ".dev"] = Data("nothex".utf8)
        XCTAssertThrowsError(try ForgeFixKeychain.token(user: user, device: device, store: corrupt))
        XCTAssertEqual(corrupt.adds, 0)
        let down = FakeStore(); down.readError = -34018
        XCTAssertThrowsError(try ForgeFixKeychain.token(user: user, device: device, store: down)) { XCTAssertTrue($0.localizedDescription.contains("-34018")) }
        XCTAssertEqual(down.adds, 0)
        let noAdd = FakeStore(); noAdd.addError = -25291
        XCTAssertThrowsError(try ForgeFixKeychain.token(user: user, device: device, store: noAdd))
        XCTAssertThrowsError(try ForgeFixKeychain.token(user: user, device: device, store: FakeStore(), random: { Data([1]) }))
    }
    func testNoConsentFailsBeforeAnyNetworkOrProvisioning() async {
        do {
            try await ForgeStore.shared.sendFixReport(projectID: UUID(), versionID: UUID(), kind: "crash", diagnostic: "secret", consent: false, reportID: UUID())
            XCTFail("Must require consent")
        } catch { XCTAssertTrue(error.localizedDescription.contains("consent")) }
    }
}
