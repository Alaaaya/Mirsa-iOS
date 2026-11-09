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
}
