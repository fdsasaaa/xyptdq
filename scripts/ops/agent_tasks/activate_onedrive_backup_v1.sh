#!/bin/bash
# Match the owner's downloaded recovery file, arm the timer, then verify the actual systemd service.
set -euo pipefail
umask 077
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ]
CONTROL="${XYPTDQ_AGENT_CONTROL_REPO:-/var/lib/xyptdq-agent/control.git}"
COMMIT="${XYPTDQ_AGENT_REQUIRED_COMMIT:?}"
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT
for item in recovery_escrow.py install_timer.sh onedrive_backup.py; do
  git --git-dir="$CONTROL" show "$COMMIT:scripts/backup/$item" > "$WORK/$item"
done
export XYPTDQ_ACTIVATION_SOURCE="$WORK"
python3 - <<'PY'
import datetime as dt,hashlib,importlib.util,json,os,pathlib,subprocess
root=pathlib.Path('/var/lib/xyptdq-backup')
source=pathlib.Path(os.environ['XYPTDQ_ACTIVATION_SOURCE'])
out=pathlib.Path(os.environ['XYPTDQ_AGENT_RESULT_FILE'])
result={'task':'activate_onedrive_backup_v1','credential_contents_published':False,
        'calendar_triggered_run_verified':False,'service_test_invocation':'manual_systemd_start'}
phase='verify_independent_recovery_file'

def module(name,path):
    spec=importlib.util.spec_from_file_location(name,str(path))
    m=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

def command(args,timeout=60):
    p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                     universal_newlines=True,timeout=timeout)
    if p.returncode:
        raise RuntimeError('required server command failed')
    return p.stdout.strip()

def unit_state():
    state={}
    for prop,verb in [('active','is-active'),('enabled','is-enabled')]:
        p=subprocess.run(['systemctl',verb,'xyptdq-backup.timer'],stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL,universal_newlines=True,timeout=15)
        state[prop]=p.stdout.strip()
    return state

try:
    installed=pathlib.Path('/usr/local/lib/xyptdq-backup/onedrive_backup.py')
    if hashlib.sha256(installed.read_bytes()).digest()!=hashlib.sha256((source/'onedrive_backup.py').read_bytes()).digest():
        raise RuntimeError('installed backup implementation differs from the pinned version')
    b=module('backup',installed)
    cfg=b.load_config('/etc/xyptdq-backup/config.json')
    first=json.loads(b.private_file(root/'first-cloud-backup-receipt.json').read_text())
    if first.get('status')!='PASS' or not first.get('download_verified') or not first.get('remote_repository_read_data_verified'):
        raise RuntimeError('verified first cloud backup is required')
    grant_id='onedrive-recovery-20261101-01'
    base=root/'ssh-grants'
    grant=json.loads(b.private_file(base/(grant_id+'.json')).read_text())
    payload=b.private_file(base/(grant_id+'.recovery.json')).read_bytes()
    escrow=module('escrow',source/'recovery_escrow.py')
    confirmation=escrow.verify_export(grant,payload,
        'E8A866FB7F115C1F7F3D6DBB9C83FB1CC68CA3173644A303DD294F92883EAD13',
        cfg['repository'],b.private_file(cfg['password_file']).read_text().strip())
    if grant.get('grant_id')!=grant_id or grant['suffix'].encode() in pathlib.Path('/root/.ssh/authorized_keys').read_bytes():
        raise RuntimeError('one-use export authorization must be revoked')
    confirmation.update(confirmed_at=b.now(),owner_storage='Windows LOCALAPPDATA/XYPTDQ-BackupRecovery/xyptdq-recovery.json',
                        single_use_export_revoked=True)
    b.atomic_json(root/'independent-recovery-confirmation.json',confirmation)
    result.update(independent_key_escrow_confirmed=True,owner_file_sha256_verified=True,
                  current_repository_key_verified=True,single_use_export_revoked=True)
    phase='install_and_activate_daily_timer'
    command(['install','-o','root','-g','root','-m','0700',str(source/'install_timer.sh'),
             '/usr/local/lib/xyptdq-backup/install_timer.sh'])
    command(['bash','/usr/local/lib/xyptdq-backup/install_timer.sh'],timeout=120)
    result['timer']=unit_state()
    if result['timer']!={'active':'active','enabled':'enabled'}:
        raise RuntimeError('daily timer is not active and enabled')
    result['daily_timer_enabled']=True
    result['schedule']={'time':'03:30','timezone':'Asia/Shanghai','maximum_jitter_minutes':5,
                        'persistent_catchup':True,'failure_retry_minutes':15}
    phase='run_actual_systemd_backup_service'
    started=dt.datetime.now(dt.timezone.utc)
    command(['systemctl','start','xyptdq-backup.service'],timeout=1500)
    properties=command(['systemctl','show','xyptdq-backup.service','--property=Result',
                        '--property=ExecMainStatus','--property=ActiveState','--property=ExecMainCode'])
    service=dict(line.split('=',1) for line in properties.splitlines() if '=' in line)
    if service.get('Result')!='success' or service.get('ExecMainStatus')!='0' or service.get('ActiveState')!='inactive':
        raise RuntimeError('systemd backup service did not finish successfully')
    phase='verify_service_snapshot_and_remote_inventory'
    status=json.loads(b.private_file(root/'status.json').read_text())
    stamp=dt.datetime.fromisoformat(status['observed_at'])
    if status.get('outcome')!='PASS' or not status.get('download_verified') or stamp<started:
        raise RuntimeError('service did not create a new verified backup receipt')
    sid=b.snapshot_id(status['snapshot_id'])
    restored=json.loads(b.private_file(root/'restore-check'/'RESTORE_VERIFIED.json').read_text())
    if restored.get('snapshot_id')!=sid or dt.datetime.fromisoformat(restored['verified_at'])<started:
        raise RuntimeError('service snapshot download verification is not current')
    inventory=json.loads(b.run(['rclone','cat',cfg['repository'].split(':',1)[1]+'-inventory/status.json']))
    if inventory.get('snapshot_id')!=status['snapshot_id'] or inventory.get('observed_at')!=status['observed_at']:
        raise RuntimeError('remote backup inventory does not match the service receipt')
    snapshots=json.loads(b.restic('snapshots','--json','--host',b.HOST,'--tag',b.TAG))
    if not any(x['id']==first['snapshot_id'] for x in snapshots):
        raise RuntimeError('original verified snapshot is missing')
    result.update(status='PASS',phase='complete',finished_at=b.now(),snapshot_id=sid,
                  backup_finished_at=status['observed_at'],download_verified=True,
                  remote_inventory_verified=True,first_snapshot_preserved=True,
                  snapshot_count=len(snapshots),systemd_service_verified=True,service=service)
    result['timer']=unit_state()
    result['next_trigger_server_timezone']=command(['systemctl','show','xyptdq-backup.timer',
                                                   '--property=NextElapseUSecRealtime','--value'])
    if result['timer']!={'active':'active','enabled':'enabled'} or not result['next_trigger_server_timezone']:
        raise RuntimeError('daily timer lost its next scheduled trigger')
    b.atomic_json(root/'daily-timer-activation-receipt.json',result)
    out.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
except Exception as error:
    result.update(status='FAIL',phase=phase,error_type=type(error).__name__,timer=unit_state())
    out.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    raise
PY
