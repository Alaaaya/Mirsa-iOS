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
assert ui[ui.index(start):] == base[base.index(start):], "history loading, paging, artwork or download changed"
for path in ['ios-app/AppStore/StorePurchaseHistory.swift', 'ios-app/AppStore/StoreSearchState.swift', 'ios-app/AppStore/StoreDiscovery.swift']:
    old = subprocess.check_output(['git', 'show', '193256bd89abb046ada6fe5fbdca64762929619e:'+path], cwd=r)
    assert old == (r/path).read_bytes(), path
assert 'String(visible.count)' in ui and '1028' not in ui
page = ui[ui.index('struct AppStorePurchasesPage:'):]
assert ui[:ui.index('struct AppStorePurchasesPage:')] == base[:base.index('struct AppStorePurchasesPage:')], "Search or other tab changed"
assert 'LazyVGrid(columns: purchaseColumns, alignment: .center, spacing: 12)' in page
assert 'Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top), count: 3)' in page
assert 'ForEach(visible) { item in\n                            purchaseTile(item)' in page
for removed in ['StorePurchaseGroups', 'purchaseGroup(', 'purchaseRow(', '.isHeader', 'group.items', '.dateTime']:
    assert removed not in page, removed
filters = '    private var purchaseFilters: some View'
assert page[page.index(filters):page.index('    // Equal flexible columns')] == base[base.index(filters):base.index('    private func purchaseGroup(')]
tile = page[page.index('    private func purchaseTile('):page.index(start)]
assert tile.index('AsyncImage(') < tile.index('Text(item.name')
for required in ['.aspectRatio(1, contentMode: .fit)', '.overlay(alignment: .bottomTrailing)', 'purchaseDownloadBadge(item)',
                 '.background(.ultraThinMaterial', '.multilineTextAlignment(.center)', '.lineLimit(2)',
                 'store-purchase-tile-\\(item.id)', 'store-purchase-download-\\(item.id)',
                 '.frame(width: 44, height: 44)', 'await download(item)',
                 '.disabled(loading || downloading != nil || store.busy != nil)',
                 '.accessibilityLabel(tr("Download"', '+ " " + item.name']:
    assert required in tile, required
assert tile.count('await download(item)') == 1
assert 'Button { Task { await download(item) } }' in tile
assert '.environment(\\.layoutDirection, .leftToRight)' in page  # existing physical layout; centered names support both scripts
assert 'account.email' in page and 'value: -months' in page and 'String(visible.count)' in page
assert page.index('AppStoreSearchField(') < page.index('purchaseFilters\n') < page.index('String(visible.count)') < page.index('LazyVGrid(')
# Everything other than the one Purchases view, its tests and workflow stays exact.
import hashlib
changed = subprocess.check_output(['git', 'diff', '--name-only', '193256b'], cwd=r, text=True).splitlines()
allowed = {'ios-app/Apps/AppStoreSection.swift', 'scripts/appstore/purchases-group-tests.py', '.github/workflows/precise-build.yml'}
assert set(changed) <= allowed, changed
print('PASS exact baseline Search, lifecycle, filters, account/download engine, three-column flat grid, no month/date headers, glass icon tiles, corner badge action, accessible labels and dynamic count')
if '--source-only' in sys.argv:
    sys.exit(0)
history = (r/'ios-app/AppStore/StorePurchaseHistory.swift').read_text()
purchase = history[history.index('struct MirsaStorePurchase:'):history.index('/// Read-only own-account')]
columns = ui[ui.index('    private var purchaseColumns:'):ui.index('    private func purchaseTile(')]
harness = """
struct MirsaStoreApp { let id: Int64; let bundleID: String; let name: String; let version: String; let price: Double?; let artworkURL: String }
struct GridItem {
 enum Size { case flexible(minimum: Double) }
 enum Alignment { case top }
 let size: Size; let spacing: Double; let alignment: Alignment
 init(_ size: Size, spacing: Double, alignment: Alignment) {
  self.size=size; self.spacing=spacing; self.alignment=alignment
 }
}
struct FilterHarness {
 var purchases: [MirsaStorePurchase]; var months: Int; var query: String
"""
harness += visible(ui).replace('    private var visible:', '    var visible:') + '\n}\n'
harness += 'struct LayoutHarness {\n' + columns.replace('    private var purchaseColumns:', '    var purchaseColumns:') + '\n}\n'
tests = r"""
@main struct Tests {
 static func item(_ id: Int64, _ date: Date?, _ name: String = "App") -> MirsaStorePurchase {
  .init(id: id, bundleID: "example.\(id)", name: name, version: "1", date: date)
 }
 static func main() {
  let columns=LayoutHarness().purchaseColumns
  precondition(columns.count==3)
  for column in columns {
   guard case .flexible(let minimum) = column.size else { fatalError() }
   precondition(minimum==0 && column.spacing==12)
  }
  // Three equal columns fit compact and larger widths without adaptive column-count changes.
  for viewport in [320.0,375,390,430,768] {
   let content=viewport-40
   let width=(content-Double(columns.count-1)*12)/Double(columns.count)
   precondition(width>24) // square icon remains visible inside tile padding
   precondition(abs(width*3+24-content)<0.001)
  }
  let now=Date()
  let old=Calendar.current.date(byAdding:.month,value:-18,to:now)!
  let rows=[item(123,now,"YouTube"),item(456,old,"ParkingPro"),item(789,nil,"واتساب")]
  for (query,ids) in [("youtube",[123]),("EXAMPLE.456",[456]),("789",[789]),("واتساب",[789]),("none",[])] as [(String,[Int64])] {
   precondition(FilterHarness(purchases:rows,months:0,query:query).visible.map(\.id)==ids)
  }
  for months in [1,6,12] {
   precondition(FilterHarness(purchases:rows,months:months,query:"").visible.map(\.id)==[123])
  }
  precondition(FilterHarness(purchases:rows,months:0,query:"").visible.map(\.id)==[123,456,789])
  precondition(FilterHarness(purchases:[],months:0,query:"").visible.isEmpty)
  print("PASS actual Swift three equal column configuration, compact-width layout, unchanged query/month filters, count and original item identity/order")
 }
}
"""
with tempfile.TemporaryDirectory(prefix='purchase-groups-') as d:
    p = Path(d)/'test.swift'
    p.write_text('import Foundation\n'+purchase+harness+tests)
    binary = str(Path(d)/'test')
    subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(p),'-o',binary],check=True)
    subprocess.run([binary],check=True,timeout=20)
