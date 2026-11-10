#!/usr/bin/env python3
"""Source wiring guards only. Runtime Foundation regressions run in ForgeChatTimelineTests."""
import ast
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
source = (root / "ios-app/Apps/ForgeChat.swift").read_text()
status = source.split("static func status(", 1)[1].split("static var waiting:", 1)[0]
literal = r'"(?:[^"\\]|\\.)*"'
matches = re.findall(r'tr\(\s*(' + literal + r')\s*,\s*(' + literal + r')\s*,\s*ckb:\s*(' + literal + r')\s*,\s*kmr:\s*(' + literal + r')\s*\)', status)
translations = [dict(zip(["en", "ar", "ckb", "kmr"], map(ast.literal_eval, row))) for row in matches]
assert len(translations) == 4 and all(all(row.values()) for row in translations)
assert '.swipeActions(edge: .trailing, allowsFullSwipe: false)' in source
assert 'Button(role: .destructive)' in source
# Both owner-approved backgrounds are valid; retain coverage of both chat surfaces.
assert (source.count("MirsaChatTheme.bg.ignoresSafeArea()")
        + source.count("AuroraBackground().ignoresSafeArea()")) == 2
assert "ForEach(rows)" in source and "ForEach(msgs)" not in source and "ForEach(queued)" not in source
assert ".id(row.id)" in source
assert "ForgeChatTimeline.pending(outgoing: store.outgoing, echoes: store.sentEcho" in source
assert "ForgeChatTimeline.mergeConfirmed(previous: messages[id] ?? [], incoming: w.messages)" in source
assert "ForgeChatTimeline.acceptedEcho(o)" in source
assert "ForgeChatTimeline.orderedIDs(confirmed: msgs, pending: queued)" in source
assert "afterMessageID: anchor" in source
assert "if sorted != threads { threads = sorted }" in source
assert "accessibilityReduceMotion" in source and "reduceMotion ? nil : .spring" in source
assert ".scrollDismissesKeyboard(.interactively)" in source
# The layout container must not replace identifiers on its interactive children.
assert '.accessibilityIdentifier("chat-composer")' not in source
assert '.accessibilityIdentifier("chat-input")' in source
assert '.accessibilityIdentifier("chat-send")' in source
assert 'sentEcho.removeAll { $0.threadID == id }; saveEcho()' in source
assert "deleteEpoch[id, default: 0] += 1" in source
assert "if deleting.contains(id) || deleteEpoch[id] != epoch { return }" in source
assert 'private let echoKey = "mirsa.chat.sentEcho.v1"' in source
assert 'JSONDecoder().decode([ForgeChatOutgoing].self' in source
# Confirmation is published before echo removal, so no blank polling frame is possible.
read = source.split("func read(_ id:", 1)[1].split("func image(", 1)[0]
assert read.index("messages = all") < read.index("sentEcho.removeAll")
flush = source.split("func flush()", 1)[1].split("func deleteThread", 1)[0]
assert flush.index("saveEcho()") < flush.index("outgoing.removeAll")
result = {"kind": "Source guards only, not physical-device UI execution",
          "harkCumulativeCommit": "35047a5598b11929f7e4e16a1187ede8f86e0f32",
          "statusStrings": translations,
          "guards": "single UUID ForEach, persistent text echo, monotonic reads, smooth/reduced motion, navy or Aurora, swipe-delete epoch"}
out = root / "build/chat-ui-contract-proof.json"
out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps(result, ensure_ascii=False, indent=2))
print("PASS chat source guards, four statuses x four languages; device UI untested")
