import Foundation
import XCTest
@testable import Mirsa

final class ExistingProjectLibrariesTests: XCTestCase {
    private func put(_ value: UInt32, into data: inout Data, at offset: Int) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.replaceSubrange(offset..<offset + 4, with: $0) }
    }
    private func macho(_ paths: [String]) -> Data {
        var data = Data(repeating: 0, count: 4096)
        put(0xfeedfacf, into: &data, at: 0)
        put(0x0100000c, into: &data, at: 4)
        put(2, into: &data, at: 12)
        var offset = 32
        for path in paths {
            let bytes = Array(path.utf8)
            let size = (24 + bytes.count + 1 + 7) & ~7
            put(0xc, into: &data, at: offset)
            put(UInt32(size), into: &data, at: offset + 4)
            put(24, into: &data, at: offset + 8)
            data.replaceSubrange(offset + 24..<offset + 24 + bytes.count, with: bytes)
            offset += size
        }
        put(UInt32(paths.count), into: &data, at: 16)
        put(UInt32(offset - 32), into: &data, at: 20)
        return data
    }
    func testDraftBackwardsCompatibilityAndReset() throws {
        let encoder = JSONEncoder()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(PersonalProjectDraft())) as? [String: Any])
        json.removeValue(forKey: "existingLibraryEdits")
        var draft = try JSONDecoder().decode(PersonalProjectDraft.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(draft.existingLibraryEdits)
        draft.existingLibraryEdits = [ExistingLibraryEdit(owner: "Main", removed: ["@rpath/Foo.dylib"], order: [])]
        XCTAssertEqual(try JSONDecoder().decode(PersonalProjectDraft.self, from: encoder.encode(draft)), draft)
        draft.existingLibraryEdits = nil
        XCTAssertNil(try JSONDecoder().decode(PersonalProjectDraft.self, from: encoder.encode(draft)).existingLibraryEdits)
    }
    func testBackendDiscoveryAndDisposableCopyRemovalPreservesOriginal() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("existing-library-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root.appendingPathComponent("Frameworks"), withIntermediateDirectories: true)
        let load = "@executable_path/Frameworks/Only.dylib"
        let main = root.appendingPathComponent("Main")
        let original = macho([load, "/usr/lib/libSystem.B.dylib"])
        try original.write(to: main)
        try macho([]).write(to: root.appendingPathComponent("Frameworks/Only.dylib"))
        let found = try IPAEditorService.existingLibraries(in: root)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.owner, "Main")
        XCTAssertEqual(found.first?.bundledPath, "Frameworks/Only.dylib")
        XCTAssertEqual(found.first?.provenance, "bundledDependency")
        let copy = root.appendingPathExtension("copy")
        defer { try? fm.removeItem(at: copy) }
        try fm.copyItem(at: root, to: copy)
        var options = PersonalProjectOptions()
        options.existingLibraryEdits = [ExistingLibraryEdit(owner: "Main", removed: [load])]
        try IPAEditorService.run("edit_existing_libraries", input: copy, signingOptions: options)
        XCTAssertTrue(try IPAEditorService.existingLibraries(in: copy).isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: copy.appendingPathComponent("Frameworks/Only.dylib").path))
        XCTAssertEqual(try Data(contentsOf: main), original)
        XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("Frameworks/Only.dylib").path))
    }
    func testLibraryJSONProvenanceDoesNotClaimInjection() throws {
        let json = Data(#"{"id":"Main|@rpath/F.dylib","owner":"Main","loadPath":"@rpath/F.dylib","kind":"weak","bundledPath":null,"provenance":"unresolvedDependency","slices":["100000c:0","100000c:2"]}"#.utf8)
        let lib = try JSONDecoder().decode(ExistingProjectLibrary.self, from: json)
        XCTAssertEqual(lib.slices.count, 2)
        XCTAssertNil(lib.bundledPath)
        XCTAssertEqual(lib.provenance, "unresolvedDependency")
    }
    func testBackendGraphAcceptsThinArm64eWithoutGenericSlice() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("arm64e-graph-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var thin = macho(["@rpath/Arm64eOnly.dylib"])
        put(2, into: &thin, at: 8)
        try thin.write(to: root.appendingPathComponent("Main"))
        let graph = try IPAEditorService.existingLibraries(in: root)
        XCTAssertEqual(graph.map(\.loadPath), ["@rpath/Arm64eOnly.dylib"])
        XCTAssertEqual(graph.first?.slices, ["100000c:2"])
    }

    func testBackendGraphAcceptsUniversalArm64eWithoutGenericSlice() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fat-arm64e-graph-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var thin = macho(["@rpath/UniversalArm64eOnly.dylib"])
        put(2, into: &thin, at: 8)
        var fat = Data(repeating: 0, count: 4096)
        func big(_ value: UInt32, at offset: Int) {
            var be = value.bigEndian
            withUnsafeBytes(of: &be) { fat.replaceSubrange(offset..<offset + 4, with: $0) }
        }
        big(0xcafebabe, at: 0)
        big(1, at: 4)
        big(0x0100000c, at: 8)
        big(2, at: 12)
        big(4096, at: 16)
        big(UInt32(thin.count), at: 20)
        big(12, at: 24)
        fat.append(thin)
        try fat.write(to: root.appendingPathComponent("Main"))
        let graph = try IPAEditorService.existingLibraries(in: root)
        XCTAssertEqual(graph.map(\.loadPath), ["@rpath/UniversalArm64eOnly.dylib"])
        XCTAssertEqual(graph.first?.slices, ["100000c:2"])
    }

}
