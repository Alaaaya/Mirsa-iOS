import XCTest
import SwiftUI
@testable import Mirsa

@MainActor
final class ExistingProjectLibrariesUITests: XCTestCase {
    private func lib(_ owner: String, _ path: String, bundled: Bool = true) -> ExistingProjectLibrary {
        ExistingProjectLibrary(id: owner + "|" + path, owner: owner, loadPath: path, kind: "load",
                               bundledPath: bundled ? "Frameworks/" + path : nil,
                               provenance: bundled ? "bundledDependency" : "unresolvedDependency", slices: ["arm64"])
    }
    private var libs: [ExistingProjectLibrary] {
        [lib("App", "@rpath/A.framework/A"), lib("App", "@rpath/B.framework/B"), lib("App", "@rpath/C.dylib", bundled: false),
         lib("Frameworks/A.framework/A", "@rpath/D.dylib")]
    }

    func testProvenanceMainVersusFramework() {
        XCTAssertEqual(ExistingLibraryPlan.provenanceLabel(libs[0]), tr("Via main executable", "عبر الملف الرئيسي", ckb: "لە ڕێگەی فایلی سەرەکییەوە", kmr: "Bi riya pelê sereke"))
        XCTAssertTrue(ExistingLibraryPlan.provenanceLabel(libs[3]).hasSuffix("A.framework"))
        XCTAssertNotEqual(ExistingLibraryPlan.stateLabel(libs[0]), ExistingLibraryPlan.stateLabel(libs[2]))
    }

    func testRemoveRestoreMoveReset() {
        var edits: [ExistingLibraryEdit] = []
        edits = ExistingLibraryPlan.toggleRemoved(libs[1], in: edits)
        XCTAssertEqual(edits, [ExistingLibraryEdit(owner: "App", removed: ["@rpath/B.framework/B"], order: [])])
        edits = ExistingLibraryPlan.move(libs[2], by: -1, libs: libs, in: edits)
        let e = ExistingLibraryPlan.effective(libs, owner: "App", edits: edits)
        XCTAssertEqual(e.map(\.lib.loadPath), ["@rpath/A.framework/A", "@rpath/C.dylib", "@rpath/B.framework/B"].sorted { a, b in
            ["@rpath/A.framework/A", "@rpath/C.dylib", "@rpath/B.framework/B"].firstIndex(of: a)! < ["@rpath/A.framework/A", "@rpath/C.dylib", "@rpath/B.framework/B"].firstIndex(of: b)! })
        XCTAssertEqual(e.last?.removed, true)
        edits = ExistingLibraryPlan.toggleRemoved(libs[1], in: edits)   // restore
        XCTAssertTrue(edits.allSatisfy { $0.removed.isEmpty })
        XCTAssertTrue(ExistingLibraryPlan.reset().isEmpty)
    }

    func testUnresolvedStateWording() {
        for l in [AppLanguage.english, .arabic, .sorani, .kurmanji] {
            AppLanguageStore.shared.set(l)
            XCTAssertFalse(ExistingLibraryPlan.stateLabel(libs[2]).isEmpty)
        }
        AppLanguageStore.shared.set(.english)
        XCTAssertEqual(ExistingLibraryPlan.stateLabel(libs[2]), "Location unresolved")
        AppLanguageStore.shared.set(.arabic)
    }

    func testMoveAtEdgeIsNoOp() {
        XCTAssertTrue(ExistingLibraryPlan.move(libs[0], by: -1, libs: libs, in: []).isEmpty)
    }

    func testWarningAndExplainerFourLanguagesNonEmpty() {
        for l in [AppLanguage.english, .arabic, .sorani, .kurmanji] {
            AppLanguageStore.shared.set(l)
            XCTAssertFalse(ExistingLibraryPlan.removeWarning().isEmpty)
            XCTAssertFalse(ExistingLibraryPlan.explainer().isEmpty)
        }
        AppLanguageStore.shared.set(.arabic)
    }

    private func render<V: View>(_ view: V, name: String, height: CGFloat) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: height)
        let host = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: "ar")).environment(\.layoutDirection, .leftToRight))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 600_000_000)
        let img = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        XCTAssertGreaterThan(img.size.width, 0)
        let att = XCTAttachment(image: img); att.name = name; att.lifetime = .keepAlways; add(att)
    }

    func testArabicSnapshotExistingLibrariesCard() async throws {
        AppLanguageStore.shared.set(.arabic)
        struct Host: View {
            let libs: [ExistingProjectLibrary]
            @State var edits = [ExistingLibraryEdit(owner: "App", removed: ["@rpath/B.framework/B"])]
            var body: some View { ExistingLibrariesCard(libraries: libs, edits: $edits).padding().background(Color.black) }
        }
        let more = libs + [lib("Frameworks/B.framework/B", "@rpath/E.dylib"), lib("Frameworks/B.framework/B", "@rpath/F.dylib", bundled: false)]
        try await render(Host(libs: more), name: "existing-libraries-ar", height: 1000)
    }

    func testArabicSnapshotSourceDeleteConfirmation() async throws {
        AppLanguageStore.shared.set(.arabic)
        let defaults = UserDefaults(suiteName: "ExistingLibsUISnap")!
        defaults.removePersistentDomain(forName: "ExistingLibsUISnap")
        let store = SourcesStore(defaults: defaults)
        store.sources.append(RepoSource(url: "https://dup.example/s.json", name: "Dup"))
        store.requestDelete(id: store.sources.last!.id)
        XCTAssertEqual(store.pendingDelete?.name, "Dup")
        struct Host: View {
            @ObservedObject var store: SourcesStore
            var body: some View {
                List(store.sources) { Text($0.name) }
                    .confirmationDialog(tr("Delete this source?", "تحذف هالسورس؟", ckb: "ئەم سەرچاوەیە بسڕدرێتەوە؟", kmr: "Ev çavkanî were jêbirin?"),
                                        isPresented: .constant(store.pendingDelete != nil), titleVisibility: .visible) {
                        Button(tr("Delete", "حذف", ckb: "سڕینەوە", kmr: "Jêbirin"), role: .destructive) {}
                    }
            }
        }
        try await render(Host(store: store), name: "sources-delete-confirm-ar", height: 700)
        defaults.removePersistentDomain(forName: "ExistingLibsUISnap")
    }
}
