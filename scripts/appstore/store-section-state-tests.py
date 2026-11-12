#!/usr/bin/env python3
"""Source regressions for account sharing. Runtime/Xcode validation runs separately."""
from pathlib import Path
r=Path(__file__).resolve().parents[2]
v=(r/'ios-app/Apps/AppStoreAccountView.swift').read_text()
m=(r/'ios-app/Apps/AppStoreSection.swift').read_text()
c=(r/'ios-app/AppStore/StoreOnDeviceClient.swift').read_text()
assert '@State private var account:' not in v
assert '@ObservedObject private var session = AppStoreSectionModel.shared' in v
assert 'session.updateAccount(newValue)' in v
assert 'await session.refresh()' in v
assert 'revision == sessionRevision' in m
assert 'let current = try?' not in m
assert 'country ?? account.country' in c
assert 'accountAvailable.contains(app.id)' in v
assert 'busy != nil || !canDownload(app)' in v
assert 'availableInStore(found, country: accountCountry)' in v
assert 'local.downloadOwnedApp(app, externalVersionID: externalVersionID)' in c
# Commerce, authentication and downloads must remain byte-identical.
import subprocess,re
for name in ['signIn', 'verify', 'signOut', 'downloadOwnedApp', 'acquireFreeApp', 'availableVersions']:
 old=subprocess.check_output(['git','show','HEAD:ios-app/AppStore/StoreOnDeviceClient.swift'],cwd=r,text=True)
 def method(s):
  start=s.index('    func '+name+'(')
  end=s.find('\n    func ',start+1)
  return s[start:end if end!=-1 else s.rfind('\n}')]
 assert method(old)==method(c), name
print('PASS shared session, refresh race/error guards, search-only storefront, fail-closed account availability and untouched auth/download methods')
h=(r/'ios-app/AppStore/StorePurchaseHistory.swift').read_text()
assert 'MZPurchaseDaap.woa/purchase' in h
assert 'owner.cookie.buildCookieHeader(url)' in h
assert 'completionHandler(nil)' in h
assert 'X-Apple-ActionSignature' in h
assert 'adsr' in h and 'asdp' in h
assert 'EncryptedIPAEntry' not in m[m.index('struct AppStorePurchasesPage'):]
print('PASS history uses signed Apple DAAP, blocks credential redirects, replaces local-file fake purchases')
