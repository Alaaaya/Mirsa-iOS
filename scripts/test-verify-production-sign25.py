#!/usr/bin/env python3
"""Test verifier control flow with inert Mach-O fixtures, not Apple signature validity."""
import json
import pathlib
import plistlib
import runpy
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SCRIPT = pathlib.Path(__file__).with_name('verify-production-sign25.py')
TRANSLATE = '@loader_path/Frameworks/MirsaTranslate.dylib'
BACKGROUND = '@loader_path/Frameworks/MirsaBackground.dylib'

def binary(deps=()):
    commands = []
    for dep in deps:
        name = dep.encode() + b'\0'
        size = (24 + len(name) + 7) & ~7
        commands.append(struct.pack('<IIIIII', 12, size, 24, 0, 0, 0)
                        + name + bytes(size - 24 - len(name)))
    offset = 32 + sum(map(len, commands)) + 16
    commands.append(struct.pack('<IIII', 0x1d, 16, offset, 4))
    return (struct.pack('<IIIIIIII', 0xfeedfacf, 0x100000c, 0, 2,
                        len(commands), sum(map(len, commands)), 0, 0)
            + b''.join(commands) + b'test')

def archive(path, enabled):
    files = {
        'Info.plist': plistlib.dumps({'CFBundleExecutable': 'Fixture',
                                     'CFBundleIdentifier': 'com.example.ownedfixture'}),
        'Fixture': binary((TRANSLATE, BACKGROUND) if enabled else ()),
    }
    if enabled:
        files.update({
            'Frameworks/MirsaTranslate.dylib': binary(),
            'Frameworks/MirsaBackground.dylib': binary(),
            'Frameworks/MirsaTranslations.json': json.dumps({
                'translations': {'Settings': 'الإعدادات'}, 'revision': 1, 'substrings': {}, 'regex': [],
                'online': {'bundleId': 'com.example.ownedfixture',
                           'revision': 1, 'token': 'mrt1.inert-unit-fixture'}
            }).encode(),
        })
    with zipfile.ZipFile(path, 'w') as z:
        for name, content in files.items():
            entry = zipfile.ZipInfo('Payload/Fixture.app/' + name)
            entry.external_attr = 0o100755 << 16
            z.writestr(entry, content)

class VerifyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        archive(self.root / 'ON.ipa', True)
        archive(self.root / 'OFF.ipa', False)
        self.expected = {'bundleId': 'com.example.ownedfixture', 'revision': 1,
                         'translations': {'Settings': 'الإعدادات'}}
        self.write_expected()

    def write_expected(self):
        (self.root / 'ON-dictionary-proof.json').write_text(json.dumps(self.expected))

    def test_rejects_empty_partial_extra_wrong_scope_and_wrong_revision(self):
        for changes in ({'translations': {}},
                        {'translations': {'Settings': 'الإعدادات', 'Search': 'بحث'}},
                        {'translations': {'Settings': 'خطأ'}},
                        {'bundleId': 'other.app'}, {'revision': 2}):
            with self.subTest(changes=changes):
                original = dict(self.expected)
                self.expected.update(changes)
                self.write_expected()
                with self.assertRaises(AssertionError):
                    self.run_verifier()
                self.expected = original

    def run_verifier(self, codesign=None):
        with patch.object(sys, 'argv', [str(SCRIPT), str(self.root)]), \
             patch('subprocess.run', side_effect=codesign) as calls:
            runpy.run_path(str(SCRIPT), run_name='__main__')
        return calls

    def test_archive_permissions_do_not_shadow_toggle_and_strict_checks_remain(self):
        def check(args, **kwargs):
            self.assertTrue(kwargs['check'])
            self.assertEqual(args[0], 'codesign')
            self.assertIn('--verify', args)
            self.assertIn('--strict', args)
            self.assertEqual(pathlib.Path(args[-1]).stat().st_mode & 0o777, 0o755)
        calls = self.run_verifier(check)
        self.assertEqual(calls.call_count, 4)
        proof = json.loads((self.root / 'verification.json').read_text())
        self.assertEqual(set(proof), {'ON', 'OFF'})
        self.assertEqual(proof['ON']['loads'], [TRANSLATE, BACKGROUND])
        self.assertEqual(proof['OFF']['loads'], [])

    def test_on_must_include_translation(self):
        archive(self.root / 'ON.ipa', False)
        with self.assertRaises(AssertionError):
            self.run_verifier()

    def test_off_must_exclude_translation(self):
        archive(self.root / 'OFF.ipa', True)
        with self.assertRaises(AssertionError):
            self.run_verifier()

    def test_apple_verification_failure_is_not_ignored(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_verifier(subprocess.CalledProcessError(1, 'codesign'))
        self.assertFalse((self.root / 'verification.json').exists())

if __name__ == '__main__':
    unittest.main()
