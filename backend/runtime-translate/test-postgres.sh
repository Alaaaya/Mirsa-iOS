#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
PG_BIN="${PG_BIN:-/usr/lib/postgresql/16/bin}"
p=$(mktemp -d /tmp/mrt-pg-XXXXXX)
port=$(python3 -c 'import socket;s=socket.socket();s.bind(("",0));print(s.getsockname()[1]);s.close()')
trap '"$PG_BIN/pg_ctl" -D "$p/db" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$p"' EXIT
"$PG_BIN/initdb" -D "$p/db" -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$p/db" -o "-k $p -p $port -c listen_addresses=''" -l "$p/log" start >/dev/null
psql -h "$p" -p "$port" -d postgres -v ON_ERROR_STOP=1 <<'SQL'
create role anon; create role authenticated; create role service_role;
create schema auth; create table auth.users(id uuid primary key);
SQL
psql -h "$p" -p "$port" -d postgres -v ON_ERROR_STOP=1 -f schema.sql
psql -h "$p" -p "$port" -d postgres -v ON_ERROR_STOP=1 -f schema.test.sql
psql -h "$p" -p "$port" -d postgres -v ON_ERROR_STOP=1 -f queue.test.sql
psql -h "$p" -p "$port" -d postgres -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users values ('22222222-2222-4222-8222-222222222222');
insert into public.mirsa_runtime_caps(token_hash,user_id,bundle_id,revision,expires_at)
 values(repeat('d',64),'22222222-2222-4222-8222-222222222222','com.example.app',repeat('e',64),now()+interval '1 day');
SQL
for i in $(seq 1 30); do
 psql -h "$p" -p "$port" -d postgres -At -v ON_ERROR_STOP=1 -c "select public.mirsa_runtime_reserve(null,repeat('d',64),'com.example.app',repeat('e',64),'missing',1)" > "$p/result-$i" &
done
wait
count=$(cat "$p"/result-* | grep -c '^t$')
test "$count" = 10
echo "Concurrent durable quota passed, 10 of 30 requests reserved."
