#!/bin/bash
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO_DIR="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
ARTICLE_REPO_HTTPS="https://github.com/fdsasaaa/caipiaowenzhang.git"
ARTICLE_REPO_SSH="git@github.com:fdsasaaa/caipiaowenzhang.git"
BATCH_ID="CF50-20260813"
ARTICLE_ID="LCM-CREATOR-cf50-20260813-001"
REVISION_ID="LCM-CREATOR-cf50-20260813-001:public-r1"
RUNTIME_ROOT="/var/lib/xyptdq-content/$BATCH_ID"
DRAFT_DIR="$RUNTIME_ROOT/drafts"
SCHEDULED_DIR="$RUNTIME_ROOT/scheduled"
PUB_ROOT="/var/lib/xyptdq-publisher/$BATCH_ID"
STATE_PATH="$PUB_ROOT/state.json"
LOCK_PATH="$PUB_ROOT/publisher.lock"
RECEIPT_DIR="$PUB_ROOT/receipts"
DRAFT_PATH="$DRAFT_DIR/lcm-creator-cf50-20260813-001.json"
SCHEDULED_PATH="$SCHEDULED_DIR/lcm-creator-cf50-20260813-001.json"
RECEIPT_PATH="$RECEIPT_DIR/lcm-creator-cf50-20260813-001.json"

[ -n "$RESULT_FILE" ] || { echo "missing XYPTDQ_AGENT_RESULT_FILE" >&2; exit 2; }
[ -d "$REPO_DIR/.git" ] || { echo "website repo missing" >&2; exit 3; }

TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

write_result() {
  local status="$1" phase="$2" detail="$3" cms_id="${4:-}" published_url="${5:-}"
  python3 - "$RESULT_FILE" "$status" "$phase" "$detail" "$cms_id" "$published_url" <<'PY'
import json, sys
from datetime import datetime, timezone
out,status,phase,detail,cms_id,published_url=sys.argv[1:]
payload={
  "task":"publish_cf50_canary_001_v1",
  "batch_id":"CF50-20260813",
  "article_id":"LCM-CREATOR-cf50-20260813-001",
  "revision_id":"LCM-CREATOR-cf50-20260813-001:public-r1",
  "status":status,
  "phase":phase,
  "detail":detail,
  "cms_id":int(cms_id) if cms_id.isdigit() else None,
  "published_url":published_url or None,
  "publisher_cron_expected":0,
  "legacy_repository_queue_consumed":False,
  "recurring_cron_installed":False,
  "checked_at":datetime.now(timezone.utc).isoformat(),
}
with open(out,"w",encoding="utf-8") as fh:
  json.dump(payload,fh,ensure_ascii=False,indent=2,sort_keys=True)
  fh.write("\n")
PY
}

fail_phase() {
  local phase="$1" detail="$2"
  write_result "FAIL" "$phase" "$detail"
  echo "CF50_CANARY_001=FAIL phase=$phase" >&2
  exit 20
}

POLICY="$REPO_DIR/config/content_publication_policy.json"
[ -s "$POLICY" ] || fail_phase "preflight" "publication policy missing"
POLICY_CHECK=$(php -r '
$x=json_decode(file_get_contents($argv[1]),true);
if(!is_array($x)){exit(2);} 
$ok=(($x["publishing_enabled"]??false)===true)
 && (($x["mode"]??"")==="one_shot_public_release_canary")
 && ((int)($x["canary_execution_scope"]["max_articles"]??0)===1)
 && (($x["canary_execution_scope"]["required_article_id"]??"")==="LCM-CREATOR-cf50-20260813-001")
 && (($x["canary_execution_scope"]["required_revision_id"]??"")==="LCM-CREATOR-cf50-20260813-001:public-r1")
 && (($x["canary_execution_scope"]["recurring_cron_allowed"]??true)===false);
echo $ok?"PASS":"FAIL";
' "$POLICY") || fail_phase "preflight" "publication policy invalid"
[ "$POLICY_CHECK" = "PASS" ] || fail_phase "preflight" "one-shot canary policy gate not satisfied"

CRON_COUNT=$(( (crontab -l 2>/dev/null || true) | grep -F 'run_scheduled_publish.sh' | wc -l ))
[ "$CRON_COUNT" -eq 0 ] || fail_phase "preflight" "publisher cron must remain absent for canary"
LEGACY_COUNT=$(find "$REPO_DIR/content/scheduled" -maxdepth 1 -type f -name '*.json' | wc -l)
[ "$LEGACY_COUNT" -eq 11 ] || fail_phase "preflight" "legacy Scheduled inventory count changed"

mkdir -p "$DRAFT_DIR" "$SCHEDULED_DIR" "$PUB_ROOT" "$RECEIPT_DIR"
chmod 0750 "$RUNTIME_ROOT" "$DRAFT_DIR" "$SCHEDULED_DIR" "$PUB_ROOT" "$RECEIPT_DIR"
for p in "$DRAFT_DIR" "$SCHEDULED_DIR" "$PUB_ROOT"; do
  [ ! -L "$p" ] || fail_phase "preflight" "runtime path must not be a symlink"
done

ACCESS_MODE=""
REMOTE_URL=""
if GIT_TERMINAL_PROMPT=0 git ls-remote "$ARTICLE_REPO_HTTPS" refs/heads/main >"$TMP_DIR/https.out" 2>"$TMP_DIR/https.err"; then
  ACCESS_MODE="https_existing_credentials"
  REMOTE_URL="$ARTICLE_REPO_HTTPS"
elif GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=12 -o StrictHostKeyChecking=accept-new" git ls-remote "$ARTICLE_REPO_SSH" refs/heads/main >"$TMP_DIR/ssh.out" 2>"$TMP_DIR/ssh.err"; then
  ACCESS_MODE="ssh_existing_credentials"
  REMOTE_URL="$ARTICLE_REPO_SSH"
else
  fail_phase "source_access" "production host has no non-interactive read access to private article repository"
fi

export GIT_TERMINAL_PROMPT=0
if [ "$ACCESS_MODE" = "ssh_existing_credentials" ]; then
  export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=12 -o StrictHostKeyChecking=accept-new"
fi

git clone --depth 1 --filter=blob:none --no-checkout "$REMOTE_URL" "$TMP_DIR/article-repo" >"$TMP_DIR/clone.out" 2>"$TMP_DIR/clone.err" || fail_phase "source_access" "private article repository clone failed"
git -C "$TMP_DIR/article-repo" sparse-checkout init --cone >/dev/null 2>&1
git -C "$TMP_DIR/article-repo" sparse-checkout set articles/approved articles/public_release >/dev/null 2>&1
git -C "$TMP_DIR/article-repo" checkout main >/dev/null 2>&1

PARENT="$TMP_DIR/article-repo/articles/approved/$ARTICLE_ID.json"
REVISION="$TMP_DIR/article-repo/articles/public_release/$BATCH_ID/$ARTICLE_ID.public-r1.json"
MANIFEST="$TMP_DIR/article-repo/articles/public_release/manifests/$BATCH_ID.json"
MAP="$REPO_DIR/content/seo_editorial_cluster_map_cf50.json"
[ -s "$PARENT" ] && [ -s "$REVISION" ] && [ -s "$MANIFEST" ] && [ -s "$MAP" ] || fail_phase "source_validation" "required parent/revision/manifest/editorial map missing"

rm -f "$DRAFT_PATH" "$SCHEDULED_PATH" "$RECEIPT_PATH"
php "$REPO_DIR/scripts/content/ingest_public_release_canary.php" \
  --revision="$REVISION" \
  --parent="$PARENT" \
  --manifest="$MANIFEST" \
  --editorial-cluster-map="$MAP" \
  --output="$DRAFT_PATH" >"$TMP_DIR/intake.out" 2>"$TMP_DIR/intake.err" || fail_phase "draft_intake" "public-release validation or Draft conversion failed"

DRAFT_CHECK=$(php -r '
$x=json_decode(file_get_contents($argv[1]),true);
$ok=is_array($x)
 && (($x["publication_state"]??"")==="draft")
 && (($x["source_article_id"]??"")==="LCM-CREATOR-cf50-20260813-001")
 && (($x["source_revision_id"]??"")==="LCM-CREATOR-cf50-20260813-001:public-r1")
 && (($x["site_category_key"]??"")==="tzjq")
 && ((int)($x["catid"]??0)===3)
 && (($x["primary_seo_cluster_id"]??"")==="ffc_research")
 && !array_key_exists("publish_at",$x);
echo $ok?"PASS":"FAIL";
' "$DRAFT_PATH") || fail_phase "draft_intake" "generated Draft is invalid"
[ "$DRAFT_CHECK" = "PASS" ] || fail_phase "draft_intake" "generated Draft failed identity/category/cluster checks"

PUBLISH_AT=$(date -u '+%Y-%m-%dT%H:%M:%S+00:00')
php "$REPO_DIR/scripts/content/promote_draft.php" --input="$DRAFT_PATH" --publish-at="$PUBLISH_AT" --output="$SCHEDULED_PATH" >"$TMP_DIR/promote.out" 2>"$TMP_DIR/promote.err" || fail_phase "schedule" "Draft promotion failed"
[ "$(find "$SCHEDULED_DIR" -maxdepth 1 -type f -name '*.json' | wc -l)" -eq 1 ] || fail_phase "schedule" "isolated canary Scheduled queue must contain exactly one article"

XYPTDQ_PUBLISH_SOURCE="$SCHEDULED_DIR" \
XYPTDQ_PUBLISH_STATE="$STATE_PATH" \
XYPTDQ_PUBLISH_LOCK="$LOCK_PATH" \
XYPTDQ_PUBLISH_LIMIT=1 \
XYPTDQ_REPO_DIR="$REPO_DIR" \
XYPTDQ_WEBROOT="$WEBROOT" \
  bash "$REPO_DIR/scripts/content/run_scheduled_publish.sh" || fail_phase "publish" "one-shot Publisher run failed"

php "$REPO_DIR/scripts/content/export_publication_receipt.php" --article="$SCHEDULED_PATH" --state="$STATE_PATH" --output="$RECEIPT_PATH" >"$TMP_DIR/receipt.out" 2>"$TMP_DIR/receipt.err" || fail_phase "receipt" "Publication Receipt export failed"

CMS_ID=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (int)($x["cms_id"]??0);' "$RECEIPT_PATH")
PUBLISHED_URL=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (string)($x["published_url"]??"");' "$RECEIPT_PATH")
[ "$CMS_ID" -gt 0 ] && [ -n "$PUBLISHED_URL" ] || fail_phase "receipt" "Publication Receipt identity incomplete"

php "$REPO_DIR/scripts/seo/verify_publication_seo.php" --receipt="$RECEIPT_PATH" >"$TMP_DIR/live-seo.out" 2>"$TMP_DIR/live-seo.err" || {
  write_result "BLOCKED_AFTER_PUBLISH" "live_seo" "article was published but live SEO verification failed; recurring cron remains disabled" "$CMS_ID" "$PUBLISHED_URL"
  echo "CF50_CANARY_001=BLOCKED_AFTER_PUBLISH" >&2
  exit 21
}

CRON_COUNT_AFTER=$(( (crontab -l 2>/dev/null || true) | grep -F 'run_scheduled_publish.sh' | wc -l ))
[ "$CRON_COUNT_AFTER" -eq 0 ] || fail_phase "postflight" "publisher cron changed unexpectedly"
[ "$(find "$REPO_DIR/content/scheduled" -maxdepth 1 -type f -name '*.json' | wc -l)" -eq 11 ] || fail_phase "postflight" "legacy Scheduled inventory changed"

write_result "PASS" "complete" "CF50-001 public-r1 published through isolated one-shot canary and passed live SEO verification" "$CMS_ID" "$PUBLISHED_URL"
echo "CF50_CANARY_001=PASS cms_id=$CMS_ID url=$PUBLISHED_URL"
