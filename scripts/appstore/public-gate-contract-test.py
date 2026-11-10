#!/usr/bin/env python3
"""Source guard: public UI has no path to App Store login/backend."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[2]
tab = (root / "ios-app/Apps/EncryptedAppsTab.swift").read_text()
assert "AppStoreAccountView" not in tab and "showingAppStore" not in tab and ".sheet(isPresented: $showingAppStore" not in tab
assert "encrypted-appstore-coming-soon" in tab and "encrypted-appstore-account" not in tab
for lang in ["Coming soon", "قريباً", "بەم زووانە", "Nêzîk e"]:
    assert lang in tab, lang
users = []
for f in (root / "ios-app").rglob("*.swift"):
    t = f.read_text()
    if f.name == "AppStoreAccountView.swift":
        continue
    if "AppStoreAccountView(" in t or "MirsaStoreServerClient.shared" in t and f.name != "StoreServerIdentity.swift":
        users.append(str(f))
assert not users, users
assert "publicLoginEnabled = false" in (root / "ios-app/Apps/StoreServerIdentity.swift").read_text()
assert 'layoutDirection' in tab
(root / "build").mkdir(exist_ok=True)
(root / "build/public-gate-proof.json").write_text(json.dumps({"publicStoreGate": "PASS"}))
print("public gate PASS")
