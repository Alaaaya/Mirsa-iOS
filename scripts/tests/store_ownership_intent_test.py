#!/usr/bin/env python3
"""Offline source invariants supplement Swift request/evidence tests. No Apple traffic."""
import pathlib
import re
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
VIEW = (ROOT / "ios-app/Apps/AppStoreAccountView.swift").read_text()
FETCH = "vendor/ApplePackage/Sources/ApplePackage/Commands/StoreDownloadEndpoint+Fetch.swift"

def action(name):
    match = re.search(r"    private func " + name + r"\(", VIEW)
    assert match, name
    rest = VIEW[match.start():]
    return rest.split("\n    private func ", 1)[0]

class OwnershipIntent(unittest.TestCase):
    def test_acquisition_has_one_explicit_entry_point(self):
        self.assertEqual(VIEW.count("client.acquireFreeAppAndDownload(app, externalVersionID: version)"), 1)
        self.assertIn("client.acquireFreeAppAndDownload(app, externalVersionID: version)", action("acquire"))
        self.assertIn("guard app.price == 0", action("acquire"))
        self.assertIn("Button { acquire(app) }", VIEW)
        for name in ["search", "loadVersions", "download", "openChartApp"]:
            self.assertNotIn("acquireFreeApp", action(name))
            self.assertNotIn("acquire(app)", action(name))

    def test_explicit_get_downloads_atomically_and_updates_ownership(self):
        body = action("acquire")
        self.assertNotIn("downloadOwnedApp", body)
        self.assertNotIn("loadVersions", body)
        self.assertIn("ownership[app.id] = .owned", body)
        self.assertIn('t("Get", "احصل عليه"', VIEW)

    def test_known_missing_blocks_actions_until_explicit_get(self):
        self.assertIn("guard ownership[app.id] != .licenseRequired", action("loadVersions"))
        self.assertIn("guard canDownload(app)", action("download"))
        self.assertIn("(ownership[app.id] != .licenseRequired)", VIEW)
        self.assertIn("diagnostic.requiresLicense", action("recordOwnershipFailure"))
        self.assertNotIn("httpStatus == 403", action("recordOwnershipFailure"))
        self.assertIn("ownership = [:]", VIEW)

    def test_selected_version_preserved_by_separate_download(self):
        body = action("download")
        self.assertIn("let version = chosen[app.bundleID]", body)
        self.assertIn("externalVersionID: version", body)
        self.assertIn("let version = chosen[app.bundleID]", action("acquire"))
        self.assertIn("externalVersionID: version", action("acquire"))

    def test_engine_and_ui_argument_parity(self):
        base_ref = "2f15e577d949a539a1b3a60ed350a2d42e31e027"
        for path in ["ios-app/AppStore/StoreClient.swift", "ios-app/AppStore/StoreOnDeviceClient.swift",
                     "vendor/ApplePackage/Sources/ApplePackage/Commands/VersionFinder.swift",
                     "vendor/ApplePackage/Sources/ApplePackage/Commands/Download.swift"]:
            base = subprocess.check_output(["git", "show", base_ref + ":" + path], cwd=ROOT, text=True)
            current = (ROOT / path).read_text()
            if path.endswith("StoreClient.swift"):
                import sys
                sys.path.insert(0, str(ROOT / "scripts/appstore"))
                from commerce_lock_scope import legacy_reservations
                current = legacy_reservations(current)
                a = current.index('    /// Public fresh metadata')
                b = current.index('    func availableVersions(', a)
                current = current[:a] + current[b:]
            elif path.endswith("StoreOnDeviceClient.swift"):
                a = current.index('    func freeAppForRecovery(')
                b = current.index('    func availableVersions(', a)
                current = current[:a] + current[b:]
            if path.endswith("StoreClient.swift"):
                a = current.index('    /// One explicit free Get action')
                b = current.index('    /// Returns a local encrypted IPA', a)
                current = current[:a] + current[b:]
            elif path.endswith("StoreOnDeviceClient.swift"):
                a = current.index('    func acquireFreeAppAndDownload(')
                b = current.index('    func availableVersions(', a)
                current = current[:a] + current[b:]
            OLD = "        if let diagnostic = error as? StoreProductDiagnostic { return diagnostic }"
            NEW = '        if let diagnostic = error as? StoreProductDiagnostic {\n            if diagnostic.requiresReauthentication {\n                // Explicit owner policy: drop only the rejected Apple store session.\n                // Preserve stable machine identity, saved apps, signing accounts and all files.\n                do { try signOut() } catch { return MirsaStoreError.serviceUnavailable }\n            }\n            return diagnostic\n        }'
            current = current.replace(NEW, OLD)
            self.assertEqual(current, base, path)
        self.assertIn("client.availableVersions(app)", action("loadVersions"))
        self.assertIn("client.downloadOwnedApp(app, externalVersionID: version)", action("download"))
        self.assertIn("found.first(where: { $0.id == chart.id })", action("openChartApp"))
        self.assertIn("selected = app", action("openChartApp"))
        # Public catalogue storefront is not passed into authenticated commerce calls.
        for name in ["loadVersions", "download"]:
            self.assertNotIn("country:", action(name))
            self.assertNotIn("searchCountry", action(name))

    def test_request_parity_with_device_working_base(self):
        current = (ROOT / FETCH).read_text()
        base = subprocess.check_output(["git", "show", "2f15e577d949a539a1b3a60ed350a2d42e31e027:" + FETCH], cwd=ROOT, text=True)
        # Credential headers, guid, dsid, cookie handling, AMD and payload unchanged.
        def request(text):
            return text.split("    func makeRequest(", 1)[1].split("\n}\n", 1)[0]
        # Owner explicitly approved native ent/download. Legacy wire payload is unchanged.
        body = request(current).replace('        kbSync: String? = nil,\n', '')
        a = body.index('        if self == .entitlement {')
        b = body.index('        if !externalVersionID.isEmpty {', a)
        body = body[:a] + body[b:]
        body = body.replace('self == .entitlement ? "application/x-www-form-urlencoded; charset=utf-8" : "application/x-apple-plist"', '"application/x-apple-plist"')
        self.assertEqual(body, request(base))

if __name__ == "__main__":
    unittest.main()
