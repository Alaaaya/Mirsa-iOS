#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
PG_BIN=${PG_BIN:-/usr/lib/postgresql/16/bin}
p=$(mktemp -d /tmp/mrt-fair-pg-XXXXXX)
port=$(python3 -c 'import socket;s=socket.socket();s.bind(("",0));print(s.getsockname()[1])')
trap '"$PG_BIN/pg_ctl" -D "$p/db" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$p"' EXIT
"$PG_BIN/initdb" -D "$p/db" -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$p/db" -o "-k $p -p $port -c listen_addresses=''" -l "$p/log" start >/dev/null
export PGHOST=$p PGPORT=$port PGDATABASE=postgres
psql -Xq -v ON_ERROR_STOP=1 <<'SQL'
create role anon;create role authenticated;create role service_role;create schema auth;create table auth.users(id uuid primary key);
SQL
psql -Xq -v ON_ERROR_STOP=1 -f schema.sql >/dev/null
psql -Xq -v ON_ERROR_STOP=1 -f staging-fair-budget27.sql
psql -Xq -v ON_ERROR_STOP=1 -f staging-fair-budget27.test.sql
MIRSA_FAIR_DISPOSABLE27=1 "${DENO_BIN:-deno}" test --allow-env --allow-run=/usr/bin/psql staging-fair-budget27.test.ts
echo 'PASS isolated staging all-user budgets, 20k canonical cache, auth, finite ceilings and races'
