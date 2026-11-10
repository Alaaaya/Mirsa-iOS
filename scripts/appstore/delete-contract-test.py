#!/usr/bin/env python3
"""Source wiring and language guards, not physical-device uninstall proof."""
import ast
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
store = (root / "ios-app/Apps/AppsStore.swift").read_text()
helper = (root / "ios-app/Apps/RealAppDeletion.swift").read_text()
delete = store.split("func delete(_ app: ManagedApp", 1)[1].split("// MARK: Self-install", 1)[0]
assert "RealAppDeletion.perform(" in delete
assert "networkReady: networkReady(vm)" in delete
assert "bundleID: current.installedBundleID" in delete
assert "try await Task.detached { try SideloadService.uninstall(bundleID: bid) }.value" in delete
assert "try? await" not in delete
assert "commit: { self.removeLocalApp(current) }" in delete
assert "fail(RealAppDeletion.failureMessage, offersSettings: true)" in delete
assert "deletingApps.insert(app.id).inserted" in delete
assert delete.index("await backupData(current, quiet: true)") < delete.index("private func removeLocalApp")
assert helper.index("guard try await uninstall(bundleID)") < helper.index("commit()")
# The working installation_proxy bridge and profile behavior are deliberately unchanged.
ffi = (root / "rust-core/src/sideload.rs").read_text()
uninstall = ffi.split("async fn uninstall(", 1)[1].split("// ---------------------------------------------------------------------------", 1)[0]
assert ".uninstall(bundle_id, None)" in uninstall
literal = r'"(?:[^"\\]|\\.)*"'
match = re.search(r'tr\(\s*(' + literal + r')\s*,\s*(' + literal + r')\s*,\s*ckb:\s*(' + literal + r')\s*,\s*kmr:\s*(' + literal + r')\s*\)', helper)
assert match
translations = dict(zip(["en", "ar", "ckb", "kmr"], map(ast.literal_eval, match.groups())))
assert all("LocalDevVPN" in value for value in translations.values())
out = root / "build/delete-contract-proof.json"
out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps({"kind": "Source guards only, device uninstall untested",
                           "failureMessage": translations, "transaction": "confirmed uninstall before local mutation",
                           "FFI": "existing working installation_proxy unchanged"}, ensure_ascii=False, indent=2))
print("PASS delete transaction source guards and failure guidance x four languages")
