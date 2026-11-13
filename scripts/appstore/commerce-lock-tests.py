#!/usr/bin/env python3
"""Execute the production reservation helper with cancellation/failure/logout fixtures."""
from pathlib import Path
import subprocess,tempfile
r=Path(__file__).resolve().parents[2]
s=(r/'ios-app/AppStore/StoreClient.swift').read_text()
helper=s[s.index('    private func beginQueued()'):s.index('    func purchaseHistory()')].replace('private func','func')
v=s[s.index('    func versionMetadata('):s.index('    /// One explicit free Get')]
assert 'begin(' not in v and 'beginQueued(' not in v and 'busy' not in v
assert 'persist(owner)' not in v and 'try check(run)' in v
for name in ['downloadOwnedApp','acquireFreeAppAndDownload','availableVersions','acquireFreeApp']:
 body=s.split('    func '+name+'(',1)[1].split('\n    }',1)[0]
 assert 'try await beginQueued()\n        defer { busy = false }' in body
source='''import Foundation
enum MirsaStoreError: Error { case busy, operationCancelled }
actor Harness {
 var busy=false
 var generation:UInt64=0
 var started=0
 func prepare() throws {}
 func occupy() { busy=true }
 func release() { busy=false }
 func logout() { generation += 1 }
 func isBusy() -> Bool { busy }
 func count() -> Int { started }
 func operation(fail:Bool=false) async throws {
  _ = try await beginQueued()
  defer { busy=false }
  started += 1
  try await Task.sleep(nanoseconds:10_000_000)
  if fail { throw MirsaStoreError.operationCancelled }
 }
'''+helper+'''
}
@main struct Tests {
 static func main() async throws {
  let h=Harness()
  await h.occupy()
  let cancelled=Task { try await h.operation() }
  cancelled.cancel()
  do { try await cancelled.value; fatalError("cancellation lost") } catch {}
  let held=await h.isBusy(); precondition(held)
  let queued=Task { try await h.operation() }
  await h.release()
  try await queued.value
  do { try await h.operation(fail:true); fatalError("error lost") } catch {}
  let released=await h.isBusy(); precondition(!released)
  try await h.operation()
  let count=await h.count(); precondition(count==3)
  await h.occupy()
  let stale=Task { try await h.operation() }
  try await Task.sleep(nanoseconds:10_000_000)
  await h.logout(); await h.release()
  do { try await stale.value; fatalError("logout crossed wait") } catch {}
  print("PASS actual reservation queue, success/error/cancel defer, cancelled waiter preserves owner lock, logout fences queued request, metadata never reserves or persists")
 }
}
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'tests.swift';p.write_text(source)
 subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(p),'-o',d+'/tests'],check=True)
 subprocess.run([d+'/tests'],check=True,timeout=20)
