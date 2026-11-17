"""Keep Settings and the packaged app on the official primary icon only."""
import hashlib
import pathlib
import plistlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class PrimaryIconOnlyTests(unittest.TestCase):
    def test_no_picker_or_alternate_registration(self):
        self.assertNotIn('MirsaAppIconPickerSection', (ROOT / 'ios-app/Apps/AppsView.swift').read_text())
        self.assertFalse((ROOT / 'ios-app/Apps/MirsaAppIconPickerSection.swift').exists())
        self.assertNotIn('ALTERNATE_APPICON', (ROOT / 'project.yml').read_text())
        self.assertFalse(list((ROOT / 'ios-app/Assets.xcassets').glob('MirsaIcon*')))

    def test_official_primary_assets_unchanged(self):
        for p in (ROOT / 'ios-app/Assets.xcassets/AppIcon.appiconset').iterdir():
            original = subprocess.check_output(['git', '-C', str(ROOT), 'show', 'fd105ff:' + str(p.relative_to(ROOT))])
            self.assertEqual(hashlib.sha256(p.read_bytes()).digest(), hashlib.sha256(original).digest())

    def test_source_plist_has_no_alternates(self):
        def visit(value):
            if isinstance(value, dict):
                self.assertNotIn('CFBundleAlternateIcons', value)
                for child in value.values(): visit(child)
            elif isinstance(value, list):
                for child in value: visit(child)
        visit(plistlib.loads((ROOT / 'ios-app/Info.plist').read_bytes()))


if __name__ == '__main__':
    unittest.main()
