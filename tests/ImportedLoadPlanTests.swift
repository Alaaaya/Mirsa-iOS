import XCTest
@testable import Mirsa

final class ImportedLoadPlanTests: XCTestCase {
    private func entry(_ owner: String, _ path: String, slice: Int = 0) -> ImportedLoad {
        ImportedLoad(owner: owner, mainOwner: owner == "Main", slice: slice, subtype: 0,
                     loadPath: path, weak: false, resolvedPath: nil)
    }

    func testRemovalIsPerOwnerAndResetRestoresOriginalWithoutMutation() {
        let entries = [entry("Main", "@rpath/Shared"), entry("Main", "@rpath/Shared", slice: 1),
                       entry("Main", "@rpath/Other"), entry("Frameworks/Vendor.framework/Vendor", "@rpath/Shared")]
        let edits = ImportedLoadPlan.removing("@rpath/Shared", owner: "Main", entries: entries, edits: [])
        XCTAssertEqual(edits.first?.remove, ["@rpath/Shared"])
        XCTAssertEqual(ImportedLoadPlan.paths(owner: "Main", entries: entries, edits: edits), ["@rpath/Other"])
        XCTAssertEqual(ImportedLoadPlan.paths(owner: "Frameworks/Vendor.framework/Vendor", entries: entries, edits: edits), ["@rpath/Shared"])
        XCTAssertEqual(ImportedLoadPlan.paths(owner: "Main", entries: entries, edits: []), ["@rpath/Shared", "@rpath/Other"])
        XCTAssertEqual(entries.count, 4)
    }

    func testReorderThenRemoveProducesCompleteRemainingOrder() throws {
        let entries = [entry("Main", "A"), entry("Main", "B"), entry("Main", "C")]
        let moved = ImportedLoadPlan.moving("B", by: -1, owner: "Main", entries: entries, edits: [])
        XCTAssertEqual(moved.first?.order, ["B", "A", "C"])
        let removed = ImportedLoadPlan.removing("A", owner: "Main", entries: entries, edits: moved)
        XCTAssertEqual(removed.first?.order, ["B", "C"])
        XCTAssertEqual(removed.first?.remove, ["A"])
        let restored = try JSONDecoder().decode([ImportedLoadEdit].self, from: JSONEncoder().encode(removed))
        XCTAssertEqual(restored, removed)
        XCTAssertEqual(ImportedLoadPlan.paths(owner: "Main", entries: entries, edits: restored), ["B", "C"])
    }

    func testOutOfBoundsAndUnknownChangesAreNoOps() {
        let entries = [entry("Main", "A")]
        XCTAssertEqual(ImportedLoadPlan.moving("A", by: -1, owner: "Main", entries: entries, edits: []), [])
        XCTAssertEqual(ImportedLoadPlan.moving("A", by: 1, owner: "Main", entries: entries, edits: []), [])
        XCTAssertEqual(ImportedLoadPlan.removing("unknown", owner: "Main", entries: entries, edits: []), [])
        XCTAssertEqual(ImportedLoadPlan.removing("A", owner: "../outside", entries: entries, edits: []), [])
    }

    func testMissingOrMixedCapabilitiesRemainReadOnly() {
        let original = entry("Main", "A")
        XCTAssertFalse(ImportedLoadPlan.canEdit(owner: "Main", entries: [original]))
        var supported = original
        supported.editable = true
        XCTAssertTrue(ImportedLoadPlan.canEdit(owner: "Main", entries: [supported]))
        XCTAssertFalse(ImportedLoadPlan.canEdit(owner: "Main", entries: [supported, original]))
        XCTAssertFalse(ImportedLoadPlan.canEdit(owner: "Missing", entries: [supported]))
    }

    func testContractDecodesNullableUnresolvedAndSnakeCase() throws {
        let data = Data(#"{"version":1,"entries":[{"owner":"Main","main_owner":true,"slice":0,"subtype":2,"load_path":"@rpath/Vendor","weak":true,"resolved_path":null}],"warning":"retained"}"#.utf8)
        let report = try JSONDecoder().decode(ImportedLoadReport.self, from: data)
        XCTAssertTrue(report.entries[0].mainOwner)
        XCTAssertNil(report.entries[0].resolvedPath)
        XCTAssertTrue(report.entries[0].weak)
    }
}
