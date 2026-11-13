#!/usr/bin/env python3
"""Binding/laziness/install source guards. Runtime data/state tests run separately."""
from pathlib import Path
import ast,gzip,hashlib,json,re
root=Path(__file__).resolve().parents[2]
s=(root/'ios-app/Apps/SourcesTab.swift').read_text()
detail=s.split('struct SourceDetailView: View {',1)[1].split('private struct RepoAppRow:',1)[0]
parent=s.split('struct SourcesTab: View {',1)[1].split('struct SourceDetailView:',1)[0]
row=s.split('private struct RepoAppRow:',1)[1].split('private struct RepoAppInfo:',1)[0]
assert 'SourceDetailView(source: s, store: store, onSelectIPA: onSelectIPA)' in parent
assert 'if store.apps.isEmpty' not in parent
assert '.task { await store.loadMissing() }' in parent
assert '@ObservedObject private var store: SourcesStore' in detail
assert 'self.store = store' in detail
assert '.task(id: source.url) { await store.ensureLoaded(source.url) }' in detail
assert 'store.listing(for: source.url, query: query)' in detail
assert 'store.loadErrors[source.url]' in detail
assert 'store.apps[source.url] == nil' in detail
assert 'List {' in detail and 'ForEach(shown)' in detail
assert 'ScrollView {' not in detail and 'VStack' not in detail.split('ForEach(shown)',1)[1].split('if store.loading',1)[0]
assert 'installed: apps.apps.first { $0.id == app.bundleID }, onSelectIPA: onSelectIPA' in detail
assert 'installFromURL(app.downloadURL, location: target, appID: app.bundleID)' in row
assert 'try await onSelectIPA(url)' in row and 'downloader.download(app.downloadURL.absoluteString)' in row
assert 'requests[src.url]?.cancel()' in s
assert 'guard sources.contains(where: { $0.url == url }) else { return false }' in s
assert 'Task.detached(priority: .userInitiated)' in s
assert 'if let running = requests[url] { return await running.value }' in s
literal=r'"(?:[^"\\]|\\.)*"'
matches=re.findall(r'tr\(\s*('+literal+r')\s*,\s*('+literal+r')\s*,\s*ckb:\s*('+literal+r')\s*,\s*kmr:\s*('+literal+r')\s*\)',detail)
strings=[dict(zip(['en','ar','ckb','kmr'],map(ast.literal_eval,row))) for row in matches]
assert len(strings)==5 and all(all(row.values()) for row in strings)
fixtures={}
for name in ['apptesters','ryp0']:
 data=gzip.decompress((root/'tests/SourceFixtures'/(name+'.json.gz')).read_bytes())
 proof=json.loads((root/'tests/SourceFixtures'/(name+'-proof.json')).read_text())
 assert len(data)==proof['bytes'] and hashlib.sha256(data).hexdigest()==proof['sha256']
 apps=json.loads(data)['apps']; assert len(apps)==proof['rawApps']
 assert proof['configuredURL'] in s
 fixtures[name]=proof
out=root/'build/source-ui-contract-proof.json';out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps({'kind':'Source guards, not physical-device UI or install execution','strings':strings,'fullJSONFixtures':fixtures,
 'binding':'same injected store; per-URL on-entry ensureLoaded; missing URL loading independent of global cache',
 'rendering':'SwiftUI List with lazy ForEach, existing install/selection paths preserved',
 'historicalOrigin':'4a286fd471da63840fd170481e389d89a286595c',
 'releaseComparison':'1.7 and 1.8 identical source blob; 1.9 only temp-download cleanup changed, not catalogue or navigation'},ensure_ascii=False,indent=2))
print('PASS source UI binding/lazy list/install routes, five messages x four languages; full pinned JSON SHA/counts')
