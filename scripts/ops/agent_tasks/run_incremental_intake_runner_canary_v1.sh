#!/bin/bash
# Production canary for the generic incremental intake runner.
# Preconditions: first Draft/ledger canary (003) already PASS, automatic intake disabled.
# Expected mutation: exactly one additional Draft+ledger record for revision 004.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
INTAKE_ROOT="${XYPTDQ_INTAKE_ROOT:-/var/lib/xyptdq-content/intake}"
SOURCE_DIR="$INTAKE_ROOT/source/caipiaowenzhang"
LEDGER="$INTAKE_ROOT/state.json"
DRAFT_DIR="$INTAKE_ROOT/drafts"
EXPECTED_ID="LCM-CREATOR-cf50-20260813-004"
EXPECTED_REV="$EXPECTED_ID:public-r1"
EXPECTED_DRAFT="$DRAFT_DIR/LCM-CREATOR-cf50-20260813-004_public-r1.draft.json"
[ -n "$RESULT_FILE" ] || exit 2

TMP=$(mktemp -d /tmp/xyptdq-runner-canary.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
[ -s "$LEDGER" ] || exit 3
cp "$LEDGER" "$TMP/ledger.before"
DRAFT_EXISTED=false
[ -e "$EXPECTED_DRAFT" ] && DRAFT_EXISTED=true

write_result() {
  local status="$1" phase="$2" detail="$3" rollback="$4"
  python3 - "$RESULT_FILE" "$status" "$phase" "$detail" "$rollback" "$EXPECTED_DRAFT" <<'PY'
import json,sys
out,status,phase,detail,rollback,draft=sys.argv[1:]
p={
 'task':'run_incremental_intake_runner_canary_v1','status':status,'phase':phase,'detail':detail,
 'canary_article_id':'LCM-CREATOR-cf50-20260813-004','canary_revision_id':'LCM-CREATOR-cf50-20260813-004:public-r1',
 'draft_path':draft,'rollback_performed':rollback=='true','automatic_intake_enabled':False,
 'cms_write_attempted':False,'publish_at_created':False,'scheduled_queue_mutated':False,
 'publisher_invoked':False,'cron_mutated':False,'publication_queue_consumed':False
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}

rollback_canary() {
  local changed=false
  cp "$TMP/ledger.before" "$LEDGER" && chmod 0640 "$LEDGER" && changed=true
  if [ "$DRAFT_EXISTED" = false ] && [ -e "$EXPECTED_DRAFT" ]; then rm -f "$EXPECTED_DRAFT"; changed=true; fi
  echo "$changed"
}

fail() {
  local phase="$1" detail="$2" rb="false"
  if [ -s "$TMP/ledger.before" ]; then rb=$(rollback_canary || echo true); fi
  write_result FAIL "$phase" "$detail" "$rb"
  echo "INCREMENTAL_INTAKE_RUNNER_CANARY=FAIL phase=$phase" >&2
  exit 20
}

[ -d "$REPO/.git" ] || fail repo_sync "canonical website repo missing"
[ -z "$(git -C "$REPO" status --porcelain)" ] || fail repo_sync "canonical website repo dirty"
git -C "$REPO" fetch --prune origin main >/dev/null 2>&1 || fail repo_sync "website main fetch failed"
git -C "$REPO" checkout -q main || fail repo_sync "website main checkout failed"
git -C "$REPO" reset --hard origin/main >/dev/null || fail repo_sync "website main reset failed"

# Canary must run while unattended mode is still disabled.
POLICY_OK=$(python3 - "$REPO/config/content_inventory_policy.json" "$REPO/config/content_source_sync_policy.json" <<'PY'
import json,sys
a=json.load(open(sys.argv[1],encoding='utf-8')); b=json.load(open(sys.argv[2],encoding='utf-8'))
print('yes' if (a.get('activation') or {}).get('automatic_intake_enabled') is False and b.get('sync_enabled') is False else 'no')
PY
)
[ "$POLICY_OK" = yes ] || fail policy_preflight "automatic intake is not disabled before runner canary"

python3 "$REPO/scripts/content/inventory_diff.py" --source-repo="$SOURCE_DIR" --website-repo="$REPO" --ledger="$LEDGER" --output="$TMP/before.json" 2>"$TMP/before.err" || fail inventory_before "pre-canary inventory diff failed"
if ! python3 - "$TMP/before.json" "$EXPECTED_REV" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8')); rev=sys.argv[2]
assert x.get('status')=='PASS'
assert x.get('A_upstream_official_ready')==45
assert x.get('website_ingress_known')==12
assert x.get('ledger_known')==1
assert x.get('new_draft_candidates')==32
ids=x.get('candidate_revision_ids') or []
assert ids and ids[0]==rev
PY
then
  fail inventory_before "pre-canary watermarks or expected first candidate mismatch"
fi
[ "$DRAFT_EXISTED" = false ] || fail runtime_preflight "004 canary Draft already exists"

if ! XYPTDQ_INTAKE_MODE=canary XYPTDQ_INTAKE_LIMIT=1 /bin/bash "$REPO/scripts/content/run_incremental_inventory_intake.sh" >"$TMP/runner.out" 2>"$TMP/runner.err"; then
  fail runner "incremental intake runner returned nonzero"
fi

[ -s "$EXPECTED_DRAFT" ] || fail draft_verify "expected 004 Draft missing"
if ! python3 - "$EXPECTED_DRAFT" "$LEDGER" "$EXPECTED_REV" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8')); l=json.load(open(sys.argv[2],encoding='utf-8')); rev=sys.argv[3]
assert p.get('publication_state')=='draft'
assert 'publish_at' not in p
assert p.get('source_revision_id')==rev
assert p.get('source_article_id')=='LCM-CREATOR-cf50-20260813-004'
assert p.get('primary_seo_cluster_id')=='ffc_research'
records=l.get('records') or {}
assert len(records)==2
r=records.get(rev)
assert isinstance(r,dict)
assert r.get('lifecycle_state')=='draft'
assert r.get('cms_id') is None and r.get('scheduled_at') is None and r.get('published_at') is None
PY
then
  fail draft_verify "004 Draft or ledger identity verification failed"
fi

python3 "$REPO/scripts/content/inventory_diff.py" --source-repo="$SOURCE_DIR" --website-repo="$REPO" --ledger="$LEDGER" --output="$TMP/after.json" 2>"$TMP/after.err" || fail inventory_after "post-canary inventory diff failed"
if ! python3 - "$TMP/after.json" "$EXPECTED_REV" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8')); rev=sys.argv[2]
assert x.get('status')=='PASS'
assert x.get('A_upstream_official_ready')==45
assert x.get('website_ingress_known')==12
assert x.get('ledger_known')==2
assert x.get('new_draft_candidates')==31
assert rev not in (x.get('candidate_revision_ids') or [])
PY
then
  fail inventory_after "post-canary idempotent reconciliation failed"
fi

SOURCE_HEAD=$(git -C "$SOURCE_DIR" rev-parse HEAD)
python3 - "$RESULT_FILE" "$SOURCE_HEAD" "$EXPECTED_DRAFT" "$TMP/runner.out" <<'PY'
import json,sys
out,source,draft,runner_out=sys.argv[1:]
p={
 'task':'run_incremental_intake_runner_canary_v1','status':'PASS','phase':'complete',
 'detail':'generic incremental runner committed exactly one Draft-only candidate and durable ledger record; post-run reconciliation passed',
 'source_repository':'fdsasaaa/caipiaowenzhang','source_ref':'main','source_commit':source,
 'canary_article_id':'LCM-CREATOR-cf50-20260813-004','canary_revision_id':'LCM-CREATOR-cf50-20260813-004:public-r1',
 'draft_path':draft,'draft_publication_state':'draft','draft_primary_seo_cluster_id':'ffc_research',
 'ledger_records_after':2,'ledger_known_after':2,'remaining_new_draft_candidates':31,
 'runner_mode':'canary','runner_limit':1,'idempotent_reconciliation':'PASS',
 'rollback_performed':False,'automatic_intake_enabled':False,
 'cms_write_attempted':False,'publish_at_created':False,'scheduled_queue_mutated':False,
 'publisher_invoked':False,'cron_mutated':False,'publication_queue_consumed':False
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

echo INCREMENTAL_INTAKE_RUNNER_CANARY=PASS
