#!/bin/bash
# Read-only diagnosis for the first recurring CF50 publication slot.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
STATE="/var/lib/xyptdq-publisher/CF50-20260813-wave1/state.json"
LOCK="/var/lib/xyptdq-publisher/CF50-20260813-wave1/publisher.lock"
SOURCE="/var/lib/xyptdq-content/CF50-20260813-wave1/scheduled"
LOG_DIR="/var/log/xyptdq-publisher"
CRON="/etc/cron.d/xyptdq-publisher"
[ -n "$RESULT_FILE" ] || exit 2
python3 - "$RESULT_FILE" "$REPO" "$STATE" "$LOCK" "$SOURCE" "$LOG_DIR" "$CRON" <<'PY'
import json,os,pathlib,subprocess,sys
out,repo,state,lock,source,logdir,cron=sys.argv[1:]
def exists(p): return pathlib.Path(p).exists()
def text(p):
    try:return pathlib.Path(p).read_text(encoding='utf-8',errors='replace')
    except:return ''
logs=sorted(pathlib.Path(logdir).glob('run_*.log')) if exists(logdir) else []
latest=str(logs[-1]) if logs else ''
latest_text=text(latest) if latest else ''
try: dirty=subprocess.check_output(['git','-C',repo,'status','--porcelain'],text=True,stderr=subprocess.STDOUT).strip()
except Exception as e: dirty='ERROR:'+str(e)
cron_text=text(cron)
p={
 'task':'diagnose_cf50_011_cron_v1','status':'PASS','read_only':True,
 'state_exists':exists(state),'lock_exists':exists(lock),'source_exists':exists(source),
 'source_json_count':len(list(pathlib.Path(source).glob('*.json'))) if exists(source) else -1,
 'cron_exists':exists(cron),'cron_has_minute7':'7 * * * *' in cron_text,
 'cron_has_source':('XYPTDQ_PUBLISH_SOURCE='+source) in cron_text,
 'cron_has_state':('XYPTDQ_PUBLISH_STATE='+state) in cron_text,
 'cron_has_lock':('XYPTDQ_PUBLISH_LOCK='+lock) in cron_text,
 'repo_exists':exists(pathlib.Path(repo)/'.git'),'repo_dirty':bool(dirty), 'repo_status':dirty[:2000],
 'log_dir_exists':exists(logdir),'log_count':len(logs),'latest_log':latest,
 'latest_log_tail':latest_text[-6000:] if latest_text else '',
 'runtime_mutated':False,'cms_write_attempted':False,'cron_mutated':False
}
pathlib.Path(out).write_text(json.dumps(p,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY
echo DIAGNOSE_CF50_011_CRON_V1=PASS
