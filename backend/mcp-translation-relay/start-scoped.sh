#!/bin/sh
set -eu
umask 077
ROOT=${MIRSA_RELAY_ROOT:-/home/kit/mirsa-mcp-events22}
cd "$ROOT"
exec 8>translation25/server.lock
# Wait for the previous scoped ingress to release its lock during a controlled restart.
flock -w 5 8 || exit 1
set -a
. ./.env
set +a
export MIRSA_RELAY_BASE_MODULE="$ROOT/server.mjs"
export MIRSA_RELAY_INGRESS_ONLY=1
export DB_PATH="$ROOT/state.sqlite"
export PORT=54173
exec node translation25/extension.mjs >>translation25/server.log 2>&1
