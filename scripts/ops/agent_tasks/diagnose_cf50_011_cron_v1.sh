#!/bin/bash
set -euo pipefail
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
CRON="/etc/cron.d/xyptdq-publisher"
STATE="/var/lib/xyptdq-publisher/CF50-20260813-wave1/state.json"
LOG_DIR="/var/log/xyptdq-publisher"
[ -n "$RESULT_FILE" ] || exit 2
python3 - "$RESULT_FILE" "$REPO" "$CRON" "$STATE" "$LOG_DIR" <<'PY'
import json,sys,os,glob,subprocess
out,repo,cron,state,logdir=sys.argv[1:]
def sh(cmd):
    p=subprocess.run(cmd,shell=True,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    return p.returncode,p.stdout.strip()
rc,status=sh(f"git -C {repo!r} status --porcelain 2>&1")
cron_text=''
if os.path.isfile(cron):
    try: cron_text=open(cron,encoding='utf-8',errors='replace').read()
    except Exception as e: cron_text='ERR:'+repr(e)
logs=sorted(glob.glob(os.path.join(logdir,'run_*.log')))[-5:]
log_items=[]
for p in logs:
    try:
        txt=open(p,encoding='utf-8',errors='replace').read()
    except Exception as e: txt='ERR:'+repr(e)
    log_items.append({'path':p,'mtime':os.path.getmtime(p),'tail':txt[-4000:]})
payload={
 'task':'diagnose_cf50_011_cron_v1','read_only':True,
 'cron_exists':os.path.isfile(cron),'cron_text':cron_text,
 'state_exists':os.path.isfile(state),'repo_status_rc':rc,'repo_status':status,
 'recent_logs':log_items,'publisher_log_dir_exists':os.path.isdir(logdir),
 'runtime_mutated':False,'cron_mutated':False,'cms_write_attempted':False}
with open(out,'w',encoding='utf-8') as f: json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
