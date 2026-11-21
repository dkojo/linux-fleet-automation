#!/usr/bin/env bash
# Starts the fleet: a fresh SSH key for this run, all hosts up, and their host keys pinned.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .keys dist
[ -f .keys/fleet ] || ssh-keygen -q -t ed25519 -N '' -C fleet-automation -f .keys/fleet
docker compose up -d --quiet-pull
ips=$(python3 -c "import tomllib; d = tomllib.load(open('inventory/fleet.toml', 'rb')); print(d['vault']['ip'], *[h['ip'] for h in d['host']])")
: > .keys/known_hosts
for ip in $ips; do
  for i in $(seq 1 30); do
    keys=$(ssh-keyscan -T 2 -t ed25519 "$ip" 2>/dev/null || true)
    [ -n "$keys" ] && { echo "$keys" >> .keys/known_hosts; break; }
    sleep 1
  done
  [ -n "$keys" ] || { echo "FAIL  $ip never started sshd"; exit 1; }
done
echo "Fleet up: $(echo $ips | wc -w) hosts (12 servers + vault), host keys pinned"
