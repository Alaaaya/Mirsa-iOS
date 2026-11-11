"""Fail closed before publication using the live 243 updater's actual Swift comparator."""
import hashlib
import json
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
baseline = json.loads((ROOT / "tests/fixtures/update-baseline243.json").read_text())
source = (ROOT / "ios-app/Apps/UpdaterMetadata.swift").read_bytes()
assert hashlib.sha256(source).hexdigest() == baseline["comparatorSHA256"], "243 comparator changed; independently revalidate migration"
with zipfile.ZipFile(sys.argv[1]) as archive:
    names = [n for n in archive.namelist() if n.startswith("Payload/") and n.count("/") == 2 and n.endswith(".app/Info.plist")]
    assert len(names) == 1
    current = plistlib.loads(archive.read(names[0]))
    assert current["CFBundleShortVersionString"] == "2.1"
    for name in archive.namelist():
        if name.endswith(".appex/Info.plist"):
            ext = plistlib.loads(archive.read(name))
            assert ext["CFBundleShortVersionString"] == current["CFBundleShortVersionString"]
            assert ext["CFBundleVersion"] == current["CFBundleVersion"]
old = baseline["ipa"]["info"]["CFBundleVersion"]
previous = "4.61.1"  # Actual verified production 2.0 IPA, build 261
new = current["CFBundleVersion"]
assert int(current["MirsaBuild"]) > 261, "actual MirsaBuild must advance past production 2.0"
# JSON-encoded numeric versions are also valid Swift string literals.
with tempfile.TemporaryDirectory() as tmp:
    script = pathlib.Path(tmp) / "Upgrade243.swift"
    script.write_bytes(source + (
        "\nprecondition(UpdaterMetadata.isNewer(remote: " + json.dumps(new) +
        ", installed: " + json.dumps(old) + "))\n" +
        "precondition(!UpdaterMetadata.isNewer(remote: " + json.dumps(old) +
        ", installed: " + json.dumps(new) + "))\n" +
        "precondition(UpdaterMetadata.isNewer(remote: " + json.dumps(new) +
        ", installed: " + json.dumps(previous) + "))\n" +
        'precondition(UpdaterMetadata.isNewer(remote: "2.1", installed: "1.3.243"))\n' +
        'precondition(UpdaterMetadata.isNewer(remote: "2.1", installed: "1.4"))\n' +
        'precondition(!UpdaterMetadata.isNewer(remote: "1.4", installed: "2.1"))\n' +
        'print("Actual 243 updater migration PASS")\n'
    ).encode())
    subprocess.run(["swift", str(script)], check=True)
print(json.dumps({"baselineIPA": baseline["ipa"]["sha256"], "oldBuild": old,
                  "previousBuild": previous, "newBuild": new, "shortVersion": current["CFBundleShortVersionString"],
                  "actual243Comparator": "PASS"}))
