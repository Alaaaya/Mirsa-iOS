#!/usr/bin/env python3
"""Run the real input/history state without SwiftUI, disk secrets or network."""
from pathlib import Path
import subprocess,tempfile
r=Path(__file__).resolve().parents[2]
source=(r/'ios-app/AppStore/StoreSearchState.swift').read_text()
tests=r"""
enum MirsaStoreError: Error { case invalidInput }
@main struct Tests {
 static func main() throws {
  precondition(try StoreSearchQuery.parse(" parkingpro ") == .name("parkingpro"))
  precondition(try StoreSearchQuery.parse("000123") == .appID("123"))
  precondition(try StoreSearchQuery.parse("https://apps.apple.com/tr/app/name/id123?token=secret#secret") == .appID("123"))
  precondition(try StoreSearchQuery.parse("apps.apple.com/app/id456") == .appID("456"))
  for bad in ["", "0", "-1://bad", "https://evil.invalid/id123", "https://apps.apple.com.evil.invalid/id123",
              "https://secret@Apple.com/id123", "https://apps.apple.com:8443/id123", "http://apps.apple.com/id123",
              "https://apps.apple.com/app/idbad", "https://apps.apple.com/app/id123/../", "a\nb",
              String(repeating:"x",count:257), "9999999999999999999999999"] {
   do { _ = try StoreSearchQuery.parse(bad); fatalError("accepted invalid input") } catch {}
  }
  var data=StoreRecentSearches.adding("parkingpro",to:Data())
  data=StoreRecentSearches.adding("PARKINGPRO",to:data)
  precondition(StoreRecentSearches.read(data)==["PARKINGPRO"])
  data=StoreRecentSearches.adding("https://apps.apple.com/tr/app/name/id123?token=secret",to:data)
  precondition(!String(decoding:data,as:UTF8.self).contains("secret"))
  precondition(StoreRecentSearches.read(data).first=="123")
  let removed=StoreRecentSearches.removing("123",from:data)
  precondition(StoreRecentSearches.read(removed)==["PARKINGPRO"])
  precondition(StoreRecentSearches.removing("absent",from:removed)==removed)
  precondition(StoreRecentSearches.read(StoreRecentSearches.encode([])).isEmpty)
  for i in 1...30 { data=StoreRecentSearches.adding("app \(i)",to:data) }
  precondition(StoreRecentSearches.read(data).count==12)
  precondition(StoreRecentSearches.read(data).first=="app 30")
  precondition(StoreRecentSearches.read(Data(repeating:32,count:4097)).isEmpty)
  precondition(StoreRecentSearches.read(Data("broken".utf8)).isEmpty)
  precondition(StoreRecentSearches.read(Data()).isEmpty)
  print("PASS actual Search name/AppID/link parsing; hostile URLs rejected; local recents bounded/deduplicated, canonical IDs drop URL secrets; malformed storage/clear safe")
 }
}
"""
# Throwing expressions cannot be evaluated in precondition's nonthrowing autoclosure.
tests=tests.replace('precondition(try StoreSearchQuery.parse(', 'precondition((try StoreSearchQuery.parse(')
import re
tests=re.sub(r'precondition\(\(try StoreSearchQuery.parse\(([^\n]+?)\) == ([^\n]+?)\)',r'precondition((try StoreSearchQuery.parse(\1)) == \2)',tests)
# Use regular local values instead for clarity.
lines=[]
for line in tests.splitlines():
 if 'precondition((try StoreSearchQuery.parse' in line:
  expr=line.strip()[len('precondition('):-1]
  expr=expr.replace('(try ', '(try! ')
  line='  precondition('+expr+')'
 lines.append(line)
tests='\n'.join(lines)
v=(r/'ios-app/Apps/AppStoreAccountView.swift').read_text()
controls=v[v.index('    private func searchControls('):v.index('    // MARK: result row')]
assert '.onSubmit { search() }' in controls and '.mirsaPrimary' not in controls
assert 'store-search-account' in v and 'Button(action: onOpenAccount)' in v
assert 'recentSearchData = Data()' in v
select=v[v.index('    private func selectCountry('):v.index('    private func search()')]
assert 'search()' not in select
with tempfile.TemporaryDirectory(prefix='search-state-') as d:
 p=Path(d)/'test.swift';p.write_text(source+tests)
 subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(p),'-o',str(Path(d)/'test')],check=True)
 subprocess.run([str(Path(d)/'test')],check=True,timeout=20)
