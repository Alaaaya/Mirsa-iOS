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

# Compile the actual bounded metadata scheduler, not a reimplementation.
metadata=s[s.index('    private var versionNameCache:'):s.index('    /// One explicit free Get')].replace('private var','var').replace('private func','func')
stubs="""import Foundation
enum MirsaStoreError: Error { case invalidInput, invalidPackage, operationCancelled }
enum MirsaStoreServerClient {
 struct VersionMetadata: Sendable { let externalVersionID:String; let status:String; let version:String? }
 static func numericVersion(_ s:String)->Bool { !s.isEmpty && s.allSatisfy { $0.isNumber } }
}
struct MirsaStoreApp: Sendable {
 let id:Int
 var software: Int { id }
}
struct Owner: Sendable { var cookie="snapshot" }
actor Engine {
 var active=0; var maximum=0; var calls=0
 func versionMetadata(account: inout Owner, app:Int, version:String) async throws -> String {
  active += 1; calls += 1; maximum=max(maximum,active)
  defer { active -= 1 }
  try await Task.sleep(nanoseconds:20_000_000)
  account.cookie="changed"
  return "v"+version
 }
 func stats()->(Int,Int) { (maximum,calls) }
}
actor MetadataHarness {
 let engine=Engine()
 var generation:UInt64=0
 var busy=true
 func prepare() throws {}
 func requiredAccount() throws -> Owner { Owner() }
 func check(_ run:UInt64) throws {
  guard run==generation, !Task.isCancelled else { throw MirsaStoreError.operationCancelled }
 }
 func logout() { generation += 1 }
 func stats() async -> (Int,Int) { await engine.stats() }
 func lockHeld()->Bool { busy }
"""
tests="""
}
@main struct Tests {
 static func main() async throws {
  let h=MetadataHarness()
  let app=MirsaStoreApp(id:1)
  let ids=(1...20).map(String.init)
  let results=try await h.versionMetadata(app, externalVersionIDs:ids)
  precondition(results.count==20)
  let stats=await h.stats()
  precondition(stats.0==6 && stats.1==20, "must be concurrent and bounded")
  _ = try await h.versionMetadata(app, externalVersionIDs:ids)
  let cached=await h.stats(); precondition(cached.1==20, "cache must avoid network")
  let held=await h.lockHeld(); precondition(held, "metadata changed commerce lock")
  await h.logout()
  _ = try await h.versionMetadata(app, externalVersionIDs:["1"])
  let isolated=await h.stats(); precondition(isolated.1==21, "old session cache leaked")
  print("PASS actual metadata scheduler: six concurrent maximum, all names, cache hit skips requests, session-isolated cache and no commerce reservation")
 }
}
"""
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'metadata.swift';p.write_text(stubs+metadata+tests)
 subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(p),'-o',d+'/tests'],check=True)
 subprocess.run([d+'/tests'],check=True,timeout=20)
