#!/bin/bash
# ============================================================
# deploy.sh - production deployment with exact-ref and hard SEO guards
# Usage: ./deploy.sh [git-ref]
# ============================================================
set -euo pipefail

GIT_REF="${1:-main}"
DEPLOY_ID=$(date +%Y%m%d_%H%M%S)
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
REPO_DIR="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
BACKUP_ROOT="${XYPTDQ_BACKUP_ROOT:-/root/backups}"
CANONICAL="https://www.laocaimi.org"

if [ ! -d "$REPO_DIR/.git" ] && [ -d /root/xyptdq/.git ]; then
    REPO_DIR=/root/xyptdq
fi
[ -d "$REPO_DIR/.git" ] || { echo "ERROR: Git working copy not found" >&2; exit 1; }
[ -d "$WEBROOT" ] || { echo "ERROR: webroot not found: $WEBROOT" >&2; exit 1; }

TMP_PARENT=""
TMP_WORKTREE=""
cleanup() {
    if [ -n "${TMP_WORKTREE:-}" ] && [ -e "$TMP_WORKTREE" ]; then
        git -C "$REPO_DIR" worktree remove --force "$TMP_WORKTREE" >/dev/null 2>&1 || true
    fi
    [ -n "${TMP_PARENT:-}" ] && [ -d "$TMP_PARENT" ] && rm -rf "$TMP_PARENT"
}
trap cleanup EXIT

sanitize_homepage_robots() {
    local file="$1"
    [ -f "$file" ] || { echo "ERROR: homepage template missing: $file" >&2; return 1; }
    php -r '
$file=$argv[1]; $src=(string)file_get_contents($file); $count=0;
$dst=preg_replace("~<meta\\s+name=[\x22\x27]robots[\x22\x27]\\s+content=[\x22\x27]none[\x22\x27]\\s*/?>~i", "<meta name=\x22robots\x22 content=\x22index,follow,max-image-preview:large\x22>", $src, -1, $count);
if ($dst===null) exit(2);
if ($count>0 && file_put_contents($file,$dst,LOCK_EX)===false) exit(3);
if (preg_match("~<meta\\s+name=[\x22\x27]robots[\x22\x27]\\s+content=[\x22\x27]none[\x22\x27]~i", (string)file_get_contents($file))) exit(4);
echo "[robots] sanitized=$count file=$file\n";
' "$file"
}

assert_rendered_home_indexable() {
    local body="$1"
    php -r '
$s=(string)file_get_contents($argv[1]);
if (preg_match("~<meta\\b[^>]*name=[\x22\x27]robots[\x22\x27][^>]*content=[\x22\x27]none[\x22\x27][^>]*>~i",$s)) exit(1);
' "$body"
}

echo "=== Deployment start ==="
echo "DEPLOY_ID: $DEPLOY_ID"
echo "GIT_REF: $GIT_REF"
echo "REPO_DIR: $REPO_DIR"
echo "WEBROOT: $WEBROOT"

echo "--- Refresh Git refs ---"
git -C "$REPO_DIR" fetch --prune origin
GIT_SHA=$(git -C "$REPO_DIR" rev-parse "$GIT_REF^{commit}")
echo "GIT_SHA: $GIT_SHA"

echo "--- Create exact-ref deployment worktree ---"
TMP_PARENT=$(mktemp -d /tmp/xyptdq-deploy.XXXXXX)
TMP_WORKTREE="$TMP_PARENT/worktree"
git -C "$REPO_DIR" worktree add --detach "$TMP_WORKTREE" "$GIT_SHA" >/dev/null

BACKUP_SCRIPT="$TMP_WORKTREE/scripts/backup.sh"
HEALTH_SCRIPT="$TMP_WORKTREE/scripts/health-check.sh"
SITEMAP_SCRIPT="$TMP_WORKTREE/scripts/seo/generate_sitemap.php"
SOURCE_HOME="$TMP_WORKTREE/site/template/pc/default/home/index.html"
for required in "$BACKUP_SCRIPT" "$HEALTH_SCRIPT" "$SITEMAP_SCRIPT" "$SOURCE_HOME"; do
    [ -f "$required" ] || { echo "ERROR: required deployment component missing: $required" >&2; exit 2; }
done

# Make the immutable target-ref payload indexable before it ever reaches the
# webroot. Production is sanitized again after rsync as a defense-in-depth guard.
echo "--- Sanitize target-ref homepage robots ---"
sanitize_homepage_robots "$SOURCE_HOME"

echo "--- Pre-deploy backup ---"
XYPTDQ_BACKUP_ID="$DEPLOY_ID" \
XYPTDQ_BACKUP_ROOT="$BACKUP_ROOT" \
XYPTDQ_REPO_DIR="$REPO_DIR" \
XYPTDQ_WEBROOT="$WEBROOT" \
"$BACKUP_SCRIPT"
BACKUP_DIR="$BACKUP_ROOT/deploy_${DEPLOY_ID}"
[ -s "$BACKUP_DIR/checksums.sha256" ] || { echo "ERROR: backup checksum manifest missing" >&2; exit 3; }
(
    cd "$BACKUP_DIR"
    sha256sum -c checksums.sha256 >/dev/null
) || { echo "ERROR: pre-deploy backup verification failed" >&2; exit 4; }
echo "BACKUP_VERIFY: PASS"

echo "--- Sync exact-ref site code ---"
rsync -avz --delete \
    --exclude='.git' \
    --exclude='cache' \
    --exclude='uploadfile' \
    --exclude='uploads' \
    --exclude='config/database.php' \
    --exclude='.user.ini' \
    "$TMP_WORKTREE/site/" "$WEBROOT/"

echo "--- Sanitize production homepage robots ---"
PROD_HOME="$WEBROOT/template/pc/default/home/index.html"
sanitize_homepage_robots "$PROD_HOME"
if grep -Fq '<meta name="robots" content="none">' "$PROD_HOME"; then
    echo "ERROR: legacy homepage robots=none remains in production template" >&2
    exit 20
fi

echo "--- Generate sitemap ---"
XYPTDQ_WEBROOT="$WEBROOT" \
XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" \
XYPTDQ_SITEMAP="$WEBROOT/sitemap.xml" \
php "$SITEMAP_SCRIPT"

echo "--- Repair web permissions ---"
chown -R www-data:www-data "$WEBROOT"
find "$WEBROOT" -type d -exec chmod 755 {} \;
find "$WEBROOT" -type f -exec chmod 644 {} \;

echo "--- SEO deployment assertions ---"
test -s "$WEBROOT/robots.txt" || { echo "ERROR: robots.txt missing/empty" >&2; exit 21; }
test -s "$WEBROOT/sitemap.xml" || { echo "ERROR: sitemap.xml missing/empty" >&2; exit 22; }
grep -Fq 'Sitemap: https://www.laocaimi.org/sitemap.xml' "$WEBROOT/robots.txt" || {
    echo "ERROR: robots.txt does not advertise canonical sitemap" >&2
    exit 23
}

echo "--- Health check ---"
XYPTDQ_WEBROOT="$WEBROOT" "$HEALTH_SCRIPT"

HOME_BODY="$TMP_PARENT/rendered-home.html"
HOME_CODE=$(curl -sk --max-time 30 -o "$HOME_BODY" -w '%{http_code}' "$CANONICAL/")
ROBOTS_CODE=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/robots.txt")
SITEMAP_CODE=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/sitemap.xml")
if [ "$HOME_CODE" != "200" ] || [ "$ROBOTS_CODE" != "200" ] || [ "$SITEMAP_CODE" != "200" ]; then
    echo "ERROR: endpoint verification failed home=$HOME_CODE robots=$ROBOTS_CODE sitemap=$SITEMAP_CODE" >&2
    exit 24
fi
if ! assert_rendered_home_indexable "$HOME_BODY"; then
    echo "ERROR: rendered homepage still contains robots=none" >&2
    exit 26
fi
echo "RENDERED_HOME_INDEXABLE: PASS"

echo "--- Record deployment ---"
DEPLOY_LOG="$BACKUP_DIR/DEPLOY_RECORD.txt"
{
    echo "DEPLOY_ID: $DEPLOY_ID"
    echo "GIT_SHA: $GIT_SHA"
    echo "GIT_REF: $GIT_REF"
    echo "DATE: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "RESULT: SUCCESS"
    echo "BACKUP_VERIFY: PASS"
    echo "HOME_HTTP: $HOME_CODE"
    echo "ROBOTS_HTTP: $ROBOTS_CODE"
    echo "SITEMAP_HTTP: $SITEMAP_CODE"
    echo "RENDERED_HOME_INDEXABLE: PASS"
} > "$DEPLOY_LOG"
chmod 600 "$DEPLOY_LOG"

echo ""
echo "=== Deployment complete ==="
echo "DEPLOY_ID: $DEPLOY_ID"
echo "GIT_SHA: $GIT_SHA"
