#!/bin/bash
# Read-only proof of a real timer trigger followed by a verified cloud backup.
set -euo pipefail
umask 077
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ]
python3 - <<'PY'
import datetime as dt,importlib.util,json,os,pathlib,subprocess
root=pathlib.Path('/var/lib/xyptdq-backup')
out=pathlib.Path(os.environ['XYPTDQ_AGENT_RESULT_FILE'])
result={'task':'audit_onedrive_daily_run_v1','read_only':True,
        'backup_started_by_probe':False,'calendar_triggered_run_verified':False}

def command(args):
    p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,universal_newlines=True,timeout=90)
    if p.returncode:
        raise RuntimeError('backup evidence command failed')
    return p.stdout.strip()

def property_value(unit,prop):
    return command(['systemctl','show',unit,'--property='+prop,'--value'])

def epoch(stamp):
    return int(command(['date','--date',stamp,'+%s']))

try:
    spec=importlib.util.spec_from_file_location('backup','/usr/local/lib/xyptdq-backup/onedrive_backup.py')
    b=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(b)
    cfg=b.load_config('/etc/xyptdq-backup/config.json')
    activation=json.loads(b.private_file(root/'daily-timer-activation-receipt.json').read_text())
    if activation.get('status')!='PASS' or not activation.get('independent_key_escrow_confirmed'):
        raise RuntimeError('verified activation evidence is required')
    timer='xyptdq-backup.timer'
    service='xyptdq-backup.service'
    result['timer']={k:property_value(timer,p) for k,p in [('active','ActiveState'),('enabled','UnitFileState')]}
    trigger=property_value(timer,'LastTriggerUSec')
    result['last_timer_trigger_server_timezone']=trigger
    if trigger in ('','n/a') or epoch(trigger)<=dt.datetime.fromisoformat(activation['finished_at']).timestamp():
        result['status']='WAITING_FIRST_CALENDAR_TRIGGER'
    elif property_value(service,'ActiveState') in ('active','activating'):
        result['status']='WAITING_BACKUP_COMPLETION'
    else:
        if result['timer']!={'active':'active','enabled':'enabled'}:
            raise RuntimeError('daily timer is not active and enabled')
        started=epoch(property_value(service,'ExecMainStartTimestamp'))
        finished=epoch(property_value(service,'ExecMainExitTimestamp'))
        if property_value(service,'Result')!='success' or property_value(service,'ExecMainStatus')!='0':
            raise RuntimeError('latest backup service did not succeed')
        if not epoch(trigger)<=started<=finished<=epoch(trigger)+2*3600:
            raise RuntimeError('successful service cannot be linked to the timer/retry window')
        status=json.loads(b.private_file(root/'status.json').read_text())
        stamp=dt.datetime.fromisoformat(status['observed_at']).timestamp()
        if status.get('outcome')!='PASS' or not status.get('download_verified') or not started<=stamp<=finished+2:
            raise RuntimeError('backup receipt does not match this service execution')
        sid=b.snapshot_id(status['snapshot_id'])
        restored=json.loads(b.private_file(root/'restore-check'/'RESTORE_VERIFIED.json').read_text())
        if restored.get('snapshot_id')!=sid:
            raise RuntimeError('download verification does not match the latest snapshot')
        inventory=json.loads(b.run(['rclone','cat',cfg['repository'].split(':',1)[1]+'-inventory/status.json']))
        if inventory.get('snapshot_id')!=status['snapshot_id'] or inventory.get('observed_at')!=status['observed_at']:
            raise RuntimeError('OneDrive inventory is not current')
        result.update(status='PASS',calendar_triggered_run_verified=True,snapshot_id=sid,
                      backup_finished_at=status['observed_at'],download_verified=True,
                      remote_inventory_verified=True)
    result['observed_at']=b.now()
except Exception as error:
    result.update(status='FAIL',error_type=type(error).__name__)
    out.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    raise
out.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
PY
