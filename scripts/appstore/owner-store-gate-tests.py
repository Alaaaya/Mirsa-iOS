from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[2]
source = (root / 'ios-app/Apps/StoreServerIdentity.swift').read_text()
start = source.index('enum MirsaStoreOwnerAccess {')
end = source.index('\n}\n', start) + 3
gate = source[start:end]
checks = '''
assert(MirsaStoreOwnerAccess.allows(deviceID: "91f71c66-b727-450e-8de2-244a1cf85915"))
assert(MirsaStoreOwnerAccess.allows(deviceID: "91F71C66-B727-450E-8DE2-244A1CF85915"))
assert(!MirsaStoreOwnerAccess.allows(deviceID: ""))
assert(!MirsaStoreOwnerAccess.allows(deviceID: "00000000-0000-0000-0000-000000000000"))
assert(!MirsaStoreOwnerAccess.allows(deviceID: "91f71c66-b727-450e-8de2-244a1cf85916"))
assert(!MirsaStoreOwnerAccess.allows(deviceID: " 91f71c66-b727-450e-8de2-244a1cf85915"))
print("compiled actual owner-only gate PASS")
'''
with tempfile.TemporaryDirectory() as d:
    p = Path(d) / 'gate.swift'
    p.write_text(gate + checks)
    subprocess.run(['swift', str(p)], check=True)
