#!/bin/bash
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
INTAKE_ROOT="${XYPTDQ_INTAKE_ROOT:-/var/lib/xyptdq-content/intake}"
SOURCE_DIR="$INTAKE_ROOT/source/caipiaowenzhang"
LEDGER="$INTAKE_ROOT/state.json"
DRAFT_DIR="$INTAKE_ROOT/drafts"
LOG_DIR="${XYPTDQ_INTAKE_LOG_DIR:-/var/log/xyptdq-intake}"
CRON_FILE="${XYPTDQ_INTAKE_CRON_FILE:-/etc/cron.d/xyptdq-intake}"
[ -n "$RESULT_FILE" ] || exit 2
TMP=$(mktemp -d /tmp/xyptdq-idle-intake-audit.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
fail() {
  python3 - "$RESULT_FILE" "$1" "$2" <<'PY'
import json,sys
out,phase,detail=sys.argv[1:]
p={'task':'audit_idle_intake_after_zero_fix_v1','status':'FAIL','phase':phase,'detail':detail,'read_only':True,'runtime_mutation_attempted':False,'cms_write_attempted':False,'scheduled_queue_mutated':False,'publisher_invoked':False,'publisher_cron_mutated':False,'intake_cron_mutated':False,'publication_queue_consumed':False}
open(out,'w',encoding='utf-8').write(json.dumps(p,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
PY
  exit 20
}
[ -d "$REPO/.git" ] || fail repo "website repo missing"
[ -z "$(git -C "$REPO" status --porcelain)" ] || fail repo "website repo dirty"
[ -d "$SOURCE_DIR/.git" ] || fail source "private source cache missing"
[ -s "$LEDGER" ] || fail ledger "ledger missing"
[ -d "$DRAFT_DIR" ] || fail drafts "Draft dir missing"
[ -d "$LOG_DIR" ] || fail logs "intake log dir missing"
[ -s "$CRON_FILE" ] || fail cron "intake cron missing"
COUNT=$( (grep -R -h -F 'run_incremental_inventory_intake.sh' /etc/cron.d /etc/crontab 2>/dev/null || true) | grep -v '^#' | wc -l | tr -d ' ')
[ "$COUNT" = 1 ] || fail cron "expected one active intake cron, found $COUNT"
grep -Fq '23 * * * * root XYPTDQ_INTAKE_MODE=auto XYPTDQ_INTAKE_LIMIT=25 /bin/bash' "$CRON_FILE" || fail cron "intake cron schedule mismatch"
SOURCE_HEAD=$(git -C "$SOURCE_DIR" rev-parse HEAD)
SOURCE_ORIGIN=$(git -C "$SOURCE_DIR" rev-parse refs/remotes/origin/main)
[ "$SOURCE_HEAD" = "$SOURCE_ORIGIN" ] || fail source "private source cache not synced to origin/main"
python3 "$REPO/scripts/content/inventory_diff.py" --source-repo="$SOURCE_DIR" --website-repo="$REPO" --ledger="$LEDGER" --output="$TMP/inventory.json" >/dev/null 2>&1 || fail inventory "inventory reconciliation failed"
python3 - "$TMP/inventory.json" <<'PY' || fail inventory "current inventory is not fully reconciled"
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
assert x.get('status')=='PASS'
assert x.get('A_upstream_official_ready')==45
assert x.get('website_ingress_known')==12
assert x.get('ledger_known')==33
assert x.get('new_draft_candidates')==0
assert x.get('cf50_final5_release_authorized') is False
assert x.get('cf50_frozen_final5_count')==5
assert not (x.get('candidate_revision_ids') or [])
PY
python3 - "$LOG_DIR" "$SOURCE_HEAD" "$TMP/logs.json" <<'PY' || fail logs "post-fix idle cron logs failed audit"
import json,sys,pathlib,re
root=pathlib.Path(sys.argv[1]); source=sys.argv[2]; out=pathlib.Path(sys.argv[3])
rx=re.compile(r'^run_(\d{8}T\d{6}Z)\.log$')
rows=[]
for p in sorted(root.glob('run_*.log')):
    m=rx.match(p.name)
    if not m or m.group(1) < '20260816T052300Z':
        continue
    x=json.loads(p.read_text(encoding='utf-8'))
    assert x.get('status')=='PASS', p.name
    assert x.get('mode')=='auto', p.name
    assert (x.get('selected_revision_ids') or [])==[], p.name
    assert x.get('ledger_known_before')==33, p.name
    assert x.get('candidate_count_before')==0, p.name
    assert x.get('source_commit')==source, p.name
    rows.append({'file':p.name,'ledger_known_before':33,'candidate_count_before':0,'selected':0})
assert len(rows)>=5, len(rows)
assert rows[-1]['file'] >= 'run_20260816T092300Z.log', rows[-1]['file']
out.write_text(json.dumps({'count':len(rows),'runs':rows},ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY
python3 - "$LEDGER" "$DRAFT_DIR" "$TMP/runtime.json" <<'PY' || fail runtime "ledger/Draft safety audit failed"
import json,sys,pathlib
ledger=pathlib.Path(sys.argv[1]); drafts=pathlib.Path(sys.argv[2]); out=pathlib.Path(sys.argv[3])
frozen={'LCM-CREATOR-cf50-20260813-020','LCM-CREATOR-cf50-20260813-029','LCM-CREATOR-cf50-20260813-038','LCM-CREATOR-cf50-20260813-039','LCM-CREATOR-cf50-20260813-040'}
x=json.loads(ledger.read_text(encoding='utf-8')); rec=x.get('records') or {}
assert isinstance(rec,dict) and len(rec)==33
for rev,r in rec.items():
    assert r.get('lifecycle_state')=='draft'
    assert r.get('cms_id') is None and r.get('scheduled_at') is None and r.get('published_at') is None
    aid=str(r.get('article_id') or '')
    assert aid not in frozen
    p=pathlib.Path(str(r.get('draft_path') or '')); assert p.is_file()
    d=json.loads(p.read_text(encoding='utf-8'))
    assert d.get('publication_state')=='draft' and 'publish_at' not in d
    assert str(d.get('source_article_id') or '')==aid
for p in drafts.glob('*.json'):
    d=json.loads(p.read_text(encoding='utf-8'))
    assert d.get('publication_state')=='draft' and 'publish_at' not in d
    assert str(d.get('source_article_id') or '') not in frozen
files=list(drafts.glob('*.json')); assert len(files)==33
out.write_text(json.dumps({'ledger_records':33,'draft_files':33,'frozen_final5_present':False},ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY
python3 - "$RESULT_FILE" "$SOURCE_HEAD" "$TMP/logs.json" <<'PY'
import json,sys
out,source,logs_p=sys.argv[1:]
logs=json.load(open(logs_p,encoding='utf-8'))
p={'task':'audit_idle_intake_after_zero_fix_v1','status':'PASS','phase':'complete','detail':'post-fix natural :23 cron runs remained healthy no-op at zero inventory; durable intake state is 33 Drafts / 0 candidates and final5 remain frozen','read_only':True,'source_commit_current':source,'ledger_records_current':33,'runtime_draft_files_current':33,'new_draft_candidates_current':0,'post_fix_idle_runs_audited':logs['count'],'post_fix_idle_run_summaries':logs['runs'],'intake_cron_count':1,'intake_cron_schedule':'23 * * * *','cf50_final5_release_authorized':False,'cf50_frozen_final5_count':5,'runtime_mutation_attempted':False,'cms_write_attempted':False,'scheduled_queue_mutated':False,'publisher_invoked':False,'publisher_cron_mutated':False,'intake_cron_mutated':False,'publication_queue_consumed':False}
open(out,'w',encoding='utf-8').write(json.dumps(p,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
PY
echo IDLE_INTAKE_AFTER_ZERO_FIX_AUDIT=PASS
