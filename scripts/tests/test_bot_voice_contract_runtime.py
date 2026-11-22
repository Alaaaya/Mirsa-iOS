#!/usr/bin/env python3
"""Compile unchanged production labels/projection with minimal iOS-free seams.
Not an iOS app build, AVAudioPlayer test, or backend roundtrip.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
swiftc = os.environ.get("SWIFTC") or shutil.which("swiftc")
if not swiftc:
    raise SystemExit("Set SWIFTC to a Swift compiler.")
voice = (root / "ios-app/Apps/ChatVoice.swift").read_text()
labels = voice[voice.index("enum ChatVoiceText {"):voice.index("/// The shared audio session")]
timeline = (root / "ios-app/Apps/ForgeChatTimeline.swift").read_text()
projection = timeline[:timeline.index("/// Mutation acknowledgments")]
seams = """
enum AppLanguage: CaseIterable { case english, arabic, german, kurmanji, sorani }
final class AppLanguageStore { static let shared = AppLanguageStore(); var current = AppLanguage.english }
enum ForgeChatMutationPolicy { static let reactions = ["❤️", "👍", "🔥"] }
struct ChatBuildProgress: Codable, Equatable {
    let requestMessageID: UUID
    func matches(_ id: UUID) -> Bool { requestMessageID == id }
}
"""
checks = """
var plays = Set<String>(), pauses = Set<String>()
for language in AppLanguage.allCases {
    AppLanguageStore.shared.current = language
    precondition(ChatVoiceText.playbackLabel(isBot: false, playing: false) == ChatVoiceText.play)
    precondition(ChatVoiceText.playbackLabel(isBot: false, playing: true) == ChatVoiceText.pause)
    precondition(ChatVoiceText.playbackLabel(isBot: true, playing: false) == ChatVoiceText.playBot)
    precondition(ChatVoiceText.playbackLabel(isBot: true, playing: true) == ChatVoiceText.pauseBot)
    precondition(ChatVoiceText.playBot != ChatVoiceText.play)
    precondition(ChatVoiceText.pauseBot != ChatVoiceText.pause)
    plays.insert(ChatVoiceText.playBot); pauses.insert(ChatVoiceText.pauseBot)
}
precondition(plays.count == 5 && pauses.count == 5)
let thread = UUID()
let meta = ChatAttachmentMeta(id: UUID(), kind: "audio", name: "reply.m4a",
    mime: "audio/mp4", size: 1024, durationMS: 12000, sha256: String(repeating: "a", count: 64),
    expiresAt: "2026-11-23T00:00:00.000Z")
for role in ["kat", "assistant", "operator"] {
    let message = ForgeChatMessage(id: UUID(), threadID: thread, role: role, text: nil, attachments: [meta])
    let decoded = try JSONDecoder().decode(ForgeChatMessage.self, from: JSONEncoder().encode(message))
    precondition(decoded.role == role && decoded.text == nil && decoded.attachments == [meta])
    precondition(decoded.attachments?.first?.url == nil)
}
precondition(!meta.isExpired(now: Date(timeIntervalSince1970: 0)))
precondition(meta.isExpired(now: Date.distantFuture))
let unavailable = ChatAttachmentMeta(id: UUID(), kind: "audio", name: "reply.m4a", available: false)
precondition(unavailable.isExpired())
print("PASS compiled production bot/user labels in 5 locales, 3 bot-role projections, private-ID metadata and expiry")
"""
with tempfile.TemporaryDirectory(prefix="mirsa-bot-audio-") as temp:
    source = Path(temp) / "main.swift"
    source.write_text(projection + "\n" + seams + labels + checks)
    binary = Path(temp) / "bot-voice-contract"
    subprocess.run([swiftc, str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
