#!/bin/bash
# Runs on each host, after the logrotate config from Git is in place: rotate now, then prove the
# app's new requests land in the fresh log (not in a rotated or deleted file).
set -euo pipefail
log=/var/log/revenue/app.log
size_before=$(stat -c %s "$log")
logrotate -f /etc/logrotate.d/revenue
ls /var/log/revenue/app.log.1.gz >/dev/null
size_after=$(stat -c %s "$log")
for i in 1 2 3; do
  python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=3)"
done
sleep 0.5
new_lines=$(grep -c 'GET /health' "$log" || true)
echo "app.log ${size_before}B -> ${size_after}B, archive app.log.1.gz, new requests in app.log: $new_lines"
[ "$new_lines" -ge 3 ] || { echo "the app is still writing to the rotated file: its logs are being lost"; exit 1; }
