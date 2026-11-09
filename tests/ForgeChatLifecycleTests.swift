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
}
