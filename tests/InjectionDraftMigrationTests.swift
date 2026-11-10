import XCTest
@testable import Mirsa

final class InjectionDraftMigrationTests: XCTestCase {
    func testOldDraftWithoutNewFieldsKeepsLegacyMethodAndTargets() throws {
        var original = PersonalProjectDraft()
        original.name = "Original app"
        original.directInjection = false
        original.tweakTargets = ["one:path": "PlugIns/Widget.appex/Widget"]
        original.componentOrder = ["one:path", "two:path"]
        let encoded = try JSONEncoder().encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["injectionMethods", "injectionProcessTargets", "injectionSharedTargets"] { json.removeValue(forKey: key) }
        let migrated = try JSONDecoder().decode(PersonalProjectDraft.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(migrated.injectionMethods)
        XCTAssertNil(migrated.injectionProcessTargets)
        XCTAssertNil(migrated.injectionSharedTargets)
        XCTAssertEqual(migrated.tweakTargets, original.tweakTargets)
        XCTAssertEqual(migrated.componentOrder, original.componentOrder)
        XCTAssertEqual(InjectionMethodStore.method(for: "one:path", methods: migrated.injectionMethods, legacyDirect: migrated.directInjection), .load_control)
    }

    func testPerComponentSelectionsAndOrderSurviveRelaunchWithoutCrossProjectChanges() throws {
        var draft = PersonalProjectDraft()
        draft.injectionMethods = ["one:path": "shared_library", "two:path": "separate_extension"]
        draft.injectionSharedTargets = ["one:path": "Frameworks/Common.dylib"]
        draft.injectionProcessTargets = ["two:path": ["Main", "PlugIns/Widget.appex/Widget"]]
        draft.componentOrder = ["two:path", "one:path"]
        let restored = try JSONDecoder().decode(PersonalProjectDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored, draft)
        var anotherProject = restored
        anotherProject.injectionMethods?["one:path"] = "direct"
        XCTAssertEqual(restored.injectionMethods?["one:path"], "shared_library")
        XCTAssertEqual(anotherProject.injectionMethods?["two:path"], "separate_extension")
        XCTAssertEqual(restored.componentOrder, ["two:path", "one:path"])
    }

    func testUnknownPersistedMethodRemainsInvalidAfterRoundTrip() throws {
        var draft = PersonalProjectDraft()
        draft.injectionMethods = ["one:path": "future_unsupported"]
        let restored = try JSONDecoder().decode(PersonalProjectDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored.injectionMethods?["one:path"], "future_unsupported")
        XCTAssertNil(InjectionMethodStore.method(for: "one:path", methods: restored.injectionMethods, legacyDirect: true))
    }
}
