#!/usr/bin/env python3
"""Check real public fixture certificates/CMS, not mocked Apple verification."""
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tests/Fixtures'


def openssl(*args):
    return subprocess.run(['openssl', *map(str, args)], check=True, capture_output=True).stdout


class IdentityTests(unittest.TestCase):
    def test_public_leaf_is_only_for_code_signing_and_matches_profile(self):
        pem = openssl('pkcs12', '-in', FIXTURES / 'LCSignSynthetic.p12',
                      '-passin', 'pass:mirsa-test', '-clcerts', '-nokeys')
        with tempfile.TemporaryDirectory() as temporary:
            leaf = Path(temporary) / 'leaf.pem'
            leaf.write_bytes(pem)
            text = openssl('x509', '-in', leaf, '-text', '-noout').decode()
            self.assertIn('X509v3 Key Usage: critical\n                Digital Signature\n', text)
            self.assertIn('X509v3 Extended Key Usage: critical\n                Code Signing\n', text)
            self.assertIn('X509v3 Basic Constraints: critical\n                CA:FALSE\n', text)
            der = openssl('x509', '-in', leaf, '-outform', 'DER')
        payload = openssl('cms', '-verify', '-inform', 'DER', '-in',
                          FIXTURES / 'LCSignSynthetic.mobileprovision', '-noverify')
        profile = plistlib.loads(payload)
        self.assertEqual(profile['DeveloperCertificates'], [der])
        self.assertEqual(profile['TeamIdentifier'], ['TEAM'])
        self.assertEqual(profile['Entitlements'], {
            'application-identifier': 'TEAM.com.test.app',
            'com.apple.developer.team-identifier': 'TEAM', 'get-task-allow': True})


if __name__ == '__main__':
    unittest.main()
