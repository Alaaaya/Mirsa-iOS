import XCTest
@testable import Mirsa

final class CertificateParity29Tests: XCTestCase {
    private var library: ExistingProjectLibrary {
        ExistingProjectLibrary(id: "Main|@rpath/Tweak.dylib", owner: "Main", loadPath: "@rpath/Tweak.dylib", kind: "load", bundledPath: "Frameworks/Tweak.dylib", provenance: "bundledDependency", slices: ["100000c:0"])
    }
    func testNewDefaultsAndSavedInjectionChoices() throws {
        let draft = PersonalProjectDraft()
        XCTAssertEqual(draft.directInjection, false)
        XCTAssertEqual(InjectionMethodStore.method(for: "x", methods: nil, legacyDirect: draft.directInjection), .load_control)
        XCTAssertTrue(PersonalProjectOptions().useLoader)
        XCTAssertTrue(draft.fileSharing)
        XCTAssertFalse(draft.removeEmbeddedProfile)
        var saved = draft
        saved.directInjection = true; saved.fileSharing = false
        let restored = try JSONDecoder().decode(PersonalProjectDraft.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(restored.directInjection, true)
        XCTAssertFalse(restored.fileSharing)
        XCTAssertEqual(InjectionMethodStore.method(for: "x", methods: ["x": "direct"], legacyDirect: false), .direct)
    }
    func testLegacyPlanDecodesAndDisableIsDistinctFromDelete() throws {
        let legacy = Data(#"{"owner":"Main","removed":[],"order":[]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ExistingLibraryEdit.self, from: legacy).disabled)
        let disabled = ExistingLibraryPlan.toggleDisabled(library, in: [])
        XCTAssertTrue(ExistingLibraryPlan.isDisabled(library, in: disabled))
        XCTAssertTrue(disabled[0].removed.isEmpty)
        let decoded = try JSONDecoder().decode([ExistingLibraryEdit].self, from: JSONEncoder().encode(disabled))
        XCTAssertEqual(decoded, disabled)
        let removed = ExistingLibraryPlan.toggleRemoved(library, in: disabled)
        XCTAssertFalse(ExistingLibraryPlan.isDisabled(library, in: removed))
        XCTAssertEqual(removed[0].removed, [library.loadPath])
        XCTAssertTrue(ExistingLibraryPlan.toggleDisabled(library, in: disabled).isEmpty)
    }
    func testMovingPreservesDisabledChoice() {
        let other = ExistingProjectLibrary(id: "Main|@rpath/Other.dylib", owner: "Main", loadPath: "@rpath/Other.dylib", kind: "load", bundledPath: "Frameworks/Other.dylib", provenance: "bundledDependency", slices: [])
        let plan = ExistingLibraryPlan.toggleDisabled(library, in: [])
        let moved = ExistingLibraryPlan.move(other, by: -1, libs: [library, other], in: plan)
        XCTAssertTrue(ExistingLibraryPlan.isDisabled(library, in: moved))
        XCTAssertFalse(ExistingLibraryPlan.provenanceLabel(other).contains("LoadControl"))
    }
    func testRuntimeProvenanceRequiresBackendVerificationNotFilename() {
        let runtime = ExistingProjectLibrary(id: "runtime|A.dylib", owner: "Frameworks/MirsaLoadOrder.txt", loadPath: "A.dylib", kind: "runtime", bundledPath: "Frameworks/A.dylib", provenance: "verifiedMirsaRuntime", slices: [])
        XCTAssertTrue(ExistingLibraryPlan.isVerifiedRuntime(runtime))
        let arbitrary = ExistingProjectLibrary(id: "fake", owner: "Main", loadPath: "@rpath/MirsaLoader.dylib", kind: "load", bundledPath: "Frameworks/MirsaLoader.dylib", provenance: "bundledDependency", slices: [])
        XCTAssertFalse(ExistingLibraryPlan.isVerifiedRuntime(arbitrary))
        XCTAssertFalse(ExistingLibraryPlan.isVerifiedRuntime(library))
        let disabled = ExistingLibraryPlan.toggleDisabled(runtime, in: [])
        XCTAssertTrue(ExistingLibraryPlan.isDisabled(runtime, in: disabled))
        XCTAssertEqual(disabled.first?.owner, "Frameworks/MirsaLoadOrder.txt")
    }

}
