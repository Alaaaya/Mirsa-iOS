#!/usr/bin/env python3
"""WEB operator only. Serialize and prepare the inert CI account, never real users.
Run before dispatch, with NO active/queued run in this repository. Does not alter
auth, quota function/limits, labels, reviews, capabilities, or historical usage.
The workflow concurrency group separately serializes future cross-branch runs.
"""
import fcntl
import json
import os
from pathlib import Path
import subprocess

REPO = 'Alaaaya/Mirsa-iOS'
ROOT = Path('/home/kit/runtime-staging25')
SUBJECT = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
STATUSES = ('queued', 'in_progress', 'waiting', 'pending', 'requested')
SQL = """
begin;
DO $$begin
 if current_setting('data_directory') <> '/home/kit/runtime-staging25/pgdata'
 then raise exception 'Not isolated staging'; end if;
end$$;
select pg_advisory_xact_lock(hashtextextended('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',812589));
select json_build_object('phase','before','requests',requests,'issues',issues)
from public.mirsa_runtime_usage
where user_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
and day=(clock_timestamp() at time zone 'UTC')::date;
delete from public.mirsa_runtime_usage
where user_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
and day=(clock_timestamp() at time zone 'UTC')::date;
commit;
"""

def active_runs(call):
    found = []
    for status in STATUSES:
        raw = call(['gh', 'api', '--paginate',
            f'repos/{REPO}/actions/runs?status={status}&per_page=100',
            '--jq', '.workflow_runs[] | {id,status}'])
        for line in raw.splitlines():
            run = json.loads(line)
            if run['status'] != 'completed':
                found.append({'id': run['id'], 'status': run['status']})
    return found

def prepare(call):
    active = active_runs(call)
    if active:
        raise RuntimeError('Refusing synthetic fixture reset while CI is active: ' + json.dumps(active))
    directory = call(['/usr/bin/psql', '-XAtq', '-U', 'kit', '-h', str(ROOT/'socket'),
        '-p', '33077', '-d', 'postgres', '-c', 'show data_directory;']).strip()
    if directory != str(ROOT/'pgdata'):
        raise RuntimeError('Not isolated staging; no mutation performed')
    # Close the operator preflight window immediately before the transaction.
    if active_runs(call):
        raise RuntimeError('CI started during preflight; no mutation performed')
    return call(['/usr/bin/psql', '-XAtq', '-U', 'kit', '-h', str(ROOT/'socket'),
        '-p', '33077', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], input=SQL)

def main():
    if not (ROOT/'pgdata').is_dir():
        raise SystemExit('WEB isolated operator database required; never run in Actions or production')
    os.environ['GH_TOKEN'] = Path('/home/kit/.gh_token').read_text().strip()
    def call(args, **kwargs):
        return subprocess.check_output(args, text=True, **kwargs)
    with open('/home/kit/native-refresh-private26/synthetic-ci-dispatch27.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        print(prepare(call))
        print('Only current-day inert synthetic account allowance prepared; security limits unchanged.')

if __name__ == '__main__':
    main()
