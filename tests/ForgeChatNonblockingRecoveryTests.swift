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
    func testSuccessfulRetryClearsSendBanner() async {
        let pending = ForgeChatOutgoing(id: UUID(), threadID: UUID(), newThread: true, text: "retry", imageBase64: nil)
        var fail = true
        let store = ForgeChatStore(testRequest: { body in
            guard body["action"] as? String == "chat-send" else { return self.list }
            if fail { throw URLError(.timedOut) }
            return self.ok
        })
        store.outgoing = [pending]
        await store.flush()
        XCTAssertEqual(store.error, ForgeChatText.failed)
        fail = false
        await store.flush()
        XCTAssertTrue(store.outgoing.isEmpty)
        XCTAssertNil(store.error)
    }

    func testServerConfirmedMessageClearsTimedOutSendButNotOtherPendingFailure() async throws {
        let tid = UUID()
        let confirmed = ForgeChatOutgoing(id: UUID(), threadID: tid, newThread: true, text: "arrived", imageBase64: nil)
        let other = ForgeChatOutgoing(id: UUID(), threadID: tid, newThread: true, text: "still offline", imageBase64: nil)
        let rows = [ForgeChatMessage(id: confirmed.id, threadID: tid, role: "user", text: confirmed.text),
                    ForgeChatMessage(id: UUID(), threadID: tid, role: "kat", text: "reply")]
        struct Read: Encodable { let messages: [ForgeChatMessage] }
        let response = try JSONEncoder().encode(Read(messages: rows))
        let store = ForgeChatStore(testRequest: { _ in response })
        store.threads = [ForgeChatThread(id: tid, title: nil, status: "open", createdAt: nil, updatedAt: nil)]
        store.outgoing = [confirmed, other]
        store.error = ForgeChatText.failed
        await store.read(tid)
        XCTAssertEqual(store.outgoing, [other])
        XCTAssertEqual(store.error, ForgeChatText.failed)
        // An unrelated assistant reply must not pretend that the other UUID was sent.
        await store.read(tid)
        XCTAssertEqual(store.outgoing, [other])
        store.outgoing = [confirmed]
        await store.read(tid)
        XCTAssertTrue(store.outgoing.isEmpty)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.messages[tid]?.count, 2)
    }
    func testOnlyNonattachment409BecomesConversationConflict() {
        for code in ["intake_changed", "confirmation_required", "id_conflict", "other_conflict", ""] {
            XCTAssertNotNil(ForgeChatConversationConflict.response(status: 409, code: code), code)
        }
        for code in ["attachment_in_use", "attachment_storage_limit", "attachment_conflict", "bad_attachment_ids", "attachments_disabled"] {
            XCTAssertNil(ForgeChatConversationConflict.response(status: 409, code: code), code)
        }
        // Do not change auth, quota, expiry, validation or transient retry behavior.
        for status in [200, 401, 403, 404, 410, 422, 429, 503] {
            XCTAssertNil(ForgeChatConversationConflict.response(status: status, code: "intake_changed"))
        }
    }

    func testConversationConflictPersistsPayloadAndReloadNeverAutomaticallyResends() async throws {
        for code in ["intake_changed", "confirmation_required", "id_conflict", "unknown_conflict"] {
            let row = ForgeChatOutgoing(id: UUID(), threadID: UUID(), newThread: true,
                text: "hide side buttons too", imageBase64: nil, attachmentIDs: [UUID()])
            var attempts = 0
            let store = ForgeChatStore(testRequest: { body in
                guard body["action"] as? String == "chat-send" else { return self.list }
                attempts += 1
                throw ForgeChatConversationConflict.response(status: 409, code: code)!
            })
            store.outgoing = [row]
            await store.flush()
            await store.flush()
            XCTAssertEqual(attempts, 1)
            XCTAssertEqual(store.outgoing.first?.id, row.id)
            XCTAssertEqual(store.outgoing.first?.text, row.text)
            XCTAssertEqual(store.outgoing.first?.attachmentIDs, row.attachmentIDs)
            XCTAssertEqual(store.outgoing.first?.conversationConflict, code)
            XCTAssertTrue(store.sentEcho.isEmpty)
            XCTAssertTrue(store.returnedText.isEmpty) // never restore chips as unavailable
            XCTAssertEqual(store.error, ForgeChatConversationConflict(code: code).message)

            // Same Codable persistence path as the production outgoing v1 queue.
            let disk = try JSONEncoder().encode(store.outgoing)
            let reloaded = ForgeChatStore(testRequest: { body in
                if body["action"] as? String == "chat-send" { attempts += 1 }
                return self.list
            })
            reloaded.outgoing = try JSONDecoder().decode([ForgeChatOutgoing].self, from: disk)
            await reloaded.flush()
            XCTAssertEqual(attempts, 1)
            XCTAssertEqual(reloaded.outgoing, store.outgoing)
            XCTAssertTrue(reloaded.sentEcho.isEmpty)
        }
    }

    func testExplicitSameTextSendResumesOriginalIDAndUploadedAttachments() async throws {
        let row = ForgeChatOutgoing(id: UUID(), threadID: UUID(), newThread: true,
            text: "hide side buttons too", imageBase64: nil, attachmentIDs: [UUID()])
        var paused = row
        paused.conversationConflict = "intake_changed"
        var calls: [[String: Any]] = []
        let store = ForgeChatStore(testRequest: { body in
            guard body["action"] as? String == "chat-send" else { return self.list }
            calls.append(body)
            return self.ok
        })
        store.outgoing = [paused]
        // Empty composer chips must reuse the original uploaded IDs, not lose them.
        let id = store.send(threadID: row.threadID, text: row.text, jpeg: nil)
        XCTAssertEqual(id, row.id)
        await store.flush()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?["id"] as? String, row.id.uuidString.lowercased())
        XCTAssertEqual(calls.first?["text"] as? String, row.text)
        XCTAssertEqual(calls.first?["attachmentIDs"] as? [String], row.attachmentIDs?.map { $0.uuidString.lowercased() })
        XCTAssertNil(calls.first?["image"])
        XCTAssertTrue(store.outgoing.isEmpty)
        XCTAssertEqual(store.sentEcho.map(\.id), [row.id])
    }

    func testNewConversationTextNeverUnpausesOrConfirmsConflictedMessage() async {
        var paused = ForgeChatOutgoing(id: UUID(), threadID: UUID(), newThread: true,
            text: "make a tweak", imageBase64: nil, attachmentIDs: [UUID()])
        paused.conversationConflict = "confirmation_required"
        var calls: [[String: Any]] = []
        let store = ForgeChatStore(testRequest: { body in
            guard body["action"] as? String == "chat-send" else { return self.list }
            calls.append(body)
            return self.ok
        })
        store.outgoing = [paused]
        let id = store.send(threadID: paused.threadID, text: "what do you mean?", jpeg: nil)
        await store.flush()
        XCTAssertNotEqual(id, paused.id)
        XCTAssertEqual(store.outgoing, [paused])
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?["text"] as? String, "what do you mean?")
        XCTAssertNil(calls.first?["attachmentIDs"])
    }

    func testSavedOutgoingV1WithoutConflictFieldStillDecodes() throws {
        let row = ForgeChatOutgoing(id: UUID(), threadID: UUID(), newThread: true, text: "saved", imageBase64: nil)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any])
        object.removeValue(forKey: "conversationConflict")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(ForgeChatOutgoing.self, from: legacy)
        XCTAssertNil(decoded.conversationConflict)
        XCTAssertEqual(decoded, row)
    }


}
