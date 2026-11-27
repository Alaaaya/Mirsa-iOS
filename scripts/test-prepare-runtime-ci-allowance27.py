import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('allowance', Path(__file__).with_name('prepare-runtime-ci-allowance27.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class AllowanceTests(unittest.TestCase):
    def test_any_active_ci_refuses_without_sql(self):
        for status in m.STATUSES:
            calls = []
            def call(args, **kw):
                calls.append((args, kw))
                return json.dumps([{'workflow_runs': [{'id': 123, 'status': status}]}])
            with self.assertRaises(RuntimeError):
                m.prepare(call)
            self.assertTrue(all(c[0][0] == 'gh' for c in calls))

    def test_wrong_database_refuses_without_mutation(self):
        def call(args, **kw):
            if args[0] == 'gh':
                return '[{"workflow_runs":[]}]'
            self.assertNotIn('input', kw)
            return '/production/data'
        with self.assertRaises(RuntimeError):
            m.prepare(call)

    def test_race_start_refuses_without_mutation(self):
        calls = 0
        def call(args, **kw):
            nonlocal calls
            self.assertNotIn('input', kw)
            if args[0] != 'gh':
                return str(m.ROOT/'pgdata')
            calls += 1
            if calls > len(m.STATUSES):
                return '[{"workflow_runs":[{"id":124,"status":"in_progress"}]}]'
            return '[{"workflow_runs":[]}]'
        with self.assertRaises(RuntimeError):
            m.prepare(call)

    def test_reset_exact_inert_subject_current_day_only(self):
        mutations = []
        def call(args, **kw):
            if args[0] == 'gh':
                return '[{"workflow_runs":[]}]'
            if 'input' in kw:
                mutations.append(kw['input'])
                return 'prepared'
            return str(m.ROOT/'pgdata')
        self.assertEqual(m.prepare(call), 'prepared')
        self.assertEqual(mutations, [m.SQL])
        self.assertIn("current_setting('data_directory')", m.SQL)
        self.assertIn("day=(clock_timestamp() at time zone 'UTC')::date", m.SQL)
        self.assertNotIn('alter ', m.SQL.lower())
        self.assertNotIn('truncate ', m.SQL.lower())
        self.assertNotIn('mirsa_runtime_caps', m.SQL)

    def test_workflow_cross_branch_serialization(self):
        text = Path('.github/workflows/final-bundle25.yml').read_text()
        self.assertIn('group: mirsa-runtime-staging-synthetic-account27', text)
        self.assertIn('cancel-in-progress: false', text)
        group = text.split('concurrency:',1)[1].split('permissions:',1)[0]
        self.assertNotIn('github.ref', group)

if __name__ == '__main__':
    unittest.main()
