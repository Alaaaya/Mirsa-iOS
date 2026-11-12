#!/usr/bin/env python3
"""Execute production history gate and reproduce old bool/busy misclassification.
All collaborators are synthetic, and no network or Apple credentials are used."""
from pathlib import Path
import subprocess, tempfile
r = Path(__file__).resolve().parents[2]
s = (r/'ios-app/AppStore/StoreServerClient.swift').read_text()
authorize = s[s.index('    func authorizeHistory()'):s.index('    func currentAccount()')]
legacy = s[s.index('    func loginAvailable()'):s.index('    /// History shares')]
fixture = r"""
import Foundation
struct MirsaStoreServerError: Error, Equatable { let code: String }
enum MirsaStoreError: Error { case busy, operationCancelled }
actor Harness {
 var busy = false
 var generation: UInt64 = 0
 var calls = 0
 var checks = 0
 var denial: Error?
 var hold: CheckedContinuation<Void, Never>?
 func check(_ run: UInt64) throws {
  checks += 1
  if Task.isCancelled || generation != run { throw MirsaStoreError.operationCancelled }
 }
 func currentAccount() async throws -> Int? {
  guard !busy else { throw MirsaStoreError.busy }
  busy = true; defer { busy = false }
  calls += 1
  if let denial { throw denial }
  return nil // typed signed_out, same capability semantics as real client
 }
 func block() async { busy = true; await withCheckedContinuation { hold = $0 }; busy = false }
 func release() { let c = hold; hold = nil; c?.resume() }
 func setDenial(_ error: Error?) { denial = error }
 func count() -> Int { calls }
 func checkCount() -> Int { checks }
 func isBlocked() -> Bool { hold != nil }
 func revokeGeneration() { generation += 1 }
"""
tests = r"""
}
@main struct Tests {
 static func main() async throws {
  let gate = Harness()
  let refresh = Task { await gate.block() }
  while !(await gate.isBlocked()) { await Task.yield() }
  let old = await gate.loginAvailable()
  precondition(!old, "legacy gate should reproduce false denial during refresh")
  let history = Task { try await gate.authorizeHistory() }
  try await Task.sleep(nanoseconds: 150_000_000)
  let before = await gate.count(); precondition(before == 0)
  await gate.release(); await refresh.value
  try await history.value
  let after = await gate.count(); precondition(after == 1, "must freshly verify server, not trust refresh/cache")

  for code in ["staging_denied", "unauthorized", "device_required", "upstream_unavailable"] {
   await gate.setDenial(MirsaStoreServerError(code: code))
   do { try await gate.authorizeHistory(); fatalError("authorization bypass") }
   catch let e as MirsaStoreServerError { precondition(e.code == code) }
  }
  await gate.setDenial(URLError(.notConnectedToInternet))
  do { try await gate.authorizeHistory(); fatalError("network must fail closed") }
  catch let e as URLError { precondition(e.code == .notConnectedToInternet) }
  await gate.setDenial(nil)

  let refresh2 = Task { await gate.block() }
  while !(await gate.isBlocked()) { await Task.yield() }
  let cancelled = Task { try await gate.authorizeHistory() }
  cancelled.cancel()
  do { try await cancelled.value; fatalError("cancelled authorization") } catch is CancellationError {} catch MirsaStoreError.operationCancelled {}
  let checks = await gate.checkCount()
  let changed = Task { try await gate.authorizeHistory() }
  while await gate.checkCount() == checks { await Task.yield() }
  await gate.revokeGeneration()
  do { try await changed.value; fatalError("identity generation changed") } catch is CancellationError {} catch MirsaStoreError.operationCancelled {}
  await gate.release(); await refresh2.value
  print("PASS actual history gate: reproduced legacy busy=false-denial, waited for refresh, fresh capability check, denial/network fail closed, cancellation/generation protection")
 }
}
"""
# Ensure the account call still contains the genuine server authorization path.
account = s[s.index('    func currentAccount()'):s.index('    func signIn(')]
assert 'try await credentials(run)' in account and 'request("/account"' in account
assert 'guard state.status == "authenticated"' in account
shared=(r/'ios-app/Apps/StoreServerIdentity.swift').read_text()
assert 'historyGate: {' in shared and 'try await MirsaStoreServerClient.shared.authorizeHistory()' in shared
history=(r/'ios-app/AppStore/StorePurchaseHistory.swift').read_text()
assert 'SAPSigner.connect()' in history and 'AMD' not in history
with tempfile.TemporaryDirectory(prefix='history-gate-') as d:
 p=Path(d)/'test.swift';p.write_text(fixture+legacy+authorize+tests)
 subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(p),'-o',str(Path(d)/'test')],check=True)
 subprocess.run([str(Path(d)/'test')],check=True,timeout=20)
