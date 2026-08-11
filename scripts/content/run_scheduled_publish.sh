#!/bin/bash
# Deterministic scheduled publisher wrapper.
# Intended for cron only after publisher_capabilities.json has durable idempotency verified.
set -euo pipefail

REPO_DIR="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
LIMIT="${XYPTDQ_PUBLISH_LIMIT:-2}"
LOG_DIR="${XYPTDQ_PUBLISH_LOG_DIR:-/var/log/xyptdq-publisher}"
NATIVE_ADAPTER="$REPO_DIR/scripts/content/cms_publish_native_adapter.php"
POLICY="$REPO_DIR/config/content_publication_policy.json"

fail() {
    echo "[scheduled-publish] ERROR: $*" >&2
    exit 1
}

[ -d "$REPO_DIR/.git" ] || fail "repo missing: $REPO_DIR"
[ -s "$NATIVE_ADAPTER" ] || fail "native Xunrui adapter missing"
mkdir -p "$LOG_DIR"
chmod 750 "$LOG_DIR"

# Never discard unknown server work. The canonical automation clone must be clean.
if [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
    fail "canonical repo is not clean; refusing automatic reset"
fi

git -C "$REPO_DIR" fetch --prune origin main >/dev/null 2>&1
git -C "$REPO_DIR" checkout -q main
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

RUN_SHA=$(git -C "$REPO_DIR" rev-parse HEAD)
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
LOG_FILE="$LOG_DIR/run_${RUN_ID}.log"

{
    echo "run_id=$RUN_ID"
    echo "git_sha=$RUN_SHA"
    echo "limit=$LIMIT"
    echo "adapter=native_xunrui_v2"
    php "$REPO_DIR/scripts/content/auto_publish_filequeue.php" \
        --source="$REPO_DIR/content/scheduled" \
        --state=/var/lib/xyptdq-publisher/state.json \
        --lock=/var/lib/xyptdq-publisher/publisher.lock \
        --limit="$LIMIT" \
        --adapter="$NATIVE_ADAPTER" \
        --commit

    XYPTDQ_WEBROOT="$WEBROOT" \
    XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" \
    XYPTDQ_SITEMAP="$WEBROOT/sitemap.xml" \
        php "$REPO_DIR/scripts/seo/generate_sitemap.php"

    echo "result=PASS"
} >> "$LOG_FILE" 2>&1

chmod 640 "$LOG_FILE"
# Retain 60 days of publisher run logs; logs contain no credentials by design.
find "$LOG_DIR" -type f -name 'run_*.log' -mtime +60 -delete 2>/dev/null || true
