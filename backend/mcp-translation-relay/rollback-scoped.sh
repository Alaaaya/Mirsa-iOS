#!/bin/sh
set -eu
ROOT=${MIRSA_RELAY_ROOT:-/home/kit/mirsa-mcp-events22}
exec 9>"$ROOT/translation25/activate.lock"
flock -w 10 9
rm -f "$ROOT/translation25/enabled"
for chain in PREROUTING OUTPUT; do
 sudo -n iptables -t nat -D "$chain" -p tcp --dport 45829 -m addrtype --dst-type LOCAL -m comment --comment mirsa-translation25 -j REDIRECT --to-ports 54173 2>/dev/null || true
done
# Do not restore SQLite or alter any subscriptions/parent process.
tmux kill-session -t mirsa-translation-relay25 2>/dev/null || true
