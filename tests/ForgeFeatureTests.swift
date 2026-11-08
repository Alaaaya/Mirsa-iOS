import XCTest
import UIKit
import ImageIO
@testable import Mirsa

@MainActor final class ForgeFeatureTests: XCTestCase {
    func testArchiveErrorsLocalizedInAllFourLanguagesAndDoNotLeakPaths() {
        let errors = ["Archive size limit exceeded", "Archive compression ratio limit exceeded",
                      "Too many archive entries", "Unsafe archive path: /private/secret",
                      "Duplicate archive path", "Archive links and special files are not supported",
                      "Case-colliding archive path component", "App executable is missing", "Invalid Zip header"]
        for error in errors {
            let messages = AppLanguage.allCases.map { IPAEditorService.archiveError(error, language: $0) }
            XCTAssertEqual(Set(messages).count, 4)
            for message in messages {
                XCTAssertFalse(message.isEmpty)
                XCTAssertFalse(message.contains("/private/secret"))
                XCTAssertNotEqual(message, error)
            }
        }
    }

    func testEncryptionWarningPolicyAndFourLanguageConsent() throws {
        let clean = PersonalEncryptionWarning(main_encrypted: false, embedded_encrypted: 0)
        let extensionOnly = PersonalEncryptionWarning(main_encrypted: false, embedded_encrypted: 1)
        let main = PersonalEncryptionWarning(main_encrypted: true, embedded_encrypted: 0)
        XCTAssertFalse(clean.requiresConsent)
        XCTAssertTrue(extensionOnly.requiresConsent)
        XCTAssertTrue(main.requiresConsent)
        XCTAssertNotEqual(main.message(.english), extensionOnly.message(.english))
        XCTAssertTrue(extensionOnly.message(.english).contains("not encrypted"))
        XCTAssertEqual(Set(AppLanguage.allCases.map { main.message($0) }).count, 4)
        XCTAssertEqual(Set(AppLanguage.allCases.map { PersonalEncryptionWarning.proceed($0) }).count, 4)
        XCTAssertEqual(Set(AppLanguage.allCases.map { PersonalEncryptionWarning.title($0) }).count, 4)
        for language in AppLanguage.allCases {
            XCTAssertFalse(main.message(language).isEmpty)
            XCTAssertFalse(PersonalEncryptionWarning.cancel(language).isEmpty)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(PersonalEncryptionWarning.self, from: Data("{}".utf8)))
    }

    private func project(_ bundle: String = "com.test.target") -> ForgeProject {
        ForgeProject(name: "Test", bundleID: bundle, appName: "Test", appVersion: "1", executable: "Test", classes: ["UIView"])
    }
    private func version() -> ForgeVersion { ForgeVersion(prompt: "Test", code: "%hook UIView\n%end", settings: [], explain: "") }

    func testClassesBoundedAndInvalidRejected() {
        XCTAssertEqual(ForgeFeaturePolicy.classes(["UIView", "", "bad class", "secret\nline"]), ["UIView"])
        XCTAssertEqual(ForgeFeaturePolicy.classes(Array(repeating: "UIView", count: 999)).count, 400)
        XCTAssertTrue(ForgeFeaturePolicy.classes([String(repeating: "X", count: 82)]).isEmpty)
    }
    func testNamesRemainBuilderCompatible() {
        let name = ForgeFeaturePolicy.name("١٢ مرحبا! " + String(repeating: "A", count: 90))
        XCTAssertNotNil(name.range(of: "^[A-Za-z][A-Za-z0-9 _.-]{0,39}$", options: .regularExpression))
    }
    func testMergeRequiresTwoThroughFiveDistinctSameTargetVersions() throws {
        let p = project(), a = version(), b = version()
        try ForgeFeaturePolicy.mergeSelection([(p, a), (p, b)], bundleID: p.bundleID)
        XCTAssertThrowsError(try ForgeFeaturePolicy.mergeSelection([(p, a)], bundleID: p.bundleID))
        XCTAssertThrowsError(try ForgeFeaturePolicy.mergeSelection([(p, a), (p, a)], bundleID: p.bundleID))
        XCTAssertThrowsError(try ForgeFeaturePolicy.mergeSelection([(p, a), (project("com.other.app"), b)], bundleID: p.bundleID))
        XCTAssertThrowsError(try ForgeFeaturePolicy.mergeSelection((0..<6).map { _ in (p, version()) }, bundleID: p.bundleID))
    }
    func testMergeCandidatesOnlyBuiltSameBundleWithLocalDylib() {
        func built(_ code: String = "%hook UIView\n%end") -> ForgeVersion { var v = version(); v.code = code; v.builtWithValues = [:]; return v }
        var p1 = project(), p2 = project(), other = project("com.other.app")
        let a = built(), b = built(), unbuilt = version(), missing = built(), empty = built(), noCode = built("")
        let foreign = built()
        p1.versions = [a, unbuilt, missing, noCode]; p2.versions = [b, empty]; other.versions = [foreign]
        let sizes: [UUID: Int] = [a.id: 10, b.id: 5, empty.id: 0, noCode.id: 3, foreign.id: 9, unbuilt.id: 4]
        let c = ForgeFeaturePolicy.mergeCandidates([p1, p2, other], bundleID: "com.test.target") { _, v in sizes[v.id] }
        XCTAssertEqual(Set(c.map { $0.1.id }), [a.id, b.id])
    }
    func testSelectionPruningAndCountValidation() {
        let p = project(); var vs: [ForgeVersion] = []
        for _ in 0..<7 { var v = version(); v.builtWithValues = [:]; vs.append(v) }
        let cands = vs.map { (p, $0) }
        XCTAssertFalse(ForgeFeaturePolicy.canMerge([], candidates: cands))
        XCTAssertFalse(ForgeFeaturePolicy.canMerge([vs[0].id], candidates: cands))
        XCTAssertTrue(ForgeFeaturePolicy.canMerge(Set(vs[0..<2].map { $0.id }), candidates: cands))
        XCTAssertTrue(ForgeFeaturePolicy.canMerge(Set(vs[0..<5].map { $0.id }), candidates: cands))
        XCTAssertFalse(ForgeFeaturePolicy.canMerge(Set(vs[0..<6].map { $0.id }), candidates: cands))
        let stale = Set(vs[0..<2].map { $0.id })
        XCTAssertEqual(ForgeFeaturePolicy.prunedSelection(stale, candidates: [cands[0]]), [vs[0].id])
        XCTAssertFalse(ForgeFeaturePolicy.canMerge(stale, candidates: [cands[0]]))
        XCTAssertFalse(ForgeFeaturePolicy.canMerge([UUID(), UUID()], candidates: cands))
    }
    func testVersionGuardIdentityRoundtripAndLegacyDecoding() throws {
        var v = version(); let original = v.id; v.guardID = original; v.repairChainID = UUID(); v.id = UUID()
        let copy = try JSONDecoder().decode(ForgeVersion.self, from: JSONEncoder().encode(v))
        XCTAssertEqual(copy.tweakID, original); XCTAssertEqual(copy.repairChainID, v.repairChainID)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(v)) as? [String: Any])
        raw.removeValue(forKey: "guardID"); raw.removeValue(forKey: "repairChainID")
        let legacy = try JSONDecoder().decode(ForgeVersion.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertEqual(legacy.tweakID, legacy.id)
    }
    func testSanitizerRedactsSecretsPathsAndAddressesWithoutBreakingArabic() {
        let result = ForgeFeaturePolicy.sanitizedLog("Exception Type: SIGABRT\nPassword: secret\nBearer abc\nx@y.example\n/private/var/mobile/data\nسبب الخطأ")
        XCTAssertFalse(result.contains("secret")); XCTAssertFalse(result.contains("abc")); XCTAssertFalse(result.contains("x@y"))
        XCTAssertFalse(result.contains("/private")); XCTAssertTrue(result.contains("SIGABRT")); XCTAssertTrue(result.contains("سبب الخطأ"))
        XCTAssertLessThanOrEqual(ForgeFeaturePolicy.sanitizedLog(String(repeating: "خطأ", count: 24000)).utf8.count, 24000)
    }
    private func capture(_ guardValue: Bool? = nil, target: String = "com.test.target") throws -> Data {
        var o: [String: Any] = ["schema": "mirsa.inspector.v1", "bundleID": target, "tweakID": "12345678-1234-1234-1234-123456789abc",
            "nodes": [["class": "UIView", "depth": 0, "parent": -1, "frame": [0, 0, 100, 100], "identifier": "[redacted]", "label": "[redacted]", "text": "[redacted]", "secure": false]],
            "truncated": false, "limitations": "UIKit only", "logs": ["inspector: explicit foreground capture requested"]]
        if let guardValue { o["guardDisabled"] = guardValue }
        return try JSONSerialization.data(withJSONObject: o)
    }
    func testCaptureGuardUnknownDisabledAndWrongTweakFailClosed() throws {
        let tweak = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!
        XCTAssertFalse(try ForgeCapture.read(capture(), bundleID: "com.test.target").repairAllowed(tweakID: tweak))
        XCTAssertFalse(try ForgeCapture.read(capture(true), bundleID: "com.test.target").repairAllowed(tweakID: tweak))
        XCTAssertTrue(try ForgeCapture.read(capture(false), bundleID: "com.test.target").repairAllowed(tweakID: tweak))
        XCTAssertFalse(try ForgeCapture.read(capture(false), bundleID: "com.test.target").repairAllowed(tweakID: UUID()))
        XCTAssertThrowsError(try ForgeCapture.read(capture(false, target: "com.other.app"), bundleID: "com.test.target"))
    }
    func testCaptureRejectsOversizeAndUnredactedImport() throws {
        XCTAssertThrowsError(try ForgeCapture.read(Data(repeating: 32, count: 24001), bundleID: "com.test.target"))
        var o = try XCTUnwrap(JSONSerialization.jsonObject(with: capture()) as? [String: Any])
        var nodes = try XCTUnwrap(o["nodes"] as? [[String: Any]])
        nodes[0]["text"] = "my password"; o["nodes"] = nodes
        XCTAssertThrowsError(try ForgeCapture.read(JSONSerialization.data(withJSONObject: o), bundleID: "com.test.target"))
    }
    func testFreshJPEGHasBoundedRGBDimensionsAndNoGPS() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 100)).image { _ in UIColor.red.setFill(); UIBezierPath(rect: CGRect(x: 0, y: 0, width: 2000, height: 100)).fill() }
        let data = try ForgeFeaturePolicy.jpeg(XCTUnwrap(image.pngData()))
        XCTAssertLessThanOrEqual(data.count, 1024 * 1024)
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertLessThanOrEqual((props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 9999, 1600)
        XCTAssertNil(props[kCGImagePropertyGPSDictionary])
        XCTAssertThrowsError(try ForgeFeaturePolicy.jpeg(Data([1, 2, 3])))
    }
    func testRepairProposalSavePreservesCurrentAndOriginal() throws {
        let store = ForgeStore.shared; let p = project()
        store.projects.append(p)
        defer { try? store.delete(p.id) }
        let original = version(); store.addVersion(p.id, original)
        var repair = version(); repair.guardID = original.id
        store.acceptRepair(p.id, proposal: repair)
        XCTAssertEqual(store.project(p.id)?.current, original.id)
        XCTAssertEqual(store.project(p.id)?.versions.count, 2)
        XCTAssertEqual(store.project(p.id)?.versions.last?.tweakID, original.id)
        let first = try store.repairChain(p.id, versionID: original.id)
        let second = try store.repairChain(p.id, versionID: repair.id)
        XCTAssertEqual(first.0, second.0); XCTAssertEqual(first.1, second.1)
    }

    func testForgeFeatureUIHasSoraniAndKurmanjiForEveryKey() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ios-app/Apps/ForgeFeaturesView.swift")
        let source = try String(contentsOf: path, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: "text\\(\"((?:[^\"\\\\]|\\\\.)*)\"")
        let ns = source as NSString
        let keys = Set(regex.matches(in: source, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) })
        XCTAssertGreaterThan(keys.count, 30)
        for k in keys {
            let ckb = MirsaTr.ckb[k] ?? MirsaTr.extraCkb[k] ?? MirsaTr.forgeCkb[k]
            let kmr = MirsaTr.kmr[k] ?? MirsaTr.extraKmr[k] ?? MirsaTr.forgeKmr[k]
            XCTAssertNotNil(ckb, "missing ckb: \(k)"); XCTAssertNotNil(kmr, "missing kmr: \(k)")
            XCTAssertFalse((ckb ?? "").isEmpty); XCTAssertFalse((kmr ?? "").isEmpty)
        }
        XCTAssertEqual(Set(MirsaTr.forgeCkb.keys), Set(MirsaTr.forgeKmr.keys))
    }
}
