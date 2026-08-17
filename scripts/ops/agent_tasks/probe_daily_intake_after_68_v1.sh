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
EXPECTED_SOURCE="93fd1f9d021ce191780a66f501ed2634db141640"
EXPECTED_DAILY_MANIFEST="articles/public_release/manifests/DAILY-20260817.json"
[ -n "$RESULT_FILE" ] || exit 2
TMP=$(mktemp -d /tmp/xyptdq-daily-intake-probe.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
fail() {
  python3 - "$RESULT_FILE" "$1" "$2" <<'PY'
import json,sys
out,phase,detail=sys.argv[1:]
p={
  'task':'probe_daily_intake_after_68_v1','status':'FAIL','phase':phase,'detail':detail,
  'read_only':True,'runtime_mutation_attempted':False,'cms_write_attempted':False,
  'scheduled_queue_mutated':False,'publisher_invoked':False,'publisher_cron_mutated':False,
  'intake_cron_mutated':False,'publication_queue_consumed':False
}
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
SOURCE_REMOTE=$(git -C "$SOURCE_DIR" ls-remote origin refs/heads/main | awk 'NR==1{print $1}')
[ -n "$SOURCE_REMOTE" ] || fail source "cannot resolve remote article main"
[ "$SOURCE_REMOTE" = "$EXPECTED_SOURCE" ] || fail source "article main differs from expected recovered inventory commit: $SOURCE_REMOTE"
[ "$SOURCE_HEAD" = "$SOURCE_REMOTE" ] || fail source "private source cache did not sync to new article main; head=$SOURCE_HEAD remote=$SOURCE_REMOTE"
[ -s "$SOURCE_DIR/$EXPECTED_DAILY_MANIFEST" ] || fail source "DAILY-20260817 manifest missing from synced source cache"

python3 "$REPO/scripts/content/inventory_diff.py" \
  --source-repo="$SOURCE_DIR" --website-repo="$REPO" --ledger="$LEDGER" \
  --output="$TMP/inventory.json" >/dev/null 2>&1 || fail inventory "inventory reconciliation failed"

python3 - "$TMP/inventory.json" <<'PY' || fail inventory "68-article inventory is not fully reconciled"
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
assert x.get('status')=='PASS', x.get('status')
assert x.get('A_upstream_official_ready')==68, x.get('A_upstream_official_ready')
assert x.get('website_ingress_known')==12, x.get('website_ingress_known')
assert x.get('ledger_known')==56, x.get('ledger_known')
assert x.get('new_draft_candidates')==0, x.get('new_draft_candidates')
assert x.get('cf50_final5_release_authorized') is False
assert x.get('cf50_frozen_final5_count')==5
assert not (x.get('candidate_revision_ids') or [])
PY

python3 - "$LEDGER" "$DRAFT_DIR" "$SOURCE_DIR/$EXPECTED_DAILY_MANIFEST" "$TMP/runtime.json" <<'PY' || fail runtime "new DAILY-20260817 public-r1 items were not safely materialized as Draft-only"
import json,sys,pathlib
ledger_p,drafts_p,manifest_p,out_p=map(pathlib.Path,sys.argv[1:])
frozen={'LCM-CREATOR-cf50-20260813-020','LCM-CREATOR-cf50-20260813-029','LCM-CREATOR-cf50-20260813-038','LCM-CREATOR-cf50-20260813-039','LCM-CREATOR-cf50-20260813-040'}
ledger=json.loads(ledger_p.read_text(encoding='utf-8'))
rec=ledger.get('records') or {}
assert isinstance(rec,dict) and len(rec)==56, len(rec)
manifest=json.loads(manifest_p.read_text(encoding='utf-8'))
assert manifest.get('approved_public_release_count')==23
revs=[a['revision_id'] for a in manifest.get('articles') or []]
assert len(revs)==23 and len(set(revs))==23
missing=[r for r in revs if r not in rec]
assert not missing, missing
for rev,r in rec.items():
    assert r.get('lifecycle_state')=='draft', (rev,r.get('lifecycle_state'))
    assert r.get('cms_id') is None and r.get('scheduled_at') is None and r.get('published_at') is None, rev
    aid=str(r.get('article_id') or '')
    assert aid not in frozen, aid
    p=pathlib.Path(str(r.get('draft_path') or ''))
    assert p.is_file(), p
    d=json.loads(p.read_text(encoding='utf-8'))
    assert d.get('publication_state')=='draft', rev
    assert 'publish_at' not in d, rev
    assert str(d.get('source_article_id') or '')==aid, rev
files=list(drafts_p.glob('*.json'))
assert len(files)==56, len(files)
for p in files:
    d=json.loads(p.read_text(encoding='utf-8'))
    assert d.get('publication_state')=='draft'
    assert 'publish_at' not in d
    assert str(d.get('source_article_id') or '') not in frozen
out_p.write_text(json.dumps({
  'ledger_records':56,'draft_files':56,'daily_20260817_revisions_in_ledger':23,
  'frozen_final5_present':False
},ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY

python3 - "$LOG_DIR" "$EXPECTED_SOURCE" "$TMP/logs.json" <<'PY' || fail logs "09:23 natural intake did not prove the expected 23-item transition"
import json,sys,pathlib,re
root=pathlib.Path(sys.argv[1]); expected=sys.argv[2]; out=pathlib.Path(sys.argv[3])
rx=re.compile(r'^run_(\d{8}T\d{6}Z)\.log$')
rows=[]
for p in sorted(root.glob('run_*.log')):
    m=rx.match(p.name)
    if not m or m.group(1) < '20260817T012300Z':
        continue
    try:
        x=json.loads(p.read_text(encoding='utf-8'))
    except Exception:
        continue
    rows.append((p,x))
assert rows, 'no intake log at/after 2026-08-17 01:23Z'
matched=[]
for p,x in rows:
    selected=x.get('selected_revision_ids') or []
    if x.get('source_commit')==expected and x.get('candidate_count_before')==23 and x.get('ledger_known_before')==33 and len(selected)==23:
        matched.append((p,x))
assert matched, [(p.name,x.get('status'),x.get('source_commit'),x.get('candidate_count_before'),x.get('ledger_known_before'),len(x.get('selected_revision_ids') or [])) for p,x in rows]
p,x=matched[-1]
assert x.get('status')=='PASS', x.get('status')
out.write_text(json.dumps({
  'file':p.name,'status':x.get('status'),'source_commit':x.get('source_commit'),
  'candidate_count_before':x.get('candidate_count_before'),'ledger_known_before':x.get('ledger_known_before'),
  'selected_count':len(x.get('selected_revision_ids') or []),
  'selected_revision_ids':x.get('selected_revision_ids') or []
},ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY

python3 - "$RESULT_FILE" "$SOURCE_HEAD" "$TMP/inventory.json" "$TMP/runtime.json" "$TMP/logs.json" <<'PY'
import json,sys
out,source,inv_p,run_p,log_p=sys.argv[1:]
inv=json.load(open(inv_p,encoding='utf-8'))
run=json.load(open(run_p,encoding='utf-8'))
log=json.load(open(log_p,encoding='utf-8'))
p={
  'task':'probe_daily_intake_after_68_v1','status':'PASS','phase':'complete',
  'detail':'article main advanced from 45 to 68 official public-r1 and the natural 09:23 intake consumed exactly the 23 new revisions into Draft-only runtime state',
  'read_only':True,'source_commit_current':source,
  'upstream_official_ready':inv.get('A_upstream_official_ready'),
  'website_ingress_known':inv.get('website_ingress_known'),'ledger_known':inv.get('ledger_known'),
  'new_draft_candidates_current':inv.get('new_draft_candidates'),
  'daily_20260817_public_r1_count':23,'ledger_records_current':run['ledger_records'],
  'runtime_draft_files_current':run['draft_files'],'daily_20260817_revisions_in_ledger':run['daily_20260817_revisions_in_ledger'],
  'natural_intake_log':log['file'],'natural_intake_selected_count':log['selected_count'],
  'natural_intake_candidate_count_before':log['candidate_count_before'],'natural_intake_ledger_known_before':log['ledger_known_before'],
  'intake_cron_count':1,'intake_cron_schedule':'23 * * * *',
  'cf50_final5_release_authorized':False,'cf50_frozen_final5_count':5,
  'runtime_mutation_attempted':False,'cms_write_attempted':False,'scheduled_queue_mutated':False,
  'publisher_invoked':False,'publisher_cron_mutated':False,'intake_cron_mutated':False,'publication_queue_consumed':False
}
open(out,'w',encoding='utf-8').write(json.dumps(p,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
PY

echo DAILY_INTAKE_AFTER_68_PROBE=PASS
