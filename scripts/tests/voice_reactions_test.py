#!/usr/bin/env python3
"""Offline contract/arity audit. Native Swift parse + simulator build remain required."""
from pathlib import Path
import re, plistlib
root = Path(__file__).resolve().parents[2]
def read(path): return (root / path).read_text()
voice = read("ios-app/Apps/ChatVoice.swift")
upload = read("ios-app/Apps/AttachmentUploader.swift")
chat = read("ios-app/Apps/ForgeChat.swift")
meta = read("ios-app/Apps/ForgeChatTimeline.swift")
assert ".requestRecordPermission()" in voice
assert "SFSpeechRecognizer" not in voice and "Speech.framework" not in voice
assert "maxDuration: TimeInterval = 300" in voice
assert "5 * 1024 * 1024" in voice
assert 'body["durationMS"] = durationMS' in upload
assert 'body["mime"] = "audio/mp4"' in upload
assert "ChatVoiceRules.verify(data" in upload
assert "ChatVoiceRules.verify(d, meta: expected ?? known[id])" in upload
assert "meta.size == Int64(data.count)" in voice and "sha.lowercased()" in voice
assert "botReaction = bot.flatMap" in meta
assert "botReaction, editedAt" in meta
assert 'latest.attachments?.contains(where: { $0.kind == "audio" }) != true' in meta
assert 'attachmentIDs: [meta.id])' in chat
assert 'guard drafts.items(threadID).isEmpty, replyTo == nil' in chat
for marker in ["chat-voice-record", "chat-voice-recording", "chat-voice-send", "chat-voice-discard", "chat-mirsa-reaction"]:
    assert marker in chat
for lang in ["ar", "en", "de", "kmr", "ckb"]:
    text = read(f"ios-app/{lang}.lproj/InfoPlist.strings")
    assert '"NSMicrophoneUsageDescription"' in text and len(text) > 65
plistlib.loads((root/"ios-app/Info.plist").read_bytes())
assert (root/"ios-app/Voice/voice-fixture.m4a").read_bytes()[4:8] == b"ftyp"
# Every payload binding lists all three associated audio fields.
for line in upload.splitlines():
    for pattern in re.findall(r"\.audio\(([^)]*)\)", line):
        if "let " in pattern:
            assert len(pattern.split(",")) == 3, line
print("PASS voice/reaction offline contract + audio arity audit (not a native compile)")
