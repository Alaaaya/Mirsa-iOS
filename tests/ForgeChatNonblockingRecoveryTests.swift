import XCTest
@testable import Mirsa

@MainActor
final class ForgeChatNonblockingRecoveryTests: XCTestCase {
    private let ok = Data("{}".utf8)
    private let list = Data("{\"threads\":[]}".utf8)

    func testFailedOlderMessageDoesNotBlockNewerMessageInSameThread() async {
        let tid = UUID()
        let old = ForgeChatOutgoing(id: UUID(), threadID: tid, newThread: true, text: "saved old", imageBase64: "original-image")
        let newer = ForgeChatOutgoing(id: UUID(), threadID: tid, newThread: true, text: "new message", imageBase64: nil)
        var calls: [[String: Any]] = []
        let store = ForgeChatStore(testRequest: { body in
            guard body["action"] as? String == "chat-send" else { return self.list }
            calls.append(body)
            if body["id"] as? String == old.id.uuidString.lowercased() { throw URLError(.timedOut) }
            return self.ok
        })
        store.outgoing = [old, newer]
        await store.flush()
        XCTAssertEqual(calls.compactMap { $0["id"] as? String }, [old.id, newer.id].map { $0.uuidString.lowercased() })
        XCTAssertEqual(store.outgoing, [old])
        XCTAssertEqual(store.sentEcho.map(\.id), [newer.id])
        XCTAssertNotNil(store.error)
        await store.flush()
        XCTAssertEqual(store.outgoing, [old])
        XCTAssertEqual(calls.last?["id"] as? String, old.id.uuidString.lowercased())
        XCTAssertEqual(calls.last?["text"] as? String, old.text)
        XCTAssertEqual((calls.last?["image"] as? [String: String])?["base64"], "original-image")
        XCTAssertEqual(store.sentEcho.map(\.id), [newer.id])
    }

    func testAttachment503PreservesOriginalBindingButDoesNotBlockOtherThread() async {
        let attachment = UUID()
        let old = ForgeChatOutgoing(id: UUID(), threadID: UUID(), newThread: true, text: "file message", imageBase64: nil, attachmentIDs: [attachment])
        let newer = ForgeChatOutgoing(id: UUID(), threadID: UUID(), newThread: true, text: "another thread", imageBase64: nil)
        var attempts: [[String: Any]] = []
        let store = ForgeChatStore(testRequest: { body in
            guard body["action"] as? String == "chat-send" else { return self.list }
            attempts.append(body)
            if body["id"] as? String == old.id.uuidString.lowercased() {
                throw ChatAttachmentError(status: 503, code: "provider_unavailable")
            }
            return self.ok
        })
        store.outgoing = [old, newer]
        await store.flush()
        await store.flush()
        XCTAssertEqual(store.outgoing, [old])
        XCTAssertEqual(store.sentEcho.map(\.id), [newer.id])
        let retries = attempts.filter { $0["id"] as? String == old.id.uuidString.lowercased() }
        XCTAssertEqual(retries.count, 2)
        for body in retries {
            XCTAssertEqual(body["threadID"] as? String, old.threadID.uuidString.lowercased())
            XCTAssertEqual(body["attachmentIDs"] as? [String], [attachment.uuidString.lowercased()])
            XCTAssertEqual(body["text"] as? String, old.text)
            XCTAssertNil(body["image"])
        }
    }

    func testComposerSendEnqueuesWhileOlderMessageIsUnsent() async {
        let tid = UUID()
        let old = ForgeChatOutgoing(id: UUID(), threadID: tid, newThread: true, text: "old", imageBase64: nil)
        let store = ForgeChatStore(testRequest: { _ in throw URLError(.notConnectedToInternet) })
        store.outgoing = [old]
        store.send(threadID: tid, text: "new", jpeg: nil)
        XCTAssertEqual(store.outgoing.count, 2)
        XCTAssertEqual(store.outgoing.first, old)
        XCTAssertEqual(store.outgoing.last?.text, "new")
        XCTAssertEqual(store.outgoing.last?.afterMessageID, old.id)
        XCTAssertNotEqual(store.outgoing.last?.id, old.id)
        await store.flush()
        XCTAssertEqual(store.outgoing.count, 2)
    }

    func testMessageAddedDuringAwaitIsAttemptedInSamePass() async {
        let tid = UUID()
        let old = ForgeChatOutgoing(id: UUID(), threadID: tid, newThread: true, text: "old", imageBase64: nil)
        let newer = ForgeChatOutgoing(id: UUID(), threadID: tid, newThread: true, text: "arrived during network", imageBase64: nil)
        var store: ForgeChatStore!
        var sent: [String] = []
        store = ForgeChatStore(testRequest: { body in
            guard body["action"] as? String == "chat-send" else { return self.list }
            sent.append(body["id"] as! String)
            if body["id"] as? String == old.id.uuidString.lowercased() {
                store.outgoing.append(newer)
                throw URLError(.timedOut)
            }
            return self.ok
        })
        store.outgoing = [old]
        await store.flush()
        XCTAssertEqual(sent, [old.id, newer.id].map { $0.uuidString.lowercased() })
        XCTAssertEqual(store.outgoing, [old])
        XCTAssertEqual(store.sentEcho.map(\.id), [newer.id])
    }

    func testQuotaFailureNeverSilentlyDropsSavedMessages() async {
        let old = ForgeChatOutgoing(id: UUID(), threadID: UUID(), newThread: true, text: "keep me", imageBase64: nil)
        let store = ForgeChatStore(testRequest: { body in
            if body["action"] as? String == "chat-send" { throw ForgeClient.Failure.message("limit") }
            return self.list
        })
        store.outgoing = [old]
        await store.flush()
        XCTAssertEqual(store.outgoing, [old])
        XCTAssertTrue(store.sentEcho.isEmpty)
        XCTAssertEqual(store.error, "limit")
    }
}
