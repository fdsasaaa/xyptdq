#!/bin/bash
# Drive rclone's documented non-interactive configuration protocol, keeping all
# configuration and OAuth state private. Never emit config contents to the bridge.
set -euo pipefail
umask 077
[ "$(id -u)" -eq 0 ]
python3 - <<'PY'
import configparser, json, os, pathlib, stat, subprocess

config = pathlib.Path('/etc/xyptdq-backup/rclone.conf')
private_state = pathlib.Path('/var/lib/xyptdq-backup/onedrive-setup.json')
result_path = pathlib.Path(os.environ['XYPTDQ_AGENT_RESULT_FILE'])
result = {'task':'start_onedrive_config_v1', 'remote_name':'onedrive',
          'configuration_contents_published':False, 'remote_snapshot_created':False,
          'daily_timer_enabled':False}

def finish(status, **fields):
    result.update(status=status, **fields)
    result_path.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')

def invoke(arguments):
    p = subprocess.run(['/usr/local/bin/rclone', '--config', str(config)] + arguments,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       universal_newlines=True, timeout=45)
    if p.returncode != 0:
        finish('CONFIG_COMMAND_FAILED', command_exit_code=p.returncode)
        raise SystemExit(1)
    try:
        question = json.loads(p.stdout)
    except ValueError:
        finish('CONFIG_RESPONSE_REQUIRES_PRIVATE_REVIEW')
        raise SystemExit(1)
    # The full provider response can contain sensitive state. Save only privately.
    private_state.write_text(json.dumps(question, indent=2) + '\n')
    private_state.chmod(0o600)
    return question

config.parent.mkdir(mode=0o700, exist_ok=True)
config.parent.chmod(0o700)
c = configparser.ConfigParser(interpolation=None)
if config.exists() or config.is_symlink():
    s = config.lstat()
    if not stat.S_ISREG(s.st_mode) or s.st_uid != 0 or s.st_mode & 0o077:
        finish('UNSAFE_EXISTING_CONFIGURATION')
        raise SystemExit(1)
    try:
        c.read(str(config))
    except configparser.Error:
        finish('EXISTING_CONFIGURATION_REQUIRES_PRIVATE_REVIEW')
        raise SystemExit(1)
if c.has_section('onedrive'):
    if c.get('onedrive','type',fallback='') != 'onedrive':
        finish('EXISTING_REMOTE_TYPE_CONFLICT')
        raise SystemExit(1)
    if c.get('onedrive','token',fallback='').strip():
        finish('EXISTING_AUTHORIZATION_PRESERVED', next_action='validate_existing_account')
        raise SystemExit(0)
    args = ['config','update','onedrive','config_is_local','false','--non-interactive']
else:
    args = ['config','create','onedrive','onedrive','config_is_local','false','--non-interactive']
q = invoke(args)
for attempt in range(3):
    option = q.get('Option') or {}
    name = option.get('Name','')
    if name == 'config_is_local':
        q = invoke(['config','update','onedrive','--non-interactive','--continue',
                    '--state',q['State'],'--result','false'])
        continue
    if name == 'config_token':
        finish('WAITING_BROWSER_DEVICE_AUTHORIZATION',
               server_configuration_started=True,
               next_action='authorize_on_user_browser_device',
               browser_device_command='rclone authorize "onedrive"',
               setup_state_saved_privately=True)
        break
    if not q.get('State'):
        finish('PROVIDER_CONFIGURATION_FINISHED_REQUIRES_VALIDATION',
               server_configuration_started=True, next_action='validate_selected_drive')
        break
    # Only expose provider option names we explicitly recognize, never Help/defaults.
    safe_name = name if name in ('config_type','config_driveid','config_driveok','region') else 'other'
    finish('WAITING_PROVIDER_CONFIGURATION', next_option=safe_name,
           server_configuration_started=True, setup_state_saved_privately=True)
    break
else:
    finish('CONFIGURATION_STEP_LIMIT_REACHED')
    raise SystemExit(1)
if config.exists():
    config.chmod(0o600)
PY
