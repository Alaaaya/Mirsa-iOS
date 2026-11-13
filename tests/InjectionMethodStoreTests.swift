import XCTest
@testable import Mirsa

final class InjectionMethodStoreTests: XCTestCase {
    private let main = "A", ext = "PlugIns/W.appex/W", ext2 = "PlugIns/X.appex/X"
    private let shared = "Frameworks/S.framework/S"
    private let json = """
    {"targets":[{"id":"A","kind":"main","label":"A"},{"id":"PlugIns/W.appex/W","kind":"extension","label":"W"},{"id":"PlugIns/X.appex/X","kind":"extension","label":"X"}],
     "methods":[{"id":"direct","enabled":true,"reason":null},{"id":"bogus","enabled":true,"reason":null}],
     "sharedCandidates":[],"sharedDisabledReason":"shared_unavailable",
     "components":[
      {"id":"t1","methods":[{"id":"direct","enabled":true,"reason":null},{"id":"load_control","enabled":true,"reason":null},{"id":"shared_library","enabled":true,"reason":null},{"id":"separate_extension","enabled":true,"reason":null},{"id":"bogus","enabled":true,"reason":null}],
       "eligibleTargets":{"direct":["A","PlugIns/W.appex/W"],"load_control":["A"],"separate_extension":["PlugIns/W.appex/W","PlugIns/X.appex/X"]},
       "sharedCandidates":[{"id":"Frameworks/S.framework/S","label":"S","processes":["A","PlugIns/W.appex/W"]}]},
      {"id":"t2","methods":[{"id":"direct","enabled":true,"reason":null},{"id":"load_control","enabled":false,"reason":"arm64e"},{"id":"shared_library","enabled":true,"reason":null},{"id":"separate_extension","enabled":true,"reason":null}],
       "eligibleTargets":{"direct":["A"]},"sharedCandidates":[]}
     ]}
    """
    private var caps: InjectionCapabilities { InjectionCapabilities.parse(Data(json.utf8))! }
    private func entry(_ id: String, methods: [String: String]? = nil, target: String? = nil, proc: [String: [String]]? = nil, sh: [String: String]? = nil, legacy: Bool? = nil, caps c: InjectionCapabilities? = nil) throws -> InjectionPlanEntry {
        try InjectionMethodStore.entry(id: id, library: "l", tweakTarget: target, methods: methods, legacyDirect: legacy, processTargets: proc, sharedTargets: sh, caps: c ?? caps)
    }

    func testDefaultCapabilitiesFailClosed() {
        let c = InjectionCapabilities()
        for m in InjectionMethod.allCases { XCTAssertFalse(c.isEnabled(m, component: "t1")); XCTAssertNotNil(c.disabledReason(m, component: "t1")) }
        XCTAssertThrowsError(try entry("t1", methods: ["t1": "direct"], caps: c))
    }
    func testParsePerComponentAndIgnoresUnknownMethod() {
        XCTAssertEqual(caps.components.count, 2)
        XCTAssertEqual(caps.component("t1")?.enabled.count, 4)
        XCTAssertEqual(caps.component("t1")?.eligible(.separate_extension), [ext, ext2])
        XCTAssertEqual(caps.component("t1")?.sharedCandidates.first?.processes, [main, ext])
        XCTAssertEqual(caps.extensionTargets.map(\.id), [ext, ext2])
    }
    func testComponentsDoNotInherit() {
        XCTAssertTrue(caps.isEnabled(.load_control, component: "t1"))
        XCTAssertFalse(caps.isEnabled(.load_control, component: "t2"))
        XCTAssertFalse(caps.isEnabled(.direct, component: "missing"))
        XCTAssertEqual(caps.disabledReason(.load_control, component: "t2"), InjectionCapabilities.reasonText("arm64e"))
    }
    func testBackendEnabledWithoutSelectableThingIsDisabled() {
        // t2 claims shared + separate enabled but has no candidates or extension ids.
        XCTAssertFalse(caps.isEnabled(.shared_library, component: "t2"))
        XCTAssertFalse(caps.isEnabled(.separate_extension, component: "t2"))
    }
    func testGlobalCapsNeverEnableComponent() {
        XCTAssertTrue(caps.enabled.contains(.direct))
        XCTAssertFalse(caps.isEnabled(.direct, component: "other"))
        XCTAssertThrowsError(try entry("other", methods: ["other": "direct"]))
    }
    func testParseGarbageIsNil() { XCTAssertNil(InjectionCapabilities.parse(Data("[]".utf8))) }
    func testLegacyMigration() {
        XCTAssertEqual(InjectionMethodStore.method(for: "a", methods: nil, legacyDirect: false), .load_control)
        XCTAssertEqual(InjectionMethodStore.method(for: "a", methods: nil, legacyDirect: nil), .direct)
        XCTAssertEqual(InjectionMethodStore.method(for: "a", methods: ["a": "direct"], legacyDirect: false), .direct)
        XCTAssertEqual(InjectionMethodStore.method(for: "x", methods: ["a": "direct"], legacyDirect: false), .load_control)
    }
    func testUnconfiguredLegacyDefaultsPreserved() throws {
        let e = try entry("t1", legacy: false)
        XCTAssertEqual(e.method, .load_control); XCTAssertEqual(e.target, main)
        XCTAssertEqual(try entry("t1").method, .direct)
    }
    func testUnknownStoredMethodFailsClosed() {
        XCTAssertNil(InjectionMethodStore.method(for: "t1", methods: ["t1": "future"], legacyDirect: nil))
        XCTAssertThrowsError(try entry("t1", methods: ["t1": "future"])) { XCTAssertEqual($0 as? InjectionMethodStore.PlanError, .unknownMethod("future")) }
    }
    func testDirectTargetMustBeEligibleForComponent() throws {
        XCTAssertEqual(try entry("t1", methods: ["t1": "direct"], target: ext).target, ext)
        XCTAssertThrowsError(try entry("t1", methods: ["t1": "direct"], target: ext2)) { XCTAssertEqual($0 as? InjectionMethodStore.PlanError, .staleTarget(ext2)) }
        XCTAssertThrowsError(try entry("t2", methods: ["t2": "direct"], target: ext))
    }
    func testLoadControlDisabledForComponent() {
        XCTAssertThrowsError(try entry("t2", methods: ["t2": "load_control"])) { XCTAssertEqual($0 as? InjectionMethodStore.PlanError, .unsupported(.load_control)) }
        XCTAssertEqual((try? entry("t1", methods: ["t1": "load_control"]))?.method, .load_control)
    }
    func testSeparateExtensionSelection() throws {
        XCTAssertThrowsError(try entry("t1", methods: ["t1": "separate_extension"])) { XCTAssertEqual($0 as? InjectionMethodStore.PlanError, .missingSelection(.separate_extension)) }
        let e = try entry("t1", methods: ["t1": "separate_extension"], proc: ["t1": [ext, ext2]])
        XCTAssertEqual(e.targets, [ext, ext2])
        XCTAssertThrowsError(try entry("t1", methods: ["t1": "separate_extension"], proc: ["t1": [ext, ext]])) { XCTAssertEqual($0 as? InjectionMethodStore.PlanError, .duplicateProcess(ext)) }
        XCTAssertThrowsError(try entry("t1", methods: ["t1": "separate_extension"], proc: ["t1": ["Payload/gone"]]))
    }
    func testSharedUsesCandidateProcessesNoBasenameInference() throws {
        let e = try entry("t1", methods: ["t1": "shared_library"], sh: ["t1": shared])
        XCTAssertEqual(e.sharedTarget, shared); XCTAssertEqual(e.targets, [main, ext])
        XCTAssertThrowsError(try entry("t1", methods: ["t1": "shared_library"], sh: ["t1": "Payload/other/S"])) { XCTAssertEqual($0 as? InjectionMethodStore.PlanError, .staleTarget("Payload/other/S")) }
        XCTAssertThrowsError(try entry("t1", methods: ["t1": "shared_library"]))
    }
    func testStaleCapabilitiesRejectAfterReloadEmpties() {
        XCTAssertThrowsError(try entry("t1", methods: ["t1": "separate_extension"], proc: ["t1": [ext]], caps: InjectionCapabilities()))
    }
    func testPlanEntryJSONOmitsEmptyOptionals() throws {
        let e = try entry("t1", methods: ["t1": "direct"])
        let s = String(data: try JSONEncoder().encode(e), encoding: .utf8)!
        XCTAssertTrue(s.contains("direct")); XCTAssertFalse(s.contains("sharedTarget"))
    }

    func testSharedCandidatesWithSameBinaryRequireDistinctProcessSelection() throws {
        var c = caps
        let other = SharedCandidate(id: shared, label: "S", processes: [main, ext2])
        c.components["t1"]?.sharedCandidates.append(other)
        XCTAssertThrowsError(try entry("t1", methods: ["t1": "shared_library"], sh: ["t1": shared], caps: c))
        let e = try entry("t1", methods: ["t1": "shared_library"], sh: ["t1": other.selectionID], caps: c)
        XCTAssertEqual(e.sharedTarget, shared)
        XCTAssertEqual(e.targets, [main, ext2])
        XCTAssertNotEqual(c.components["t1"]?.sharedCandidates.first?.selectionID, other.selectionID)
    }
    func testOptionalMainWithSeparateExtensionRequiresAnExtensionToo() throws {
        let e = try entry("t1", methods: ["t1": "separate_extension"], proc: ["t1": [main, ext]])
        XCTAssertEqual(e.targets, [main, ext])
        XCTAssertThrowsError(try entry("t1", methods: ["t1": "separate_extension"], proc: ["t1": [main]]))
    }
    func testLoadControlUsesOnlyVerifiedSelectedProcess() throws {
        var c = caps
        c.components["t1"]?.eligibleTargets[.load_control] = [ext]
        XCTAssertEqual(try entry("t1", methods: ["t1": "load_control"], target: ext, caps: c).target, ext)
        XCTAssertThrowsError(try entry("t1", methods: ["t1": "load_control"], caps: c))
    }
}
