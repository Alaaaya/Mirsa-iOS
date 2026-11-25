#!/usr/bin/env python3
"""Operator-only isolated fixture setup. Never called by the public service.
Repeated CI shares a signed synthetic subject, so a fresh JWT alone does not
refresh that disposable account's daily allowance. Keep real quota checks intact.
"""
import json
import subprocess
from pathlib import Path

ROOT = Path('/home/kit/runtime-staging25')
SUBJECT = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'

def sql_for_fixture():
    return """begin;
DO $$ begin
 if current_setting('data_directory') <> '/home/kit/runtime-staging25/pgdata' then
  raise exception 'Not the isolated staging cluster';
 end if;
end $$;
select row_to_json(u) from public.mirsa_runtime_usage u
 where user_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee' and day=current_date for update;
update public.mirsa_runtime_usage set requests=0,chars=0,issues=0,minute_requests=0
 where user_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee' and day=current_date;
commit;
"""

def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-active-ci', required=True, action='store_true',
                        help='Operator verified no other CI currently uses this synthetic fixture')
    parser.parse_args()
    if ROOT.resolve() != ROOT or (ROOT / 'pgdata/PG_VERSION').read_text().strip() != '16':
        raise SystemExit('Isolated staging root required')
    args = ['/usr/bin/psql', '-XAt', '-h', str(ROOT / 'socket'), '-p', '33077',
            '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']
    result = subprocess.run(args, input=sql_for_fixture(), text=True, capture_output=True, check=True)
    before = [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]
    print(json.dumps(dict(stagingOnly=True, syntheticOnly=True, previousUsage=before,
                         productionModified=False, quotaLimitsModified=False)))

if __name__ == '__main__':
    main()
