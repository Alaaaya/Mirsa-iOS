import XCTest
import UIKit
import SwiftUI
import ImageIO
@testable import Mirsa

@MainActor final class ForgeFeatureTests: XCTestCase {
    func testGuideCopyInExistingFourLanguagesAndUniqueSeenKeys() {
        let previous = AppLanguageStore.shared.current
        defer { AppLanguageStore.shared.set(previous) }
        XCTAssertEqual(Set(ForgeGuide.allCases.map(\.seenKey)).count, 4)
        var subtitles: [ForgeGuide: Set<String>] = [:]
        for language in AppLanguage.allCases {
            AppLanguageStore.shared.set(language)
            for feature in ForgeGuide.allCases {
                XCTAssertFalse(feature.subtitle.isEmpty)
                XCTAssertFalse(feature.subtitle.contains("\n"))
                XCTAssertEqual(feature.steps.count, 3)
                XCTAssertTrue(feature.steps.allSatisfy { !$0.isEmpty })
                subtitles[feature, default: []].insert(feature.subtitle)
            }
        }
        XCTAssertTrue(subtitles.values.allSatisfy { $0.count == 4 })
        AppLanguageStore.shared.set(.english)
        XCTAssertTrue(ForgeGuide.crash.steps.joined().contains("cannot read system crash logs"))
        XCTAssertTrue(ForgeGuide.crash.steps.joined().contains("not prove"))
        XCTAssertTrue(ForgeGuide.publish.steps.joined().contains("HTTPS"))
        XCTAssertTrue(ForgeGuide.publish.steps.joined().contains(".dylib or .deb"))
        XCTAssertTrue(ForgeGuide.archive.steps.joined().contains("signing"))
    }

    func testGuideLTRLayoutAndSnapshotsAcrossLanguagesAndSeenState() {
        let previous = AppLanguageStore.shared.current
        let defaults = UserDefaults.standard
        let saved = ForgeGuide.allCases.map { ($0.seenKey, defaults.object(forKey: $0.seenKey)) }
        defer {
            AppLanguageStore.shared.set(previous)
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        for language in AppLanguage.allCases {
            AppLanguageStore.shared.set(language)
            for feature in ForgeGuide.allCases {
                for largeFont in [false, true] {
                    for seen in [false, true] {
                        defaults.set(seen, forKey: feature.seenKey)
                        let view = ForgeFeatureGuide(feature)
                            .padding(14).background(Color.black)
                            .environment(\.dynamicTypeSize, largeFont ? .accessibility5 : .large)
                            .environment(\.layoutDirection, .leftToRight)
                            .ignoresSafeArea()
                        // Keep the render-server surface phone-sized even at AX5.
                        // Capture the entire scrollable guide in tiles, never one giant window.
                        let host = UIHostingController(rootView: ScrollView { view }
                            .scrollIndicators(.hidden).ignoresSafeArea())
                        let scene = UIApplication.shared.connectedScenes
                            .compactMap { $0 as? UIWindowScene }.first
                        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: .zero)
                        window.frame = CGRect(x: 0, y: 0, width: 320, height: 852)
                        window.rootViewController = host
                        window.makeKeyAndVisible()
                        host.view.frame = window.bounds
                        host.view.setNeedsLayout()
                        host.view.layoutIfNeeded()
                        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
                        let name = "guide-\(feature.rawValue)-\(language.rawValue)-\(seen ? "seen" : "first")-\(largeFont ? "AX5" : "normal")"
                        guard let scroll = Self.scrollView(in: host.view) else {
                            XCTFail("Missing guide scroll viewport: " + name)
                            window.isHidden = true; window.rootViewController = nil
                            continue
                        }
                        scroll.contentInsetAdjustmentBehavior = .never
                        host.view.layoutIfNeeded()
                        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                        let height = ceil(scroll.contentSize.height)
                        XCTAssertTrue(height.isFinite && height > 0, name)
                        XCTAssertLessThanOrEqual(scroll.contentSize.width, 321, name)
                        XCTAssertEqual(host.view.effectiveUserInterfaceLayoutDirection, .leftToRight, name)
                        let format = UIGraphicsImageRendererFormat()
                        format.scale = 1
                        format.opaque = true
                        var tiles: [(UIImage, CGFloat, CGFloat, CGFloat)] = []
                        var y: CGFloat = 0
                        while y < height {
                            let offset = min(y, max(0, height - scroll.bounds.height))
                            scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
                            scroll.layoutIfNeeded()
                            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                            let tile = Self.snapshot(host.view)
                            XCTAssertTrue(Self.hasVisiblePixels(tile), "blank guide tile: " + name + " y=\(y)")
                            let count = min(scroll.bounds.height, height - y)
                            tiles.append((tile, y, y - offset, count))
                            y += count
                        }
                        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: height), format: format).image { ctx in
                            UIColor.black.setFill()
                            ctx.fill(CGRect(x: 0, y: 0, width: 320, height: height))
                            for (tile, top, crop, count) in tiles {
                                ctx.cgContext.saveGState()
                                ctx.cgContext.clip(to: CGRect(x: 0, y: top, width: 320, height: count))
                                tile.draw(at: CGPoint(x: 0, y: top - crop))
                                ctx.cgContext.restoreGState()
                            }
                        }
                        XCTAssertTrue(Self.hasVisiblePixels(image), "blank guide snapshot: " + name)
                        XCTAssertEqual(image.size.width, 320)
                        XCTAssertEqual(image.size.height, height, "Incomplete guide capture: " + name)
                        window.isHidden = true
                        window.rootViewController = nil
                        let attachment = XCTAttachment(image: image)
                        attachment.name = name
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
            }
        }
    }

    func testCommunityDescriptionsStayGroundedAndOwnershipIsPreserved() {
        var project = ForgeProject(name: "Glass", bundleID: "com.ry0.ryP0", appName: "ryP0",
                                   appVersion: "1", executable: "ryP0", classes: [])
        project.versions = [ForgeVersion(prompt: "Make the navigation bar glass", code: "", settings: [],
                                        explain: "Glass navigation bar with appearance settings")]
        let own: [String: Any] = ["name": "Glass", "target_bundle_id": project.bundleID, "mine": true]
        XCTAssertEqual(ForgeCommunityEntry(own).groundedDescription(projects: [project]),
                       project.currentVersion?.explain)
        var other = own; other["mine"] = false
        XCTAssertNil(ForgeCommunityEntry(other).groundedDescription(projects: [project]))
        var uploaded = own; uploaded["provenance"] = "uploaded"
        XCTAssertTrue(ForgeCommunityEntry(uploaded).uploaded)
        XCTAssertNil(ForgeCommunityEntry(uploaded).groundedDescription(projects: [project]))
        var described = uploaded; described["description"] = "  User-written description  "
        XCTAssertEqual(ForgeCommunityEntry(described).groundedDescription(projects: []), "User-written description")
        var different = own; different["name"] = "Unrelated"
        XCTAssertNil(ForgeCommunityEntry(different).groundedDescription(projects: [project]))
        XCTAssertNil(ForgeCommunityEntry([:]).groundedDescription(projects: [project]))
        project.versions = [ForgeVersion(prompt: "Manual edit", code: "", settings: [], explain: "")]
        XCTAssertNil(ForgeCommunityEntry(own).groundedDescription(projects: [project]))
    }

    func testCommunityActionExplanationsInEveryLanguageMatchHandlers() {
        let previous = AppLanguageStore.shared.current
        defer { AppLanguageStore.shared.set(previous) }
        var versions = Set<String>()
        for language in AppLanguage.allCases {
            AppLanguageStore.shared.set(language)
            let explanations = ForgeCommunityCard.Action.allCases.map {
                ForgeCommunityCard.explanation($0)
            }
            XCTAssertEqual(Set(explanations).count, 4)
            XCTAssertTrue(explanations.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            XCTAssertNotEqual(ForgeCommunityCard.explanation(.use), ForgeCommunityCard.explanation(.use, uploaded: true))
            XCTAssertNotEqual(ForgeCommunityCard.explanation(.version), ForgeCommunityCard.explanation(.version, uploaded: true))
            versions.insert(ForgeCommunityCard.explanation(.version))
        }
        XCTAssertEqual(versions.count, 4)
        AppLanguageStore.shared.set(.arabic)
        XCTAssertEqual(ForgeCommunityCard.explanation(.version), "قارن النسخ، اكتب شو الجديد، وانشر تحديثك.")
        XCTAssertTrue(ForgeCommunityCard.explanation(.edit).contains("اسم"))
        XCTAssertTrue(ForgeCommunityCard.explanation(.delete).contains("المجتمع"))
    }

    func testCommunityOriginalApprovedCardSnapshotsInFourLanguages() throws {
        let previous = AppLanguageStore.shared.current
        let savedProjects = ForgeStore.shared.projects
        defer { AppLanguageStore.shared.set(previous); ForgeStore.shared.projects = savedProjects }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ryP0-primary-CgBI.png")
        let originalIcon = try Data(contentsOf: fixture)
        let png = try XCTUnwrap(PersonalAppsLibrary.validatedIconPNG(originalIcon))
        let icon = try XCTUnwrap(UIImage(data: png))
        // This exact primary PNG was extracted from the owner's real ryP0 IPA, not a generated logo.
        ForgeStore.shared.projects = [ForgeProject(name: "TweakryP0", bundleID: "com.ry0.ryP0",
            appName: "ryP0", appVersion: "1", executable: "ryP0", classes: [])]
        for language in AppLanguage.allCases {
            AppLanguageStore.shared.set(language)
            for width in [320.0, 390.0] {
                let description = tr("Glass navigation bar with appearance settings",
                    "شريط تنقل زجاجي مع إعدادات للمظهر",
                    ckb: "شریتی گواستنەوەی شووشەیی لەگەڵ ڕێکخستنەکانی دەرکەوتن",
                    kmr: "Barê navîgasyonê yê camî bi mîhengên xuyangê")
                let card = ForgeCommunityCard(
                    entry: ["name": "TweakryP0", "target_bundle_id": "com.ry0.ryP0",
                            "description": description, "mine": true],
                    knownTargetIcon: icon, onUse: {}, onEdit: {}, onVersion: {}, onDelete: {})
                let view = VStack(alignment: .leading, spacing: 20) {
                    Text(ForgeCommunityCard.title).font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .trailing)
                    card
                    Spacer(minLength: 0)
                }.padding(16).background(ForgeCommunityCard.sheetColor)
                    .environment(\.layoutDirection, .leftToRight).ignoresSafeArea()
                let host = UIHostingController(rootView: view)
                let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: .zero)
                window.frame = CGRect(x: 0, y: 0, width: width, height: 600)
                window.rootViewController = host; window.makeKeyAndVisible()
                host.view.frame = window.bounds
                host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                XCTAssertEqual(host.view.effectiveUserInterfaceLayoutDirection, .leftToRight)
                let image = Self.snapshot(host.view)
                XCTAssertTrue(Self.hasVisiblePixels(image), "Community screenshot must not be blank")
                let attachment = XCTAttachment(image: image)
                attachment.name = "community-original-\(language.rawValue)-\(Int(width))"
                attachment.lifetime = .keepAlways; add(attachment)
                window.isHidden = true; window.rootViewController = nil
            }
        }
    }

    private static func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }

    /// Retries the window snapshot (the simulator render server can transiently fail) and
    /// falls back to the layer renderer. Blank results are still asserted by the caller.
    private static func snapshot(_ view: UIView) -> UIImage {
        var image = UIImage()
        for attempt in 0..<4 {
            autoreleasepool {
                let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
                if attempt < 3 {
                    image = renderer.image { _ in view.drawHierarchy(in: view.bounds, afterScreenUpdates: true) }
                } else {
                    image = renderer.image { ctx in view.layer.render(in: ctx.cgContext) }
                }
            }
            if hasVisiblePixels(image) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            view.setNeedsLayout(); view.layoutIfNeeded()
        }
        return image
    }

    private static func hasVisiblePixels(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return false }
        let bpp = cg.bitsPerPixel / 8, total = cg.width * cg.height
        var lit = 0
        var i = 0
        while i < total {
            let o = i * bpp
            if Int(ptr[o]) + Int(ptr[o + 1]) + Int(ptr[o + 2]) > 90 { lit += 1 }
            i += 7
        }
        return lit > 20
    }

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
    func testAttachContextAllCases() throws {
        let cap = try ForgeCapture.read(capture(false), bundleID: "com.test.target")
        guard case .attached(let list) = ForgeCaptureContext.attach(current: [], prompt: "hi", capture: cap, projectBundleID: "com.test.target", consent: true) else { return XCTFail() }
        XCTAssertEqual(list, ["UIView"])
        let out = ForgeCaptureContext.composed(prompt: "hi", classes: list)
        XCTAssertEqual(out.components(separatedBy: "UIView").count - 1, 1); XCTAssertTrue(out.hasPrefix("hi"))
        XCTAssertEqual(ForgeCaptureContext.composed(prompt: "hi", classes: []), "hi")
        XCTAssertEqual(ForgeCaptureContext.attach(current: list, prompt: "hi", capture: cap, projectBundleID: "com.test.target", consent: true), .alreadyAttached(list))
        XCTAssertEqual(ForgeCaptureContext.attach(current: [], prompt: "hi", capture: cap, projectBundleID: "com.test.target", consent: false), .rejected(.consentOff))
        XCTAssertEqual(ForgeCaptureContext.attach(current: [], prompt: "hi", capture: cap, projectBundleID: "com.other", consent: true), .rejected(.wrongBundle))
        XCTAssertEqual(ForgeCaptureContext.attach(current: [], prompt: String(repeating: "x", count: 2000), capture: cap, projectBundleID: "com.test.target", consent: true), .rejected(.tooLong))
        XCTAssertTrue(ForgeCaptureContext.chipText(3).contains("📎")); XCTAssertFalse(ForgeCaptureContext.chipText(3).contains("User-reviewed")); XCTAssertFalse(ForgeCaptureContext.reasonText(.tooLong).isEmpty)
    }
    func testPreviewHidesRawDebugAndLocalizesKnownLimitation() throws {
        var o = try XCTUnwrap(JSONSerialization.jsonObject(with: capture()) as? [String: Any])
        o["limitations"] = "Foreground originating scene only."
        let data = try JSONSerialization.data(withJSONObject: o)
        let text = ForgeCaptureContext.previewText(data)
        XCTAssertFalse(text.contains("inspector: explicit foreground")); XCTAssertFalse(text.contains("Foreground originating scene"))
        XCTAssertNotNil(ForgeCaptureContext.limitationsText("Some unknown warning")); XCTAssertEqual(ForgeCaptureContext.limitationsText("Some unknown warning"), "Some unknown warning")
        XCTAssertNoThrow(try ForgeCapture.read(data, bundleID: "com.test.target"))
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
    func testBig3MarkClampsAndRejectsEmptyCanvas() {
        XCTAssertEqual(ForgeImageMark.normalize(CGRect(x: -10, y: 20, width: 90, height: 120), in: CGSize(width: 100, height: 100)), CGRect(x: 0, y: 0.2, width: 0.8, height: 0.8))
        XCTAssertEqual(ForgeImageMark.normalize(.zero, in: .zero), .zero)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 160)).image { _ in UIColor.white.setFill(); UIBezierPath(rect: CGRect(x: 0, y: 0, width: 120, height: 160)).fill() }
        XCTAssertNotNil(ForgeImageMark.marked(image.jpegData(compressionQuality: 0.8)!, region: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4)))
    }
    func testBig3ArchiveContentHashAndPersistence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = MirsaVersionArchive(root: root)
        let a = root.appendingPathComponent("a.ipa"), b = root.appendingPathComponent("b.ipa")
        try Data([1, 2, 3]).write(to: a); try Data([3, 2, 1]).write(to: b)
        archive.archive(a, bundleID: "com.test.archive", name: "Archive", version: "1", signed: false)
        archive.archive(a, bundleID: "com.test.archive", name: "Archive", version: "1", signed: false)
        archive.archive(b, bundleID: "com.test.archive", name: "Archive", version: "1", signed: false)
        XCTAssertEqual(archive.items.count, 2, "Same-size different content must not be discarded")
        XCTAssertEqual(archive.bytes(of: "com.test.archive"), 6)
        XCTAssertNotEqual(archive.items[0].sha256, archive.items[1].sha256)
        XCTAssertEqual(MirsaVersionArchive(root: root).items.count, 2)
        archive.deleteOld("com.test.archive")
        XCTAssertEqual(archive.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path), "Deleting archive copies must preserve input")
    }
    func testBig3InterruptedMarkerKeepsHonestAttribution() {
        let report = ForgeFixDiagnostic.sanitized("Termination Reason: Mirsa launch marker reports an interrupted launch; attribution unconfirmed. Counter 2.", kind: "crash")
        XCTAssertTrue(report.contains("attribution unconfirmed"))
        XCTAssertFalse(report.contains("Counter"))
    }

}
