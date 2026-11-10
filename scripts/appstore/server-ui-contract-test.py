#!/usr/bin/env python3
"""Source guards, not device/UI runtime testing. Writes all four UI translations as proof."""
import ast
import json
from pathlib import Path
import re
root = Path(__file__).resolve().parents[2]
source = (root / "ios-app/Apps/AppStoreAccountView.swift").read_text()
literal = r'"(?:[^"\\]|\\.)*"'
pattern = re.compile(r'\bt\(\s*(' + literal + r')\s*,\s*(' + literal + r')\s*,\s*(' + literal + r')\s*,\s*(' + literal + r')\s*\)', re.S)
rows = []
for match in pattern.finditer(source):
    values = [ast.literal_eval(value) for value in match.groups()]
    assert all(value.strip() for value in values), values
    rows.append(dict(zip(["en", "ar", "ckb", "kmr"], values)))
assert len(rows) == len(re.findall(r'\bt\(\s*"', source)), "Every Store UI string needs all four languages"
assert "MirsaStoreServerClient.shared" in source
assert "MirsaStoreClient.shared" not in source
assert ".environment(\\.layoutDirection, .leftToRight)" in source
assert 'defer { password = ""; code = "" }' in source
assert source.count('password = ""') >= 5
assert 'client.verify(code: c, password: secret)' in source
assert 'client.availableVersions(app)' in source
assert 'client.downloadOwnedApp(app, externalVersionID: version)' in source
assert 'guard generation == operationGeneration else { throw CancellationError() }' in source
assert source.index("try Task.checkCancellation()", source.index("private func download")) < source.index("try await onDownloaded(url)")
assert "a.country.uppercased()" in source
assert "Country code (us, de, tr)" not in source
assert "الرمز يلي وصل عآيفونك" in source
assert "Sent only to Apple." not in source
assert "Saved only in this device" not in source
identity = (root / "ios-app/Apps/StoreServerIdentity.swift").read_text()
forge = (root / "ios-app/Apps/ForgeFixTransport.swift").read_text()
readonly = forge.split("static func existingFixCredentials", 1)[1].split("static func fixToken", 1)[0]
assert "existingFixCredentials(bearer: bearer, user: user)" in identity
assert "ForgeFixSystemKeychain().read" in readonly
assert "SecItemCopyMatching" in readonly
for mutation in ["SecItemAdd", "SecItemUpdate", "SecItemDelete", "fixRequest(", "deviceID()", "ForgeFixKeychain.token("]:
    assert mutation not in readonly, mutation
assert "fixToken()" not in identity
assert ".reversed()" not in source
client = (root / "ios-app/AppStore/StoreServerClient.swift").read_text()
assert 'forHTTPHeaderField: "x-mirsa-device"' in client
assert 'forHTTPHeaderField: "x-mirsa-device-token"' in client
assert 'owner: refreshed, device: token)' in client
for code in ["staging_denied", "device_limit", "invalid_version"]:
    assert 'case "' + code + '"' in source
output = root / "build/store-server-ui-text-proof.json"
output.parent.mkdir(exist_ok=True)
output.write_text(json.dumps({"kind": "source guards only, not device UI execution", "strings": rows}, ensure_ascii=False, indent=2))
print(f"PASS {len(rows)} Store UI strings x four languages; source-only password, LTR, version-selection and late-import guards")
