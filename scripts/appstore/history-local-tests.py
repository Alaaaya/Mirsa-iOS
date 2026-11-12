#!/usr/bin/env python3
"""Run actual device-gate/history method with no Apple calls or credentials."""
from pathlib import Path
import subprocess,tempfile
r=Path(__file__).resolve().parents[2]
h=(r/'ios-app/AppStore/StorePurchaseHistory.swift').read_text()
diagnostic=h[h.index('struct PurchaseHistoryDiagnostic:'):h.index('enum MirsaStorePurchaseHistory {')]
redactor=(r/'vendor/ApplePackage/Sources/ApplePackage/Supplement/AuthenticationServiceError.swift').read_text()
redactor='enum AuthenticationServiceError {\n'+redactor[redactor.index('    public static func redact('):]
s=(r/'ios-app/AppStore/StoreSecurity.swift').read_text()
errors=s[s.index('enum MirsaStoreError:'):s.index('protocol MirsaStoreVault')]
s=(r/'ios-app/AppStore/StoreServerClient.swift').read_text()
server=s[s.index('enum MirsaStoreServerError:'):s.index('/// The server')]
s=(r/'ios-app/AppStore/StoreOnDeviceClient.swift').read_text()
method=s[s.index('    func purchaseHistory()'):s.index('    func acquireFreeApp(')]
fixture='''
struct MirsaStorePurchase {}
actor Local {
 var calls = 0
 func purchaseHistory() async throws -> [MirsaStorePurchase] { calls += 1; return [] }
}
actor Harness {
 let local = Local()
 var allowed = false
 func setAllowed() { allowed = true }
 func authorize() async throws {
  guard allowed else { throw MirsaStoreServerError(code: "staging_denied") }
 }
'''
test='''
}
@main struct Tests {
 static func main() async throws {
  let client = Harness()
  do { _ = try await client.purchaseHistory(); fatalError("gate bypass") }
  catch let e as PurchaseHistoryDiagnostic {
   precondition(e.localizedDescription.contains("device authorization"))
   precondition(e.localizedDescription.contains("staging_denied"))
   precondition(!e.localizedDescription.contains("error 0"))
  }
  let before = await client.local.calls; precondition(before == 0)
  await client.setAllowed()
  _ = try await client.purchaseHistory()
  let after = await client.local.calls; precondition(after == 1)
  print("PASS actual history-only device gate names denied authorization; no local/Apple work before authorization")
  print("Bridged legacy local errors: busy=\\((MirsaStoreError.busy as NSError).code), denied=\\((MirsaStoreServerError(code: "staging_denied") as NSError).code)")
 }
}
'''.replace('\\(', '\\(')
with tempfile.TemporaryDirectory(prefix='history-local-') as d:
 p=Path(d)/'main.swift';p.write_text('import Foundation\n'+redactor+diagnostic+errors+server+fixture+method+test)
 subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(p),'-o',str(Path(d)/'test')],check=True)
 subprocess.run([str(Path(d)/'test')],check=True,timeout=30)
