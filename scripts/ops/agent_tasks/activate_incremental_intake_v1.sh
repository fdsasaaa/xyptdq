#!/bin/bash
# Final activation gate for unattended Draft-only intake.
# Requires the generic runner canary (004) to have left ledger=2/candidates=31.
# Performs one real auto-mode intake (005), verifies ledger=3/candidates=30, then installs exactly one :23 cron.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
INTAKE_ROOT="${XYPTDQ_INTAKE_ROOT:-/var/lib/xyptdq-content/intake}"
SOURCE_DIR="$INTAKE_ROOT/source/caipiaowenzhang"
LEDGER="$INTAKE_ROOT/state.json"
DRAFT_DIR="$INTAKE_ROOT/drafts"
CRON_FILE="${XYPTDQ_INTAKE_CRON_FILE:-/etc/cron.d/xyptdq-intake}"
EXPECTED_ID="LCM-CREATOR-cf50-20260813-005"
EXPECTED_REV="$EXPECTED_ID:public-r1"
EXPECTED_DRAFT="$DRAFT_DIR/LCM-CREATOR-cf50-20260813-005_public-r1.draft.json"
[ -n "$RESULT_FILE" ] || exit 2

TMP=$(mktemp -d /tmp/xyptdq-intake-activate.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
[ -s "$LEDGER" ] || exit 3
cp "$LEDGER" "$TMP/ledger.before"
DRAFT_EXISTED=false
CRON_EXISTED=false
[ -e "$EXPECTED_DRAFT" ] && DRAFT_EXISTED=true
[ -e "$CRON_FILE" ] && { CRON_EXISTED=true; cp "$CRON_FILE" "$TMP/cron.before"; }

write_fail() {
  local phase="$1" detail="$2" rollback="$3"
  python3 - "$RESULT_FILE" "$phase" "$detail" "$rollback" <<'PY'
import json,sys
out,phase,detail,rollback=sys.argv[1:]
p={
 'task':'activate_incremental_intake_v1','status':'FAIL','phase':phase,'detail':detail,
 'activation_article_id':'LCM-CREATOR-cf50-20260813-005','activation_revision_id':'LCM-CREATOR-cf50-20260813-005:public-r1',
 'rollback_performed':rollback=='true','automatic_intake_cron_installed':False,
 'cms_write_attempted':False,'publish_at_created':False,'scheduled_queue_mutated':False,
 'publisher_invoked':False,'publisher_cron_mutated':False,'publication_queue_consumed':False
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}

rollback_activation() {
  local changed=false
  cp "$TMP/ledger.before" "$LEDGER" && chmod 0640 "$LEDGER" && changed=true
  if [ "$DRAFT_EXISTED" = false ] && [ -e "$EXPECTED_DRAFT" ]; then rm -f "$EXPECTED_DRAFT"; changed=true; fi
  if [ "$CRON_EXISTED" = true ] && [ -s "$TMP/cron.before" ]; then
    cp "$TMP/cron.before" "$CRON_FILE"; chmod 0644 "$CRON_FILE"; chown root:root "$CRON_FILE"; changed=true
  elif [ "$CRON_EXISTED" = false ] && [ -e "$CRON_FILE" ]; then
    rm -f "$CRON_FILE"; changed=true
  fi
  echo "$changed"
}

fail() {
  local phase="$1" detail="$2" rb=false
  if [ -s "$TMP/ledger.before" ]; then rb=$(rollback_activation || echo true); fi
  write_fail "$phase" "$detail" "$rb"
  echo "INCREMENTAL_INTAKE_ACTIVATION=FAIL phase=$phase" >&2
  exit 20
}

[ -d "$REPO/.git" ] || fail repo_sync "canonical website repo missing"
[ -z "$(git -C "$REPO" status --porcelain)" ] || fail repo_sync "canonical website repo dirty"
git -C "$REPO" fetch --prune origin main >/dev/null 2>&1 || fail repo_sync "website main fetch failed"
git -C "$REPO" checkout -q main || fail repo_sync "website main checkout failed"
git -C "$REPO" reset --hard origin/main >/dev/null || fail repo_sync "website main reset failed"

POLICY_OK=$(python3 - "$REPO/config/content_inventory_policy.json" "$REPO/config/content_source_sync_policy.json" <<'PY'
import json,sys
a=json.load(open(sys.argv[1],encoding='utf-8')); b=json.load(open(sys.argv[2],encoding='utf-8'))
print('yes' if (a.get('activation') or {}).get('automatic_intake_enabled') is True and b.get('sync_enabled') is True else 'no')
PY
)
[ "$POLICY_OK" = yes ] || fail policy_preflight "automatic intake policies are not enabled"

# Activation requires no pre-existing managed or unmanaged intake cron.
COUNT_BEFORE=$(grep -R -h -F 'run_incremental_inventory_intake.sh' /etc/cron.d /etc/crontab 2>/dev/null | grep -v '^#' | wc -l | tr -d ' ')
[ "$COUNT_BEFORE" = 0 ] || fail cron_preflight "intake cron already exists before first activation"
[ "$DRAFT_EXISTED" = false ] || fail runtime_preflight "005 activation Draft already exists"

python3 "$REPO/scripts/content/inventory_diff.py" --source-repo="$SOURCE_DIR" --website-repo="$REPO" --ledger="$LEDGER" --output="$TMP/before.json" 2>"$TMP/before.err" || fail inventory_before "pre-activation inventory diff failed"
if ! python3 - "$TMP/before.json" "$EXPECTED_REV" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8')); rev=sys.argv[2]
assert x.get('status')=='PASS'
assert x.get('A_upstream_official_ready')==45
assert x.get('website_ingress_known')==12
assert x.get('ledger_known')==2
assert x.get('new_draft_candidates')==31
ids=x.get('candidate_revision_ids') or []
assert ids and ids[0]==rev
PY
then
  fail inventory_before "pre-activation watermarks or expected 005 candidate mismatch"
fi

if ! XYPTDQ_INTAKE_MODE=auto XYPTDQ_INTAKE_LIMIT=1 /bin/bash "$REPO/scripts/content/run_incremental_inventory_intake.sh" >"$TMP/auto.out" 2>"$TMP/auto.err"; then
  fail auto_runner "auto-mode one-shot returned nonzero"
fi

[ -s "$EXPECTED_DRAFT" ] || fail draft_verify "005 Draft missing after auto-mode one-shot"
if ! python3 - "$EXPECTED_DRAFT" "$LEDGER" "$EXPECTED_REV" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8')); l=json.load(open(sys.argv[2],encoding='utf-8')); rev=sys.argv[3]
assert d.get('publication_state')=='draft'
assert 'publish_at' not in d
assert d.get('source_revision_id')==rev
assert d.get('source_article_id')=='LCM-CREATOR-cf50-20260813-005'
assert d.get('primary_seo_cluster_id')=='ffc_research'
r=(l.get('records') or {}).get(rev)
assert len(l.get('records') or {})==3 and isinstance(r,dict)
assert r.get('lifecycle_state')=='draft'
assert r.get('cms_id') is None and r.get('scheduled_at') is None and r.get('published_at') is None
PY
then
  fail draft_verify "005 Draft/ledger verification failed"
fi

python3 "$REPO/scripts/content/inventory_diff.py" --source-repo="$SOURCE_DIR" --website-repo="$REPO" --ledger="$LEDGER" --output="$TMP/after.json" 2>"$TMP/after.err" || fail inventory_after "post-auto inventory diff failed"
if ! python3 - "$TMP/after.json" "$EXPECTED_REV" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8')); rev=sys.argv[2]
assert x.get('status')=='PASS'
assert x.get('A_upstream_official_ready')==45
assert x.get('website_ingress_known')==12
assert x.get('ledger_known')==3
assert x.get('new_draft_candidates')==30
assert rev not in (x.get('candidate_revision_ids') or [])
PY
then
  fail inventory_after "post-auto idempotent reconciliation failed"
fi

/bin/bash "$REPO/scripts/content/install_incremental_intake_cron.sh" >"$TMP/install.out" 2>"$TMP/install.err" || fail cron_install "intake cron installation failed"
COUNT_AFTER=$(grep -R -h -F 'run_incremental_inventory_intake.sh' /etc/cron.d /etc/crontab 2>/dev/null | grep -v '^#' | wc -l | tr -d ' ')
[ "$COUNT_AFTER" = 1 ] || fail cron_verify "expected exactly one intake cron after activation"
[ -s "$CRON_FILE" ] || fail cron_verify "managed intake cron file missing"
grep -Fq '23 * * * * root XYPTDQ_INTAKE_MODE=auto XYPTDQ_INTAKE_LIMIT=25' "$CRON_FILE" || fail cron_verify "managed intake cron schedule mismatch"

SOURCE_HEAD=$(git -C "$SOURCE_DIR" rev-parse HEAD)
python3 - "$RESULT_FILE" "$SOURCE_HEAD" "$CRON_FILE" <<'PY'
import json,sys
out,source,cron=sys.argv[1:]
p={
 'task':'activate_incremental_intake_v1','status':'PASS','phase':'complete',
 'detail':'auto-mode one-shot committed exactly 005 as Draft, reconciliation passed, then exactly one isolated Draft intake cron was installed',
 'source_repository':'fdsasaaa/caipiaowenzhang','source_ref':'main','source_commit':source,
 'activation_article_id':'LCM-CREATOR-cf50-20260813-005','activation_revision_id':'LCM-CREATOR-cf50-20260813-005:public-r1',
 'draft_publication_state':'draft','draft_primary_seo_cluster_id':'ffc_research',
 'ledger_records_after':3,'ledger_known_after':3,'remaining_new_draft_candidates':30,
 'auto_mode_one_shot':'PASS','idempotent_reconciliation':'PASS',
 'automatic_intake_cron_installed':True,'intake_cron_file':cron,'intake_cron_count':1,
 'intake_cron_schedule':'23 * * * *','intake_limit_per_run':25,
 'rollback_performed':False,'cms_write_attempted':False,'publish_at_created':False,
 'scheduled_queue_mutated':False,'publisher_invoked':False,'publisher_cron_mutated':False,
 'publication_queue_consumed':False
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

echo INCREMENTAL_INTAKE_ACTIVATION=PASS
