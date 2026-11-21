#!/bin/bash
# Runs on each host: apply every pending update with the distro's package manager, then prove
# nothing is left pending and the revenue API still answers.
set -euo pipefail
. /etc/os-release
case "$ID" in
  rocky|centos|rhel)
    before=$(dnf -q check-update --refresh 2>/dev/null | grep -cE '^[[:alnum:]_.+-]+\.[[:alnum:]_]+ ' || true)
    dnf -y -q --setopt=install_weak_deps=False upgrade >/dev/null
    after=$(dnf -q check-update 2>/dev/null | grep -cE '^[[:alnum:]_.+-]+\.[[:alnum:]_]+ ' || true)
    reboot=$( (dnf -q needs-restarting -r >/dev/null 2>&1 && echo no) || echo maybe)
    ;;
  ubuntu|debian)
    export DEBIAN_FRONTEND=noninteractive
    apt-get -qq update
    before=$(apt-get -s upgrade | grep -c '^Inst ' || true)
    apt-get -y -qq -o Dpkg::Options::=--force-confold upgrade >/dev/null
    after=$(apt-get -s upgrade | grep -c '^Inst ' || true)
    reboot=$([ -f /var/run/reboot-required ] && echo yes || echo no)
    ;;
  *) echo "unsupported distro: $ID"; exit 1 ;;
esac
health=$(python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=3).status)" 2>/dev/null || echo down)
echo "updated=$before pending=$after reboot_required=$reboot app=$health"
[ "$after" = 0 ] || { echo "updates still pending after patching"; exit 1; }
[ "$health" = 200 ] || { echo "revenue API down after patching"; exit 1; }
