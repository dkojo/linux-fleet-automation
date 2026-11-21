#!/bin/bash
# Runs on each host: install the node_exporter tarball the orchestrator copied to /tmp, verify its
# checksum, and run it as its own user. Re-running with the same version changes nothing.
set -euo pipefail
version="$1" sha="$2" tgz=/tmp/node_exporter.tar.gz
if pgrep -x node_exporter >/dev/null && /usr/local/bin/node_exporter --version 2>&1 | grep -q "version $version "; then
  echo "node_exporter $version already running: no change"; exit 0
fi
echo "$sha  $tgz" | sha256sum -c --quiet
tar -xzf "$tgz" -C /tmp
install -m 755 "/tmp/node_exporter-$version.linux-amd64/node_exporter" /usr/local/bin/node_exporter
id node_exporter >/dev/null 2>&1 || useradd -r -s /sbin/nologin node_exporter
pkill -x node_exporter || true
setsid su -s /bin/sh node_exporter -c 'exec /usr/local/bin/node_exporter --web.listen-address=:9100' </dev/null >/dev/null 2>&1 &
rm -rf "$tgz" "/tmp/node_exporter-$version.linux-amd64"
sleep 1
pgrep -x node_exporter >/dev/null
echo "node_exporter $version installed and running as node_exporter"
