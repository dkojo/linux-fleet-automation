#!/bin/bash
# Boots a fleet host without systemd: authorise the ops key, seed the revenue app's data and a
# month of logs, start the app as its own user, then run sshd in the foreground.
set -euo pipefail

install -d -m 700 -o ops -g ops /home/ops/.ssh
install -m 600 -o ops -g ops /run/keys/fleet.pub /home/ops/.ssh/authorized_keys

install -d -m 755 -o revenue -g revenue /var/log/revenue /var/lib/revenue
install -d -m 755 /etc/revenue
echo "REGION=${REGION:-accra}" > /etc/revenue/app.env

if [ ! -s /var/lib/revenue/ledger.csv ]; then
  python3 - <<'EOF'
import random, socket
random.seed(socket.gethostname())
with open('/var/lib/revenue/ledger.csv', 'w') as f:
    f.write('receipt,taxpayer,amount_ghs\n')
    for i in range(5000):
        f.write(f'R{i:06d},TIN{random.randint(10**9, 10**10 - 1)},{random.randint(50, 90000) / 100:.2f}\n')
    # about 2 MB of old request logs, waiting for log rotation
with open('/var/log/revenue/app.log', 'w') as f:
    for i in range(24000):
        f.write(f'2026-10-{1 + i % 28:02d} 03:{i % 60:02d}:00 INFO GET /receipts/{i} 200\n')
EOF
  chown revenue:revenue /var/lib/revenue/ledger.csv /var/log/revenue/app.log
fi

setsid su -s /bin/sh revenue -c 'exec python3 /opt/revenue/revenue_api.py' </dev/null >/dev/null 2>&1 &
exec /usr/sbin/sshd -D -e
