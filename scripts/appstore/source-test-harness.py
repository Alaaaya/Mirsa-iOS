#!/usr/bin/env python3
"""Compile the actual source models/store/parser on macOS, without iOS screen dependencies.
Only unrelated update-all UI entrypoints are omitted, never catalogue or deletion behavior.
The iOS build separately compiles the complete unmodified production SourcesTab.swift.
"""
from pathlib import Path
import sys,gzip
root=Path(__file__).resolve().parents[2]; work=Path(sys.argv[1])
source=(root/'ios-app/Apps/SourcesTab.swift').read_text()
body=source[source.index('struct RepoApp:'):source.index('\nextension Color {')]
# These three methods require the full installation UI, not catalogue I/O or persistence.
a=body.index('    func moveVisible('); b=body.index('    /// Sources that ship',a)
body=body[:a]+body[b:]
# Real screenshot parsing/URL safety, not a stub parser.
screen=(root/'ios-app/Apps/AppScreenshots.swift').read_text(); screen=screen[screen.index('enum ScreenshotPolicy {'):screen.index('    static func validBundleID(')]+'}\n'
policy=(root/'ios-app/Discovery/DiscoveryCore.swift').read_text(); policy=policy[policy.index('enum DiscoveryURLPolicy {'):policy.index('// MARK: - Query parsing')]
headers='import Foundation\nimport Combine\n'
out=work/'Sources/MirsaStoreKit'
(out/'SourcesCatalogHarness.swift').write_text(headers+body+'\n'+screen+'\n'+policy)
(out/'MirsaSourceFeed.swift').write_text((root/'ios-app/Apps/MirsaSourceFeed.swift').read_text())
(out/'SourceTestLocalization.swift').write_text('func tr(_ en: String, _ ar: String) -> String { en }\nenum MirsaTr { static func f(_ key: String, _ n: Int) -> String { "HTTP \\(n)" } }\n')
tests=work/'Tests/MirsaStoreKitTests'
for name in ['SourceCatalogTests.swift','SourceDeletionTests.swift']:
 text=(root/'tests'/name).read_text().replace('@testable import Mirsa\n','@testable import MirsaStoreKit\n')
 # async XCTest methods support the main actor consistently across Swift toolchains.
 if name=='SourceDeletionTests.swift':
  import re
  text=re.sub(r'(    func test\w+\(\))\s*(throws)?\s*\{',lambda m:m[1]+' async'+(' throws' if m[2] else '')+' {',text)
 (tests/name).write_text(text)
fixtures=work/'source-fixtures';fixtures.mkdir()
for name in ['apptesters','ryp0']:
 (fixtures/(name+'.json')).write_bytes(gzip.decompress((root/'tests/SourceFixtures'/(name+'.json.gz')).read_bytes()))
print('Actual production catalogue/persistence/parser extracted; two full pinned JSON fixtures decompressed')
