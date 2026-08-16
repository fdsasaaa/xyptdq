#!/bin/bash
# Read-only production audit for the first scheduled automatic Draft intake run.
# This task must not mutate Drafts, ledger, CMS, Scheduled, Publisher or cron state.
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
FIRST_CRON_GLOB="$LOG_DIR/run_20260816T0223"'*.log'
[ -n "$RESULT_FILE" ] || exit 2

TMP=$(mktemp -d /tmp/xyptdq-intake-audit.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

fail() {
  local phase="$1" detail="$2"
  python3 - "$RESULT_FILE" "$phase" "$detail" <<'PY'
import json,sys
out,phase,detail=sys.argv[1:]
p={
 'task':'audit_first_scheduled_intake_v1','status':'FAIL','phase':phase,'detail':detail,
 'read_only':True,'runtime_mutation_attempted':False,'cms_write_attempted':False,
 'publish_at_created':False,'scheduled_queue_mutated':False,'publisher_invoked':False,
 'publisher_cron_mutated':False,'intake_cron_mutated':False,'publication_queue_consumed':False
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
  echo "FIRST_SCHEDULED_INTAKE_AUDIT=FAIL phase=$phase" >&2
  exit 20
}

[ -d "$REPO/.git" ] || fail repo "website repository missing"
[ -z "$(git -C "$REPO" status --porcelain)" ] || fail repo "website repository is dirty"
[ -d "$SOURCE_DIR/.git" ] || fail source "private source checkout missing"
[ -s "$LEDGER" ] || fail ledger "intake ledger missing"
[ -d "$DRAFT_DIR" ] || fail drafts "runtime Draft directory missing"
[ -d "$LOG_DIR" ] || fail logs "intake log directory missing"
[ -s "$CRON_FILE" ] || fail cron "managed intake cron missing"

# The intake cron must be singular and remain isolated from Publisher cadence.
COUNT=$( (grep -R -h -F 'run_incremental_inventory_intake.sh' /etc/cron.d /etc/crontab 2>/dev/null || true) | grep -v '^#' | wc -l | tr -d ' ')
[ "$COUNT" = 1 ] || fail cron "expected exactly one active intake cron, found $COUNT"
grep -Fq '23 * * * * root XYPTDQ_INTAKE_MODE=auto XYPTDQ_INTAKE_LIMIT=25 /bin/bash' "$CRON_FILE" || fail cron "managed intake cron schedule/limit mismatch"

SOURCE_HEAD=$(git -C "$SOURCE_DIR" rev-parse HEAD)
SOURCE_ORIGIN=$(git -C "$SOURCE_DIR" rev-parse refs/remotes/origin/main)
[ "$SOURCE_HEAD" = "$SOURCE_ORIGIN" ] || fail source "private source checkout is not synchronized to cached origin/main"

# The first scheduled run after activation was 2026-08-16 02:23 UTC (10:23 Asia/Singapore).
shopt -s nullglob
FIRST_LOGS=( $FIRST_CRON_GLOB )
shopt -u nullglob
[ "${#FIRST_LOGS[@]}" -eq 1 ] || fail logs "expected exactly one 02:23 UTC first-run log, found ${#FIRST_LOGS[@]}"
FIRST_LOG="${FIRST_LOGS[0]}"

python3 - "$FIRST_LOG" "$TMP/first.json" <<'PY' || fail first_run "first scheduled intake log is not valid successful JSON"
import json,sys
src,out=sys.argv[1:]
with open(src,encoding='utf-8') as f: x=json.load(f)
assert x.get('status')=='PASS'
assert x.get('mode')=='auto'
assert x.get('ledger_known_before')==3
assert x.get('candidate_count_before',0)>=30
sel=x.get('selected_revision_ids') or []
assert len(sel)==25
assert x.get('limit')==25
assert x.get('writes_planned') is True
assert x.get('ledger_known_after')==28
assert x.get('candidate_count_after')==x.get('candidate_count_before')-25
assert x.get('idempotent_reconciliation')=='PASS'
assert x.get('draft_only') is True
assert x.get('publish_at_created') is False
assert x.get('publisher_invoked') is False
with open(out,'w',encoding='utf-8') as f: json.dump(x,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

# Audit every scheduled intake log since the first cron run. A later no-op is allowed,
# but any non-JSON/error log or any publication-side flag fails closed.
python3 - "$LOG_DIR" "$TMP/log-audit.json" <<'PY' || fail logs "one or more scheduled intake logs failed safety audit"
import json,sys,pathlib,re
root=pathlib.Path(sys.argv[1]); out=pathlib.Path(sys.argv[2])
rx=re.compile(r'^run_(\d{8}T\d{6}Z)\.log$')
rows=[]
for p in sorted(root.glob('run_*.log')):
    m=rx.match(p.name)
    if not m or m.group(1) < '20260816T022300Z':
        continue
    try:
        x=json.loads(p.read_text(encoding='utf-8'))
    except Exception as e:
        raise SystemExit(f'invalid scheduled intake log {p.name}: {e}')
    if x.get('status')!='PASS' or x.get('mode')!='auto':
        raise SystemExit(f'non-PASS/non-auto scheduled intake log: {p.name}')
    if x.get('publish_at_created') not in (None,False):
        raise SystemExit(f'publish_at created in {p.name}')
    if x.get('publisher_invoked') not in (None,False):
        raise SystemExit(f'Publisher invoked in {p.name}')
    selected=x.get('selected_revision_ids') or []
    if len(selected)>25:
        raise SystemExit(f'run limit exceeded in {p.name}')
    if selected:
        if x.get('draft_only') is not True or x.get('idempotent_reconciliation')!='PASS':
            raise SystemExit(f'Draft/idempotency guard missing in {p.name}')
    rows.append({'file':p.name,'selected':len(selected),'ledger_before':x.get('ledger_known_before'),'ledger_after':x.get('ledger_known_after'),'candidates_before':x.get('candidate_count_before'),'candidates_after':x.get('candidate_count_after'),'source_commit':x.get('source_commit')})
if not rows:
    raise SystemExit('no scheduled intake logs at/after first cron time')
out.write_text(json.dumps({'count':len(rows),'runs':rows},ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY

# Current durable runtime must remain Draft-only and the Issue #264 final five must stay absent.
python3 - "$LEDGER" "$DRAFT_DIR" "$TMP/runtime.json" <<'PY' || fail runtime "ledger/Draft safety audit failed"
import json,sys,pathlib
ledger_path=pathlib.Path(sys.argv[1]); draft_dir=pathlib.Path(sys.argv[2]); out=pathlib.Path(sys.argv[3])
frozen={
 'LCM-CREATOR-cf50-20260813-020','LCM-CREATOR-cf50-20260813-029',
 'LCM-CREATOR-cf50-20260813-038','LCM-CREATOR-cf50-20260813-039','LCM-CREATOR-cf50-20260813-040'
}
l=json.loads(ledger_path.read_text(encoding='utf-8')); records=l.get('records') or {}
if not isinstance(records,dict): raise SystemExit('ledger records malformed')
checked=0
for rev,r in records.items():
    if not isinstance(r,dict): raise SystemExit(f'ledger row malformed: {rev}')
    aid=str(r.get('article_id') or '')
    if aid in frozen: raise SystemExit(f'frozen final5 leaked into ledger: {aid}')
    if r.get('lifecycle_state')!='draft': raise SystemExit(f'non-draft lifecycle in intake ledger: {rev}')
    if r.get('cms_id') is not None or r.get('scheduled_at') is not None or r.get('published_at') is not None:
        raise SystemExit(f'publication identity leaked into intake ledger: {rev}')
    p=pathlib.Path(str(r.get('draft_path') or ''))
    if not p.is_file(): raise SystemExit(f'ledger Draft missing: {rev}')
    d=json.loads(p.read_text(encoding='utf-8'))
    if d.get('publication_state')!='draft': raise SystemExit(f'non-draft runtime file: {rev}')
    if 'publish_at' in d: raise SystemExit(f'publish_at leaked into runtime Draft: {rev}')
    if d.get('source_revision_id')!=rev or d.get('source_article_id')!=aid:
        raise SystemExit(f'ledger/Draft identity mismatch: {rev}')
    if aid in frozen: raise SystemExit(f'frozen final5 leaked into runtime Draft: {aid}')
    checked+=1
# Also scan all JSON Draft files, including any orphan not in ledger.
for p in draft_dir.glob('*.json'):
    d=json.loads(p.read_text(encoding='utf-8'))
    aid=str(d.get('source_article_id') or '')
    if aid in frozen: raise SystemExit(f'frozen final5 leaked into Draft directory: {aid}')
    if d.get('publication_state')!='draft' or 'publish_at' in d:
        raise SystemExit(f'unsafe Draft file: {p.name}')
out.write_text(json.dumps({'ledger_records':len(records),'checked_ledger_drafts':checked,'draft_files':len(list(draft_dir.glob("*.json"))),'frozen_final5_present':False},ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY

python3 "$REPO/scripts/content/inventory_diff.py" --source-repo="$SOURCE_DIR" --website-repo="$REPO" --ledger="$LEDGER" --output="$TMP/inventory.json" >/dev/null 2>&1 || fail inventory "current inventory reconciliation failed"
python3 - "$TMP/inventory.json" <<'PY' || fail inventory "current inventory policy/final5 assertions failed"
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
assert x.get('status')=='PASS'
assert x.get('cf50_final5_release_authorized') is False
assert x.get('cf50_frozen_final5_count')==5
ids=set(x.get('candidate_revision_ids') or [])
for n in ('020','029','038','039','040'):
    assert f'LCM-CREATOR-cf50-20260813-{n}:public-r1' not in ids
PY

python3 - "$RESULT_FILE" "$FIRST_LOG" "$SOURCE_HEAD" "$CRON_FILE" "$TMP/first.json" "$TMP/log-audit.json" "$TMP/runtime.json" "$TMP/inventory.json" <<'PY'
import json,sys
out,first_log,source,cron,first_p,logs_p,runtime_p,inventory_p=sys.argv[1:]
first=json.load(open(first_p,encoding='utf-8')); logs=json.load(open(logs_p,encoding='utf-8')); runtime=json.load(open(runtime_p,encoding='utf-8')); inv=json.load(open(inventory_p,encoding='utf-8'))
p={
 'task':'audit_first_scheduled_intake_v1','status':'PASS','phase':'complete','read_only':True,
 'detail':'first scheduled :23 automatic intake run and all later intake logs are safe; durable runtime remains Draft-only and final5 frozen',
 'first_scheduled_log':first_log,'first_scheduled_selected_count':len(first.get('selected_revision_ids') or []),
 'first_scheduled_ledger_before':first.get('ledger_known_before'),'first_scheduled_ledger_after':first.get('ledger_known_after'),
 'first_scheduled_candidates_before':first.get('candidate_count_before'),'first_scheduled_candidates_after':first.get('candidate_count_after'),
 'scheduled_runs_audited':logs.get('count'),'scheduled_run_summaries':logs.get('runs'),
 'source_commit_current':source,'intake_cron_file':cron,'intake_cron_count':1,'intake_cron_schedule':'23 * * * *','intake_limit_per_run':25,
 'ledger_records_current':runtime.get('ledger_records'),'runtime_draft_files_current':runtime.get('draft_files'),
 'A_upstream_official_ready_current':inv.get('A_upstream_official_ready'),'website_ingress_known_current':inv.get('website_ingress_known'),
 'ledger_known_current':inv.get('ledger_known'),'new_draft_candidates_current':inv.get('new_draft_candidates'),
 'cf50_final5_release_authorized':inv.get('cf50_final5_release_authorized'),'cf50_frozen_final5_count':inv.get('cf50_frozen_final5_count'),
 'runtime_mutation_attempted':False,'cms_write_attempted':False,'publish_at_created':False,'scheduled_queue_mutated':False,
 'publisher_invoked':False,'publisher_cron_mutated':False,'intake_cron_mutated':False,'publication_queue_consumed':False
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

echo FIRST_SCHEDULED_INTAKE_AUDIT=PASS
