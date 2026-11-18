#!/usr/bin/env python3
"""App Store login is open to every user; Apple credentials never go to Mirsa's server."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[2]
ident = (root / "ios-app/Apps/StoreServerIdentity.swift").read_text()
assert "publicLoginEnabled = true" in ident
assert "gate: { true }" in ident and "stateGate: { .authorized }" in ident
for n in ["EncryptedAppsTab.swift", "ClassicEncryptedAppsTab.swift"]:
    assert "MirsaStoreServerClient.shared.loginAvailable()" not in (root / "ios-app/Apps" / n).read_text(), n
native = (root / "ios-app/AppStore/StoreOnDeviceClient.swift").read_text()
assert "/login" not in native and "/verify" not in native
(root / "build").mkdir(exist_ok=True)
(root / "build/public-gate-proof.json").write_text(json.dumps({"publicStoreGate": "OPEN"}))
print("public gate OPEN PASS")
