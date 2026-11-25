#!/usr/bin/env python3
"""Executed host policy tests plus source/asset contract checks, not device proof."""
from pathlib import Path
import hashlib, json, os, shutil, struct, subprocess, tempfile, unittest
root = Path(__file__).resolve().parent
repo = root.parent
source = (root / "BackgroundNotifications.m").read_text()

class BackgroundTests(unittest.TestCase):
    def test_native_policy(self):
        compiler = os.environ.get("CC") or shutil.which("clang") or shutil.which("cc") or shutil.which("clang-18")
        self.assertIsNotNone(compiler)
        with tempfile.TemporaryDirectory() as tmp:
            binary = str(Path(tmp) / "policy")
            subprocess.run([compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", str(root / "PolicyTests.c"), "-o", binary], check=True)
            subprocess.run([binary], check=True)

    def test_asset_exact_sources_and_macho(self):
        assets = repo / "ios-app/BackgroundNotificationAssets"
        provenance = json.loads((assets / "provenance.json").read_text())
        digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
        for name, expected in provenance["sources"].items():
            self.assertEqual(digest(root / name), expected, name)
        binary = assets / "MirsaBackground.dylib"
        self.assertEqual(digest(binary), provenance["dylibSHA256"])
        data = binary.read_bytes()
        self.assertEqual(struct.unpack_from("<II", data), (0xfeedfacf, 0x0100000c))
        self.assertIn(b"@rpath/MirsaBackground.dylib", data)
        self.assertIn(b"/System/Library/Frameworks/UserNotifications.framework", data)
        self.assertIn(b"/System/Library/Frameworks/CoreLocation.framework", data)

    def test_permission_and_privacy_contract(self):
        self.assertIn("if (!_policy.enabled || !_policy.consent) return;", source)
        self.assertIn("settings.authorizationStatus == UNAuthorizationStatusNotDetermined", source)
        self.assertIn("UNAuthorizationOptionAlert", source)
        self.assertNotIn("UNAuthorizationOptionSound", source)
        self.assertIn("kCLAuthorizationStatusAuthorizedAlways", source)
        self.assertIn("if (status == kCLAuthorizationStatusNotDetermined)", source)
        for forbidden in ("NSURLSession", "NSLog", "AVAudioRecorder", "startUpdatingLocation", "coordinate.", "setDelegate:"):
            self.assertNotIn(forbidden, source)
        body = source.split("didUpdateLocations:", 1)[1].split("- (void)locationManager:", 1)[0]
        self.assertIn("(void)locations", body)
        self.assertNotIn("locations.", body)

    def test_scoped_hooks_and_original_callbacks(self):
        self.assertIn("@selector(setApplicationIconBadgeNumber:)", source)
        self.assertIn("@selector(setBadgeCount:withCompletionHandler:)", source)
        self.assertIn("((void (*)(id, SEL, NSInteger))original)", source)
        self.assertIn("if (completion) completion(error)", source)
        self.assertNotIn("UNUserNotificationCenterDelegate", source)
        self.assertNotIn("didReceiveRemoteNotification", source)
        self.assertIn('content.body = @"في نشاط جديد بالتطبيق"', source)
        self.assertIn('requestWithIdentifier:@"MirsaBackgroundActivity"', source)

    def test_no_permission_when_off_and_legacy_default(self):
        options = (repo / "ios-app/Apps/PersonalProjectOptions.swift").read_text()
        self.assertIn("var backgroundNotifications = false", options)
        self.assertIn("var backgroundMethods: [BackgroundNotificationMethod] = []", options)
        for key in ("backgroundNotifications", "backgroundAudio", "backgroundLocation"):
            self.assertIn("var " + key + ": Bool? = nil", options)
        service = (repo / "ios-app/Apps/BackgroundNotifications.swift").read_text()
        self.assertIn("guard options.backgroundNotifications else { return }", service)
        self.assertIn("guard enabled else { return original }", service)
        self.assertIn("if methods.contains(.significantLocation)", service)

    def test_ui_placement_and_exact_copy(self):
        ui = (repo / "ios-app/Apps/PersonalProjectDetailView.swift").read_text()
        translation = ui.index('accessibilityIdentifier("project-sign-translate-ar")')
        background = ui.index('            backgroundNotificationsSettings', translation)
        strict = ui.index('toggle(personalText("Strict profile match"')
        self.assertLess(translation, background)
        self.assertLess(background, strict)
        self.assertIn("إشعارات بالخلفية", ui)
        self.assertIn("بتاكل بطارية، وبتوقف إذا سكّرت التطبيق من المهام", ui)
        self.assertIn("if draft.backgroundNotifications ?? false", ui)

    def test_audio_and_background_expiration(self):
        self.assertIn("AVAudioSessionCategoryOptionMixWithOthers", source)
        self.assertNotIn("AVAudioSessionCategoryOptionDuckOthers", source)
        self.assertIn("self->_policy.consent = YES", source)
        self.assertIn("_policy.audioStopped = YES; [self stopAudio]", source)
        self.assertIn("expirationHandler:", source)
        self.assertGreaterEqual(source.count("endBackgroundTask:task"), 2)

if __name__ == "__main__":
    unittest.main(verbosity=2)
