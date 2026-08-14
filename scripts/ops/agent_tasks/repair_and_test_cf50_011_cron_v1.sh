#!/bin/bash
# Repair the proven CF50-011 cron launch regression, run one delayed production canary,
# and restore recurring polling only after end-to-end validation passes.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CRON="/etc/cron.d/xyptdq-publisher"
SOURCE="/var/lib/xyptdq-content/CF50-20260813-wave1/scheduled"
STATE="/var/lib/xyptdq-publisher/CF50-20260813-wave1/state.json"
LOCK="/var/lib/xyptdq-publisher/CF50-20260813-wave1/publisher.lock"
LOG_DIR="/var/log/xyptdq-publisher"
RECEIPT_DIR="/var/lib/xyptdq-publisher/CF50-20260813-wave1/receipts"
VERIFY_DIR="/var/lib/xyptdq-publisher/CF50-20260813-wave1/seo-verification"
RUNNER="$REPO/scripts/content/run_scheduled_publish.sh"
INSTALLER="$REPO/scripts/content/install_publisher_cron.sh"
EXPECTED_ARTICLE_ID="LCM-CREATOR-cf50-20260813-011"
LEGACY="$REPO/content/scheduled"

[ -n "$RESULT_FILE" ] || exit 2
[ "$(id -u)" -eq 0 ] || exit 3

SUCCESS=0
PHASE="preflight"
DETAIL=""
TARGET_KEY=""
TARGET_PUBLISH_AT=""
CMS_ID=""
PUBLISHED_URL=""
NEW_LOG=""
NEXT_ARTICLE_ID=""
NEXT_PUBLISH_AT=""

json_count() {
  find "$1" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l
}

state_metrics() {
  python3 - "$STATE" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1])
if not p.exists():
    print("0|0|0|0")
    raise SystemExit
x=json.loads(p.read_text(encoding="utf-8"))
a=x.get("articles",{})
vals=list(a.values()) if isinstance(a,dict) else []
pub=sum(1 for v in vals if isinstance(v,dict) and v.get("status")=="published")
sched=sum(1 for v in vals if isinstance(v,dict) and v.get("status")=="scheduled")
failed=sum(1 for v in vals if isinstance(v,dict) and v.get("status")=="failed")
print(f"{len(vals)}|{pub}|{sched}|{failed}")
PY
}

write_result() {
  local status="$1"
  local legacy_count source_count state_exists cron_exists metrics
  legacy_count=$(json_count "$LEGACY")
  source_count=$(json_count "$SOURCE")
  state_exists=false; [ -f "$STATE" ] && state_exists=true
  cron_exists=false; [ -f "$CRON" ] && cron_exists=true
  metrics=$(state_metrics 2>/dev/null || printf '0|0|0|0')
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$DETAIL" "$legacy_count" "$source_count" "$state_exists" "$cron_exists" "$metrics" "$TARGET_KEY" "$TARGET_PUBLISH_AT" "$CMS_ID" "$PUBLISHED_URL" "$NEW_LOG" "$NEXT_ARTICLE_ID" "$NEXT_PUBLISH_AT" <<'PY'
import json, sys
from datetime import datetime, timezone
(out,status,phase,detail,legacy_count,source_count,state_exists,cron_exists,metrics,
 target_key,target_publish_at,cms_id,published_url,new_log,next_article_id,next_publish_at)=sys.argv[1:]
total,published,scheduled,failed=(int(x) for x in metrics.split("|"))
payload={
  "task":"repair_and_test_cf50_011_cron_v1",
  "status":status,
  "phase":phase,
  "detail":detail,
  "root_cause":"cron directly executed a non-executable checkout of run_scheduled_publish.sh (mode 0600)",
  "durable_fix":"cron invokes run_scheduled_publish.sh through /bin/bash",
  "test_delay_seconds":10,
  "target_article_id":"LCM-CREATOR-cf50-20260813-011",
  "target_article_key":target_key or None,
  "target_publish_at":target_publish_at or None,
  "cms_id":int(cms_id) if cms_id.isdigit() else None,
  "published_url":published_url or None,
  "new_runtime_log":new_log or None,
  "legacy_repository_scheduled_count":int(legacy_count),
  "isolated_source_file_count":int(source_count),
  "state_exists":state_exists=="true",
  "state_article_count":total,
  "state_published_count":published,
  "state_scheduled_count":scheduled,
  "state_failed_count":failed,
  "remaining_unpublished_count":scheduled+failed,
  "cron_installed_after_test":cron_exists=="true",
  "cron_poll_schedule":"7 * * * *",
  "editorial_timezone":"Asia/Singapore",
  "editorial_slots":["10:00","19:00"],
  "next_article_id":next_article_id or None,
  "next_publish_at":next_publish_at or None,
  "queue_semantics_note":"scheduled JSON files are retained for idempotency; 11->10 means remaining unpublished state, not physical file deletion",
  "checked_at":datetime.now(timezone.utc).isoformat(),
}
with open(out,"w",encoding="utf-8") as fh:
    json.dump(payload,fh,ensure_ascii=False,indent=2,sort_keys=True)
    fh.write("\n")
PY
}

fail() {
  PHASE="$1"
  DETAIL="$2"
  rm -f "$CRON" 2>/dev/null || true
  systemctl reload cron >/dev/null 2>&1 || true
  write_result "FAIL"
  echo "CF50_011_REPAIR_TEST=FAIL phase=$PHASE" >&2
  exit 20
}

on_exit() {
  if [ "$SUCCESS" -ne 1 ]; then
    rm -f "$CRON" 2>/dev/null || true
    systemctl reload cron >/dev/null 2>&1 || true
  fi
}
trap on_exit EXIT

# Canonical clone must be clean before controlled synchronization.
[ -d "$REPO/.git" ] || fail "repo_sync" "canonical repo missing"
[ -z "$(git -C "$REPO" status --porcelain)" ] || fail "repo_sync" "canonical repo dirty"
git -C "$REPO" fetch --prune origin main >/dev/null 2>&1 || fail "repo_sync" "fetch main failed"
git -C "$REPO" checkout -q main || fail "repo_sync" "checkout main failed"
git -C "$REPO" reset --hard origin/main >/dev/null || fail "repo_sync" "reset to origin/main failed"

[ -s "$RUNNER" ] || fail "preflight" "publisher runner missing"
[ -s "$INSTALLER" ] || fail "preflight" "publisher cron installer missing"
grep -Fq '/bin/bash $RUNNER_Q' "$INSTALLER" || fail "preflight" "durable bash-invocation fix is not present in main"
[ -d "$SOURCE" ] || fail "preflight" "isolated Wave1 source missing"
[ "$(json_count "$SOURCE")" -eq 11 ] || fail "preflight" "isolated Wave1 source count is not 11"
[ "$(json_count "$LEGACY")" -eq 11 ] || fail "preflight" "historical repository Scheduled inventory changed"
[ ! -f "$STATE" ] || fail "preflight" "Wave1 state already exists; refusing ambiguous one-shot test"

TARGET_META=$(python3 - "$SOURCE" "$EXPECTED_ARTICLE_ID" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1]); expected=sys.argv[2]
hits=[]
for p in sorted(root.glob("*.json")):
    try:
        x=json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        continue
    if x.get("source_article_id")==expected:
        hits.append((p.name,str(x.get("article_key","")),str(x.get("publish_at",""))))
if len(hits)!=1:
    raise SystemExit(2)
name,key,publish_at=hits[0]
if not key or not publish_at:
    raise SystemExit(3)
print("|".join((name,key,publish_at)))
PY
) || fail "preflight" "could not resolve exactly one CF50-011 Scheduled record"
IFS='|' read -r TARGET_FILE TARGET_KEY TARGET_PUBLISH_AT <<<"$TARGET_META"
[ -n "$TARGET_KEY" ] || fail "preflight" "CF50-011 article_key missing"

python3 - "$TARGET_PUBLISH_AT" <<'PY' || fail "preflight" "CF50-011 is not yet due"
from datetime import datetime, timezone
import sys
s=sys.argv[1]
dt=datetime.fromisoformat(s.replace("Z","+00:00"))
now=datetime.now(timezone.utc)
if dt.astimezone(timezone.utc) > now:
    raise SystemExit(1)
PY

# Disable the recurring cron before the one-shot test. Failure paths keep it disabled.
PHASE="disable_cron"
rm -f "$CRON"
systemctl reload cron >/dev/null 2>&1 || fail "disable_cron" "cron reload failed after disabling Publisher"
[ ! -e "$CRON" ] || fail "disable_cron" "Publisher cron still exists after disable"
systemctl is-active --quiet cron || fail "disable_cron" "cron daemon is not active"

# The user explicitly requested a short delayed production test after the repair.
PHASE="delay"
sleep 10

BEFORE_LOG_COUNT=$(find "$LOG_DIR" -maxdepth 1 -type f -name 'run_*.log' 2>/dev/null | wc -l)

PHASE="publish_011"
XYPTDQ_PUBLISH_SOURCE="$SOURCE" \
XYPTDQ_PUBLISH_STATE="$STATE" \
XYPTDQ_PUBLISH_LOCK="$LOCK" \
XYPTDQ_PUBLISH_LIMIT=1 \
XYPTDQ_REPO_DIR="$REPO" \
XYPTDQ_WEBROOT="$WEBROOT" \
  /bin/bash "$RUNNER" || fail "publish_011" "one-shot Publisher invocation failed"

AFTER_LOG_COUNT=$(find "$LOG_DIR" -maxdepth 1 -type f -name 'run_*.log' 2>/dev/null | wc -l)
[ "$AFTER_LOG_COUNT" -eq $((BEFORE_LOG_COUNT + 1)) ] || fail "post_publish" "expected exactly one new Publisher runtime log"
NEW_LOG=$(find "$LOG_DIR" -maxdepth 1 -type f -name 'run_*.log' -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)
[ -s "$NEW_LOG" ] || fail "post_publish" "new Publisher runtime log missing"

[ -f "$STATE" ] || fail "post_publish" "Wave1 state was not created"
METRICS=$(state_metrics)
IFS='|' read -r STATE_TOTAL STATE_PUBLISHED STATE_SCHEDULED STATE_FAILED <<<"$METRICS"
[ "$STATE_TOTAL" -eq 11 ] || fail "post_publish" "state does not cover all 11 Wave1 articles"
[ "$STATE_PUBLISHED" -eq 1 ] || fail "post_publish" "one-shot test did not publish exactly one article"
[ "$STATE_SCHEDULED" -eq 10 ] || fail "post_publish" "remaining unpublished count is not 10"
[ "$STATE_FAILED" -eq 0 ] || fail "post_publish" "Wave1 state contains failed articles"

STATE_TARGET=$(python3 - "$STATE" "$TARGET_KEY" <<'PY'
import json, sys
x=json.load(open(sys.argv[1],encoding="utf-8"))
e=x.get("articles",{}).get(sys.argv[2],{})
print(f"{e.get('status','')}|{e.get('cms_id','')}")
PY
)
IFS='|' read -r TARGET_STATUS CMS_ID <<<"$STATE_TARGET"
[ "$TARGET_STATUS" = "published" ] || fail "post_publish" "the single publication was not CF50-011"
[[ "$CMS_ID" =~ ^[0-9]+$ ]] && [ "$CMS_ID" -gt 0 ] || fail "post_publish" "CF50-011 cms_id missing"

grep -Fq "[filequeue] PUBLISHED key=$TARGET_KEY cms_id=$CMS_ID" "$NEW_LOG" || fail "post_publish" "runtime log lacks CF50-011 PUBLISHED evidence"
grep -Fq "[scheduled-publish] SEO_VERIFY_PASS key=$TARGET_KEY cms_id=$CMS_ID" "$NEW_LOG" || fail "live_seo" "CF50-011 live SEO verification did not PASS"
grep -Fq 'seo_verification=PASS' "$NEW_LOG" || fail "live_seo" "Publisher aggregate SEO status is not PASS"
grep -Fq 'result=PASS' "$NEW_LOG" || fail "post_publish" "Publisher runtime result is not PASS"

RECEIPT=$(find "$RECEIPT_DIR" -maxdepth 1 -type f -name "${TARGET_KEY}.${CMS_ID}.json" -print -quit)
[ -s "$RECEIPT" ] || fail "receipt" "CF50-011 publication receipt missing"
PUBLISHED_URL=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (string)($x["published_url"]??"");' "$RECEIPT")
[ -n "$PUBLISHED_URL" ] || fail "receipt" "CF50-011 published_url missing"
VERIFY_FILE="$VERIFY_DIR/${TARGET_KEY}.${CMS_ID}.json"
[ -s "$VERIFY_FILE" ] || fail "live_seo" "CF50-011 SEO verification artifact missing"

[ "$(json_count "$SOURCE")" -eq 11 ] || fail "postflight" "isolated Scheduled files were unexpectedly deleted or added"
[ "$(json_count "$LEGACY")" -eq 11 ] || fail "postflight" "historical repository Scheduled inventory was consumed"

# Identify the next not-yet-published Wave1 item before re-enabling polling.
NEXT_META=$(python3 - "$SOURCE" "$STATE" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])
state=json.load(open(sys.argv[2],encoding="utf-8")).get("articles",{})
rows=[]
for p in root.glob("*.json"):
    x=json.loads(p.read_text(encoding="utf-8"))
    key=str(x.get("article_key",""))
    if state.get(key,{}).get("status")=="published":
        continue
    rows.append((str(x.get("publish_at","")),str(x.get("source_article_id",""))))
rows.sort()
if rows:
    print(rows[0][1]+"|"+rows[0][0])
PY
)
IFS='|' read -r NEXT_ARTICLE_ID NEXT_PUBLISH_AT <<<"$NEXT_META"

# Restore recurring polling only after the one-shot publish + SEO checks are all green.
PHASE="restore_recurring"
XYPTDQ_PUBLISH_SOURCE="$SOURCE" \
XYPTDQ_PUBLISH_STATE="$STATE" \
XYPTDQ_PUBLISH_LOCK="$LOCK" \
XYPTDQ_REPO_DIR="$REPO" \
  /bin/bash "$INSTALLER" || fail "restore_recurring" "fixed Publisher cron installer failed"

[ -s "$CRON" ] || fail "restore_recurring" "Publisher cron was not restored"
[ "$(stat -c '%a:%u:%g' "$CRON")" = "644:0:0" ] || fail "restore_recurring" "Publisher cron owner/mode invalid"
grep -Eq '^7 \* \* \* \* root ' "$CRON" || fail "restore_recurring" "Publisher cron polling schedule invalid"
grep -Fq "XYPTDQ_PUBLISH_SOURCE=$SOURCE" "$CRON" || fail "restore_recurring" "Publisher cron source binding invalid"
grep -Fq "XYPTDQ_PUBLISH_STATE=$STATE" "$CRON" || fail "restore_recurring" "Publisher cron state binding invalid"
grep -Fq "XYPTDQ_PUBLISH_LOCK=$LOCK" "$CRON" || fail "restore_recurring" "Publisher cron lock binding invalid"
grep -Eq '/bin/bash .*/scripts/content/run_scheduled_publish\.sh' "$CRON" || fail "restore_recurring" "Publisher cron does not use durable /bin/bash invocation"
systemctl reload cron >/dev/null 2>&1 || fail "restore_recurring" "cron reload failed after restore"
systemctl is-active --quiet cron || fail "restore_recurring" "cron daemon inactive after restore"

PHASE="complete"
DETAIL="CF50-011 published after 10-second delayed one-shot test, live SEO passed, and recurring Publisher polling restored with durable bash invocation"
SUCCESS=1
write_result "PASS"
echo "CF50_011_REPAIR_TEST=PASS cms_id=$CMS_ID url=$PUBLISHED_URL remaining=10"
