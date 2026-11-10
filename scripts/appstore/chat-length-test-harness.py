#!/usr/bin/env python3
"""Compile the actual production message policy with the standalone regressions."""
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
work = Path(sys.argv[1])
source = (root / "ios-app/Apps/ForgeChat.swift").read_text()
start = source.index("enum ForgeChatText {")
end = source.index("\nenum ForgeChatTransient:", start)
policy = "import Foundation\n" + source[start:end] + "\n"
assert policy.count("enum ForgeChatText {") == 1
(work / "Sources/MirsaStoreKit/ForgeChatText.swift").write_text(policy)
tests = (root / "tests/ForgeChatLengthTests.swift").read_text()
(work / "Tests/MirsaStoreKitTests/ForgeChatLengthTests.swift").write_text(tests)
print("Actual production ForgeChatText extracted, no replacement length policy")
