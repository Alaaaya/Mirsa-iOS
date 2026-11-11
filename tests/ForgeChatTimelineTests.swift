import Foundation
import XCTest
#if canImport(MirsaStoreKit)
@testable import MirsaStoreKit
#else
@testable import Mirsa
#endif

final class ForgeChatTimelineTests: XCTestCase {
    private let thread = UUID()
    private func outgoing() -> ForgeChatOutgoing {
        ForgeChatOutgoing(id: UUID(), threadID: thread, newThread: true, text: "Hello", imageBase64: "image")
    }
    private func message(_ id: UUID = UUID(), text: String = "Hello") -> ForgeChatMessage {
        ForgeChatMessage(id: id, threadID: thread, role: "user", text: text)
    }

    func testAcceptedEchoKeepsIdentityTextThreadButDropsUploadedImage() {
        let sent = outgoing()
        let echo = ForgeChatTimeline.acceptedEcho(sent)
        XCTAssertEqual(echo.id, sent.id)
        XCTAssertEqual(echo.threadID, sent.threadID)
        XCTAssertEqual(echo.text, sent.text)
        XCTAssertNil(echo.imageBase64)
    }

    func testEchoSurvivesCodableRelaunchAndLaggingRead() throws {
        let sent = outgoing()
        let saved = try JSONEncoder().encode([ForgeChatTimeline.acceptedEcho(sent)])
        let restored = try JSONDecoder().decode([ForgeChatOutgoing].self, from: saved)
        XCTAssertEqual(ForgeChatTimeline.pending(outgoing: [], echoes: restored, confirmed: [], threadID: thread).map(\.id), [sent.id])
    }

    func testRetryAndEchoWithSameIDRenderOnlyOneRow() {
        let sent = outgoing()
        let rows = ForgeChatTimeline.pending(outgoing: [sent], echoes: [ForgeChatTimeline.acceptedEcho(sent)], confirmed: [], threadID: thread)
        XCTAssertEqual(rows.map(\.id), [sent.id])
    }

    func testServerAcknowledgementReplacesEchoWithoutChangingVisibleID() {
        let sent = outgoing()
        let echo = ForgeChatTimeline.acceptedEcho(sent)
        let before = ForgeChatTimeline.pending(outgoing: [], echoes: [echo], confirmed: [], threadID: thread).map(\.id)
        let confirmed = [message(sent.id)]
        let pending = ForgeChatTimeline.pending(outgoing: [], echoes: [echo], confirmed: confirmed, threadID: thread)
        XCTAssertEqual(confirmed.map(\.id) + pending.map(\.id), before)
    }

    func testEmptyAndStalePartialReadsCannotRemoveVisibleMessages() {
        let first = message(), second = message()
        let previous = [first, second]
        XCTAssertEqual(ForgeChatTimeline.mergeConfirmed(previous: previous, incoming: []), previous)
        XCTAssertEqual(ForgeChatTimeline.mergeConfirmed(previous: previous, incoming: [first]), previous)
    }

    func testUnchangedReadIsEqualAndUpdatedTextKeepsSameID() {
        let first = message(), second = message()
        XCTAssertEqual(ForgeChatTimeline.mergeConfirmed(previous: [first, second], incoming: [first, second]), [first, second])
        let edited = message(first.id, text: "Updated")
        let merged = ForgeChatTimeline.mergeConfirmed(previous: [first, second], incoming: [edited])
        XCTAssertEqual(merged.map(\.id), [first.id, second.id])
        XCTAssertEqual(merged.first?.text, "Updated")
    }

    func testNewReplyAppendsExactlyOnceAndDuplicateServerIDsAreDeduplicated() {
        let first = message(), reply = message()
        let merged = ForgeChatTimeline.mergeConfirmed(previous: [first], incoming: [first, reply, reply])
        XCTAssertEqual(merged.map(\.id), [first.id, reply.id])
    }

    func testPendingEchoStaysBeforeNewerSendAndOtherThreadsStayHidden() {
        let first = outgoing(), second = outgoing()
        let other = ForgeChatOutgoing(id: UUID(), threadID: UUID(), newThread: true, text: "Other", imageBase64: nil)
        XCTAssertEqual(ForgeChatTimeline.pending(outgoing: [second, other], echoes: [first], confirmed: [], threadID: thread).map(\.id), [first.id, second.id])
    }
    func testReplyBeforeUserReadIsReconciledToServerCausalOrderWithoutDuplicates() {
        let sent = outgoing()
        let user = message(sent.id)
        let reply = ForgeChatMessage(id: UUID(), threadID: thread, role: "assistant", text: "Answer")
        let merged = ForgeChatTimeline.mergeConfirmed(previous: [reply], incoming: [user, reply, reply])
        XCTAssertEqual(merged.map(\.id), [user.id, reply.id])
        XCTAssertEqual(ForgeChatTimeline.mergeConfirmed(previous: merged, incoming: [user, reply]), merged)
    }

    func testFirstOptimisticSendStaysBeforeReplyUntilServerUserArrives() {
        let sent = outgoing()
        let echo = ForgeChatTimeline.acceptedEcho(sent)
        let reply = ForgeChatMessage(id: UUID(), threadID: thread, role: "assistant", text: "Answer")
        let pending = ForgeChatTimeline.pending(outgoing: [], echoes: [echo], confirmed: [reply], threadID: thread)
        XCTAssertEqual(ForgeChatTimeline.orderedIDs(confirmed: [reply], pending: pending), [sent.id, reply.id])
        let confirmed = ForgeChatTimeline.mergeConfirmed(previous: [reply], incoming: [message(sent.id), reply])
        XCTAssertEqual(ForgeChatTimeline.orderedIDs(confirmed: confirmed, pending: [echo]), [sent.id, reply.id])
    }

    func testFollowupEchoStaysAfterPriorReplyButBeforeItsOwnReply() throws {
        let priorUser = message()
        let priorReply = ForgeChatMessage(id: UUID(), threadID: thread, role: "kat", text: "Earlier")
        let sent = ForgeChatOutgoing(id: UUID(), threadID: thread, newThread: false, text: "Followup", imageBase64: nil, afterMessageID: priorReply.id)
        let echo = try JSONDecoder().decode(ForgeChatOutgoing.self, from: JSONEncoder().encode(ForgeChatTimeline.acceptedEcho(sent)))
        let reply = ForgeChatMessage(id: UUID(), threadID: thread, role: "assistant", text: "Later")
        XCTAssertEqual(ForgeChatTimeline.orderedIDs(confirmed: [priorUser, priorReply, reply], pending: [echo]), [priorUser.id, priorReply.id, sent.id, reply.id])
        XCTAssertEqual(echo.afterMessageID, priorReply.id)
    }

    func testMultiplePendingRowsKeepSendOrderAndStableIDs() {
        let prior = message()
        let first = ForgeChatOutgoing(id: UUID(), threadID: thread, newThread: false, text: "One", imageBase64: nil, afterMessageID: prior.id)
        let second = ForgeChatOutgoing(id: UUID(), threadID: thread, newThread: false, text: "Two", imageBase64: nil, afterMessageID: first.id)
        let reply = message()
        XCTAssertEqual(ForgeChatTimeline.orderedIDs(confirmed: [prior, reply], pending: [first, second, first]), [prior.id, first.id, second.id, reply.id])
    }

    func testCanonicalReorderRetainsRowsMissingFromPartialPoll() {
        let first = message(), missing = message(), late = message()
        let merged = ForgeChatTimeline.mergeConfirmed(previous: [late, missing, first], incoming: [first, late])
        XCTAssertEqual(merged.map(\.id), [first.id, missing.id, late.id])
        XCTAssertEqual(ForgeChatTimeline.mergeConfirmed(previous: merged, incoming: []), merged)
    }

    func testLegacySavedDraftWithoutAnchorStillDecodesAndRendersOnce() throws {
        let sent = outgoing()
        let data = try JSONEncoder().encode(sent)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "afterMessageID")
        let restored = try JSONDecoder().decode(ForgeChatOutgoing.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(restored.afterMessageID)
        XCTAssertEqual(ForgeChatTimeline.orderedIDs(confirmed: [], pending: [restored, restored]), [sent.id])
    }


    // Mirsa 2.1 attachments: IDs survive relaunch/retry, legacy rows stay decodable, metadata is tolerant.
    func testAttachmentIDsSurviveCodableAndEcho() throws {
        let ids = [UUID(), UUID()]
        let sent = ForgeChatOutgoing(id: UUID(), threadID: thread, newThread: true, text: "Hello", imageBase64: nil, attachmentIDs: ids)
        let restored = try JSONDecoder().decode([ForgeChatOutgoing].self, from: JSONEncoder().encode([sent]))
        XCTAssertEqual(restored.first?.attachmentIDs, ids)
        XCTAssertEqual(restored.first?.id, sent.id)
        XCTAssertEqual(ForgeChatTimeline.acceptedEcho(sent).attachmentIDs, ids)
        let legacy = Data("[{\"id\":\"\(UUID().uuidString)\",\"threadID\":\"\(thread.uuidString)\",\"newThread\":true,\"text\":\"x\"}]".utf8)
        XCTAssertNil(try JSONDecoder().decode([ForgeChatOutgoing].self, from: legacy).first?.attachmentIDs)
    }

    func testMessageAttachmentsDecodeTolerantly() throws {
        let a = UUID()
        let json = """
        {"id":"\(UUID().uuidString)","threadID":"\(thread.uuidString)","role":"user","text":"hi",
         "attachments":[{"id":"\(a.uuidString)","kind":"link","name":"example.com","url":"https://example.com","available":true},{"bogus":1},
                        {"id":"\(UUID().uuidString)","kind":"image","name":"photo.jpg","mime":"image/jpeg","size":1234,"expiresAt":"2000-01-01T00:00:00Z","available":false}]}
        """
        let m = try JSONDecoder().decode(ForgeChatMessage.self, from: Data(json.utf8))
        XCTAssertEqual(m.attachments?.count, 2)
        XCTAssertEqual(m.attachments?.first?.id, a)
        XCTAssertEqual(m.attachments?.last?.isExpired(), true)
        XCTAssertNil(try JSONDecoder().decode(ForgeChatMessage.self, from: Data("{\"id\":\"\(UUID().uuidString)\",\"role\":\"kat\"}".utf8)).attachments)
    }
}
