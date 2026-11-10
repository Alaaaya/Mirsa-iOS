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
}
