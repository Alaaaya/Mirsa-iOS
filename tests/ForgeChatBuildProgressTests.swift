import Foundation
import SwiftUI
import UIKit
import XCTest
#if canImport(MirsaStoreKit)
@testable import MirsaStoreKit
#else
@testable import Mirsa
#endif

final class ForgeChatBuildProgressTests: XCTestCase {
    private func json(_ id: UUID, _ pid: UUID, phase: String = "building", fraction: String = "0.4") -> Data {
        Data("{\"id\":\"\(id)\",\"role\":\"user\",\"buildProgress\":{\"requestMessageID\":\"\(pid)\",\"phase\":\"\(phase)\",\"fraction\":\(fraction),\"events\":[{\"phase\":\"building\",\"line\":\"x\"}]}}".utf8)
    }
    private func user(_ id: UUID = UUID()) -> ForgeChatMessage { ForgeChatMessage(id: id, threadID: UUID(), role: "user", text: "t") }

    func testExactIDMatchShows() throws {
        let id = UUID()
        XCTAssertEqual(try JSONDecoder().decode(ForgeChatMessage.self, from: json(id, id)).buildProgress?.fraction, 0.4)
    }
    func testMismatchedIDDropped() throws {
        XCTAssertNil(try JSONDecoder().decode(ForgeChatMessage.self, from: json(UUID(), UUID())).buildProgress)
    }
    func testUnknownPhaseDropped() throws {
        let id = UUID()
        XCTAssertNil(try JSONDecoder().decode(ForgeChatMessage.self, from: json(id, id, phase: "bogus")).buildProgress)
    }
    func testInvalidFractionBecomesUnknownNotFake() throws {
        let id = UUID()
        XCTAssertNil(try JSONDecoder().decode(ForgeChatMessage.self, from: json(id, id, fraction: "7")).buildProgress?.fraction)
        XCTAssertNil(ChatBuildProgress.cleanFraction(.nan))
        XCTAssertNil(ChatBuildProgress.cleanFraction(-0.5))
    }
    func testMissingFieldKeepsMessageAndEventsBounded() throws {
        let id = UUID()
        XCTAssertNil(try JSONDecoder().decode(ForgeChatMessage.self, from: Data("{\"id\":\"\(id)\",\"role\":\"user\"}".utf8)).buildProgress)
        let many = (0..<100).map { _ in ChatBuildEvent(phase: .building, line: String(repeating: "a", count: 500), at: nil) }
        let p = ChatBuildProgress(requestMessageID: id, phase: .building, events: many)
        XCTAssertEqual(p.events.count, 40); XCTAssertEqual(p.events[0].line.count, 160)
    }
    func testEncodeRoundTrip() throws {
        let id = UUID()
        var m = user(id); m.buildProgress = ChatBuildProgress(requestMessageID: id, phase: .check, fraction: 0.8)
        let back = try JSONDecoder().decode(ForgeChatMessage.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back.buildProgress, m.buildProgress)
    }

    // MARK: real lifecycle fallback
    func testLifecycleLossyDecodeAndExactBinding() {
        let src = UUID(), lid = UUID()
        let data = Data("{\"lifecycle\":[{\"bad\":1},{\"id\":\"\(lid)\",\"sourceMessageID\":\"\(src)\",\"kind\":\"k\",\"state\":\"working\",\"version\":2}]}".utf8)
        let rows = ChatLifecycleEntry.lossy(data)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(ChatBuildPresentation.resolve(message: user(src), lifecycle: rows, messages: []).map { $0.phase }, .building)
        XCTAssertNil(ChatBuildPresentation.resolve(message: user(), lifecycle: rows, messages: []))
        XCTAssertTrue(ChatBuildPresentation.resolve(message: user(src), lifecycle: rows, messages: [])!.coarse)
    }
    func testQueuedAndUnknownStates() {
        let src = UUID()
        let q = ChatLifecycleEntry(id: UUID(), sourceMessageID: src, state: "queued")
        XCTAssertEqual(ChatBuildPresentation.resolve(message: user(src), lifecycle: [q], messages: [])?.phase, .queued)
        for s in ["clarification", "unknown", "weird"] {
            XCTAssertNil(ChatBuildPresentation.resolve(message: user(src), lifecycle: [ChatLifecycleEntry(id: UUID(), sourceMessageID: src, state: s)], messages: []))
        }
    }
    func testReadyNeedsMatchingArtifact() {
        let src = UUID(), art = UUID(), thread = UUID()
        let e = ChatLifecycleEntry(id: UUID(), sourceMessageID: src, state: "ready", artifactID: art)
        XCTAssertNil(ChatBuildPresentation.resolve(message: user(src), lifecycle: [e], messages: [user(src)]))
        let res = ForgeChatResult(inboxID: nil, tweakID: nil, bundleID: nil, name: nil, version: nil,
                                  artifact: ForgeChatArtifact(id: art, kind: "file", name: nil, size: nil, sha256: nil, expiresAt: nil))
        let reply = ForgeChatMessage(id: UUID(), threadID: thread, role: "result", text: nil, result: res)
        XCTAssertEqual(ChatBuildPresentation.resolve(message: user(src), lifecycle: [e], messages: [user(src), reply])?.phase, .ready)
        XCTAssertFalse(ChatBuildPresentation.resolve(message: user(src), lifecycle: [e], messages: [user(src), reply])!.isRunning)
    }

    // MARK: style selection (one at a time)
    func testOnlyOneStyleAtATime() {
        let id = UUID(); var m = user(id)
        m.buildProgress = ChatBuildProgress(requestMessageID: id, phase: .building)
        XCTAssertNotNil(ChatBuildPresentation.card(style: .terminal, message: m, lifecycle: [], messages: [m]))
        XCTAssertNil(ChatBuildPresentation.pill(style: .terminal, messages: [m], lifecycle: []))
        XCTAssertNil(ChatBuildPresentation.card(style: .pill, message: m, lifecycle: [], messages: [m]))
        XCTAssertNotNil(ChatBuildPresentation.pill(style: .pill, messages: [m], lifecycle: []))
        m.buildProgress = ChatBuildProgress(requestMessageID: id, phase: .ready)
        XCTAssertNil(ChatBuildPresentation.pill(style: .pill, messages: [m], lifecycle: []))
    }
    func testStyleDefaultsToTerminalAndPersists() {
        let d = UserDefaults.standard
        let old = d.object(forKey: ChatBuildStyle.key)
        defer { if let old { d.set(old, forKey: ChatBuildStyle.key) } else { d.removeObject(forKey: ChatBuildStyle.key) } }
        d.removeObject(forKey: ChatBuildStyle.key)
        XCTAssertEqual(ChatBuildStyle.resolve(d.string(forKey: ChatBuildStyle.key) ?? ""), .terminal)
        d.set(ChatBuildStyle.pill.rawValue, forKey: ChatBuildStyle.key)
        XCTAssertEqual(ChatBuildStyle.resolve(d.string(forKey: ChatBuildStyle.key) ?? ""), .pill)
        XCTAssertEqual(ChatBuildStyle.resolve("junk"), .terminal)
    }

    // MARK: synthetic render snapshots, 5 languages x 2 styles (SYNTHETIC fixtures, not real builds)
    @MainActor func testRenderAllLanguagesAndStyles() throws {
        let d = UserDefaults.standard
        let old = d.object(forKey: AppLanguageStore.key)
        defer { if let old { d.set(old, forKey: AppLanguageStore.key) } else { d.removeObject(forKey: AppLanguageStore.key) } }
        let id = UUID()
        let p = ChatBuildProgress(requestMessageID: id, buildID: "SYNTHETIC-TEST", phase: .building, fraction: 0.5, title: "SYNTHETIC TEST",
                                  events: [ChatBuildEvent(phase: .building, line: "SYNTHETIC TEST line", at: nil)])
        let coarse = ChatBuildProgress(requestMessageID: id, phase: .queued, coarse: true)
        for lang in AppLanguage.allCases {
            d.set(lang.rawValue, forKey: AppLanguageStore.key)
            let views: [(String, AnyView)] = [
                ("terminal", AnyView(ChatBuildTerminalCard(progress: p))),
                ("terminal-coarse", AnyView(ChatBuildTerminalCard(progress: coarse))),
                ("pill", AnyView(ChatBuildPill(progress: p))),
                ("pill-coarse", AnyView(ChatBuildPill(progress: coarse)))]
            for (name, v) in views {
                let r = ImageRenderer(content: v.padding(16).background(Color.gray).environment(\.colorScheme, .dark))
                r.scale = 2
                let img = try XCTUnwrap(r.uiImage, "\(name) \(lang.rawValue)")
                XCTAssertGreaterThan(img.size.width, 50)
                let att = XCTAttachment(image: img)
                att.name = "SYNTHETIC-\(name)-\(lang.rawValue)"; att.lifetime = .keepAlways
                add(att)
            }
        }
    }

    // MARK: encode + ready rules
    func testEncodeOmitsCoarse() throws {
        let p = ChatBuildProgress(requestMessageID: UUID(), phase: .building, coarse: true)
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any]
        XCTAssertNil(obj?["coarse"]); XCTAssertNotNil(obj?["phase"])
    }
    func testExplicitReadyRequiresArtifact() {
        let src = UUID(); var m = user(src)
        m.buildProgress = ChatBuildProgress(requestMessageID: src, phase: .ready)
        XCTAssertNil(ChatBuildPresentation.resolve(message: m, lifecycle: [], messages: [m]))
        let art = UUID()
        let e = ChatLifecycleEntry(id: UUID(), sourceMessageID: src, state: "ready", artifactID: art)
        let res = ForgeChatResult(inboxID: nil, tweakID: nil, bundleID: nil, name: nil, version: nil,
                                  artifact: ForgeChatArtifact(id: art, kind: "file", name: nil, size: nil, sha256: nil, expiresAt: nil))
        let reply = ForgeChatMessage(id: UUID(), threadID: m.threadID, role: "result", text: nil, result: res)
        XCTAssertNotNil(ChatBuildPresentation.resolve(message: m, lifecycle: [e], messages: [m, reply]))
    }

    // MARK: full thread hosted snapshots (SYNTHETIC fixture, no network)
    @MainActor func testFullThreadSnapshots() async throws {
        let d = UserDefaults.standard
        let keys = [AppLanguageStore.key, ChatBuildStyle.key]
        let old = keys.map { d.object(forKey: $0) }
        defer { for (k, v) in zip(keys, old) { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } } }
        for lang in [AppLanguage.arabic, .german] {
            for style in [ChatBuildStyle.terminal, .pill] {
                d.set(lang.rawValue, forKey: AppLanguageStore.key); d.set(style.rawValue, forKey: ChatBuildStyle.key)
                let store = ForgeChatStore(testRequest: { _ in throw URLError(.notConnectedToInternet) })
                let tid = UUID(), mid = UUID()
                store.threads = [ForgeChatThread(id: tid, title: "SYNTHETIC TEST", status: "open", createdAt: nil, updatedAt: nil)]
                store.messages[tid] = [ForgeChatMessage(id: mid, threadID: tid, role: "user", text: "SYNTHETIC TEST request")]
                store.lifecycle[tid] = [ChatLifecycleEntry(id: UUID(), sourceMessageID: mid, state: "working")]
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
                window.rootViewController = UIHostingController(rootView: ForgeChatThreadView(threadID: tid, store: store))
                window.makeKeyAndVisible()
                try await Task.sleep(nanoseconds: 400_000_000)
                let img = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                let att = XCTAttachment(image: img)
                att.name = "SYNTHETIC-thread-\(style.rawValue)-\(lang.rawValue)"; att.lifetime = .keepAlways
                add(att)
                window.isHidden = true
            }
        }
    }
}
