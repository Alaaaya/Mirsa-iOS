#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('gate', Path(__file__).with_name('public-gate-test-harness.py'))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
class GateHarnessTests(unittest.TestCase):
    def test_actual_source(self):
        source = (Path(__file__).resolve().parents[2] / 'ios-app/Apps/StoreServerIdentity.swift').read_text()
        extracted = gate.extract_gate(source)
        self.assertIn(extracted.rstrip(), source)
        self.assertNotIn('extension', extracted)
    def test_true_is_not_replaced_with_false(self):
        source = 'enum MirsaStoreAvailability {\n    static let publicLoginEnabled = true\n}\n'
        self.assertEqual(gate.extract_gate(source), source)
    def test_fail_closed(self):
        valid = 'enum MirsaStoreAvailability {\n    static let publicLoginEnabled = false\n}\n'
        for source in ['', valid + valid, valid.replace('false', 'compute()'), valid.replace('\n}', '\n    static let extra = 1\n}')]:
            with self.subTest(source=source), self.assertRaises(ValueError):
                gate.extract_gate(source)
if __name__ == '__main__':
    unittest.main()
