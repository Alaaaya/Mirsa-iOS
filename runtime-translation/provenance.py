#!/usr/bin/env python3
"""Bind the bundled generic binary to reviewed source and its actual build output."""
from pathlib import Path
import hashlib, json
root = Path(__file__).resolve().parent
names = ["RuntimeTranslate.m", "Online.h", "OnlineMerge.h", "Activation.h", "ActivationKey.h", "Banner.h", "Tokens.h", "Bidi.h", "fishhook.c", "fishhook.h", "runtime-table.json", "Table.h", "build-apple.sh", "build-linux.sh"]
assets = root.parent / "ios-app/RuntimeTranslationAssets"
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
obj = {"format": 1, "genericTableEmpty": json.loads((root / "runtime-table.json").read_text()).get("translations") == {},
       "sources": {name: digest(root / name) for name in names}, "dylibSHA256": digest(assets / "MirsaTranslate.dylib")}
(assets / "provenance.json").write_text(json.dumps(obj, indent=2, sort_keys=True) + "\n")
