import XCTest
import SwiftUI
@testable import Mirsa

@MainActor
final class ForgeCommunityUpdateTests: XCTestCase {
    private func version(_ code: String, settings: Int = 0, created: Date = Date(timeIntervalSince1970: 1_700_000_000), imported: Bool = false) -> ForgeVersion {
        var v = ForgeVersion(prompt: "p", code: code,
            settings: (0..<settings).map { ForgeSetting(key: "k\($0)", title: "t", default: true) }, explain: "")
        v.created = created
        if imported { v.importedInfo = ForgeDylibInfo(arch: "arm64", size: 1, linked: [], classes: [], selectors: [], summary: "") }
        return v
    }
    private func project(_ versions: [ForgeVersion], current: UUID? = nil) -> ForgeProject {
        var p = ForgeProject(name: "Tweak", bundleID: "com.x.y", appName: "X", appVersion: "1", executable: "x", classes: [])
        p.versions = versions; p.current = current
        return p
    }

    func testEntryDecodesContractFieldsAndLegacyNull() {
        let pid = UUID(), vid = UUID()
        let e = ForgeCommunityEntry(["id": "a", "version": 2, "updated_at": "2026-11-08T10:00:00Z", "changelog": " fix ",
            "author_project_id": pid.uuidString, "author_version_id": vid.uuidString, "author_local_version": 3,
            "author_version_created_at": "2026-11-07T10:00:00Z", "mine": true])
        XCTAssertEqual(e.version, 2); XCTAssertEqual(e.changelog, "fix"); XCTAssertEqual(e.authorProjectID, pid)
        XCTAssertEqual(e.authorVersionID, vid); XCTAssertEqual(e.authorLocalVersion, 3)
        XCTAssertNotNil(e.updatedAt); XCTAssertNotNil(e.authorVersionCreatedAt); XCTAssertTrue(e.mine)
        let legacy = ForgeCommunityEntry(["id": "b", "version": NSNull(), "updated_at": NSNull(), "author_project_id": "not-a-uuid"])
        XCTAssertNil(legacy.version); XCTAssertNil(legacy.updatedAt); XCTAssertNil(legacy.authorProjectID); XCTAssertFalse(legacy.mine)
    }

    func testLocalVersionIsLatestNonImportedByIndexAndRealDate() throws {
        let d1 = Date(timeIntervalSince1970: 1_700_000_000), d2 = Date(timeIntervalSince1970: 1_700_100_000)
        let v1 = version("a", created: d1), v2 = version("b", created: d2), imp = version("c", imported: true)
        let p = project([v1, v2, imp])
        let l = try XCTUnwrap(ForgeLocalVersion.latest(in: p))
        XCTAssertEqual(l.versionID, v2.id); XCTAssertEqual(l.number, 2); XCTAssertEqual(l.created, d2); XCTAssertEqual(l.projectID, p.id)
        XCTAssertNil(ForgeLocalVersion.latest(in: project([imp])))
        XCTAssertNil(ForgeLocalVersion.latest(in: project([])))
    }

    func testPayloadUsesExactComparedVersionNotRolledBackCurrent() throws {
        let old = version("old", settings: 1), latest = version("latest", settings: 2)
        let p = project([old, latest], current: old.id)   // user rolled back to the older version
        XCTAssertEqual(p.currentVersion?.id, old.id)
        let l = try XCTUnwrap(ForgeLocalVersion.latest(in: p))
        XCTAssertEqual(l.versionID, latest.id)
        let body = try ForgeStore.updatePayload(project: p, local: l, entry: "e1", changelog: " new stuff ", expectedVersion: 4)
        XCTAssertEqual(body["code"] as? String, "latest")
        XCTAssertEqual((body["settings"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(body["localVersionID"] as? String, latest.id.uuidString)
        XCTAssertEqual(body["localVersionNumber"] as? Int, 2)
        XCTAssertEqual(body["projectID"] as? String, p.id.uuidString)
        XCTAssertEqual(body["expectedVersion"] as? Int, 4)
        XCTAssertEqual(body["changelog"] as? String, "new stuff")
        XCTAssertEqual(body["action"] as? String, "gallery-update")
        XCTAssertNotNil(body["localVersionCreatedAt"] as? String)
        // comparison uses the same version
        let lines = try XCTUnwrap(ForgeCommunityUpdateLogic.changeLines(publishedCode: "old", publishedSettings: 1, local: p.versions.first { $0.id == l.versionID }))
        XCTAssertEqual(lines.count, 2)
    }

    func testPayloadValidation() throws {
        let v = version("x"); let p = project([v]); let l = try XCTUnwrap(ForgeLocalVersion.latest(in: p))
        XCTAssertThrowsError(try ForgeStore.updatePayload(project: p, local: l, entry: "e", changelog: "  \n", expectedVersion: 1))
        let other = project([v])   // different project id, same version id
        XCTAssertThrowsError(try ForgeStore.updatePayload(project: other, local: l, entry: "e", changelog: "ok", expectedVersion: 1))
        let gone = ForgeLocalVersion(projectID: p.id, versionID: UUID(), number: 1, created: Date())
        XCTAssertThrowsError(try ForgeStore.updatePayload(project: p, local: gone, entry: "e", changelog: "ok", expectedVersion: 1))
    }

    func testPublishLinkageUsesTheSentVersion() {
        let a = version("a"), b = version("b"); let p = project([a, b])
        let l = ForgeStore.linkage(project: p, version: a)
        XCTAssertEqual(l["localVersionNumber"] as? Int, 1); XCTAssertEqual(l["localVersionID"] as? String, a.id.uuidString)
        XCTAssertEqual(l["projectID"] as? String, p.id.uuidString)
    }

    func testChangeLinesNeverFakeZero() {
        let v = version("a\nb", settings: 1)
        XCTAssertNil(ForgeCommunityUpdateLogic.changeLines(publishedCode: nil, publishedSettings: nil, local: v))
        XCTAssertNil(ForgeCommunityUpdateLogic.changeLines(publishedCode: "a", publishedSettings: 1, local: nil))
        XCTAssertEqual(ForgeCommunityUpdateLogic.changeLines(publishedCode: "a", publishedSettings: 1, local: v)?.count, 1)
        XCTAssertEqual(ForgeCommunityUpdateLogic.changeLines(publishedCode: "a\nb", publishedSettings: 1, local: v)?.count, 1)
        XCTAssertEqual(ForgeCommunityUpdateLogic.changeLines(publishedCode: "a\nb", publishedSettings: 3, local: v)?.count, 2)
    }

    func testCanPublishGates() {
        let l = ForgeLocalVersion(projectID: UUID(), versionID: UUID(), number: 1, created: Date())
        func ok(uploaded: Bool = false, pub: Int? = 1, local: ForgeLocalVersion? = l, log: String = "x", loaded: Bool = true, working: Bool = false) -> Bool {
            ForgeCommunityUpdateLogic.canPublish(uploaded: uploaded, publishedVersion: pub, local: local, changelog: log, publishedLoaded: loaded, working: working)
        }
        XCTAssertTrue(ok())
        XCTAssertFalse(ok(uploaded: true)); XCTAssertFalse(ok(pub: nil)); XCTAssertFalse(ok(local: nil))
        XCTAssertFalse(ok(log: " \n ")); XCTAssertFalse(ok(loaded: false)); XCTAssertFalse(ok(working: true))
    }

    func testBadgeNegativeCasesAndSourceRoundtrip() throws {
        var used = version("c"); used.communitySourceID = "e1"; used.usedPublishedVersion = 1
        var p = project([used])
        XCTAssertEqual(ForgeCommunityUpdateLogic.usedOlderVersion(entryID: "e1", published: 2, mine: false, projects: [p]), 1)
        XCTAssertNil(ForgeCommunityUpdateLogic.usedOlderVersion(entryID: "e1", published: 2, mine: true, projects: [p]))   // author
        XCTAssertNil(ForgeCommunityUpdateLogic.usedOlderVersion(entryID: "e1", published: 1, mine: false, projects: [p]))   // up to date
        XCTAssertNil(ForgeCommunityUpdateLogic.usedOlderVersion(entryID: "e1", published: nil, mine: false, projects: [p])) // legacy
        XCTAssertNil(ForgeCommunityUpdateLogic.usedOlderVersion(entryID: "e2", published: 2, mine: false, projects: [p]))   // other entry
        XCTAssertNil(ForgeCommunityUpdateLogic.usedOlderVersion(entryID: "e1", published: 2, mine: false, projects: [project([version("c")])])) // same code, no source
        // Codable roundtrip keeps source and old projects without the keys still decode
        p.versions[0].usedPublishedVersion = 1
        let back = try JSONDecoder().decode(ForgeProject.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.versions[0].communitySourceID, "e1"); XCTAssertEqual(back.versions[0].usedPublishedVersion, 1)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        var vs = try XCTUnwrap(json["versions"] as? [[String: Any]]); vs[0].removeValue(forKey: "communitySourceID"); vs[0].removeValue(forKey: "usedPublishedVersion"); json["versions"] = vs
        let old = try JSONDecoder().decode(ForgeProject.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.versions[0].communitySourceID)
    }

    func testDateParsingSupabaseFractionalAndPlain() throws {
        let plain = try XCTUnwrap(ForgeCommunityUpdateLogic.parseDate("2026-11-09T00:30:01Z"))
        let micro = try XCTUnwrap(ForgeCommunityUpdateLogic.parseDate("2026-11-09T00:30:01.123456+00:00"))
        let milli = try XCTUnwrap(ForgeCommunityUpdateLogic.parseDate("2026-11-09T00:30:01.5Z"))
        XCTAssertEqual(micro.timeIntervalSince(plain), 0.123456, accuracy: 0.0001)
        XCTAssertEqual(milli.timeIntervalSince(plain), 0.5, accuracy: 0.0001)
        XCTAssertNotNil(ForgeCommunityUpdateLogic.parseDate("2026-11-09T01:30:01+01:00"))
        XCTAssertNil(ForgeCommunityUpdateLogic.parseDate("garbage"))
        let e = ForgeCommunityEntry(["id": "a", "updated_at": "2026-11-09T00:30:01.123456+00:00", "author_version_created_at": "2026-11-09T00:30:01.999+00:00"])
        XCTAssertNotNil(e.updatedAt); XCTAssertNotNil(e.authorVersionCreatedAt)
    }

    func testSourceVersionMustMatchEntry() {
        XCTAssertTrue(ForgeCommunityUpdateLogic.sourceMatches(fetchedVersion: 2, entryVersion: 2))
        XCTAssertFalse(ForgeCommunityUpdateLogic.sourceMatches(fetchedVersion: 3, entryVersion: 2))
        XCTAssertFalse(ForgeCommunityUpdateLogic.sourceMatches(fetchedVersion: nil, entryVersion: 2))
        XCTAssertFalse(ForgeCommunityUpdateLogic.sourceMatches(fetchedVersion: 1, entryVersion: nil))
    }

    func testPendingSourceClearsWithCode() {
        let s = ForgeStore.shared
        s.pendingGalleryCode = "code"; s.pendingGallerySource = (id: "e", version: 1)
        s.pendingGalleryCode = nil
        XCTAssertNil(s.pendingGallerySource)
    }

    func testEditCodeRecordsSourceOnlyWhenGiven() {
        let s = ForgeStore.shared; let saved = s.projects; defer { s.projects = saved }
        let base = version("base"); let p = project([base]); s.projects = [p]
        s.editCode(p.id, code: "x", source: (id: "e1", version: 3))
        s.editCode(p.id, code: "y")
        let vs = s.projects[0].versions
        XCTAssertEqual(vs[1].communitySourceID, "e1"); XCTAssertEqual(vs[1].usedPublishedVersion, 3)
        XCTAssertNil(vs[2].communitySourceID); XCTAssertEqual(vs[0].code, "base")
    }

    func testUpdateStringsExistInFourLanguages() {
        let previous = AppLanguageStore.shared.current; defer { AppLanguageStore.shared.set(previous) }
        var seen = Set<String>()
        for language in AppLanguage.allCases {
            AppLanguageStore.shared.set(language)
            let t = ForgeCommunityUpdateLogic.changeLines(publishedCode: "a", publishedSettings: 1, local: version("b", settings: 2)) ?? []
            XCTAssertEqual(t.count, 2); seen.insert(t.joined())
        }
        XCTAssertEqual(seen.count, 4)
    }

    // MARK: snapshots (24 = author, consumer, sheet x 4 languages x 2 widths)
    func testUpdateSnapshots() throws {
        let previous = AppLanguageStore.shared.current; let saved = ForgeStore.shared.projects
        defer { AppLanguageStore.shared.set(previous); ForgeStore.shared.projects = saved }
        let v1 = version("old", created: Date(timeIntervalSince1970: 1_699_000_000)), v2 = version("old\nnew", settings: 1, created: Date(timeIntervalSince1970: 1_700_000_000))
        var p = project([v1, v2]); p.name = "TweakryP0"; p.bundleID = "com.ry0.ryP0"
        var used = version("consumer"); used.communitySourceID = "e-consumer"; used.usedPublishedVersion = 1
        var q = project([used]); q.name = "Mine"; q.bundleID = "com.other.app"
        ForgeStore.shared.projects = [p, q]
        let author: [String: Any] = ["id": "e-author", "name": "TweakryP0", "target_bundle_id": "com.ry0.ryP0", "description": "Glass bar", "mine": true,
            "version": 2, "updated_at": "2026-11-08T10:00:00Z", "author_project_id": p.id.uuidString]
        let consumer: [String: Any] = ["id": "e-consumer", "name": "Other", "target_bundle_id": "com.other.app", "description": "Other tweak", "mine": false,
            "version": 2, "updated_at": "2026-11-08T10:00:00Z"]
        for language in AppLanguage.allCases {
            AppLanguageStore.shared.set(language)
            for width in [320.0, 390.0] {
                let views: [(String, AnyView)] = [
                    ("author", AnyView(ForgeCommunityCard(entry: author, onUse: {}, onEdit: {}, onVersion: {}, onDelete: {}).padding(16).background(ForgeCommunityCard.sheetColor))),
                    ("consumer", AnyView(ForgeCommunityCard(entry: consumer, onUse: {}, onEdit: {}, onVersion: {}, onDelete: {}).padding(16).background(ForgeCommunityCard.sheetColor))),
                    ("sheet", AnyView(ForgeCommunityUpdateSheet(entry: author, preloaded: (code: "old", settings: 0), onPublished: {})))]
                for (name, view) in views {
                    let host = UIHostingController(rootView: view.environment(\.layoutDirection, .leftToRight))
                    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                    let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: .zero)
                    window.frame = CGRect(x: 0, y: 0, width: width, height: 760)
                    window.rootViewController = host; window.makeKeyAndVisible()
                    host.view.frame = window.bounds; host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                    let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
                    XCTAssertTrue(Self.hasPixels(image), "blank \(name)")
                    let a = XCTAttachment(image: image); a.name = "community-update-\(name)-\(language.rawValue)-\(Int(width))"
                    a.lifetime = .keepAlways; add(a)
                    window.isHidden = true; window.rootViewController = nil
                }
            }
        }
    }
    private static func hasPixels(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return false }
        let n = CFDataGetLength(data); var seen = Set<UInt8>(); var i = 0
        while i < n { seen.insert(ptr[i]); if seen.count > 8 { return true }; i += 97 }
        return false
    }
}
