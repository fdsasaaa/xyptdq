#!/bin/bash
# Owner-provided public key only. No private key, password, or unrestricted shell grant.
set -euo pipefail
umask 077
[ "$(id -u)" -eq 0 ]
CONTROL="${XYPTDQ_AGENT_CONTROL_REPO:-/var/lib/xyptdq-agent/control.git}"
COMMIT="${XYPTDQ_AGENT_REQUIRED_COMMIT:?}"
TEMP=$(mktemp)
trap 'rm -f -- "$TEMP"' EXIT
git --git-dir="$CONTROL" show "$COMMIT:scripts/backup/limited_ssh.py" > "$TEMP"
install -o root -g root -m 0700 "$TEMP" /usr/local/lib/xyptdq-backup/limited_ssh.py
[ -s /usr/local/lib/xyptdq-backup/authorize_ssh.py ]
python3 - <<'PY'
import importlib.util, json, os, subprocess
settings = subprocess.check_output(['/usr/sbin/sshd','-T'], universal_newlines=True)
if 'pubkeyauthentication yes\n' not in settings:
    raise SystemExit('public key authentication is not enabled')
keyfile = next((l.partition(' ')[2] for l in settings.splitlines() if l.startswith('authorizedkeysfile ')), '')
if not {'.ssh/authorized_keys','/root/.ssh/authorized_keys','%h/.ssh/authorized_keys'}.intersection(keyfile.split()):
    raise SystemExit('nonstandard authorized keys location; private review required')
spec = importlib.util.spec_from_file_location('limited','/usr/local/lib/xyptdq-backup/limited_ssh.py')
limited = importlib.util.module_from_spec(spec)
spec.loader.exec_module(limited)
grant = limited.install(
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID65vJ4Tvq5+Ea1xELuwTjR2EhKl59QWB7PbMCo/msxr xyptdq-onedrive-once',
    'onedrive-20261101-01',
    'SHA256:6noVoCRkDD1Gh5lII16ZEWKtGH9Xz4JHtV/X0eJT8WI')
with open(os.environ['XYPTDQ_AGENT_RESULT_FILE'],'w') as f:
    json.dump({'task':'install_onedrive_auth_key_v1','status':'PASS',
               'temporary_key_installed':True,'grant':grant,
               'remote_snapshot_created':False,'daily_timer_enabled':False},f,indent=2,sort_keys=True)
PY
