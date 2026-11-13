import Foundation
import XCTest
import UIKit
@testable import Mirsa

@MainActor
final class ForgeQueuedTests: XCTestCase {
    let thread = "11111111-2222-3333-4444-555555555555"
    let orig = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    func data(_ o: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: o) }
    /// Wire contract v1 (QUEUED-RECEIPT-CONTRACT-v1.txt sha 9ca3122b..., manual-create.mjs sha e306edbc...), HTTP 200.
    func receipt(_ extra: [String: Any] = [:], thread t: String? = nil) -> [String: Any] {
        var r: [String: Any] = ["saved": true, "status": "manual-queue", "threadID": t ?? thread, "reviewID": orig, "originalID": orig, "replayed": false, "message": "x"]
        for (k, v) in extra { r[k] = v }; return r
    }
    override func tearDown() { ForgeQueued.transport = nil; super.tearDown() }

    func testContractV1FixtureAccepted() throws {
        for replay in [false, true] {
            guard case .queued(let r) = try ForgeQueued.decode(status: 200, data: data(receipt(["replayed": replay])), expectedThreadID: thread) else { return XCTFail() }
            XCTAssertEqual(r.originalID, orig); XCTAssertEqual(r.reviewID, orig); XCTAssertEqual(r.replayed, replay)
        }
    }
    func testReadyCodePathUnchanged() throws {
        guard case .generated(let o) = try ForgeQueued.decode(status: 200, data: data(["code": "// c", "settings": []]), expectedThreadID: thread) else { return XCTFail() }
        XCTAssertEqual(o["code"] as? String, "// c")
    }
    func testMalformedRejected() {
        var bads: [[String: Any]] = [receipt(["saved": false]), receipt(["threadID": "other"]), receipt(["originalID": "nope"]),
            receipt(["originalID": "bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee"]), receipt(["code": "int x;"]), receipt(["status": "queued"]),
            receipt(["replayed": "no"]), receipt(["message": 1]), ["saved": true]]
        var noReview = receipt(); noReview.removeValue(forKey: "reviewID"); bads.append(noReview)
        for b in bads { XCTAssertThrowsError(try ForgeQueued.decode(status: 200, data: data(b), expectedThreadID: thread)) }
        XCTAssertThrowsError(try ForgeQueued.decode(status: 202, data: data(["code": "x"]), expectedThreadID: thread))
        XCTAssertThrowsError(try ForgeQueued.decode(status: 204, data: data([:]), expectedThreadID: thread))
        XCTAssertThrowsError(try ForgeQueued.decode(status: 200, data: data(receipt()), expectedThreadID: thread, knownOriginalID: "bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee"))
    }
    func testIDsStableAcrossRestartAndForgotten() {
        let name = "mirsa.queued.test." + UUID().uuidString
        let body: [String: Any] = ["action": "generate", "prompt": "hello", "inspector": ["a", "b"]]
        let a = ForgeQueued.ids(for: body, defaults: UserDefaults(suiteName: name)!)
        let b = ForgeQueued.ids(for: body, defaults: UserDefaults(suiteName: name)!) // new instance = restart
        XCTAssertEqual(a.id, b.id); XCTAssertEqual(a.thread, b.thread)
        XCTAssertEqual(ForgeQueued.digest("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        ForgeQueued.forget(body, defaults: UserDefaults(suiteName: name)!)
        XCTAssertNotEqual(ForgeQueued.ids(for: body, defaults: UserDefaults(suiteName: name)!).id, a.id)
    }
    func testArabicExactTextAndLocales() throws {
        let src = try String(contentsOfFile: #filePath.replacingOccurrences(of: "tests/ForgeQueuedTests.swift", with: "ios-app/Apps/ForgeQueued.swift"), encoding: .utf8)
        for k in ["طلبك وصل وبالدور، رح يوصلك التويك هون", "Deine Anfrage", "داواکارییەکەت", "Daxwaza te"] { XCTAssertTrue(src.contains(k)) }
    }

    // MARK: store level
    func project() -> ForgeProject {
        let v = ForgeVersion(prompt: "p0", code: "// old", settings: [ForgeSetting(key: "k", title: "K", default: true)], explain: "e")
        var p = ForgeProject(name: "QueuedT", bundleID: "com.q.t", appName: "Q", appVersion: "1", executable: "Q", classes: ["A"])
        p.versions = [v]; p.current = v.id; p.values = ["k": false]; return p
    }
    func realJPEG() -> Data {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { c in UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 64, height: 64)) }
        return img.jpegData(compressionQuality: 0.8)!
    }
    func snapshot(_ p: ForgeProject) -> String { "\(p.versions.map { $0.id.uuidString + $0.code + $0.prompt }) \(p.current?.uuidString ?? "") \(p.values.sorted { $0.key < $1.key })" }
    func run(_ path: Int, store: ForgeStore, id: UUID) async throws -> Bool {
        switch path {
        case 0: return try await store.generate(id, prompt: "do it")
        case 1: return try await store.imageGenerate(id, jpeg: realJPEG(), prompt: "do it")
        default: return try await store.imageGenerate(id, jpeg: realJPEG(), region: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), prompt: "do it")
        }
    }
    func testStoreQueuedLeavesProjectUnchangedAllThreePaths() async throws {
        let store = ForgeStore.shared; let saved = store.projects; defer { store.projects = saved }
        for path in 0..<3 {
            let p = project(); store.projects = [p]; let before = snapshot(p)
            var sent: [(String, [String: Any])] = []
            ForgeQueued.transport = { body, key in
                sent.append((key, body))
                return (self.data(self.receipt(thread: body["threadID"] as? String)), 200)
            }
            let queued = try await run(path, store: store, id: p.id)
            XCTAssertTrue(queued)
            XCTAssertEqual(snapshot(store.project(p.id)!), before)
            XCTAssertNotNil(store.queuedNotice); store.queuedNotice = nil
            XCTAssertEqual(sent.count, 1); XCTAssertEqual(sent[0].0, sent[0].1["id"] as? String)
            XCTAssertFalse(store.project(p.id)!.versions.contains { $0.hasBuild })
        }
    }
    func testStoreBadReceiptThrowsAndKeepsKeyForRetry() async throws {
        let store = ForgeStore.shared; let saved = store.projects; defer { store.projects = saved }
        let p = project(); store.projects = [p]; let before = snapshot(p)
        var keys: [String] = []
        for bad in [{ (t: String) in self.receipt(["code": "x"], thread: t) }, { (t: String) in self.receipt(thread: "99999999-2222-3333-4444-555555555555") }] {
            ForgeQueued.transport = { body, key in keys.append(key); return (self.data(bad(body["threadID"] as! String)), 200) }
            do { _ = try await store.generate(p.id, prompt: "retry me"); XCTFail("must throw") } catch {}
            XCTAssertEqual(snapshot(store.project(p.id)!), before); XCTAssertNil(store.queuedNotice)
        }
        XCTAssertEqual(Set(keys).count, 1, "same request keeps the same key across lost/bad responses")
    }
    func testStoreLostResponseThenRetryReusesKey() async throws {
        let store = ForgeStore.shared; let saved = store.projects; defer { store.projects = saved }
        let p = project(); store.projects = [p]
        var keys: [String] = []
        ForgeQueued.transport = { _, key in keys.append(key); throw URLError(.networkConnectionLost) }
        do { _ = try await store.generate(p.id, prompt: "lost one"); XCTFail() } catch {}
        ForgeQueued.transport = { body, key in keys.append(key); return (self.data(self.receipt(["replayed": true], thread: body["threadID"] as? String)), 200) }
        let q = try await store.generate(p.id, prompt: "lost one")
        XCTAssertTrue(q); XCTAssertEqual(keys.count, 2); XCTAssertEqual(keys[0], keys[1])
    }
    func testStoreReadyCodeStillAddsVersion() async throws {
        let store = ForgeStore.shared; let saved = store.projects; defer { store.projects = saved }
        let p = project(); store.projects = [p]
        ForgeQueued.transport = { _, _ in (self.data(["code": "// new", "settings": [["key": "z", "title": "Z", "default": true]]]), 200) }
        let q = try await store.generate(p.id, prompt: "ready")
        XCTAssertFalse(q); XCTAssertEqual(store.project(p.id)!.versions.count, 2)
    }
}
