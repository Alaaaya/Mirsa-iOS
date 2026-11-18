"""Metadata gate regressions; the actual Swift comparator still runs in native CI."""
import contextlib
import io
import pathlib
import plistlib
import runpy
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]


class ReleaseUpgradeVersionTests(unittest.TestCase):
    def check_candidate(self, version="2.8", extension_version=None, build="6.90.1", mirsa_build="490"):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = pathlib.Path(tmp) / "Mirsa.ipa"
            info = {"CFBundleShortVersionString": version, "CFBundleVersion": build,
                    "MirsaBuild": mirsa_build}
            with zipfile.ZipFile(ipa, "w") as z:
                z.writestr("Payload/Mirsa.app/Info.plist", plistlib.dumps(info))
                ext = dict(info, CFBundleShortVersionString=extension_version or version)
                z.writestr("Payload/Mirsa.app/PlugIns/Widget.appex/Info.plist", plistlib.dumps(ext))

            # Metadata tests must not pretend to execute Swift on Linux.
            # Assert the real comparator invocations remain in the generated native script.
            def inspect_native(args, **kwargs):
                self.assertEqual(args[0], "swift")
                self.assertTrue(kwargs["check"])
                script = pathlib.Path(args[1]).read_text()
                self.assertIn('UpdaterMetadata.isNewer(remote: "' + build + '", installed:', script)
                self.assertIn('precondition(!UpdaterMetadata.isNewer(remote:', script)
                self.assertIn('installed: "6.1.1"', script)

            with mock.patch.object(sys, "argv", ["verify_release_upgrade.py", str(ipa)]), \
                 mock.patch("subprocess.run", side_effect=inspect_native) as native, \
                 contextlib.redirect_stdout(io.StringIO()):
                runpy.run_path(str(ROOT / "scripts/verify_release_upgrade.py"), run_name="__main__")
                native.assert_called_once()

    def test_accepts_release_28_and_keeps_native_comparator(self):
        self.check_candidate()

    def test_rejects_stale_27(self):
        with self.assertRaises(AssertionError):
            self.check_candidate(version="2.7")

    def test_rejects_future_unapproved_version(self):
        with self.assertRaises(AssertionError):
            self.check_candidate(version="2.9")

    def test_rejects_extension_version_mismatch(self):
        with self.assertRaises(AssertionError):
            self.check_candidate(extension_version="2.7")

    def test_rejects_nonadvancing_mirsa_build(self):
        with self.assertRaises(AssertionError):
            self.check_candidate(mirsa_build="401")


if __name__ == "__main__":
    unittest.main()
