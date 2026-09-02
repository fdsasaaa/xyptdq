#!/bin/bash
# Deterministic scheduled publisher wrapper.
# Intended for cron only after publisher_capabilities.json has durable idempotency verified.
set -euo pipefail

REPO_DIR="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
LIMIT="${XYPTDQ_PUBLISH_LIMIT:-2}"
LOG_DIR="${XYPTDQ_PUBLISH_LOG_DIR:-/var/log/xyptdq-publisher}"
SOURCE_QUEUE="${XYPTDQ_PUBLISH_SOURCE:-}"
STATE_PATH="${XYPTDQ_PUBLISH_STATE:-/var/lib/xyptdq-publisher/state.json}"
LOCK_PATH="${XYPTDQ_PUBLISH_LOCK:-/var/lib/xyptdq-publisher/publisher.lock}"
NATIVE_ADAPTER="$REPO_DIR/scripts/content/cms_publish_native_adapter.php"
POLICY="$REPO_DIR/config/content_publication_policy.json"
LEGACY_QUEUE="$REPO_DIR/content/scheduled"
RUNTIME_QUEUE_ROOT="/var/lib/xyptdq-content"

fail() {
    echo "[scheduled-publish] ERROR: $*" >&2
    exit 1
}

[ -d "$REPO_DIR/.git" ] || fail "repo missing: $REPO_DIR"
[ -s "$NATIVE_ADAPTER" ] || fail "native Xunrui adapter missing"
mkdir -p "$LOG_DIR"
chmod 750 "$LOG_DIR"

# Tolerant sync: the canonical repo may hold transient uncommitted state from the
# result transport. The publisher never modifies the repo, so resetting to origin/main
# is safe; a dirty repo must never freeze scheduled publication (fail-closed here caused
# a 19.8h silent stall - see publisher-execution-probe-20260902-01).
git -C "$REPO_DIR" fetch --prune origin main >/dev/null 2>&1 || true
git -C "$REPO_DIR" checkout -q main 2>/dev/null || git -C "$REPO_DIR" checkout -q -B main origin/main
git -C "$REPO_DIR" reset --hard origin/main >/dev/null
[ -s "$NATIVE_ADAPTER" ] || fail "native Xunrui adapter missing after sync"
[ -s "$POLICY" ] || fail "publication policy missing after sync; fail-closed"

POLICY_ENABLED=$(php -r '
$x=json_decode(file_get_contents($argv[1]),true);
if(!is_array($x) || (int)($x["schema_version"]??0)!==1){exit(2);}
echo (($x["publishing_enabled"]??null)===true)?"yes":"no";
' "$POLICY") || fail "publication policy invalid; fail-closed"
if [ "$POLICY_ENABLED" != "yes" ]; then
    echo "[scheduled-publish] PAUSED by content publication policy; no article publishing attempted"
    exit 0
fi

# Publishing must never fall back to the repository's preserved historical queue.
[ -n "$SOURCE_QUEUE" ] || fail "XYPTDQ_PUBLISH_SOURCE is required when publishing is enabled"
[ -d "$RUNTIME_QUEUE_ROOT" ] || fail "isolated queue root does not exist: $RUNTIME_QUEUE_ROOT"
[ -d "$SOURCE_QUEUE" ] || fail "isolated publish source does not exist: $SOURCE_QUEUE"
SOURCE_REAL=$(realpath "$SOURCE_QUEUE") || fail "cannot resolve isolated publish source"
ROOT_REAL=$(realpath "$RUNTIME_QUEUE_ROOT") || fail "cannot resolve isolated queue root"
LEGACY_REAL=$(realpath "$LEGACY_QUEUE") || fail "cannot resolve legacy Scheduled queue"
case "$SOURCE_REAL/" in
    "$ROOT_REAL"/*) ;;
    *) fail "resolved publish source must remain under $ROOT_REAL" ;;
esac
[ "$SOURCE_REAL" != "$LEGACY_REAL" ] || fail "legacy repository Scheduled queue is forbidden"
SOURCE_QUEUE="$SOURCE_REAL"

RUN_SHA=$(git -C "$REPO_DIR" rev-parse HEAD)
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
LOG_FILE="$LOG_DIR/run_${RUN_ID}.log"
PUBLISH_TMP=$(mktemp /tmp/xyptdq-publish-output.XXXXXX)
trap 'rm -f "$PUBLISH_TMP"' EXIT
RECEIPT_DIR="${XYPTDQ_PUBLISH_RECEIPT_DIR:-$(dirname "$STATE_PATH")/receipts}"
VERIFY_DIR="${XYPTDQ_PUBLISH_VERIFY_DIR:-$(dirname "$STATE_PATH")/seo-verification}"
mkdir -p "$RECEIPT_DIR" "$VERIFY_DIR"
chmod 750 "$RECEIPT_DIR" "$VERIFY_DIR"

{
    echo "run_id=$RUN_ID"
    echo "git_sha=$RUN_SHA"
    echo "limit=$LIMIT"
    echo "source_queue=$SOURCE_QUEUE"
    echo "adapter=native_xunrui_v2"
    php "$REPO_DIR/scripts/content/auto_publish_filequeue.php" \
        --source="$SOURCE_QUEUE" \
        --state="$STATE_PATH" \
        --lock="$LOCK_PATH" \
        --limit="$LIMIT" \
        --adapter="$NATIVE_ADAPTER" \
        --commit | tee "$PUBLISH_TMP"

    # Sitemap must be refreshed before any live SEO verification checks membership.
    XYPTDQ_WEBROOT="$WEBROOT" \
    XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" \
    XYPTDQ_SITEMAP="$WEBROOT/sitemap.xml" \
        php "$REPO_DIR/scripts/seo/generate_sitemap.php"

    mapfile -t PUBLISHED_LINES < <(grep -E '^\[filequeue\] PUBLISHED key=[a-z0-9_-]+ cms_id=[0-9]+$' "$PUBLISH_TMP" || true)
    SEO_STATUS="NO_NEW_PUBLICATIONS"
    SEO_WARN=0
    if [ "${#PUBLISHED_LINES[@]}" -gt 0 ]; then
        SEO_STATUS="PASS"
        for line in "${PUBLISHED_LINES[@]}"; do
            key=$(printf '%s\n' "$line" | sed -E 's/^\[filequeue\] PUBLISHED key=([a-z0-9_-]+) cms_id=([0-9]+)$/\1/')
            cms_id=$(printf '%s\n' "$line" | sed -E 's/^\[filequeue\] PUBLISHED key=([a-z0-9_-]+) cms_id=([0-9]+)$/\2/')
            source_file=$(php -r '
$dir=rtrim($argv[1],"/"); $key=$argv[2]; $matches=[];
foreach(glob($dir."/*.json")?:[] as $p){$x=json_decode((string)file_get_contents($p),true); if(is_array($x) && (string)($x["article_key"]??"")===$key){$matches[]=$p;}}
if(count($matches)!==1){exit(2);} echo $matches[0];
' "$SOURCE_QUEUE" "$key" 2>/dev/null || true)
            if [ -z "$source_file" ] || [ ! -f "$source_file" ]; then
                echo "[scheduled-publish] SEO_VERIFY_WARN key=$key cms_id=$cms_id reason=scheduled_source_not_unique"
                SEO_WARN=1
                continue
            fi
            receipt="$RECEIPT_DIR/${key}.${cms_id}.json"
            verify="$VERIFY_DIR/${key}.${cms_id}.json"
            if ! php "$REPO_DIR/scripts/content/export_publication_receipt.php" \
                --article="$source_file" --state="$STATE_PATH" --output="$receipt"; then
                echo "[scheduled-publish] SEO_VERIFY_WARN key=$key cms_id=$cms_id reason=receipt_export_failed"
                SEO_WARN=1
                continue
            fi
            chmod 640 "$receipt"
            if php "$REPO_DIR/scripts/seo/verify_publication_seo.php" --receipt="$receipt" > "$verify" 2>&1; then
                chmod 640 "$verify"
                echo "[scheduled-publish] SEO_VERIFY_PASS key=$key cms_id=$cms_id receipt=$receipt verification=$verify"
            else
                chmod 640 "$verify" 2>/dev/null || true
                echo "[scheduled-publish] SEO_VERIFY_WARN key=$key cms_id=$cms_id reason=live_seo_failed verification=$verify"
                SEO_WARN=1
            fi
        done
        if [ "$SEO_WARN" -ne 0 ]; then SEO_STATUS="WARN"; fi
    fi
    echo "seo_verification=$SEO_STATUS"
    echo "result=PASS"
} >> "$LOG_FILE" 2>&1

chmod 640 "$LOG_FILE"
# Retain 60 days of publisher run logs; logs contain no credentials by design.
find "$LOG_DIR" -type f -name 'run_*.log' -mtime +60 -delete 2>/dev/null || true
find "$VERIFY_DIR" -type f -name '*.json' -mtime +60 -delete 2>/dev/null || true
