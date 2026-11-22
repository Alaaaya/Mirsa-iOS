#!/usr/bin/env python3
"""Compile production VPN routing/retry methods with an offline UIApplication seam.

This is model/integration evidence, NOT a real iOS URL-dispatch or VPN test.
Run on Linux Swift or macOS; swiftc must be on PATH.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
store = (root / "ios-app/Apps/AppsStore.swift").read_text()
source = store[store.index("    private final class VPNRetrySource"):
               store.index("    static func openWiFiSettings")]
# Exercise the actual methods, only exposing private fixture state in this harness.
source = source.replace("private ", "")
stubs = r"""
import Foundation

func tr5(_ en: String, _ ar: String, de: String, ckb: String, kmr: String) -> String { en }
final class AppViewModel {}
@MainActor final class UIApplication {
    static let shared = UIApplication()
    var installed: Set<String> = []
    var opened: [URL] = []
    var failOpen = false
    func canOpenURL(_ url: URL) -> Bool { installed.contains(url.scheme!) }
    func open(_ url: URL, options: [String: String] = [:], completionHandler: ((Bool) -> Void)? = nil) {
        opened.append(url)
        completionHandler?(!failOpen)
    }
}
@MainActor final class AppsStore {
    static let shared = AppsStore()
    static var isSetupMode = false
    var ready = true
    var probes = 0
    var busy: String?
    var error: String?
    var errorOffersLocalDevVPN = false
    func networkReady(_ vm: AppViewModel) -> Bool { probes += 1; return ready }
"""
tests = r"""
@main struct Run {
    @MainActor static func main() async throws {
        let store = AppsStore.shared
        let app = UIApplication.shared
        let vm = AppViewModel()
        app.installed = ["localdevvpn", "mirsa-container", "mirsa"]
        AppsStore.openLocalDevVPN()
        precondition(app.opened.last!.absoluteString == "localdevvpn://enable?scheme=mirsa-container")
        // LocalDevVPN sends scheme:// and iOS activation reaches the existing
        // scene-active resume hook. Exercise that method, not a reimplementation.
        var retries = 0
        store.vpnRetry = { retries += 1 }
        async let one: Void = store.resumeAfterLocalDevVPN(vm: vm)
        async let two: Void = store.resumeAfterLocalDevVPN(vm: vm)
        _ = await (one, two)
        precondition(retries == 1 && store.vpnRetry == nil && !store.awaitingVPNReturn)
        await store.resumeAfterLocalDevVPN(vm: vm)
        precondition(retries == 1)
        AppsStore.isSetupMode = true
        AppsStore.openLocalDevVPN()
        precondition(app.opened.last!.absoluteString == "localdevvpn://enable?scheme=mirsa-container")
        app.installed.remove("mirsa-container")
        AppsStore.openLocalDevVPN()
        precondition(app.opened.last!.absoluteString == "localdevvpn://enable?scheme=mirsa")
        AppsStore.isSetupMode = false
        // Main remains unambiguous even if the OS query would return false.
        AppsStore.openLocalDevVPN()
        precondition(app.opened.last!.absoluteString == "localdevvpn://enable?scheme=mirsa-container")
        app.installed.remove("localdevvpn")
        AppsStore.openLocalDevVPN()
        precondition(app.opened.last!.host == "apps.apple.com")
        app.installed.insert("localdevvpn")

        // The real production retry copy outlives the updater's extraction.
        let original = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let originalApp = original.appendingPathComponent("Mirsa.app")
        try FileManager.default.createDirectory(at: originalApp, withIntermediateDirectories: true)
        try Data("verified-build".utf8).write(to: originalApp.appendingPathComponent("receipt"))
        var retained: AppsStore.VPNRetrySource? = try .init(source: originalApp)
        let retainedDirectory = retained!.directory
        try FileManager.default.removeItem(at: original)
        store.vpnRetry = { [copy = retained!] in
            let data = try! Data(contentsOf: copy.app.appendingPathComponent("receipt"))
            precondition(String(decoding: data, as: UTF8.self) == "verified-build")
            retries += 1
        }
        retained = nil
        store.ready = false
        store.probes = 0
        AppsStore.openLocalDevVPN()
        await store.resumeAfterLocalDevVPN(vm: vm)
        precondition(store.probes == 12 && store.errorOffersLocalDevVPN)
        precondition(retries == 1 && store.vpnRetry != nil)
        precondition(FileManager.default.fileExists(atPath: retainedDirectory.path))
        store.ready = true
        AppsStore.openLocalDevVPN()
        await store.resumeAfterLocalDevVPN(vm: vm)
        precondition(retries == 2 && store.error == nil && store.vpnRetry == nil)
        precondition(!FileManager.default.fileExists(atPath: retainedDirectory.path))
        print("PASS compiled production VPN methods: main/Setup routing, store fallback, single resume, bounded wait, retained update retry and cleanup")
    }
}
"""
with tempfile.TemporaryDirectory() as tmp:
    main = Path(tmp) / "Harness.swift"
    main.write_text(stubs + source + "\n}\n" + tests)
    binary = Path(tmp) / "routing"
    subprocess.run(["swiftc", str(root / "ios-app/Apps/LocalDevVPNRoute.swift"),
                    str(main), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
