import XCTest
@testable import Mirsa

final class ForgePortMapperTests: XCTestCase {
    private func scan(_ c: [String], _ s: [String]) -> ForgePortScan {
        ForgePortScan(version: "1", build: "1", bundleID: "a.b", encrypted: false, classes: Set(c), selectors: Set(s), swiftSymbols: 0)
    }
    func testHooksAndSelectors() {
        let code = "%hook Foo\n- (void)viewDidLoad {\n}\n- (BOOL)a:(int)x b:(id)y {\n}\n%end\n"
        XCTAssertEqual(ForgePortMapper.hooks(in: code)["Foo"], Set(["viewDidLoad", "a:b:"]))
    }
    func testUnambiguousSwiftRename() {
        let code = "%hook _TtC3Old4Card\n%end\n"
        let plan = ForgePortMapper.plan(code: code, old: scan(["_TtC3Old4Card"], []), new: scan(["_TtC3New4Card"], []))
        XCTAssertEqual(plan.mappings, [ForgePortMapping(old: "_TtC3Old4Card", new: "_TtC3New4Card", reason: "exactName")])
    }
    func testAmbiguousIsNotGuessed() {
        let code = "%hook _TtC3Old4Card\n%end\n"
        let plan = ForgePortMapper.plan(code: code, old: scan(["_TtC3Old4Card"], []), new: scan(["_TtC1A4Card", "_TtC1B4Card"], []))
        XCTAssertTrue(plan.mappings.isEmpty)
        XCTAssertEqual(plan.unresolved.first?.candidates.count, 2)
    }
    func testMissingSelectorReportedNotRewritten() {
        let code = "%hook Foo\n- (void)gone {\n}\n%end\n"
        let plan = ForgePortMapper.plan(code: code, old: scan(["Foo"], ["gone"]), new: scan(["Foo"], []))
        XCTAssertEqual(plan.unresolved.map(\.kind), ["selector"])
    }
}
