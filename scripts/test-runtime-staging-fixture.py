#!/usr/bin/env python3
import base64
import importlib.util
import json
import unittest
from pathlib import Path
spec = importlib.util.spec_from_file_location("fixture", Path(__file__).with_name("check-runtime-staging-fixture.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class FixtureTests(unittest.TestCase):
    def token(self, **updates):
        claims = dict(iss="urn:mirsa:runtime-staging25", aud="mirsa-runtime-staging25",
            sub="eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee", scope="runtime:bootstrap", iat=10000, exp=13600)
        claims.update(updates)
        data = base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip("=")
        return "header." + data + ".signature"
    def test_fresh_one_hour_fixture(self):
        self.assertEqual(module.validate_budget(self.token(), 10030), 3570)
    def test_stale_fixture_fails_before_build(self):
        for now in (11000, 13600, 14000):
            with self.assertRaises(ValueError):
                module.validate_budget(self.token(), now)
    def test_lifetime_not_extended(self):
        for claims in (dict(exp=17200), dict(iat=10100), dict(exp=True), dict(exp="13600")):
            with self.assertRaises(ValueError):
                module.validate_budget(self.token(**claims), 10000)
    def test_wrong_scope_not_accepted(self):
        for key in ("iss", "aud", "sub", "scope"):
            with self.assertRaises(ValueError):
                module.validate_budget(self.token(**{key:"wrong"}), 10000)
    def test_malformed_does_not_echo_secret(self):
        secret = "DO_NOT_ECHO_PRIVATE_CREDENTIAL"
        for token in (secret, "header." + secret + ".signature"):
            with self.assertRaises(ValueError) as error:
                module.validate_budget(token, 10000)
            self.assertNotIn(secret, str(error.exception))

if __name__ == "__main__":
    unittest.main()
