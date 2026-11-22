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
    @MainActor func testOnlyCurrentAudioOwnerCanStopSession() {
        let first = UUID(), second = UUID(), third = UUID()
        var stops: [UUID] = []
        ChatVoiceSession.acquire(first) { stops.append(first) }
        ChatVoiceSession.acquire(second) { stops.append(second) }
        XCTAssertEqual(stops, [first])
        ChatVoiceSession.release(first) // An idle/offscreen bubble must not evict second.
        ChatVoiceSession.acquire(third) { stops.append(third) }
        XCTAssertEqual(stops, [first, second])
        ChatVoiceSession.release(third)
    }
    func testBotVoiceProjectionPreservesPrivateAudioMetadataAndExpiry() throws {
        let thread = UUID()
        let meta = ChatAttachmentMeta(id: UUID(), kind: "audio", name: "reply.m4a",
            mime: "audio/mp4", size: 1024, durationMS: 12_000,
            sha256: String(repeating: "a", count: 64), expiresAt: "2026-11-23T00:00:00.000Z")
        for role in ["kat", "assistant", "operator"] {
            let original = ForgeChatMessage(id: UUID(), threadID: thread, role: role,
                text: nil, attachments: [meta])
            let decoded = try JSONDecoder().decode(ForgeChatMessage.self, from: JSONEncoder().encode(original))
            XCTAssertEqual(decoded.role, role)
            XCTAssertNil(decoded.text)
            XCTAssertEqual(decoded.attachments, [meta])
            XCTAssertNil(decoded.attachments?.first?.url, "Playback uses the private attachment ID, not a raw URL.")
        }
        XCTAssertFalse(meta.isExpired(now: Date(timeIntervalSince1970: 0)))
        XCTAssertTrue(meta.isExpired(now: Date.distantFuture))
        let unavailable = ChatAttachmentMeta(id: UUID(), kind: "audio", name: "reply.m4a", available: false)
        XCTAssertTrue(unavailable.isExpired())
    }

    @MainActor func testBotVoicePlaybackAccessibilityInEveryLocale() {
        let previous = AppLanguageStore.shared.current
        defer { AppLanguageStore.shared.set(previous) }
        var playLabels = Set<String>()
        var pauseLabels = Set<String>()
        for language in AppLanguage.allCases {
            AppLanguageStore.shared.set(language)
            XCTAssertEqual(ChatVoiceText.playbackLabel(isBot: false, playing: false), ChatVoiceText.play)
            XCTAssertEqual(ChatVoiceText.playbackLabel(isBot: false, playing: true), ChatVoiceText.pause)
            XCTAssertEqual(ChatVoiceText.playbackLabel(isBot: true, playing: false), ChatVoiceText.playBot)
            XCTAssertEqual(ChatVoiceText.playbackLabel(isBot: true, playing: true), ChatVoiceText.pauseBot)
            XCTAssertNotEqual(ChatVoiceText.playBot, ChatVoiceText.play)
            XCTAssertNotEqual(ChatVoiceText.pauseBot, ChatVoiceText.pause)
            playLabels.insert(ChatVoiceText.playBot)
            pauseLabels.insert(ChatVoiceText.pauseBot)
        }
        XCTAssertEqual(playLabels.count, 5)
        XCTAssertEqual(pauseLabels.count, 5)
    }

}
