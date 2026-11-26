#!/usr/bin/env python3
import importlib.util
import unittest
from pathlib import Path
spec = importlib.util.spec_from_file_location('quota', Path(__file__).with_name('prepare-runtime-staging-quota.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
class QuotaSetupTests(unittest.TestCase):
    def test_cluster_guard_precedes_mutation(self):
        sql = module.sql_for_fixture()
        self.assertLess(sql.index("current_setting('data_directory')"), sql.index('update '))
        self.assertIn('/home/kit/runtime-staging25/pgdata', sql)
    def test_only_synthetic_current_day_usage_can_change(self):
        update = module.sql_for_fixture().split('update ', 1)[1]
        self.assertIn("where user_id='" + module.SUBJECT + "' and day=(transaction_timestamp() at time zone 'UTC')::date", update)
        for forbidden in ('truncate', 'delete', 'alter ', 'mirsa_runtime_caps', 'auth.users'):
            self.assertNotIn(forbidden, update.lower())
    def test_reset_uses_same_utc_day_as_reservation_not_operator_timezone(self):
        sql = module.sql_for_fixture()
        self.assertNotIn('current_date', sql.lower())
        self.assertEqual(sql.count("day=(transaction_timestamp() at time zone 'UTC')::date"), 2)
    def test_snapshot_and_transaction(self):
        sql = module.sql_for_fixture()
        self.assertTrue(sql.startswith('begin;'))
        self.assertIn('for update;', sql)
        self.assertTrue(sql.endswith('commit;\n'))
if __name__ == '__main__':
    unittest.main()
