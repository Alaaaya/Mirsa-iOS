#!/usr/bin/env python3
"""Exercise the actual presentation grouping, with no Apple calls or SwiftUI."""
from pathlib import Path
import subprocess, tempfile, sys
r = Path(__file__).resolve().parents[2]
ui = (r/'ios-app/Apps/AppStoreSection.swift').read_text()
base = subprocess.check_output(['git', 'show', 'ff179dcf545b142791df9e251334f0dd4ba52b87:ios-app/Apps/AppStoreSection.swift'], cwd=r, text=True)
def visible(s):
    return s[s.index('    private var visible: [MirsaStorePurchase]'):s.index('    var body: some View {', s.index('    private var visible: [MirsaStorePurchase]'))]
assert visible(ui) == visible(base), "filter semantics changed"
start = '    @MainActor private func reload() async {'
assert ui[ui.index(start):] == base[base.index(start):], "history loading, paging, artwork or download changed"
for path in ['ios-app/AppStore/StorePurchaseHistory.swift', 'ios-app/AppStore/StoreSearchState.swift', 'ios-app/AppStore/StoreDiscovery.swift']:
    old = subprocess.check_output(['git', 'show', 'ff179dcf545b142791df9e251334f0dd4ba52b87:'+path], cwd=r)
    assert old == (r/path).read_bytes(), path
assert 'String(visible.count)' in ui and '1028' not in ui
assert 'ForEach(StorePurchaseGroups.make(visible))' in ui
assert 'ForEach(group.items)' in ui
row = ui[ui.index('    private func purchaseRow('):ui.index(start)]
assert row.index('await download(item)') < row.index('Text(item.name') < row.index('AsyncImage(')
assert 'fileSize' not in row and 'ByteCountFormatter' not in row
assert 'account.email' in ui and 'value: -months' in ui
print('PASS unchanged filtering, full history lifecycle, Search data, stable item IDs, actual action and dynamic count contracts')
if '--source-only' in sys.argv:
    sys.exit(0)
history = (r/'ios-app/AppStore/StorePurchaseHistory.swift').read_text()
purchase = history[history.index('struct MirsaStorePurchase:'):history.index('/// Read-only own-account')]
helper = (r/'ios-app/Apps/StorePurchaseGroups.swift').read_text()
harness = '''
struct MirsaStoreApp { let id: Int64; let bundleID: String; let name: String; let version: String; let price: Double?; let artworkURL: String }
struct FilterHarness {
 var purchases: [MirsaStorePurchase]; var months: Int; var query: String
'''
harness += visible(ui).replace('    private var visible:', '    var visible:') + '\n}\n'
tests = r"""
@main struct Tests {
 static func item(_ id: Int64, _ date: Date?, _ name: String = "App") -> MirsaStorePurchase {
  .init(id: id, bundleID: "example.\(id)", name: name, version: "1", date: date)
 }
 static func main() {
  let iso = ISO8601DateFormatter()
  func date(_ s: String) -> Date { iso.date(from:s)! }
  var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT:0)!
  var berlin = utc; berlin.timeZone = TimeZone(identifier:"Europe/Berlin")!
  let boundary = date("2026-10-31T23:30:00Z")
  let old = date("2025-12-31T23:30:00Z")
  let recent = date("2026-11-01T01:00:00Z")
  let rows = [item(9,nil),item(1,boundary),item(2,recent),item(3,recent),item(4,old),item(5,Date(timeIntervalSinceReferenceDate: .nan)),item(6,Date(timeIntervalSinceReferenceDate: .infinity)),item(7,Date(timeIntervalSinceReferenceDate: 1e20))]
  let u = StorePurchaseGroups.make(rows, calendar:utc)
  precondition(u.count == 4)
  precondition(u[0].items.map(\.id) == [2,3])
  precondition(u[1].items.map(\.id) == [1])
  precondition(u[2].items.map(\.id) == [4])
  precondition(u[3].month == nil && u[3].items.map(\.id) == [9,5,6,7])
  let b = StorePurchaseGroups.make(rows, calendar:berlin)
  precondition(b.count == 3 && b[0].items.map(\.id) == [2,3,1])
  precondition(berlin.component(.month,from:b[0].month!) == 11)
  precondition(berlin.component(.year,from:b[1].month!) == 2026)
  precondition(utc.component(.year,from:u[2].month!) == 2025)
  precondition(StorePurchaseGroups.make([],calendar:utc).isEmpty)
  precondition(StorePurchaseGroups.make([item(1,nil)],calendar:utc).first?.month == nil)
  precondition(StorePurchaseGroups.make(rows,calendar:utc).flatMap(\.items).map(\.id) == u.flatMap(\.items).map(\.id))
  // DST repetition is still a single purchase calendar month.
  let dst = StorePurchaseGroups.make([item(1,date("2026-10-25T00:30:00Z")),item(2,date("2026-10-25T01:30:00Z"))],calendar:berlin)
  precondition(dst.count == 1 && dst[0].items.map(\.id) == [2,1])
  for locale in [Locale(identifier:"ar"),Locale(identifier:"en"),Locale(identifier:"ckb"),Locale(identifier:"kmr")] {
   precondition(!StorePurchaseGroups.title(b[0].month!,locale:locale,calendar:berlin).isEmpty)
  }
  // Original query is case insensitive and matches names, bundle IDs and numeric IDs.
  let safe = [item(123,recent,"YouTube"),item(456,old,"ParkingPro"),item(789,nil)]
  for (query,ids) in [("youtube",[123]),("EXAMPLE.456",[456]),("789",[789]),("none",[])] as [(String,[Int64])] {
   let f=FilterHarness(purchases:safe,months:0,query:query).visible
   precondition(f.map(\.id)==ids)
   precondition(StorePurchaseGroups.make(f,calendar:utc).flatMap(\.items).count==f.count)
  }
  // Date filter keeps its exact existing rolling cutoff and excludes missing dates.
  let now=Date()
  let filterRows=[item(1,now),item(2,utc.date(byAdding:.month,value:-18,to:now)!),item(3,nil)]
  for months in [1,6,12] {
   precondition(FilterHarness(purchases:filterRows,months:months,query:"").visible.map(\.id)==[1])
  }
  precondition(FilterHarness(purchases:filterRows,months:0,query:"").visible.count==3)
  // Original timestamps are untouched by sorting/grouping.
  precondition(u.flatMap(\.items).first(where:{$0.id==1})?.date==boundary)
  print("PASS real Swift grouping, timezone/month/year/DST boundaries, newest-first and stable ties, missing/nonfinite/out-of-range dates, localized headers and filter/count identities")
 }
}
"""
with tempfile.TemporaryDirectory(prefix='purchase-groups-') as d:
    p = Path(d)/'test.swift'
    p.write_text(helper+purchase+harness+tests)
    binary = str(Path(d)/'test')
    subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(p),'-o',binary],check=True)
    subprocess.run([binary],check=True,timeout=20)
