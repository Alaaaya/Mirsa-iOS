#!/usr/bin/env python3
"""Actual row-action runtime and canonical request source checks. No Apple network."""
from pathlib import Path
import subprocess, tempfile, sys
r=Path(__file__).resolve().parents[2]
view=(r/'ios-app/Apps/AppStoreAccountView.swift').read_text()
base=subprocess.check_output(['git','show','2f15e57:ios-app/Apps/AppStoreAccountView.swift'],cwd=r,text=True)
def method(text,name):
    return text.split('    private func '+name+'(',1)[1].split('\n    private func ',1)[0]
row=method(view,'versionRow')
old=method(base,'versionRow')
assert row.replace('chosen[key] = id','chosen[key] = id; manualID[key] = ""') == old
assert 'manualID' not in view and 'TextField(t("Version ID' not in view
assert 'ForEach(visible, id: \\.self)' in view
assert 'versionRow(key: key, id: id, title: versionName(app, id), subtitle: "ID \\(id)")' in view
assert 'versionRow(key: key, id: nil, title: t("Latest"' in view
assert view.index('versionRow(key: key, id: nil') < view.index('if let list = versions[key]')
assert 'versionListAttempted.insert(app.id)' in view
assert 'let ids: [String]' in method(view,'loadVersions')
assert 'client.availableVersions(app)' in method(view,'loadVersions')
d=method(view,'download')
assert 'let version = chosen[app.bundleID]' in d
assert 'client.downloadOwnedApp(app, externalVersionID: version)' in d
assert 'app.version' not in d and 'versionName' not in d and 'metadata[' not in d
client=(r/'ios-app/AppStore/StoreClient.swift').read_text()
original_client = subprocess.check_output(['git','show','2f15e57:ios-app/AppStore/StoreClient.swift'],cwd=r,text=True)
extra_start = client.index('    /// Public fresh metadata')
extra_end = client.index('    func availableVersions(', extra_start)
canonical = client[:extra_start] + client[extra_end:]
# The approved one-tap free Get transaction is additive; versions and legacy engines stay exact.
atomic_start = canonical.index('    /// One explicit free Get action')
atomic_end = canonical.index('    /// Returns a local encrypted IPA', atomic_start)
OLD = "        if let diagnostic = error as? StoreProductDiagnostic { return diagnostic }"
NEW = """        if let diagnostic = error as? StoreProductDiagnostic {
            if diagnostic.requiresReauthentication {
                // Explicit owner policy: drop only the rejected Apple store session.
                // Preserve stable machine identity, saved apps, signing accounts and all files.
                do { try signOut() } catch { return MirsaStoreError.serviceUnavailable }
            }
            return diagnostic
        }"""
canonical = canonical.replace(NEW, OLD)
atomic_start = canonical.index('    /// One explicit free Get action')
atomic_end = canonical.index('    /// Returns a local encrypted IPA', atomic_start)
assert canonical[:atomic_start] + canonical[atomic_end:] == original_client
fetch=(r/'vendor/ApplePackage/Sources/ApplePackage/Commands/StoreDownloadEndpoint+Fetch.swift').read_text()
assert '"salableAdamId": app.id' in fetch
assert 'guard fresh.id == app.id' in client
print('PASS old row UI preserved, list-only selection, automatic bounded load, Latest always visible, unchanged account-bound engine, real Software.id request')
if '--source-only' in sys.argv: sys.exit()
action=row.split('return Button {',1)[1].split('} label:',1)[0]
swift='''import Foundation
struct Harness {
 var chosen: [String:String] = [:]
 mutating func select(key:String,id:String?) {
'''+action+'''
 }
}
@main struct Tests {
 static func main() {
  var h=Harness()
  let names=["885245059":"21.45.4","883790661":"21.44.1"]
  for id in names.keys {
   h.select(key:"com.google.ios.youtube",id:id)
   precondition(h.chosen["com.google.ios.youtube"] == id)
   precondition(h.chosen["com.google.ios.youtube"] != names[id])
  }
  h.select(key:"net.whatsapp.WhatsApp",id:"880000004")
  precondition(h.chosen["net.whatsapp.WhatsApp"] == "880000004")
  h.select(key:"com.google.ios.youtube",id:nil)
  precondition(h.chosen["com.google.ios.youtube"] == nil)
  precondition(h.chosen["net.whatsapp.WhatsApp"] == "880000004")
  print("PASS actual row tap preserves externalVersionID, never display string; Latest clears only selected app ID")
 }
}
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'main.swift';p.write_text(swift)
 subprocess.run(['swiftc','-parse-as-library',str(p),'-o',d+'/test'],check=True)
 subprocess.run([d+'/test'],check=True)
