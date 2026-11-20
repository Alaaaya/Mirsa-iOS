import XCTest
import CryptoKit
@testable import Mirsa

final class ChatVoiceTests: XCTestCase {
    func testAudioIntegrityRejectsSizeSHAAndNonMP4() throws {
        let data = Data([0,0,0,24]) + Data("ftypM4A ".utf8) + Data(repeating: 0, count: 32)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        func meta(size: Int64? = nil, digest: String? = nil, kind: String = "audio") -> ChatAttachmentMeta {
            ChatAttachmentMeta(id: UUID(), kind: kind, name: "voice.m4a", mime: "audio/mp4",
                size: size ?? Int64(data.count), durationMS: 1000, sha256: digest ?? sha)
        }
        XCTAssertNoThrow(try ChatVoiceRules.verify(data, meta: meta()))
        XCTAssertThrowsError(try ChatVoiceRules.verify(data, meta: nil))
        XCTAssertThrowsError(try ChatVoiceRules.verify(data, meta: meta(size: 1)))
        XCTAssertThrowsError(try ChatVoiceRules.verify(data, meta: meta(digest: String(repeating: "0", count: 64))))
        XCTAssertThrowsError(try ChatVoiceRules.verify(data, meta: meta(kind: "file")))
        XCTAssertThrowsError(try ChatVoiceRules.verify(Data(), meta: meta()))
    }
    func testClockAndLimits() {
        XCTAssertEqual(ChatVoiceRules.clock(0), "0:00")
        XCTAssertEqual(ChatVoiceRules.clock(61.9), "1:01")
        XCTAssertEqual(ChatVoiceRules.clock(300), "5:00")
        XCTAssertEqual(ChatVoiceRules.maxBytes, 5_242_880)
    }
    func testBotReactionRoundTripAndUnsupportedEmoji() throws {
        let thread = UUID(), id = UUID()
        var message = ForgeChatMessage(id: id, threadID: thread, role: "user", text: "hello")
        message.botReaction = "🔥"; message.reaction = "❤️"
        var decoded = try JSONDecoder().decode(ForgeChatMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(decoded.botReaction, "🔥")
        XCTAssertEqual(decoded.reaction, "❤️")
        message.botReaction = "not an emoji"
        decoded = try JSONDecoder().decode(ForgeChatMessage.self, from: JSONEncoder().encode(message))
        XCTAssertNil(decoded.botReaction)
    }
    func testAudioCannotBeEditedOrDeleted() {
        let thread = UUID(), id = UUID()
        let audio = ChatAttachmentMeta(id: UUID(), kind: "audio", name: "voice.m4a")
        let message = ForgeChatMessage(id: id, threadID: thread, role: "user", text: "", attachments: [audio])
        XCTAssertFalse(ForgeChatMutationPolicy.canMutate(messageID: id, messages: [message], hasPending: false, status: "open"))
    }
    @MainActor func testVoiceLabelsUseAllFiveActualLocales() {
        let previous = AppLanguageStore.shared.current
        defer { AppLanguageStore.shared.set(previous) }
        var values = Set<String>()
        for language in AppLanguage.allCases {
            AppLanguageStore.shared.set(language)
            XCTAssertFalse(ChatVoiceText.record.isEmpty)
            XCTAssertFalse(ChatVoiceText.permission.isEmpty)
            values.insert(ChatVoiceText.permission)
        }
        XCTAssertEqual(values.count, 5)
    }
}
