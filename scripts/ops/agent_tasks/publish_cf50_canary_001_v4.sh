#!/bin/bash
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO_DIR="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
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
TRANSFER_DIR="$REPO_DIR/content/ingress/public-release/$BATCH_ID"
REVISION="$TRANSFER_DIR/$ARTICLE_ID.public-r1.json"
PARENT_EVIDENCE="$TRANSFER_DIR/$ARTICLE_ID.parent-evidence.json"
MANIFEST="$TRANSFER_DIR/manifest.json"
MAP="$REPO_DIR/content/seo_editorial_cluster_map_cf50.json"

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
  "task":"publish_cf50_canary_001_v4",
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
  "source_transport":"sanitized_public_release_bundle",
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
  echo "CF50_CANARY_001_V4=FAIL phase=$phase" >&2
  exit 20
}

# Canonical server clone may lag behind GitHub main. Sync only if clean.
if [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
  fail_phase "repo_sync" "canonical website repo is dirty; refusing reset"
fi
git -C "$REPO_DIR" fetch --prune origin main >/dev/null 2>&1 || fail_phase "repo_sync" "website repo fetch failed"
git -C "$REPO_DIR" checkout -q main || fail_phase "repo_sync" "website repo main checkout failed"
git -C "$REPO_DIR" reset --hard origin/main >/dev/null || fail_phase "repo_sync" "website repo reset to origin/main failed"

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

CRON_COUNT=$( (crontab -l 2>/dev/null || true) | awk '/run_scheduled_publish\.sh/{n++} END{print n+0}' )
[ "$CRON_COUNT" -eq 0 ] || fail_phase "preflight" "publisher cron must remain absent for canary"
LEGACY_COUNT=$(find "$REPO_DIR/content/scheduled" -maxdepth 1 -type f -name '*.json' | wc -l)
[ "$LEGACY_COUNT" -eq 11 ] || fail_phase "preflight" "legacy Scheduled inventory count changed"

for required in "$REVISION" "$PARENT_EVIDENCE" "$MANIFEST" "$MAP"; do
  [ -s "$required" ] || fail_phase "source_validation" "sanitized transfer bundle is incomplete"
done
if grep -q '"content"[[:space:]]*:' "$PARENT_EVIDENCE"; then
  fail_phase "source_validation" "parent evidence must not contain parent body content"
fi

mkdir -p "$DRAFT_DIR" "$SCHEDULED_DIR" "$PUB_ROOT" "$RECEIPT_DIR"
chmod 0750 "$RUNTIME_ROOT" "$DRAFT_DIR" "$SCHEDULED_DIR" "$PUB_ROOT" "$RECEIPT_DIR"
for p in "$DRAFT_DIR" "$SCHEDULED_DIR" "$PUB_ROOT"; do
  [ ! -L "$p" ] || fail_phase "preflight" "runtime path must not be a symlink"
done

rm -f "$DRAFT_PATH" "$SCHEDULED_PATH" "$RECEIPT_PATH"
php "$REPO_DIR/scripts/content/ingest_public_release_transfer_canary.php" \
  --revision="$REVISION" \
  --parent-evidence="$PARENT_EVIDENCE" \
  --manifest="$MANIFEST" \
  --editorial-cluster-map="$MAP" \
  --output="$DRAFT_PATH" >"$TMP_DIR/intake.out" 2>"$TMP_DIR/intake.err" || fail_phase "draft_intake" "sanitized public-release validation or Draft conversion failed"

DRAFT_CHECK=$(php -r '
$x=json_decode(file_get_contents($argv[1]),true);
$ok=is_array($x)
 && (($x["publication_state"]??"")==="draft")
 && (($x["source_article_id"]??"")==="LCM-CREATOR-cf50-20260813-001")
 && (($x["source_revision_id"]??"")==="LCM-CREATOR-cf50-20260813-001:public-r1")
 && (($x["site_category_key"]??"")==="tzjq")
 && ((int)($x["catid"]??0)===3)
 && (($x["primary_seo_cluster_id"]??"")==="ffc_research")
 && (($x["source_parent_evidence_kind"]??"")==="immutable_approved_parent_identity")
 && !array_key_exists("publish_at",$x);
echo $ok?"PASS":"FAIL";
' "$DRAFT_PATH") || fail_phase "draft_intake" "generated Draft is invalid"
[ "$DRAFT_CHECK" = "PASS" ] || fail_phase "draft_intake" "generated Draft failed identity/category/cluster/provenance checks"

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
  echo "CF50_CANARY_001_V4=BLOCKED_AFTER_PUBLISH" >&2
  exit 21
}

CRON_COUNT_AFTER=$( (crontab -l 2>/dev/null || true) | awk '/run_scheduled_publish\.sh/{n++} END{print n+0}' )
[ "$CRON_COUNT_AFTER" -eq 0 ] || fail_phase "postflight" "publisher cron changed unexpectedly"
[ "$(find "$REPO_DIR/content/scheduled" -maxdepth 1 -type f -name '*.json' | wc -l)" -eq 11 ] || fail_phase "postflight" "legacy Scheduled inventory changed"

write_result "PASS" "complete" "CF50-001 public-r1 published from sanitized local transfer bundle and passed live SEO verification" "$CMS_ID" "$PUBLISHED_URL"
echo "CF50_CANARY_001_V4=PASS cms_id=$CMS_ID url=$PUBLISHED_URL"
