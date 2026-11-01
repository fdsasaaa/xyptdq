#!/bin/bash
# Renew the owner's consumed authorization-only key without changing SSH settings or password.
set -euo pipefail
umask 077
[ "$(id -u)" -eq 0 ]
CONTROL="${XYPTDQ_AGENT_CONTROL_REPO:-/var/lib/xyptdq-agent/control.git}"
COMMIT="${XYPTDQ_AGENT_REQUIRED_COMMIT:?}"
TEMP=$(mktemp)
trap 'rm -f -- "$TEMP"' EXIT
git --git-dir="$CONTROL" show "$COMMIT:scripts/backup/authorize_ssh.py" > "$TEMP"
install -o root -g root -m 0700 "$TEMP" /usr/local/lib/xyptdq-backup/authorize_ssh.py
python3 - <<'PY'
import configparser, importlib.util, json, os, pathlib, subprocess
out = pathlib.Path(os.environ['XYPTDQ_AGENT_RESULT_FILE'])
root = pathlib.Path('/var/lib/xyptdq-backup')
c = configparser.ConfigParser(interpolation=None)
c.read('/etc/xyptdq-backup/rclone.conf')
if c.get('onedrive','token',fallback='') and c.get('onedrive','drive_id',fallback=''):
    out.write_text(json.dumps({'task':'renew_onedrive_auth_key_v1','status':'ALREADY_CONFIGURED_REQUIRES_CAPACITY_CHECK',
                              'new_key_grant_installed':False})+'\n')
    raise SystemExit(0)
ports = subprocess.run(['ss','-ltnH'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,
                       universal_newlines=True,timeout=10).stdout
if '127.0.0.1:53682' in ports:
    out.write_text(json.dumps({'task':'renew_onedrive_auth_key_v1','status':'EXISTING_AUTHORIZATION_LISTENER_ACTIVE',
                              'new_key_grant_installed':False})+'\n')
    raise SystemExit(0)
previous = root/'onedrive-auth-status.json'
prior_status = 'unknown'
if previous.is_file():
    prior_status = json.loads(previous.read_text()).get('status','unknown')
    if prior_status not in ('LOGIN_TIMED_OUT_RERUN_SSH_COMMAND','WAITING_BROWSER_LOGIN',
                            'RCLONE_CONFIGURATION_FAILED','SETUP_FAILED_REQUIRES_PRIVATE_REVIEW'):
        prior_status = 'other'
spec = importlib.util.spec_from_file_location('limited','/usr/local/lib/xyptdq-backup/limited_ssh.py')
limited = importlib.util.module_from_spec(spec)
spec.loader.exec_module(limited)
grant = limited.install(
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID65vJ4Tvq5+Ea1xELuwTjR2EhKl59QWB7PbMCo/msxr xyptdq-onedrive-once',
    'onedrive-20261101-02',
    'SHA256:6noVoCRkDD1Gh5lII16ZEWKtGH9Xz4JHtV/X0eJT8WI')
out.write_text(json.dumps({'task':'renew_onedrive_auth_key_v1','status':'PASS','grant':grant,
                          'new_key_grant_installed':True,'prior_authorization_status':prior_status,
                          'browser_authorization_started':False,'remote_snapshot_created':False,
                          'daily_timer_enabled':False},indent=2,sort_keys=True)+'\n')
PY
