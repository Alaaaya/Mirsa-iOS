#!/usr/bin/env python3
"""Public login remains closed unless the server verifies owner-device access."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[2]
tab = (root / "ios-app/Apps/EncryptedAppsTab.swift").read_text()
assert "@State private var storeLoginAvailable = false" in tab
assert "storeLoginAvailable = await MirsaStoreServerClient.shared.loginAvailable()" in tab
assert "if storeLoginAvailable {" in tab
assert "Button { showingAppStore = true }" in tab
assert "private let client = MirsaStoreOnDeviceClient.shared" in (root / "ios-app/Apps/AppStoreAccountView.swift").read_text()
native = (root / "ios-app/AppStore/StoreOnDeviceClient.swift").read_text()
identity = (root / "ios-app/Apps/StoreServerIdentity.swift").read_text()
assert "await MirsaStoreServerClient.shared.loginAvailable()" in identity
assert "guard await gate()" in native
for action in ["signIn", "verify", "search", "acquireFreeApp", "availableVersions", "versionMetadata", "downloadOwnedApp"]:
    section = native.split("func " + action + "(", 1)[1].split("\n    func ", 1)[0]
    assert "try await authorize()" in section, action
assert "/login" not in native and "/verify" not in native
client = (root / "ios-app/AppStore/StoreServerClient.swift").read_text()
gate = client.split("func loginAvailable() async -> Bool {", 1)[1].split("func currentAccount()", 1)[0]
assert "try await currentAccount()" in gate and "return false" in gate
assert "return !Task.isCancelled" in gate
assert 'state.status == "signed_out"' in client
assert 'state.status == "authenticated", let account' in client
assert "encrypted-appstore-coming-soon" in tab and "encrypted-appstore-account" in tab
for lang in ["Coming soon", "قريباً", "بەم زووانە", "Nêzîk e"]:
    assert lang in tab, lang
users = []
for f in (root / "ios-app").rglob("*.swift"):
    t = f.read_text()
    if f.name in ("AppStoreAccountView.swift", "EncryptedAppsTab.swift"):
        continue
    if "AppStoreAccountView(" in t or "MirsaStoreServerClient.shared" in t and f.name != "StoreServerIdentity.swift":
        users.append(str(f))
assert not users, users
assert "publicLoginEnabled = false" in (root / "ios-app/Apps/StoreServerIdentity.swift").read_text()
assert 'layoutDirection' in tab
(root / "build").mkdir(exist_ok=True)
(root / "build/public-gate-proof.json").write_text(json.dumps({"publicStoreGate": "PASS"}))
print("public gate PASS")
