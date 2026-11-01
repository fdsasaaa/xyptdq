#!/bin/bash
# Finish the existing authorized account's default-drive choice, then run the pinned backup flow.
set -euo pipefail
umask 077
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ]
CONTROL="${XYPTDQ_AGENT_CONTROL_REPO:-/var/lib/xyptdq-agent/control.git}"
COMMIT="${XYPTDQ_AGENT_REQUIRED_COMMIT:?}"
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT
git --git-dir="$CONTROL" show "$COMMIT:scripts/backup/select_default_drive.py" > "$WORK/select.py"
git --git-dir="$CONTROL" show "$COMMIT:scripts/ops/agent_tasks/first_onedrive_backup_v1.sh" > "$WORK/backup.sh"
export XYPTDQ_SELECTION_MODULE="$WORK/select.py"
export XYPTDQ_SELECTION_RECEIPT="$WORK/selection.json"
python3 - <<'PY'
import configparser,fcntl,importlib.util,json,os,pathlib,signal,subprocess,time,urllib.request
root=pathlib.Path('/var/lib/xyptdq-backup')
cfg=pathlib.Path('/etc/xyptdq-backup/rclone.conf')
out=pathlib.Path(os.environ['XYPTDQ_AGENT_RESULT_FILE'])
phase='inspect_saved_authorization'
result={'task':'finalize_default_onedrive_v1','account_identifiers_published':False,'daily_timer_enabled':False}

def config():
    c=configparser.ConfigParser(interpolation=None)
    c.read(str(cfg))
    return c

def invoke(args):
    p=subprocess.run(['/usr/local/bin/rclone','--config',str(cfg)]+args,
                     stdout=subprocess.PIPE,stderr=subprocess.PIPE,universal_newlines=True,timeout=90)
    if p.returncode:
        raise RuntimeError('provider continuation failed')
    return json.loads(p.stdout) or {}

try:
    c=config()
    if not c.get('onedrive','token',fallback=''):
        raise RuntimeError('browser authorization is not saved')
    if not c.get('onedrive','drive_id',fallback=''):
        q=json.loads((root/'onedrive-auth-response.json').read_text())
        phase='resolve_owner_default_drive'
        access=json.loads(c.get('onedrive','token'))['access_token']
        request=urllib.request.Request('https://graph.microsoft.com/v1.0/me/drive?$select=id,driveType,quota',
                                       headers={'Authorization':'Bearer '+access})
        with urllib.request.urlopen(request,timeout=45) as response:
            drive=json.load(response)
        spec=importlib.util.spec_from_file_location('selection',os.environ['XYPTDQ_SELECTION_MODULE'])
        selection=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(selection)
        target=selection.default_drive_id(q,drive)
        result['candidate_count']=len(q['Option'].get('Examples') or [])
        phase='coordinate_paused_selection_session'
        lock=open(str(root/'onedrive-auth.lock'),'a')
        try:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:
            owners=[]
            for path in pathlib.Path('/proc').iterdir():
                if not path.name.isdigit():
                    continue
                try:
                    args=path.joinpath('cmdline').read_bytes().split(b'\x00')
                    if path.stat().st_uid==0 and b'/usr/local/lib/xyptdq-backup/authorize_ssh.py' in args:
                        owners.append(int(path.name))
                except OSError:
                    continue
            # Only the known, paused authorization helper may be stopped. No arbitrary process kill.
            current=config()
            if current.get('onedrive','drive_id',fallback=''):
                raise RuntimeError('owner selection completed concurrently; preserve it and retry')
            fresh=json.loads((root/'onedrive-auth-response.json').read_text())
            if len(owners)!=1 or fresh.get('State')!=q.get('State') or (fresh.get('Option') or {}).get('Name')!='config_driveid':
                raise RuntimeError('authorization session changed; preserve it')
            os.kill(owners[0],signal.SIGTERM)
            for _ in range(40):
                try:
                    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    time.sleep(0.25)
            else:
                raise RuntimeError('authorization session did not release its lock')
        try:
            phase='continue_exact_provider_drive_choice'
            q=invoke(['config','update','onedrive','--non-interactive','--continue','--state',q['State'],'--result',target])
            if q.get('State') and (q.get('Option') or {}).get('Name')=='config_drive_ok':
                q=invoke(['config','update','onedrive','--non-interactive','--continue','--state',q['State'],'--result','true'])
            if q.get('State') or config().get('onedrive','drive_id',fallback='')!=target:
                raise RuntimeError('default drive configuration is incomplete')
            result['default_onedrive_identity_verified']=True
        finally:
            lock.close()
    else:
        result['existing_owner_selection_preserved']=True
    phase='verify_connection_and_capacity'
    p=subprocess.run(['/usr/local/bin/rclone','--config',str(cfg),'about','onedrive:','--json'],
                     stdout=subprocess.PIPE,stderr=subprocess.PIPE,universal_newlines=True,timeout=90)
    if p.returncode:
        raise RuntimeError('capacity verification failed')
    quota=json.loads(p.stdout)
    result['quota']={k:quota[k] for k in ('total','free','used') if isinstance(quota.get(k),int)}
    result['drive_type']=config().get('onedrive','drive_type',fallback='unknown')
    spec=importlib.util.spec_from_file_location('auth','/usr/local/lib/xyptdq-backup/authorize_ssh.py')
    auth=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(auth)
    auth.save_status('AUTHORIZED_AND_CAPACITY_VERIFIED',drive_type=result['drive_type'],
                     **{dst:quota[src] for src,dst in [('total','total_bytes'),('free','free_bytes'),('used','used_bytes')] if src in quota})
    result.update(status='PASS',phase='selection_complete')
    pathlib.Path(os.environ['XYPTDQ_SELECTION_RECEIPT']).write_text(json.dumps(result)+'\n')
except Exception as error:
    result.update(status='FAIL',phase=phase,error_type=type(error).__name__)
    out.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    raise
PY
bash "$WORK/backup.sh"
python3 - <<'PY'
import json,os,pathlib
p=pathlib.Path(os.environ['XYPTDQ_AGENT_RESULT_FILE'])
result=json.loads(p.read_text())
result['selection_verification']=json.loads(pathlib.Path(os.environ['XYPTDQ_SELECTION_RECEIPT']).read_text())
p.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
PY
