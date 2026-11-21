#!/bin/bash
# Runs on each host: who am I, what am I running, and is it safe to work on?
set -euo pipefail
. /etc/os-release
free_mb=$(df -Pm / | awk 'NR==2 {print $4}')
health=$(python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=3).status)" 2>/dev/null || echo down)
echo "os=$ID $VERSION_ID  disk_free=${free_mb}MB  app=$health"
[ "$free_mb" -gt 500 ] || { echo "not enough free disk"; exit 1; }
[ "$health" = 200 ] || { echo "revenue API is not healthy"; exit 1; }
