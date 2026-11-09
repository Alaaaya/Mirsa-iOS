import XCTest
@testable import Mirsa

@MainActor
final class ForgeChatLifecycleTests: XCTestCase {
    func testDraftThreadStaysStableAcrossReopenAndPendingMessage() {
        let store = ForgeChatStore()
        store.outgoing = []
        UserDefaults.standard.removeObject(forKey: "mirsa.chat.draftThread.v1")
        let first = store.draftThreadID()
        XCTAssertEqual(first, store.draftThreadID())
        XCTAssertEqual(first, store.draftThreadID())
        // an unsent first message pins the same canonical thread
        let o = ForgeChatOutgoing(id: UUID(), threadID: first, newThread: true, text: "x", imageBase64: nil)
        store.outgoing = [o]
        XCTAssertEqual(first, store.draftThreadID())
        XCTAssertTrue(store.hasInFlight(first))
        XCTAssertEqual(store.pendingThreadIDs, [first])
        // a retry keeps the same ids
        XCTAssertEqual(store.outgoing.first?.id, o.id)
        store.outgoing = []
    }

    func testReplyWithRoleKatAndExtraFieldsDecodesAndSurvivesBadSibling() throws {
        let tid = UUID().uuidString.lowercased()
        let json = """
        {"messages":[
         {"id":"\(UUID().uuidString.lowercased())","threadID":"\(tid)","role":"user","text":"hi","createdAt":"2026-11-09T17:43:16Z","hasImage":false,"result":null},
         {"id":"\(UUID().uuidString.lowercased())","role":"kat","text":"reply","createdAt":null,"extra":{"a":1},"hasImage":"no"},
         {"id":"not-a-uuid","role":"kat","text":"bad"}
        ]}
        """.data(using: .utf8)!
        struct Lossy: Decodable { let value: ForgeChatMessage?; init(from d: Decoder) throws { value = try? ForgeChatMessage(from: d) } }
        struct W: Decodable { let messages: [Lossy] }
        let m = try JSONDecoder().decode(W.self, from: json).messages.compactMap(\.value)
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(m[1].role, "kat")
        XCTAssertEqual(m[1].text, "reply")
    }

    /// Exact sanitized live backend shape (6-digit fractional +00:00 dates, result null, role "kat"). Must decode with the strict model, none skipped.
    func testLiveBackendChatReadShapeDecodesStrictly() throws {
        let json = """
        {"thread":{"id":"75dce450-e96d-4895-b7d5-7606e8ae41af","title":"Disposable decode regression fixture","status":"working","createdAt":"2026-11-09T17:47:29.582498+00:00","updatedAt":"2026-11-09T17:47:30.992884+00:00"},"messages":[{"id":"ca6bc0cd-20b4-4c05-babd-67c7996d9ca0","threadID":"75dce450-e96d-4895-b7d5-7606e8ae41af","role":"user","text":"Disposable decode regression fixture","createdAt":"2026-11-09T17:47:29.582498+00:00","hasImage":false,"result":null},{"id":"0ae45156-990a-4537-8660-705ae49bf373","threadID":"75dce450-e96d-4895-b7d5-7606e8ae41af","role":"kat","text":"Representative operator reply for decoder regression.","createdAt":"2026-11-09T17:47:30.992884+00:00","hasImage":false,"result":null}]}
        """.data(using: .utf8)!
        struct W: Decodable { let messages: [ForgeChatMessage] }
        let m = try JSONDecoder().decode(W.self, from: json).messages
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(m[1].role, "kat")
        XCTAssertEqual(m[1].text, "Representative operator reply for decoder regression.")
    }
}
