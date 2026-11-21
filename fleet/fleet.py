#!/usr/bin/env python3
"""Runs maintenance jobs across the fleet over SSH, one batch at a time.

    fleet.py preflight              every host: reachable, disk, app health
    fleet.py <job> --batch N        patch | backup | rotate | agent, on batch N only
    fleet.py report                 the fleet report (step summary + fleet-report.json)

Batch 1 is the canary (one host per distro). The pipeline runs batch 1, then 2, 3 and 4, and a
failed host fails its step, so later batches never start: a bad change stops at the canary.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
import tomllib
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KEYS = ROOT / '.keys'
STATE = ROOT / 'dist' / 'state'
INV = tomllib.loads((ROOT / 'inventory' / 'fleet.toml').read_text())
HOSTS = INV['host']
VAULT = INV['vault']['ip']
SSH = ['ssh', '-i', str(KEYS / 'fleet'), '-o', f'UserKnownHostsFile={KEYS / "known_hosts"}',
       '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=5', '-o', 'BatchMode=yes']


def ssh(ip, command, stdin=None, check=True):
    r = subprocess.run(SSH + [f'ops@{ip}', command], input=stdin, capture_output=True, timeout=600)
    if check and r.returncode:
        lines = (r.stdout + r.stderr).decode(errors='replace').strip().splitlines()
        raise RuntimeError(lines[-1] if lines else f'ssh to {ip} failed')
    return r


def remote_script(host, script, *args):
    """Pipe a Bash script from the repo to the host and run it with sudo."""
    body = (ROOT / 'scripts' / script).read_bytes()
    r = ssh(host['ip'], 'sudo bash -s -- ' + ' '.join(args), stdin=body, check=False)
    out = (r.stdout + r.stderr).decode(errors='replace').strip().splitlines()
    return r.returncode == 0, out[-1] if out else ''


def save(job, host, ok, detail):
    STATE.mkdir(parents=True, exist_ok=True)
    (STATE / f'{job}-{host["name"]}.json').write_text(json.dumps({'ok': ok, 'detail': detail}))


# ------------------------------------------------------------------ jobs (one host each)

def job_preflight(h):
    return remote_script(h, 'preflight.sh')


def job_patch(h):
    return remote_script(h, 'patch.sh')


def job_backup(h):
    """Stream a tarball host -> runner -> vault, check both checksums match, then restore one file."""
    ts = time.strftime('%Y%m%dT%H%M%S')
    path = f'/backups/{h["name"]}/{ts}.tar.gz'
    tar = ssh(h['ip'], 'sudo tar -czf - -C / etc/revenue var/lib/revenue')
    sent = hashlib.sha256(tar.stdout).hexdigest()
    ssh(VAULT, f'mkdir -p /backups/{h["name"]} && cat > {path}', stdin=tar.stdout)
    stored = ssh(VAULT, f'sha256sum {path}').stdout.decode().split()[0]
    if stored != sent:
        return False, 'checksum mismatch on the vault'
    restored = ssh(VAULT, f'tar -xzOf {path} var/lib/revenue/ledger.csv | sha256sum').stdout.decode().split()[0]
    live = ssh(h['ip'], 'sudo sha256sum /var/lib/revenue/ledger.csv').stdout.decode().split()[0]
    if restored != live:
        return False, 'restore test: ledger.csv from the backup does not match the host'
    # keep the 7 newest backups per host
    ssh(VAULT, f'ls -1t /backups/{h["name"]}/*.tar.gz | tail -n +8 | xargs -r rm --')
    return True, f'{len(tar.stdout) // 1024} KB -> vault:{path}, sha256 {sent[:12]} matches, restore test ok'


def job_rotate(h):
    """Push the logrotate config from Git, prove it landed unchanged, then rotate and check."""
    conf = (ROOT / 'configs' / 'logrotate' / 'revenue').read_bytes()
    ssh(h['ip'], 'sudo tee /etc/logrotate.d/revenue >/dev/null && sudo chmod 644 /etc/logrotate.d/revenue', stdin=conf)
    live = ssh(h['ip'], 'sha256sum /etc/logrotate.d/revenue').stdout.decode().split()[0]
    if live != hashlib.sha256(conf).hexdigest():
        return False, 'config on the host differs from Git'
    return remote_script(h, 'rotate.sh')


def job_agent(h):
    env = dict(l.split('=', 1) for l in (ROOT / 'configs' / 'agent.env').read_text().splitlines()
               if l and not l.startswith('#'))
    ver, sha = env['NODE_EXPORTER_VERSION'], env['NODE_EXPORTER_SHA256']
    tgz = ROOT / 'dist' / f'node_exporter-{ver}.linux-amd64.tar.gz'
    ssh(h['ip'], 'cat > /tmp/node_exporter.tar.gz', stdin=tgz.read_bytes())
    ok, detail = remote_script(h, 'agent.sh', ver, sha)
    if not ok:
        return ok, detail
    for _ in range(10):
        try:
            metrics = urllib.request.urlopen(f'http://{h["ip"]}:9100/metrics', timeout=3).read().decode()
            if f'version="{ver}"' in metrics and 'node_uname_info' in metrics:
                return True, detail + f', scraped :9100/metrics'
        except OSError:
            pass
        time.sleep(1)
    return False, 'node_exporter is not serving metrics on :9100'


JOBS = {'preflight': job_preflight, 'patch': job_patch, 'backup': job_backup,
        'rotate': job_rotate, 'agent': job_agent}


def run(job, batch):
    targets = [h for h in HOSTS if batch is None or h['batch'] == batch]
    label = 'canary' if batch == 1 else f'batch {batch}' if batch else 'all hosts'
    print(f'{job} · {label} · {", ".join(h["name"] for h in targets)}')

    def one(h):
        try:
            ok, detail = JOBS[job](h)
        except Exception as e:  # an unreachable host is a failed host
            ok, detail = False, str(e)
        save(job, h, ok, detail)
        return h, ok, detail

    with ThreadPoolExecutor(max_workers=len(targets)) as pool:
        results = list(pool.map(one, targets))
    for h, ok, detail in results:
        print(f'  {"OK  " if ok else "FAIL"} {h["name"]:<10} {detail}')
    failed = [h['name'] for h, ok, _ in results if not ok]
    if failed:
        stop = 'the canary failed: rollout stopped before the rest of the fleet' if batch == 1 \
            else 'rollout stopped: later batches will not start'
        print(f'FAIL  {job} on {", ".join(failed)}; {stop}')
        sys.exit(1)
    print(f'PASS  {job} on {len(results)} host(s)')


def report():
    jobs = ['preflight', 'patch', 'backup', 'rotate', 'agent']
    icon = {True: '✅', False: '❌', None: '·'}
    rows, done = [], {j: 0 for j in jobs}
    for h in HOSTS:
        cells = []
        for j in jobs:
            f = STATE / f'{j}-{h["name"]}.json'
            ok = json.loads(f.read_text())['ok'] if f.exists() else None
            done[j] += ok is True
            cells.append(icon[ok])
        rows.append(f'| {h["name"]} | {h["distro"]} | {h["batch"]} | ' + ' | '.join(cells) + ' |')
    lines = ['## Fleet report', '',
             '| Host | Distro | Batch | Preflight | Patch | Backup | Log rotation | Agent |',
             '|---|---|---|---|---|---|---|---|', *rows, '',
             ' · '.join(f'{j}: {done[j]}/{len(HOSTS)}' for j in jobs)]
    text = '\n'.join(lines)
    print(text)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as f:
            f.write(text + '\n')
    detail = {h['name']: {j: json.loads((STATE / f'{j}-{h["name"]}.json').read_text())
                          for j in jobs if (STATE / f'{j}-{h["name"]}.json').exists()} for h in HOSTS}
    (ROOT / 'fleet-report.json').write_text(json.dumps(detail, indent=2))


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('job', choices=[*JOBS, 'report'])
    p.add_argument('--batch', type=int)
    a = p.parse_args()
    report() if a.job == 'report' else run(a.job, a.batch)
