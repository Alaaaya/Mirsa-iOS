#!/usr/bin/env python3
"""Exercise the actual grid columns and existing filters, with no Apple calls."""
from pathlib import Path
import subprocess, tempfile, sys
r = Path(__file__).resolve().parents[2]
ui = (r/'ios-app/Apps/AppStoreSection.swift').read_text()
base = subprocess.check_output(['git', 'show', '193256bd89abb046ada6fe5fbdca64762929619e:ios-app/Apps/AppStoreSection.swift'], cwd=r, text=True)
def visible(s):
    return s[s.index('    private var visible: [MirsaStorePurchase]'):s.index('    var body: some View {', s.index('    private var visible: [MirsaStorePurchase]'))]
assert visible(ui) == visible(base), "filter semantics changed"
start = '    @MainActor private func reload() async {'
download_start = '    @MainActor private func download('
assert ui[ui.index(start):ui.index(download_start)] == base[base.index(start):base.index(download_start)], "history loading, paging or artwork changed"
# Authorized recovery modifies only the failed-download branch, not original import.
old_download = base[base.index(download_start):].rsplit('\n}', 1)[0]
new_download = ui[ui.index(download_start):ui.index('    @MainActor private func recoverDownload(')]
assert old_download.split('        } catch is CancellationError {}')[0] in new_download
assert 'store.add(entry)' in new_download
for path in ['ios-app/AppStore/StorePurchaseHistory.swift', 'ios-app/AppStore/StoreSearchState.swift', 'ios-app/AppStore/StoreDiscovery.swift']:
    old = subprocess.check_output(['git', 'show', '193256bd89abb046ada6fe5fbdca64762929619e:'+path], cwd=r)
    assert old == (r/path).read_bytes(), path
assert 'String(visible.count)' in ui and '1028' not in ui
page = ui[ui.index('struct AppStorePurchasesPage:'):]
assert ui[:ui.index('struct AppStorePurchasesPage:')].replace("import ApplePackage\n", "") == base[:base.index('struct AppStorePurchasesPage:')].replace("import ApplePackage\n", ""), "Search or other tab changed"

assert 'LazyVGrid' not in page and 'purchaseTile(' not in page
assert 'ForEach(StorePurchaseGroups.make(visible))' in page
assert 'ForEach(group.items)' in page and 'purchaseRow(item)' in page
assert 'String(group.items.count)' in page and '.isHeader' in page
assert 'StorePurchaseGroups.title' in page and '.ultraThinMaterial' in page
assert 'account.email' in page and 'String(visible.count)' in page
filters = '    private var purchaseFilters: some View'
assert page[page.index(filters):page.index('    private func purchaseGroup(')] == base[base.index(filters):base.index('    private func purchaseGroup(')]
row = page[page.index('    private func purchaseRow('):page.index(start)]
assert row == base[base.index('    private func purchaseRow('):base.index(start)]
# Everything other than the one Purchases view, its tests and workflow stays exact.
import hashlib
changed = subprocess.check_output(['git', 'diff', '--name-only', '193256b'], cwd=r, text=True).splitlines()
allowed = {'ios-app/Apps/AppStoreSection.swift', 'scripts/appstore/purchases-group-tests.py', '.github/workflows/precise-build.yml',
'ios-app/Apps/AppStoreAccountView.swift', 'ios-app/AppStore/StoreClient.swift',
'ios-app/AppStore/StoreOnDeviceClient.swift', 'ios-app/AppStore/StoreFreeLicenseRecovery.swift',
'vendor/ApplePackage/Sources/ApplePackage/Commands/Purchase.swift',
'vendor/ApplePackage/Sources/ApplePackage/Commands/StoreDownloadEndpoint+Fetch.swift',
'vendor/ApplePackage/Tests/ApplePackageTests/StoreOwnershipEvidenceTests.swift',
'vendor/ApplePackage/Tests/ApplePackageTests/StoreDownloadRecoveryTests.swift',
'scripts/appstore/free-recovery-tests.py', 'scripts/appstore/versions-list-tests.py',
'scripts/tests/store_ownership_intent_test.py'}
# Later owner-authorized native dispatch is confined to these files and pinned MIT headers.
allowed.update({
    'ios-app/Apps/GuestLoader.m',
    'ios-app/Apps/EncryptedApps.swift', 'ios-app/Apps/EncryptedLocalInstall.swift',
    'scripts/appstore/encrypted-cellular-tests.py',
    'scripts/appstore/download-progress-tests.py', 'ios-app/AppStore/StorePackages.swift',
    'scripts/appstore/version-name-tests.py', 'scripts/appstore/commerce-lock-tests.py', 'scripts/appstore/commerce_lock_scope.py',
    'scripts/appstore/commerce-session-tests.py', 'vendor/ApplePackage/Package.swift',
    'vendor/ApplePackage/Sources/ApplePackage/Models/StoreDownloadEndpoint.swift',
    'vendor/ApplePackage/Sources/ApplePackage/SAP/StoreAMDProof.swift',
    'vendor/ApplePackage/Sources/CStoreAMD/StoreKBSync.cpp',
    'vendor/ApplePackage/Sources/CStoreAMD/include/CStoreAMD.h',
})
upstream = set()
for line in (r/'vendor/ApplePackage/Sources/CStoreAMD/Upstream/PROVENANCE.txt').read_text().splitlines():
    if '  ' in line and len(line.split('  ')[0]) == 64:
        digest, path = line.split('  ', 1)
        full = 'vendor/ApplePackage/Sources/CStoreAMD/Upstream/' + path
        assert hashlib.sha256((r/full).read_bytes()).hexdigest() == digest
        upstream.add(full)
upstream.update({'vendor/ApplePackage/Sources/CStoreAMD/Upstream/PROVENANCE.txt',
                 'vendor/ApplePackage/Sources/CStoreAMD/Upstream/LICENSE'})
assert set(changed) <= allowed | upstream, changed
print('PASS exact Search, filters, account history, original icon/name/date/cloud rows and download path; rounded glass month list, localized headers, month and total counts')
if '--source-only' in sys.argv: sys.exit(0)
# Execute the unmodified production grouping helper and original filters.
history = (r/'ios-app/AppStore/StorePurchaseHistory.swift').read_text()
purchase = history[history.index('struct MirsaStorePurchase:'):history.index('/// Read-only own-account')]
groups = (r/'ios-app/Apps/StorePurchaseGroups.swift').read_text()
source = """import Foundation
struct MirsaStoreApp { let id: Int64; let bundleID: String; let name: String; let version: String; let price: Double?; let artworkURL: String }
""" + purchase + groups + """
@main struct Tests {
 static func main() {
  var cal=Calendar(identifier:.gregorian); cal.timeZone=TimeZone(secondsFromGMT:0)!
  func item(_ id:Int64,_ date:Date?)->MirsaStorePurchase {
   .init(id:id,bundleID:"example",name:"App",version:"1",date:date)
  }
  let nov=cal.date(from:DateComponents(year:2026,month:11,day:13))!
  let oct=cal.date(from:DateComponents(year:2026,month:10,day:4))!
  let groups=StorePurchaseGroups.make([item(1,oct),item(2,nov),item(3,nil),item(4,nov)],calendar:cal)
  precondition(groups.map { $0.items.map(\.id) } == [[2,4],[1],[3]])
  precondition(groups.last!.month == nil)
  precondition(StorePurchaseGroups.make([],calendar:cal).isEmpty)
  let title=StorePurchaseGroups.title(nov,locale:Locale(identifier:"ar"),calendar:cal)
  precondition(!title.isEmpty)
  print("PASS actual month grouping, newest first, stable row IDs, unknown date group, Arabic header")
 }
}
"""
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'tests.swift';p.write_text(source)
 subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(p),'-o',d+'/tests'],check=True)
 subprocess.run([d+'/tests'],check=True,timeout=20)
