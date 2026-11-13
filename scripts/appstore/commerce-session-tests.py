#!/usr/bin/env python3
"""Offline source invariants for explicit-free atomic acquisition and native dispatch."""
from pathlib import Path
import hashlib
r = Path(__file__).resolve().parents[2]
client = (r/'ios-app/AppStore/StoreClient.swift').read_text()
a = client.split('    func acquireFreeAppAndDownload(', 1)[1].split('    /// Returns a local encrypted IPA', 1)[0]
assert a.count('try await beginQueued()') == 1 and a.count('requiredAccount()') == 1
assert 'fresh.id == app.id, fresh.bundleID == app.bundleID' in a
assert a.index('requireFree(fresh.price)') < a.index('engine.acquire(account: &owner') < a.index('engine.manifest(account: &owner')
assert a.index('try persist(owner)') < a.index('engine.manifest(')
assert 'version: version' in a and 'validate(output: output, app: app, version: version)' in a
assert 'vault.remove' not in a and 'try check(run)' in a
ui=(r/'ios-app/Apps/AppStoreAccountView.swift').read_text()
get=ui.split('    private func acquire(_ app:',1)[1].split('    private func loadVersions',1)[0]
assert 'guard app.price == 0' in get
assert 'let version = chosen[app.bundleID]' in get
assert 'client.acquireFreeAppAndDownload(app, externalVersionID: version)' in get
assert 'onDownloaded(url)' in get and 'operationGeneration' in get and 'Task.checkCancellation()' in get
reauth=ui.split('if diagnostic.requiresReauthentication {',1)[1].split('let explanation',1)[0]
for text in ['Sign out', 'سجّل خروج', 'بچۆ دەرەوە', 'derkeve']:
    assert text in reauth
assert 'vault.remove' not in reauth and 'signOut()' not in reauth
safe = client.split('    private func safe(', 1)[1]
assert 'if diagnostic.requiresReauthentication {' in safe
assert 'do { try signOut() }' in safe
logout = client.split('    func signOut()', 1)[1].split('    func acquireFreeApp(', 1)[0]
assert 'vault.remove("account")' in logout and 'vault.remove("machine")' not in logout
up=r/'vendor/ApplePackage/Sources/CStoreAMD/Upstream'
for line in (up/'PROVENANCE.txt').read_text().splitlines():
    if '  ' in line and len(line.split('  ')[0])==64:
        sha,path=line.split('  ',1)
        assert hashlib.sha256((up/path).read_bytes()).hexdigest()==sha, path
fetch=(r/'vendor/ApplePackage/Sources/ApplePackage/Commands/StoreDownloadEndpoint+Fetch.swift').read_text()
assert 'StoreDownloadEndpoint.entitlement.fetchProduct' in fetch
assert 'if error.requiresReauthentication || error.requiresLicense { throw error }' in fetch
print('PASS explicit free atomic Get+download, same owner/session, selected version, four-language recoverable reauth, pinned unmodified MIT headers')
