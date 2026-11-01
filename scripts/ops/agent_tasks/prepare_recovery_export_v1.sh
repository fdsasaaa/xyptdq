#!/bin/bash
# Prepare a one-use, no-forwarding export only after a real cloud snapshot is verified.
set -euo pipefail
umask 077
[ "$(id -u)" -eq 0 ]
CONTROL="${XYPTDQ_AGENT_CONTROL_REPO:-/var/lib/xyptdq-agent/control.git}"
COMMIT="${XYPTDQ_AGENT_REQUIRED_COMMIT:?}"
TEMP=$(mktemp)
trap 'rm -f -- "$TEMP"' EXIT
git --git-dir="$CONTROL" show "$COMMIT:scripts/backup/limited_ssh.py" > "$TEMP"
install -o root -g root -m 0700 "$TEMP" /usr/local/lib/xyptdq-backup/limited_ssh.py
python3 - <<'PY'
import importlib.util,json,os,pathlib
root=pathlib.Path('/var/lib/xyptdq-backup')
out=pathlib.Path(os.environ['XYPTDQ_AGENT_RESULT_FILE'])
receipt=root/'first-cloud-backup-receipt.json'
verified=json.loads(receipt.read_text()) if receipt.is_file() else {}
if verified.get('status')!='PASS' or not verified.get('download_verified'):
    out.write_text(json.dumps({'task':'prepare_recovery_export_v1','status':'WAITING_VERIFIED_CLOUD_BACKUP',
                              'grant_installed':False,'daily_timer_enabled':False})+'\n')
    raise SystemExit(0)
spec=importlib.util.spec_from_file_location('limited','/usr/local/lib/xyptdq-backup/limited_ssh.py')
limited=importlib.util.module_from_spec(spec)
spec.loader.exec_module(limited)
grant=limited.install(
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID65vJ4Tvq5+Ea1xELuwTjR2EhKl59QWB7PbMCo/msxr xyptdq-onedrive-once',
    'onedrive-recovery-20261101-01',
    'SHA256:6noVoCRkDD1Gh5lII16ZEWKtGH9Xz4JHtV/X0eJT8WI',purpose='export_recovery')
out.write_text(json.dumps({'task':'prepare_recovery_export_v1','status':'PASS','grant':grant,
                          'grant_installed':True,'credential_contents_published':False,
                          'daily_timer_enabled':False},indent=2,sort_keys=True)+'\n')
PY
