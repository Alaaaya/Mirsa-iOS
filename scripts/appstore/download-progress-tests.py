#!/usr/bin/env python3
from pathlib import Path
import subprocess,tempfile
r=Path(__file__).resolve().parents[2]
package=(r/'ios-app/AppStore/StorePackages.swift').read_text()
model=package.split('// BEGIN STORE DOWNLOAD PROGRESS')[1].split('// END STORE DOWNLOAD PROGRESS')[0]
ui=(r/'ios-app/Apps/AppStoreAccountView.swift').read_text()
assert 'didWriteData bytesWritten' in package and 'received: totalBytesWritten, expected: totalBytesExpectedToWrite' in package
assert 'received: Int64(size)' in package # cached path
assert package.index('try Self.assemble') < package.index('report?(.init(phase: .validating))')
assert ui.index('try await onDownloaded(url)') < ui.index('transfer?.apply(.init(phase: .saved))')
assert 'progressAttempt == attempt' in ui and 'progressAttempt = nil; transfer = nil' in ui
assert 'StoreDownloadProgress.$report.withValue(report)' in ui
test=r"""
@main struct Test {
 static func main() {
    var p = StoreDownloadProgress()
    precondition(p.fraction == 0)
    p.apply(.init(phase:.downloading, received:10,expected:100,time:1))
    let first=p.fraction!
    p.apply(.init(phase:.downloading, received:50,expected:100,time:3))
    precondition(p.speed == 20 && p.received == 50 && p.fraction! >= first)
    p.apply(.init(phase:.downloading, received:20,expected:100,time:4))
    precondition(p.received == 50 && p.speed == 0)
    p.apply(.init(phase:.downloading, received:100,expected:100,time:5))
    precondition(p.fraction! < 1)
    for phase in [StoreDownloadProgress.Phase.packaging,.validating,.saving] {
       let old=p.fraction!; p.apply(.init(phase:phase))
       precondition(p.fraction! >= old && p.fraction! < 1)
    }
    p.apply(.init(phase:.downloading,received:1,expected:100,time:6))
    precondition(p.phase == .saving && p.fraction == 0.99)
    p.apply(.init(phase:.saved)); precondition(p.fraction == 1)
    p.apply(.init(phase:.failed)); precondition(p.fraction == 1)
    var unknown=StoreDownloadProgress()
    unknown.apply(.init(phase:.downloading,received:100,expected:-1,time:1))
    unknown.apply(.init(phase:.downloading,received:300,expected:-1,time:3))
    precondition(unknown.fraction == nil && unknown.received == 300 && unknown.speed == 100)
    unknown.apply(.init(phase:.failed))
    precondition(unknown.fraction == nil && unknown.speed == 0)
    unknown.apply(.init(phase:.saved)); precondition(unknown.phase == .failed)
    var cached=StoreDownloadProgress()
    cached.apply(.init(phase:.downloading,received:1000,expected:1000,time:1))
    precondition(cached.fraction == 0.94 && cached.received == 1000)
    print("PASS actual progress model: bounded monotonic stages, true byte/speed metrics, unknown length no percentage, cached callback, stale/terminal events ignored, 100 only after validated library save")
 }
}
"""
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'main.swift';p.write_text('import Foundation\n'+model+test)
 subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(p),'-o',d+'/test'],check=True)
 subprocess.run([d+'/test'],check=True)
