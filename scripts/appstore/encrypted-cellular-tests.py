#!/usr/bin/env python3
"""Execute the real cellular handoff and install router, with offline iOS stubs."""
from pathlib import Path
import subprocess, tempfile, sys
r = Path(__file__).resolve().parents[2]
helper = (r/'ios-app/Apps/EncryptedLocalInstall.swift').read_text()
source = (r/'ios-app/Apps/EncryptedApps.swift').read_text()
method = source[source.index('    func install(_ entry:'):source.index('\n    #if DEBUG',source.index('    func install(_ entry:'))]
for forbidden in ['oracleUpload', 'legacyUpload', 'PersonalCertificateSigner', 'CertificateOTA.install(', 'upload(for:', 'FileManager.default.removeItem']:
    assert forbidden not in helper, forbidden
assert 'CFBundleVersion' in helper and 'CFBundleShortVersionString' not in helper
assert method.index('busy = L.t') < method.index('await WiFiPathMonitor')
assert method.index('try await EncryptedLocalInstall.handoff(file)') < method.index('SideloadService.installStoreIPA')
assert 'if !cellular {' in method and 'await apps.realAppNetworkReady(vm)' in method
cellular = method[method.index('        if cellular {'):method.index('        do {\n            _ = try await Task.detached')]
assert '.installedAt = ' not in cellular
if '--source-only' in sys.argv:
    print('PASS source contract: no sign/upload, real build metadata, Wi-Fi preserved, cellular never claims installation')
    sys.exit()
stubs = r"""
import Foundation
func tr(_ en: String, _ ar: String) -> String { en }
enum EncryptedIPAError: Error { case noInfo }
enum SideloadError: Error { case message(String) }
enum Fixture {
    static var info: [String:Any] = ["CFBundleIdentifier":"example.owned", "CFBundleVersion":"1042",
        "CFBundleShortVersionString":"1.0", "CFBundleDisplayName":"Owned & App"]
    static var multiple = false
    static var oversized = false
    static let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
}
struct ZipReader {
    struct Entry { let name: String; let uncompressedSize: UInt64 }
    init(data: Data) throws {}
    var entries: [Entry] {
        let n: UInt64 = Fixture.oversized ? 3*1024*1024 : 1024
        var out = [Entry(name:"Payload/Owned.app/Info.plist",uncompressedSize:n),
                   Entry(name:"iTunesMetadata.plist",uncompressedSize:64),
                   Entry(name:"Payload/Owned.app/SC_Info/Owned.sinf",uncompressedSize:64)]
        if Fixture.multiple { out.append(Entry(name:"Payload/Other.app/Info.plist",uncompressedSize:64)) }
        return out
    }
    func read(_ entry: Entry, length: UInt64) throws -> Data {
        precondition(entry.name.hasSuffix("/Info.plist"), "private metadata/SINF must not be read for manifest")
        return try PropertyListSerialization.data(fromPropertyList:Fixture.info, format:.xml, options:0)
    }
}
final class LocalOTAServer: @unchecked Sendable {
    static var all: [LocalOTAServer] = []
    static var failStart = false
    static var requested = true
    let token = "0123456789abcdef0123456789abcdef"
    var stopped = false
    var onStop: (@Sendable () -> Void)?
    init(file: URL) throws { precondition(file == Fixture.file); Self.all.append(self) }
    func start() async throws -> UInt16 {
        if Self.failStart { throw URLError(.cannotConnectToHost) }
        return 34567
    }
    func stop() { if !stopped { stopped = true; onStop?() } }
    func awaitFirstRequest(timeout: TimeInterval) async -> Bool {
        for _ in 0..<10 { await Task.yield() }
        return Self.requested
    }
}
@MainActor final class UIApplication {
    static let shared = UIApplication()
    var opens = 0
    var canOpen = true
    var backgrounds = 0
    func beginBackgroundTask(withName: String, expirationHandler: @escaping () -> Void) -> Int { backgrounds += 1; return backgrounds }
    func open(_ url: URL) async -> Bool { opens += 1; return canOpen }
}
final class OTABackgroundBox: @unchecked Sendable {
    static var ended = 0
    init(_ id: Int) {}
    func end() { Self.ended += 1 }
}
enum CertificateOTA { static let localManifestEndpoint: URL? = URL(string:"https://manifest.example/local") }
enum LocalOTAManifest {
    static var reachable = true
    static var metadata: [String] = []
    static func url(base: URL, port: UInt16, token: String, bundleID: String, version: String, title: String, bytes: Int64) -> URL? {
        metadata = [bundleID,version,title]; return base
    }
    static func preflight(_ url: URL, port: UInt16) async -> Bool { reachable }
}
enum OTAInstallLink { static func make(manifestURL: URL) throws -> URL { URL(string:"itms-services://?action=download-manifest")! } }
enum WiFiPathState { case unknown, wifi, notWifi }
@MainActor final class WiFiPathMonitor {
    static let shared = WiFiPathMonitor()
    var state = WiFiPathState.notWifi
    func resolve() async -> WiFiPathState { await Task.yield(); return state }
}
@MainActor final class AppsStore {
    static let shared = AppsStore()
    var busy: String?
    var error: String?
    var ready = true
    var gates = 0
    func realAppNetworkReady(_ vm: AppViewModel?) async -> Bool {
        gates += 1
        return ready && WiFiPathMonitor.shared.state == .wifi
    }
    static func friendly(_ error: Error) -> String { error.localizedDescription }
}
struct AppViewModel {}
enum L {
    static var isArabic = false
    static func t(_ key: String) -> String { key }
    static func f(_ key: String, _ value: String) -> String { key + value }
}
enum InstallErrorText { static func sanitize(_ value: String, arabic: Bool) -> String { value } }
enum EncryptedText { static func t(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String { en } }
enum SideloadService {
    static var calls = 0
    static func installStoreIPA(ipaPath: String, progress: @escaping (Double,String) -> Void) throws -> [String:Any] {
        calls += 1; return ["installed":true]
    }
}
struct EncryptedIPAEntry { var id = UUID(); var name = "Owned"; var installedAt: Date? }
@MainActor final class EncryptedAppsStore {
    static var shared = EncryptedAppsStore()
    var entries: [EncryptedIPAEntry] = []
    var busy: String?
    var progress: Double = 0
    var installingID: UUID?
    var error: String?
    var toast: String?
    var saves = 0
    static func ipaURL(_ id: UUID) -> URL { Fixture.file }
    func save() { saves += 1 }
"""
tests = r"""
@main struct Tests {
 @MainActor static func main() async throws {
    let original = Data("UNTOUCHED APPLE SIGNATURE / SINF / private purchaser@example.invalid".utf8)
    try original.write(to:Fixture.file)
    defer { try? FileManager.default.removeItem(at:Fixture.file); LocalOTAServer.all.forEach { $0.stop() } }
    let identity = try EncryptedLocalInstall.identity(in:Fixture.file)
    precondition(identity.version == "1042")
    for mode in ["multiple","oversized","missingVersion"] {
        Fixture.multiple = mode == "multiple"; Fixture.oversized = mode == "oversized"
        if mode == "missingVersion" { Fixture.info.removeValue(forKey:"CFBundleVersion") }
        do { _ = try EncryptedLocalInstall.identity(in:Fixture.file); fatalError("invalid metadata accepted") } catch {}
        Fixture.multiple = false; Fixture.oversized = false; Fixture.info["CFBundleVersion"] = "1042"
    }
    for mode in ["start","manifest","open","noRequest","success"] {
        LocalOTAServer.failStart = mode == "start"
        LocalOTAManifest.reachable = mode != "manifest"
        UIApplication.shared.canOpen = mode != "open"
        LocalOTAServer.requested = mode != "noRequest"
        do { try await EncryptedLocalInstall.handoff(Fixture.file); precondition(mode == "success") }
        catch { precondition(mode != "success") }
        precondition(LocalOTAServer.all.last!.stopped == (mode != "success"))
        precondition((try! Data(contentsOf:Fixture.file)) == original)
    }
    precondition(LocalOTAManifest.metadata == ["example.owned","1042","Owned & App"])
    for state in [WiFiPathState.notWifi, .wifi, .unknown] {
        WiFiPathMonitor.shared.state = state
        let h = EncryptedAppsStore(); EncryptedAppsStore.shared = h
        let app = EncryptedIPAEntry(); h.entries = [app]
        let nativeBefore = SideloadService.calls; let gateBefore = AppsStore.shared.gates
        await h.install(app,vm:nil)
        precondition(h.busy == nil && h.installingID == nil && AppsStore.shared.busy == nil)
        if state == .wifi {
            precondition(SideloadService.calls == nativeBefore+1 && h.entries[0].installedAt != nil && h.saves == 1)
        } else {
            precondition(SideloadService.calls == nativeBefore && h.entries[0].installedAt == nil && h.saves == 0)
        }
        if state == .notWifi {
            precondition(AppsStore.shared.gates == gateBefore && h.toast!.contains("started receiving"))
        } else { precondition(AppsStore.shared.gates == gateBefore+1) }
    }
    WiFiPathMonitor.shared.state = .notWifi
    let h = EncryptedAppsStore(); EncryptedAppsStore.shared = h
    let app = EncryptedIPAEntry(); h.entries = [app]
    let before = LocalOTAServer.all.count
    async let one: () = h.install(app,vm:nil)
    async let two: () = h.install(app,vm:nil)
    _ = await (one,two)
    precondition(LocalOTAServer.all.count == before+1, "double tap started two handoffs")
    precondition((try! Data(contentsOf:Fixture.file)) == original)
    precondition(OTABackgroundBox.ended >= 4)
    print("PASS actual cellular helper/router: original bytes retained, private metadata not read, correct build version, no upload/sign, bounded failures/cleanup, first GET only, unchanged Wi-Fi tunnel, unknown fails closed, no fake installed flag, double tap serialized")
 }
}
"""
with tempfile.TemporaryDirectory(prefix='encrypted-cellular-') as d:
    path = Path(d)/'main.swift'
    path.write_text(stubs + method + '\n}\n' + helper.replace('import UIKit','') + tests)
    subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(path),'-o',str(Path(d)/'tests')],check=True)
    subprocess.run([str(Path(d)/'tests')],check=True,timeout=30)
