#!/bin/bash
# Install backup tooling and create a private LOCAL recovery copy. No cloud auth or timer activation.
set -euo pipefail
umask 077
[ "$(id -u)" -eq 0 ]
COMMIT="${XYPTDQ_AGENT_REQUIRED_COMMIT:?}"
CONTROL="${XYPTDQ_AGENT_CONTROL_REPO:-/var/lib/xyptdq-agent/control.git}"
export DEBIAN_FRONTEND=noninteractive
if ! command -v restic >/dev/null || ! command -v rclone >/dev/null; then
  apt-get update -qq
  apt-get install -y --no-install-recommends restic rclone
fi
install -d -o root -g root -m 0700 /etc/xyptdq-backup /usr/local/lib/xyptdq-backup /var/lib/xyptdq-backup
for name in onedrive_backup.py install_timer.sh config.example.json; do
  tmp=$(mktemp)
  git --git-dir="$CONTROL" show "$COMMIT:scripts/backup/$name" > "$tmp"
  install -o root -g root -m 0700 "$tmp" "/usr/local/lib/xyptdq-backup/$name"
  rm -f "$tmp"
done
if [ ! -e /etc/xyptdq-backup/config.json ]; then
  install -o root -g root -m 0600 /usr/local/lib/xyptdq-backup/config.example.json /etc/xyptdq-backup/config.json
fi
python3 - <<'PY'
import importlib.util, json, os, pathlib, secrets
root = pathlib.Path('/etc/xyptdq-backup')
key = root / 'repository-password'
if not key.exists():
    fd = os.open(str(key), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as f:
        f.write(secrets.token_urlsafe(48) + '\n')
spec = importlib.util.spec_from_file_location('backup', '/usr/local/lib/xyptdq-backup/onedrive_backup.py')
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)
c = json.loads((root / 'config.json').read_text())
stage = b.build_stage(c)
b.verify_stage(stage)
result = {
    'task': 'prepare_onedrive_backup_v1', 'status': 'WAITING_MICROSOFT_AUTHORIZATION',
    'tools_installed': True, 'local_recovery_copy_created': True,
    'local_payload_bytes': sum(p.stat().st_size for p in stage.iterdir()),
    'local_integrity_verified': True, 'essential_cms_files_included': True,
    'remote_snapshot_created': False, 'daily_timer_enabled': False,
    'encryption_key_requires_offserver_escrow': True,
    'production_content_modified': False,
}
with open(os.environ['XYPTDQ_AGENT_RESULT_FILE'], 'w') as f:
    json.dump(result, f, indent=2, sort_keys=True)
PY
# Exercise installed Restic encryption and restore without any cloud account.
SELFTEST=$(mktemp -d /var/lib/xyptdq-backup/selftest.XXXXXX)
trap 'rm -rf -- "$SELFTEST"' EXIT
mkdir "$SELFTEST/source"
printf 'xyptdq-restic-roundtrip-v1\n' > "$SELFTEST/source/probe.txt"
restic --repo "$SELFTEST/repository" --password-file /etc/xyptdq-backup/repository-password init
restic --repo "$SELFTEST/repository" --password-file /etc/xyptdq-backup/repository-password backup --json --host xyptdq-selftest --tag xyptdq-selftest "$SELFTEST/source"
restic --repo "$SELFTEST/repository" --password-file /etc/xyptdq-backup/repository-password restore latest --target "$SELFTEST/restore"
cmp "$SELFTEST/source/probe.txt" "$SELFTEST/restore$SELFTEST/source/probe.txt"
restic --repo "$SELFTEST/repository" --password-file /etc/xyptdq-backup/repository-password check --read-data
python3 - <<'PY'
import json, os
p = os.environ['XYPTDQ_AGENT_RESULT_FILE']
with open(p) as f:
    result = json.load(f)
result['local_encrypted_roundtrip_verified'] = True
with open(p, 'w') as f:
    json.dump(result, f, indent=2, sort_keys=True)
PY
