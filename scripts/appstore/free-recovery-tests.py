#!/usr/bin/env python3
"""Exercise the actual consent/retry helper and fresh-free account guard, no Apple calls."""
from pathlib import Path
import subprocess, tempfile, sys
r = Path(__file__).resolve().parents[2]
helper = (r/'ios-app/AppStore/StoreFreeLicenseRecovery.swift').read_text().replace('import ApplePackage\n', '')
client = (r/'ios-app/AppStore/StoreClient.swift').read_text()
ui = (r/'ios-app/Apps/AppStoreAccountView.swift').read_text()
page = (r/'ios-app/Apps/AppStoreSection.swift').read_text().split('struct AppStorePurchasesPage:',1)[1]
purchase = (r/'vendor/ApplePackage/Sources/ApplePackage/Commands/Purchase.swift').read_text()
def method(s, name):
    start=s.index('    func '+name+'(')
    end=s.index('\n    func ',start+1)
    return s[start:end]
fresh=method(client,'freeAppForRecovery')
acquire=method(client,'acquireFreeApp').split('    /// Public fresh metadata')[0]
assert 'engine.acquire' not in fresh and 'country(owner)' in fresh
assert 'fresh.id == app.id, fresh.bundleID == app.bundleID' in fresh
assert 'try MirsaStorePolicy.requireFree(fresh.price)' in fresh and 'try check(run)' in fresh
assert acquire.index('requireFree(fresh.price)') < acquire.index('engine.acquire(')
for view, method_name in [(ui,'    private func recoverDownload('),(page,'    @MainActor private func recoverDownload(')]:
    retry=view.split(method_name,1)[1]
    retry=retry.split('\n    private func ',1)[0]
    assert 'StoreFreeLicenseRecovery.retryOnce(consent: true' in retry
    assert 'externalVersionID: pending.externalVersionID' in retry
    assert 'acquireFreeApp(pending.app)' in retry
    assert 'offerRecovery(' not in retry and 'recovery = StoreFreeLicenseRecovery' not in retry
    assert 'confirmationDialog(' in view and 'role: .cancel' in view
assert 'diagnostic.httpStatus == 403' in ui and 'diagnostic.httpStatus == 403' in page
assert 'let version = chosen[app.bundleID]' in ui
assert 'app: fresh, externalVersionID: version' in ui
assert 'client.freeAppForRecovery(app)' in ui and 'shared.freeAppForRecovery(item.app)' in page
assert 'selected = app' in ui  # original details route preserved
assert 'StoreProductDiagnostic(stage: "licence/"' in purchase
assert 'guard response.status == .ok else { throw diagnostic }' in purchase
assert 'failureCode(fields) != nil' in purchase
assert 'Self.confirmsExistingLicense(fields) { return }' in purchase
assert 'error.failureType == "2059"' in purchase  # fallback, NEVER positive ownership evidence
assert 'pricingParameters: "STDQ"' in purchase and 'pricingParameters: "GAME"' in purchase
assert '"appExtVrsId": "0"' in purchase
assert '"guid": guid' in purchase and '"price": "0"' in purchase
assert 'urlString = "https://\\(host)/WebObjects/MZFinance.woa/wa/buyProduct"' in purchase
print('PASS source consent-only recovery, fresh account-store free guards, version preservation, no second offer/retry, licence diagnostics and canonical STDQ request')
if '--source-only' in sys.argv: sys.exit(0)
# Compile the exact production helper and client free-lookup/acquire bodies with
# offline dependencies, including real price validation.
security=(r/'ios-app/AppStore/StoreSecurity.swift').read_text()
a=security.index('    static func requireFree(')
b=security.index('\n    static func ',a+1)
price=security[a:b]
fixture=r"""
struct Software {
 let id: Int64; let bundleID: String; let price: Double?
}
struct MirsaStoreApp {
 let id: Int64; let bundleID: String; let price: Double?
 init(_ s: Software) { id=s.id; bundleID=s.bundleID; price=s.price }
}
struct Owner { let country: String }
enum MirsaStoreError: Error { case invalidPackage, freeAppsOnly, operationCancelled }
struct MirsaStorePolicy {
PRICE
}
final class Engine {
 var app = Software(id: 310633997, bundleID: "net.whatsapp.WhatsApp", price: 0)
 var calls=0; var acquires=0; var country=""
 func lookup(bundleID: String, country: String) async throws -> Software {
  calls += 1; self.country=country; return app
 }
 func acquire(account: inout Owner, app: Software) async throws { acquires += 1 }
}
struct Client {
 var busy=false
 let engine=Engine()
 var valid=true
 func begin() throws -> UInt64 { 1 }
 func beginQueued() async throws -> UInt64 { try begin() }
 func requiredAccount() throws -> Owner { Owner(country:"tr") }
 func country(_ o: Owner) throws -> String { o.country }
 func check(_ run: UInt64) throws { if !valid { throw MirsaStoreError.operationCancelled } }
 func persist(_ o: Owner) throws {}
 func safe(_ e: Error) -> Error { e }
FRESH
ACQUIRE
}
enum RetryFailure: Error { case rejected }
@main struct Tests {
 static func main() async throws {
  precondition(StoreFreeLicenseRecovery.canOffer(status:403,price:0))
  for price in [nil,1,-1,Double.nan] as [Double?] {
   precondition(!StoreFreeLicenseRecovery.canOffer(status:403,price:price))
  }
  for code: UInt in [200,401,402,404,500] {
   precondition(!StoreFreeLicenseRecovery.canOffer(status:code,price:0))
  }
  var client=Client()
  let app=MirsaStoreApp(client.engine.app)
  _ = try await client.freeAppForRecovery(app)
  precondition(client.engine.acquires==0 && client.engine.country=="tr")
  for price in [nil, 1, -1, Double.nan] as [Double?] {
   client.engine.app=Software(id:app.id,bundleID:app.bundleID,price:price)
   do { _ = try await client.freeAppForRecovery(app); fatalError("offered unknown/paid") } catch {}
   do { try await client.acquireFreeApp(app); fatalError("purchased unknown/paid") } catch {}
   precondition(client.engine.acquires==0)
  }
  client.engine.app=Software(id:999,bundleID:app.bundleID,price:0)
  do { _ = try await client.freeAppForRecovery(app); fatalError("identity changed") } catch {}
  client.engine.app=Software(id:app.id,bundleID:"other.app",price:0)
  do { _ = try await client.freeAppForRecovery(app); fatalError("bundle changed") } catch {}
  client.engine.app=Software(id:app.id,bundleID:app.bundleID,price:0)
  client.valid=false
  do { _ = try await client.freeAppForRecovery(app); fatalError("stale session") } catch {}
  client.valid=true
  var calls:[String]=[]
  do {
   _ = try await StoreFreeLicenseRecovery.retryOnce(consent:false,acquire:{calls.append("acquire")},download:{ calls.append("download");return URL(fileURLWithPath:"/fixture") })
   fatalError("no consent")
  } catch is CancellationError {}
  precondition(calls.isEmpty)
  for version in [nil,"894893172"] as [String?] {
   let pending=StoreFreeLicenseRecovery(app:app,externalVersionID:version,revision:1)
   let result=try await StoreFreeLicenseRecovery.retryOnce(consent:true,acquire:{
    calls.append("acquire");try await client.acquireFreeApp(pending.app)
   },download:{
    precondition(pending.externalVersionID==version)
    calls.append("download");return URL(fileURLWithPath:"/fixture")
   })
   precondition(result.path=="/fixture")
  }
  precondition(calls == ["acquire","download","acquire","download"])
  calls=[]
  do {
   _ = try await StoreFreeLicenseRecovery.retryOnce(consent:true,acquire:{calls.append("acquire");throw RetryFailure.rejected},download:{calls.append("download");return URL(fileURLWithPath:"/fixture")})
   fatalError("acquisition error swallowed")
  } catch RetryFailure.rejected {}
  precondition(calls == ["acquire"])
  calls=[]
  do {
   _ = try await StoreFreeLicenseRecovery.retryOnce(consent:true,acquire:{calls.append("acquire")},download:{calls.append("403");throw RetryFailure.rejected})
   fatalError("second 403 swallowed")
  } catch RetryFailure.rejected {}
  precondition(calls == ["acquire","403"]) // no recursive acquisition/download
  print("PASS actual Swift helper consent/cancel, fresh free/paid/unknown identity/store/session guards, single retry, exact old version/latest, acquire failure and second 403 stop")
 }
}
"""
fixture=fixture.replace('PRICE',price).replace('FRESH',fresh).replace('ACQUIRE',acquire)
# Client methods mutate its busy flag; the actor in production owns this state.
fixture=fixture.replace('struct Client {','final class Client {')
with tempfile.TemporaryDirectory(prefix='free-recovery-') as d:
 p=Path(d)/'main.swift';p.write_text(helper+'\n'+fixture)
 binary=str(Path(d)/'test')
 subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(p),'-o',binary],check=True)
 subprocess.run([binary],check=True,timeout=30)
