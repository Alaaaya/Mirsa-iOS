#!/usr/bin/env python3
from pathlib import Path
import argparse, hashlib, json
root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--toolchain", choices=["apple", "linux-cross"], required=True)
args = parser.parse_args()
names = ["BackgroundNotifications.m", "Policy.h", "build-apple.sh", "build-linux.sh"]
assets = root.parent / "ios-app/BackgroundNotificationAssets"
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
obj = {"format": 1, "toolchain": args.toolchain, "architecture": "arm64", "minimumIOS": "15.0",
       "methodsDefaultOff": True, "recordsCoordinates": False, "transmitsData": False,
       "sources": {name: digest(root / name) for name in names},
       "dylibSHA256": digest(assets / "MirsaBackground.dylib")}
(assets / "provenance.json").write_text(json.dumps(obj, indent=2, sort_keys=True) + "\n")
