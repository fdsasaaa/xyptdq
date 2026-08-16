#!/bin/bash
# First durable intake canary: one formal public-r1 -> isolated Draft + intake ledger.
# No publish_at, Scheduled queue, CMS, Publisher or cron mutation is allowed.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
INTAKE_ROOT="${XYPTDQ_INTAKE_ROOT:-/var/lib/xyptdq-content/intake}"
SOURCE_DIR="$INTAKE_ROOT/source/caipiaowenzhang"
KEY_FILE="$INTAKE_ROOT/credentials/caipiaowenzhang_readonly_ed25519"
KNOWN_HOSTS="$INTAKE_ROOT/credentials/github_known_hosts"
LEDGER="$INTAKE_ROOT/state.json"
DRAFT_DIR="$INTAKE_ROOT/drafts"
REMOTE="git@github.com:fdsasaaa/caipiaowenzhang.git"
CANARY_ID="LCM-CREATOR-cf50-20260813-003"
CANARY_REV="$CANARY_ID:public-r1"
REVISION="$SOURCE_DIR/articles/public_release/CF50-20260813/$CANARY_ID.public-r1.json"
PARENT="$SOURCE_DIR/articles/approved/$CANARY_ID.json"
MANIFEST="$SOURCE_DIR/articles/public_release/manifests/CF50-20260813.json"
EDITORIAL_MAP="$REPO/content/seo_editorial_cluster_map_cf50.json"
DRAFT="$DRAFT_DIR/$CANARY_ID.public-r1.draft.json"
[ -n "$RESULT_FILE" ] || exit 2

TMP=$(mktemp -d /tmp/xyptdq-intake-canary.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$DRAFT_DIR"
chmod 0750 "$DRAFT_DIR"
LEDGER_EXISTED=false
DRAFT_EXISTED=false
[ -e "$LEDGER" ] && LEDGER_EXISTED=true
[ -e "$DRAFT" ] && DRAFT_EXISTED=true

write_fail() {
  local phase="$1" detail="$2" rollback="${3:-false}"
  python3 - "$RESULT_FILE" "$phase" "$detail" "$rollback" <<'PY'
import json,sys
out,phase,detail,rollback=sys.argv[1:]
p={
 'task':'canary_article_repo_draft_ledger_v1','status':'FAIL','phase':phase,'detail':detail,
 'canary_article_id':'LCM-CREATOR-cf50-20260813-003','canary_revision_id':'LCM-CREATOR-cf50-20260813-003:public-r1',
 'rollback_performed':rollback=='true','automatic_intake_enabled':False,
 'cms_write_attempted':False,'publish_at_created':False,'scheduled_queue_mutated':False,
 'publisher_invoked':False,'cron_mutated':False,'publication_queue_consumed':False
}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
  echo "ARTICLE_REPO_DRAFT_LEDGER_CANARY=FAIL phase=$phase" >&2
  exit 20
}

rollback_runtime() {
  local changed=false
  if [ "$DRAFT_EXISTED" = false ] && [ -e "$DRAFT" ]; then rm -f "$DRAFT"; changed=true; fi
  if [ "$LEDGER_EXISTED" = false ] && [ -e "$LEDGER" ]; then rm -f "$LEDGER"; changed=true; fi
  if [ "$LEDGER_EXISTED" = true ] && [ -s "$TMP/ledger.before" ]; then cp "$TMP/ledger.before" "$LEDGER"; chmod 0640 "$LEDGER"; changed=true; fi
  echo "$changed"
}

[ -d "$REPO/.git" ] || write_fail repo_sync "canonical website repo missing"
[ -z "$(git -C "$REPO" status --porcelain)" ] || write_fail repo_sync "canonical website repo dirty"
git -C "$REPO" fetch --prune origin main >/dev/null 2>&1 || write_fail repo_sync "website main fetch failed"
git -C "$REPO" checkout -q main || write_fail repo_sync "website main checkout failed"
git -C "$REPO" reset --hard origin/main >/dev/null || write_fail repo_sync "website main reset failed"

[ -s "$KEY_FILE" ] && [ -s "$KNOWN_HOSTS" ] || write_fail transport_preflight "read-only SSH credential/known_hosts missing"
[ -d "$SOURCE_DIR/.git" ] || write_fail transport_preflight "dedicated source cache missing; SSH proof must run first"
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -i $KEY_FILE -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$KNOWN_HOSTS -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no"
REMOTE_HEAD=$(git ls-remote "$REMOTE" refs/heads/main 2>"$TMP/lsremote.err" | awk '$2=="refs/heads/main"{print $1}') || write_fail transport_preflight "private source main ls-remote failed"
printf '%s' "$REMOTE_HEAD" | grep -Eq '^[0-9a-f]{40}$' || write_fail transport_preflight "private source main SHA missing"
[ -z "$(git -C "$SOURCE_DIR" status --porcelain)" ] || write_fail source_cache "dedicated source cache is dirty"
git -C "$SOURCE_DIR" fetch -q --prune origin main 2>"$TMP/fetch.err" || write_fail source_sync "private source fetch failed"
git -C "$SOURCE_DIR" checkout -q main || write_fail source_sync "private source main checkout failed"
git -C "$SOURCE_DIR" reset --hard origin/main >/dev/null || write_fail source_sync "private source reset failed"
SOURCE_HEAD=$(git -C "$SOURCE_DIR" rev-parse HEAD)
[ "$SOURCE_HEAD" = "$REMOTE_HEAD" ] || write_fail source_sync "private source checkout is not current main"

[ -s "$REVISION" ] && [ -s "$PARENT" ] && [ -s "$MANIFEST" ] && [ -s "$EDITORIAL_MAP" ] || write_fail package_preflight "canary source package or editorial map missing"
if [ "$DRAFT_EXISTED" = true ]; then write_fail runtime_preflight "canary Draft already exists; refusing overwrite"; fi
if [ "$LEDGER_EXISTED" = true ]; then
  cp "$LEDGER" "$TMP/ledger.before"
  PRE_RECORDS=$(python3 - "$LEDGER" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8')); r=x.get('records') or {}; print(len(r) if isinstance(r,dict) else -1)
PY
)
  [ "$PRE_RECORDS" = 0 ] || write_fail runtime_preflight "intake ledger is not empty before first canary"
fi

python3 "$REPO/scripts/content/inventory_diff.py" --source-repo="$SOURCE_DIR" --website-repo="$REPO" --ledger="$LEDGER" --output="$TMP/before.json" 2>"$TMP/before.err" || write_fail inventory_before "inventory diff before canary failed"
python3 - "$TMP/before.json" "$CANARY_REV" <<'PY' || write_fail inventory_before "pre-canary inventory assertions failed"
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8')); canary=sys.argv[2]
assert x.get('status')=='PASS'
assert x.get('A_upstream_official_ready')==45
assert x.get('website_ingress_known')==12
assert x.get('ledger_known')==0
assert x.get('new_draft_candidates')==33
assert canary in (x.get('candidate_revision_ids') or [])
assert x.get('cf50_final5_release_authorized') is False
PY

php "$REPO/scripts/content/ingest_public_release_canary.php" \
  --revision="$REVISION" --parent="$PARENT" --manifest="$MANIFEST" \
  --editorial-cluster-map="$EDITORIAL_MAP" --output="$DRAFT" >"$TMP/canary.out" 2>"$TMP/canary.err" || {
    rb=$(rollback_runtime); write_fail draft_canary "public-r1 Draft canary failed" "$rb";
  }
chmod 0640 "$DRAFT"

python3 - "$REVISION" "$DRAFT" "$SOURCE_HEAD" "$LEDGER" <<'PY' || {
import sys; raise SystemExit(1)
PY
import json,os,sys,tempfile,datetime
rev=json.load(open(sys.argv[1],encoding='utf-8')); draft=json.load(open(sys.argv[2],encoding='utf-8'))
source_commit=sys.argv[3]; ledger_path=sys.argv[4]
if draft.get('publication_state')!='draft': raise SystemExit('Draft publication_state is not draft')
if 'publish_at' in draft: raise SystemExit('Draft unexpectedly contains publish_at')
if draft.get('source_article_id')!=rev.get('article_id'): raise SystemExit('Draft source article mismatch')
if draft.get('source_revision_id')!=rev.get('revision_id'): raise SystemExit('Draft source revision mismatch')
if draft.get('source_content_hash')!=rev.get('content_hash'): raise SystemExit('Draft source hash mismatch')
if draft.get('source_fingerprint')!=rev.get('fingerprint'): raise SystemExit('Draft source fingerprint mismatch')
if draft.get('primary_seo_cluster_id')!='ffc_research': raise SystemExit('Draft primary SEO cluster mismatch')
record={
 'article_id':rev['article_id'],'revision_id':rev['revision_id'],'content_hash':rev['content_hash'],
 'fingerprint':rev['fingerprint'],'primary_keyword':rev['primary_keyword'],'slug':rev['slug'],
 'site_category_key':rev['site_category_key'],'source_batch_id':rev['source_batch_id'],
 'source_commit':source_commit,'lifecycle_state':'draft','cms_id':None,'scheduled_at':None,'published_at':None,
 'draft_path':sys.argv[2],'ingested_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
ledger={'schema_version':1,'source_repository':'fdsasaaa/caipiaowenzhang','source_ref':'main','updated_at':record['ingested_at'],'records':{rev['revision_id']:record}}
os.makedirs(os.path.dirname(ledger_path),exist_ok=True)
fd,tmp=tempfile.mkstemp(prefix=os.path.basename(ledger_path)+'.tmp.',dir=os.path.dirname(ledger_path)); os.close(fd)
try:
    with open(tmp,'w',encoding='utf-8') as f: json.dump(ledger,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
    os.chmod(tmp,0o640); os.replace(tmp,ledger_path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
if [ "$?" -ne 0 ]; then rb=$(rollback_runtime); write_fail ledger_write "Draft validation or ledger write failed" "$rb"; fi

python3 "$REPO/scripts/content/inventory_diff.py" --source-repo="$SOURCE_DIR" --website-repo="$REPO" --ledger="$LEDGER" --output="$TMP/after.json" 2>"$TMP/after.err" || {
  rb=$(rollback_runtime); write_fail inventory_after "inventory diff after canary failed" "$rb";
}
python3 - "$TMP/after.json" "$CANARY_REV" <<'PY' || {
import sys; raise SystemExit(1)
PY
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8')); canary=sys.argv[2]
assert x.get('status')=='PASS'
assert x.get('A_upstream_official_ready')==45
assert x.get('website_ingress_known')==12
assert x.get('ledger_known')==1
assert x.get('new_draft_candidates')==32
assert canary not in (x.get('candidate_revision_ids') or [])
PY
if [ "$?" -ne 0 ]; then rb=$(rollback_runtime); write_fail inventory_after "post-canary idempotency assertions failed" "$rb"; fi

python3 - "$RESULT_FILE" "$SOURCE_HEAD" "$DRAFT" "$LEDGER" "$TMP/after.json" <<'PY'
import json,sys
out,source,draft,ledger,after_path=sys.argv[1:]
after=json.load(open(after_path,encoding='utf-8'))
p={
 'task':'canary_article_repo_draft_ledger_v1','status':'PASS','phase':'complete',
 'detail':'one unsynced formal public-r1 was validated into isolated Draft and durable ledger; reconciliation then excluded it idempotently',
 'source_repository':'fdsasaaa/caipiaowenzhang','source_ref':'main','source_commit':source,
 'canary_article_id':'LCM-CREATOR-cf50-20260813-003','canary_revision_id':'LCM-CREATOR-cf50-20260813-003:public-r1',
 'draft_path':draft,'draft_publication_state':'draft','draft_primary_seo_cluster_id':'ffc_research',
 'ledger_path':ledger,'ledger_records':1,'A_upstream_official_ready':after.get('A_upstream_official_ready'),
 'website_ingress_known':after.get('website_ingress_known'),'ledger_known_after':after.get('ledger_known'),
 'remaining_new_draft_candidates':after.get('new_draft_candidates'),
 'idempotent_reconciliation':'PASS','rollback_performed':False,'automatic_intake_enabled':False,
 'cms_write_attempted':False,'publish_at_created':False,'scheduled_queue_mutated':False,
 'publisher_invoked':False,'cron_mutated':False,'publication_queue_consumed':False
}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

echo ARTICLE_REPO_DRAFT_LEDGER_CANARY=PASS
