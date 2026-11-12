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
        self.assertEqual(VIEW.count("client.acquireFreeApp(app)"), 1)
        self.assertIn("client.acquireFreeApp(app)", action("acquire"))
        self.assertIn("guard app.price == 0", action("acquire"))
        self.assertIn("Button { acquire(app) }", VIEW)
        for name in ["search", "loadVersions", "download", "openChartApp"]:
            self.assertNotIn("acquireFreeApp", action(name))
            self.assertNotIn("acquire(app)", action(name))

    def test_acquire_never_downloads_and_positive_result_updates_ownership(self):
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
        self.assertNotIn("chosen[", action("acquire"))

    def test_engine_and_ui_argument_parity(self):
        base_ref = "2f15e577d949a539a1b3a60ed350a2d42e31e027"
        for path in ["ios-app/AppStore/StoreClient.swift", "ios-app/AppStore/StoreOnDeviceClient.swift",
                     "vendor/ApplePackage/Sources/ApplePackage/Commands/VersionFinder.swift",
                     "vendor/ApplePackage/Sources/ApplePackage/Commands/Download.swift"]:
            base = subprocess.check_output(["git", "show", base_ref + ":" + path], cwd=ROOT, text=True)
            self.assertEqual((ROOT / path).read_text(), base, path)
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
        self.assertEqual(request(current), request(base))

if __name__ == "__main__":
    unittest.main()
