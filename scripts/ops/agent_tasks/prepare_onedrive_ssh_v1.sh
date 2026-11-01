#!/bin/bash
# Prepare a private SSH-launched OAuth helper and return public SSH identity only.
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
import importlib.util, ipaddress, json, os, pathlib, re, subprocess, tempfile, time

def output(args):
    p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       universal_newlines=True, timeout=20)
    if p.returncode:
        raise SystemExit('read-only SSH identity probe failed')
    return p.stdout

settings = output(['/usr/sbin/sshd','-T'])
data = {}
for line in settings.splitlines():
    key, _, value = line.partition(' ')
    if key in ('port','permitrootlogin','passwordauthentication','pubkeyauthentication'):
        data[key] = value
fingerprint = output(['ssh-keygen','-l','-E','sha256','-f','/etc/ssh/ssh_host_ed25519_key.pub']).split()[1]
if not re.fullmatch(r'SHA256:[A-Za-z0-9+/]+', fingerprint):
    raise SystemExit('unexpected host fingerprint')
route = output(['ip','-4','route','get','1.1.1.1']).split()
origin = route[route.index('src')+1] if 'src' in route else None
if origin and not ipaddress.ip_address(origin).is_global:
    origin = None
spec = importlib.util.spec_from_file_location('auth','/usr/local/lib/xyptdq-backup/authorize_ssh.py')
auth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auth)
with tempfile.TemporaryDirectory(prefix='oauth-startup.',dir='/var/lib/xyptdq-backup') as directory:
    root = pathlib.Path(directory)
    with open(str(root/'response'),'w') as stdout, open(str(root/'log'),'w') as stderr:
        p = subprocess.Popen(['/usr/local/bin/rclone','--config',str(root/'probe.conf'),
                              'config','create','onedrive','onedrive',
                              'config_is_local','true','config_auth_no_browser','true','--non-interactive'],
                             stdin=subprocess.DEVNULL,stdout=stdout,stderr=stderr)
        found = False
        try:
            for _ in range(40):
                if auth.find_login_url((root/'log').read_text(errors='replace')):
                    found = True
                    break
                if p.poll() is not None:
                    break
                time.sleep(0.25)
            if not found:
                raise SystemExit('private OAuth startup self-test failed')
        finally:
            if p.poll() is None:
                p.terminate()
                try:
                    p.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    p.kill()
                    p.wait()
result = {'task':'prepare_onedrive_ssh_v1', 'status':'PASS',
          'helper_installed':True, 'listener_exposed_publicly':False,
          'browser_authorization_started':False,
          'private_oauth_startup_selftest_verified':True,
          'ssh_host_ed25519_sha256':fingerprint, 'ssh_settings':data,
          'server_public_interface_ipv4':origin,
          'configuration_contents_published':False,
          'remote_snapshot_created':False, 'daily_timer_enabled':False}
with open(os.environ['XYPTDQ_AGENT_RESULT_FILE'],'w') as f:
    json.dump(result,f,indent=2,sort_keys=True)
PY
