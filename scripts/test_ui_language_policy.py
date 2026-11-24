import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("policy", Path(__file__).with_name("configure-ui-language-tests.py"))
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)

class LanguagePolicyTests(unittest.TestCase):
    def test_test_build_defaults_to_arabic(self):
        for requested in ["", "false"]:
            self.assertEqual(policy.language_mode("refs/heads/mirsa/wallpaper-load23", requested), "ar")
    def test_full_matrix_before_publication(self):
        for ref in ["refs/heads/main", "refs/tags/v3.0", "refs/tags/release-3.0"]:
            for requested in ["", "false", "true"]:
                self.assertEqual(policy.language_mode(ref, requested), "full")
    def test_manual_full_override(self):
        self.assertEqual(policy.language_mode("refs/heads/mirsa/wallpaper-load23", "true"), "full")
        with self.assertRaises(ValueError):
            policy.language_mode("refs/heads/test", "maybe")
    def test_runner_receives_mode_and_other_scheme_settings_survive(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "MirsaUI.xcscheme"
            path.write_text('<Scheme><BuildAction/><TestAction><Testables><TestableReference skipped="NO"/></Testables><EnvironmentVariables><EnvironmentVariable key="EXISTING" value="kept" isEnabled="YES"/></EnvironmentVariables></TestAction></Scheme>')
            for mode in ["ar", "full", "ar"]:
                policy.configure(path, mode)
                root = ET.parse(path).getroot()
                self.assertIsNotNone(root.find("BuildAction"))
                self.assertEqual(root.find("TestAction/Testables/TestableReference").get("skipped"), "NO")
                variables = root.findall("TestAction/EnvironmentVariables/EnvironmentVariable")
                ours = [v for v in variables if v.get("key") == "MIRSA_UI_LANGUAGE_MODE"]
                self.assertEqual(len(ours), 1)
                self.assertEqual(ours[0].get("value"), mode)
                self.assertEqual(ours[0].get("isEnabled"), "YES")
                self.assertEqual(next(v for v in variables if v.get("key") == "EXISTING").get("value"), "kept")

if __name__ == "__main__":
    unittest.main()
