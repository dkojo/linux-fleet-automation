#!/usr/bin/env bash
# Downloads the pinned node_exporter release once, and refuses it if the checksum differs from Git.
set -euo pipefail
cd "$(dirname "$0")/.."
. configs/agent.env
f="node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz"
mkdir -p dist
[ -f "dist/$f" ] || curl -fsSL -o "dist/$f" "https://github.com/prometheus/node_exporter/releases/download/v$NODE_EXPORTER_VERSION/$f"
echo "$NODE_EXPORTER_SHA256  dist/$f" | sha256sum -c
