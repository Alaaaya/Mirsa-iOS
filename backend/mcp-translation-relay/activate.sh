#!/bin/sh
set -eu
ROOT=${MIRSA_RELAY_ROOT:-/home/kit/mirsa-mcp-events22}
SESSION=mirsa-translation-relay25
# Serialize activation, never stop/restart the unchanged parent drainer.
exec 9>"$ROOT/translation25/activate.lock"
flock -w 10 9
tmux has-session -t "$SESSION" 2>/dev/null || tmux new-session -d -s "$SESSION" "$ROOT/translation25/start.sh"
# Bound readiness retries. Never redirect live traffic before the new ingress is healthy.
curl --fail --silent --retry 6 --retry-connrefused --retry-delay 1 --max-time 2 http://127.0.0.1:54173/healthz >/dev/null
for chain in PREROUTING OUTPUT; do
 sudo -n iptables -t nat -C "$chain" -p tcp --dport 45829 -m addrtype --dst-type LOCAL -m comment --comment mirsa-translation25 -j REDIRECT --to-ports 54173 2>/dev/null ||
 sudo -n iptables -t nat -A "$chain" -p tcp --dport 45829 -m addrtype --dst-type LOCAL -m comment --comment mirsa-translation25 -j REDIRECT --to-ports 54173
done
touch "$ROOT/translation25/enabled"
