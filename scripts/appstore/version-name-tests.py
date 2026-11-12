#!/usr/bin/env python3
"""Execute the actual UI name-loading coordinator with deterministic offline fixtures."""
from pathlib import Path
import re, subprocess, tempfile
r=Path(__file__).resolve().parents[2]
s=(r/'ios-app/Apps/AppStoreAccountView.swift').read_text()
f=s[s.index('    private func requestMetadata('):s.index('    private func recordOwnershipFailure(')].replace('private func','func')
stubs='''import Foundation
struct MirsaStoreApp { let bundleID: String }
enum MirsaStoreServerClient {
    struct VersionMetadata { let externalVersionID: String; let status: String; let version: String? }
}
@MainActor final class Client {
    var calls = 0
    var mode = "success"
    func versionMetadata(_ app: MirsaStoreApp, externalVersionIDs ids: [String]) async throws -> [MirsaStoreServerClient.VersionMetadata] {
        calls += 1
        if mode == "timeout" { throw URLError(.timedOut) }
        if mode == "error" { throw URLError(.badServerResponse) }
        if mode == "cancel" { try await Task.sleep(nanoseconds: 5_000_000_000) }
        await Task.yield()
        return ids.map { .init(externalVersionID: $0, status: "ready", version: "2.9.9") }
    }
}
@MainActor final class Harness {
    let client = Client()
    var metadata: [String: [String: MirsaStoreServerClient.VersionMetadata]] = [:]
    var metadataTasks: [String: Task<Void, Never>] = [:]
    var operationGeneration = UUID()
'''
tests='''
@main struct Tests {
    @MainActor static func main() async {
        let app = MirsaStoreApp(bundleID: "example.owned")
        for mode in ["success", "timeout", "error"] {
            let h = Harness(); h.client.mode = mode
            h.requestMetadata(app, ids: (1...20).map(String.init))
            await h.metadataTasks[app.bundleID]?.value
            precondition(h.client.calls == 5)
            precondition(h.metadata[app.bundleID]?.count == 20)
            precondition(h.metadata[app.bundleID]?.values.allSatisfy { $0.status == (mode == "success" ? "ready" : "unavailable") } == true)
            h.requestMetadata(app, ids: (1...20).map(String.init))
            precondition(h.client.calls == 5, "known names/errors should not be repeatedly requested")
        }
        let h = Harness(); h.client.mode = "cancel"
        h.requestMetadata(app, ids: ["885245059", "883790661"])
        while h.client.calls == 0 { await Task.yield() }
        h.operationGeneration = UUID(); h.metadataTasks[app.bundleID]?.cancel()
        await h.metadataTasks[app.bundleID]?.value
        precondition(h.metadata.isEmpty, "cancelled stale lookup must not publish")
        print("PASS actual version-name loader: progressive four-item batches, cached ready/failure states, bounded request count, error/timeout ID fallback and cancellation")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='version-name-tests-') as d:
    p=Path(d)/'main.swift';p.write_text(stubs+f+'\n}\n'+tests)
    subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(p),'-o',str(Path(d)/'tests')],check=True)
    subprocess.run([str(Path(d)/'tests')],check=True,timeout=30)
