#!/bin/bash
# Verify real authorization before creating the first encrypted, download-verified snapshot.
set -euo pipefail
umask 077
[ "$(id -u)" -eq 0 ]
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
python3 - <<'PY'
import configparser, datetime as dt, fcntl, importlib.util, json, os, pathlib, subprocess

root = pathlib.Path('/var/lib/xyptdq-backup')
out = pathlib.Path(os.environ['XYPTDQ_AGENT_RESULT_FILE'])
result = {'task':'first_onedrive_backup_v1','remote_snapshot_created':False,'daily_timer_enabled':False}
phase = 'authorization_probe'

def emit(status, **fields):
    result.update(status=status, phase=phase, **fields)
    out.write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')

try:
    c = configparser.ConfigParser(interpolation=None)
    c.read('/etc/xyptdq-backup/rclone.conf')
    present = {'authorization_data_present':bool(c.get('onedrive','token',fallback='').strip()),
               'selected_drive_present':bool(c.get('onedrive','drive_id',fallback='').strip())}
    if not all(present.values()):
        next_option = 'unknown'
        drive_count = 0
        response = root/'onedrive-auth-response.json'
        if response.is_file():
            try:
                q = json.loads(response.read_text()) or {}
                option = q.get('Option') or {}
                name = option.get('Name','')
                if name in ('config_is_local','config_token','config_type','config_driveid','config_drive_ok','config_refresh_token'):
                    next_option = name
                drive_count = len(option.get('Examples') or []) if name == 'config_driveid' else 0
            except ValueError:
                pass
        log = root/'onedrive-auth-private.log'
        private_log = log.read_text(errors='replace') if log.is_file() else ''
        ports = subprocess.run(['ss','-ltnH'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,
                               universal_newlines=True,timeout=10).stdout
        emit('WAITING_AUTHORIZATION_COMPLETION', read_only=True, **present,
             next_option=next_option, available_drive_count=drive_count,
             callback_received_marker='Got code' in private_log,
             waiting_for_code_marker='Waiting for code' in private_log,
             oauth_loopback_listener_active='127.0.0.1:53682' in ports)
        raise SystemExit(0)
    phase = 'load_protected_configuration'
    spec = importlib.util.spec_from_file_location('backup','/usr/local/lib/xyptdq-backup/onedrive_backup.py')
    b = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(b)
    cfg = b.load_config('/etc/xyptdq-backup/config.json')
    phase = 'verify_remote_capacity'
    quota = json.loads(b.run(['rclone','about','onedrive:','--json']))
    result['quota'] = {k:quota[k] for k in ('total','used','free') if isinstance(quota.get(k),int)}
    result['drive_type'] = c.get('onedrive','drive_type',fallback='unknown')
    if isinstance(quota.get('free'),int) and quota['free'] < 256*1024*1024:
        raise RuntimeError('insufficient initial backup headroom')
    with open(str(root/'operation.lock'),'a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        phase = 'verify_dedicated_repository'
        remote = cfg['repository'].split(':',1)[1]
        b.run(['rclone','mkdir',remote])
        listing = json.loads(b.run(['rclone','lsjson','--max-depth','1',remote]))
        if listing:
            if not any(item.get('Name') == 'config' and not item.get('IsDir') for item in listing):
                raise RuntimeError('nonempty destination is not a restic repository')
            b.restic('snapshots','--json')
            result['repository_initialized_this_run'] = False
        else:
            phase = 'initialize_empty_repository'
            b.restic('init')
            result['repository_initialized_this_run'] = True
        phase = 'backup_and_download_verification'
        backup_result = b.backup(cfg)
        result['remote_snapshot_created'] = True
        result['snapshot_id'] = b.snapshot_id(backup_result['snapshot_id'])
        result['download_verified'] = backup_result['download_verified']
        result['backup_finished_at'] = backup_result['observed_at']
        stage = pathlib.Path(cfg['state_dir'])/'staging'
        result['local_payload_bytes'] = sum(p.stat().st_size for p in stage.iterdir() if p.is_file())
        phase = 'remote_repository_integrity_check'
        b.restic('check','--read-data')
        result['remote_repository_read_data_verified'] = True
    phase = 'complete'
    emit('PASS', key_escrow_confirmed=False, timer_activation_pending_key_escrow=True)
    b.atomic_json(root/'first-cloud-backup-receipt.json',result)
except Exception as error:
    emit('FAIL', error_type=type(error).__name__)
    raise
PY
