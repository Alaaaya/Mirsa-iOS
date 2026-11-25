#!/usr/bin/env python3
"""Validate the Mirsa IPA's exact resource bytes without extracting untrusted paths."""
from pathlib import Path
import argparse, hashlib, json, plistlib, zipfile
root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("ipa", type=Path)
args = parser.parse_args()
assets = root.parent / "ios-app/BackgroundNotificationAssets"
digest = lambda data: hashlib.sha256(data).hexdigest()
with zipfile.ZipFile(args.ipa) as archive:
    names = archive.namelist()
    assert len(names) == len(set(names)), "duplicate ZIP entries"
    app_infos = [n for n in names if n.startswith("Payload/") and len(n.split("/")) == 3 and n.endswith(".app/Info.plist")]
    assert len(app_infos) == 1, "exactly one main app expected"
    app = app_infos[0].removesuffix("Info.plist")
    for name in ["MirsaBackground.dylib", "provenance.json"]:
        assert archive.read(app + "BackgroundNotificationAssets/" + name) == (assets / name).read_bytes(), name
    provenance = json.loads((assets / "provenance.json").read_text())
    assert provenance["dylibSHA256"] == digest(archive.read(app + "BackgroundNotificationAssets/MirsaBackground.dylib"))
    for name, expected in provenance["sources"].items():
        assert digest((root / name).read_bytes()) == expected, name
    info = plistlib.loads(archive.read(app_infos[0]))
    # Merely bundling the resource must never activate this feature inside Mirsa.
    assert app + "MirsaBackgroundNotifications.plist" not in names
    assert app + "Frameworks/MirsaBackground.dylib" not in names
    executable = info["CFBundleExecutable"]
    assert "/" not in executable
    assert b"@rpath/MirsaBackground.dylib" not in archive.read(app + executable)
print("IPA contains exact background resource/provenance, not activated in Mirsa")
