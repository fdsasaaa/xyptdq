#!/bin/bash
# ============================================================
# deploy.sh - production deployment with SEO safety guards
# Usage: ./deploy.sh [git-ref]
# ============================================================
set -euo pipefail

GIT_REF="${1:-main}"
DEPLOY_ID=$(date +%Y%m%d_%H%M%S)
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
REPO_DIR="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"

if [ ! -d "$REPO_DIR/.git" ] && [ -d /root/xyptdq/.git ]; then
    REPO_DIR=/root/xyptdq
fi

if [ ! -d "$REPO_DIR/.git" ]; then
    echo "ERROR: Git working copy not found. Checked: $REPO_DIR and /root/xyptdq" >&2
    exit 1
fi
if [ ! -d "$WEBROOT" ]; then
    echo "ERROR: webroot not found: $WEBROOT" >&2
    exit 1
fi

BACKUP_SCRIPT="$REPO_DIR/scripts/backup.sh"
HEALTH_SCRIPT="$REPO_DIR/scripts/health-check.sh"
ROBOTS_PATCH="$REPO_DIR/scripts/seo/patch_homepage_noindex.php"
SITEMAP_SCRIPT="$REPO_DIR/scripts/seo/generate_sitemap.php"

for required in "$BACKUP_SCRIPT" "$HEALTH_SCRIPT" "$ROBOTS_PATCH" "$SITEMAP_SCRIPT"; do
    if [ ! -f "$required" ]; then
        echo "ERROR: required deployment component missing: $required" >&2
        exit 1
    fi
done

echo "=== Deployment start ==="
echo "DEPLOY_ID: $DEPLOY_ID"
echo "GIT_REF: $GIT_REF"
echo "REPO_DIR: $REPO_DIR"
echo "WEBROOT: $WEBROOT"

# 1. Refresh refs. The server only needs read access to GitHub.
echo "--- Refresh Git refs ---"
git -C "$REPO_DIR" fetch --prune origin
GIT_SHA=$(git -C "$REPO_DIR" rev-parse "$GIT_REF^{commit}")
echo "GIT_SHA: $GIT_SHA"

# 2. Pre-deploy backup.
echo "--- Pre-deploy backup ---"
XYPTDQ_REPO_DIR="$REPO_DIR" XYPTDQ_WEBROOT="$WEBROOT" "$BACKUP_SCRIPT"

# 3. Sync tracked site code, preserving runtime/secrets/uploads.
echo "--- Sync site code ---"
rsync -avz --delete \
    --exclude='.git' \
    --exclude='cache' \
    --exclude='uploadfile' \
    --exclude='uploads' \
    --exclude='config/database.php' \
    --exclude='.user.ini' \
    "$REPO_DIR/site/" "$WEBROOT/"

# 4. Enforce the current P0 indexing guard after every deploy.
# The legacy repository homepage still contains a historical robots=none tag;
# this post-deploy guard prevents it from ever reaching production unchanged.
echo "--- Enforce homepage indexing guard ---"
php "$ROBOTS_PATCH" --file="$WEBROOT/template/pc/default/home/index.html" --apply || {
    rc=$?
    # Exit code 0 = already indexable/patched. Exit 3 is check-only only and
    # should never occur because --apply is supplied. Any other code is unsafe.
    echo "ERROR: homepage robots patch failed with code $rc" >&2
    exit "$rc"
}

# 5. Generate fresh sitemap from live CMS data.
echo "--- Generate sitemap ---"
XYPTDQ_WEBROOT="$WEBROOT" \
XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" \
XYPTDQ_SITEMAP="$WEBROOT/sitemap.xml" \
php "$SITEMAP_SCRIPT"

# 6. Permissions. Do not touch ownership of the Git working copy.
echo "--- Repair web permissions ---"
chown -R www-data:www-data "$WEBROOT"
find "$WEBROOT" -type d -exec chmod 755 {} \;
find "$WEBROOT" -type f -exec chmod 644 {} \;

# 7. SEO deployment assertions.
echo "--- SEO deployment assertions ---"
if grep -Fq '<meta name="robots" content="none">' "$WEBROOT/template/pc/default/home/index.html"; then
    echo "ERROR: legacy homepage robots=none remains after deployment" >&2
    exit 20
fi

test -s "$WEBROOT/robots.txt" || { echo "ERROR: robots.txt missing/empty" >&2; exit 21; }
test -s "$WEBROOT/sitemap.xml" || { echo "ERROR: sitemap.xml missing/empty" >&2; exit 22; }

grep -Fq 'Sitemap: https://www.laocaimi.org/sitemap.xml' "$WEBROOT/robots.txt" || {
    echo "ERROR: robots.txt does not advertise canonical sitemap" >&2
    exit 23
}

# 8. Service/HTTP health check.
echo "--- Health check ---"
XYPTDQ_WEBROOT="$WEBROOT" "$HEALTH_SCRIPT"

# 9. Verify public endpoints without exposing response bodies.
HOME_CODE=$(curl -sk -o /dev/null -w '%{http_code}' https://www.laocaimi.org/)
ROBOTS_CODE=$(curl -sk -o /dev/null -w '%{http_code}' https://www.laocaimi.org/robots.txt)
SITEMAP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' https://www.laocaimi.org/sitemap.xml)
if [ "$HOME_CODE" != "200" ] || [ "$ROBOTS_CODE" != "200" ] || [ "$SITEMAP_CODE" != "200" ]; then
    echo "ERROR: endpoint verification failed home=$HOME_CODE robots=$ROBOTS_CODE sitemap=$SITEMAP_CODE" >&2
    exit 24
fi

# 10. Record deployment only after all guards pass.
echo "--- Record deployment ---"
BACKUP_ROOT="${XYPTDQ_BACKUP_ROOT:-/root/backups}"
DEPLOY_LOG="$BACKUP_ROOT/deploy_${DEPLOY_ID}/DEPLOY_RECORD.txt"
if [ -d "$(dirname "$DEPLOY_LOG")" ]; then
    {
        echo "DEPLOY_ID: $DEPLOY_ID"
        echo "GIT_SHA: $GIT_SHA"
        echo "GIT_REF: $GIT_REF"
        echo "DATE: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "RESULT: SUCCESS"
        echo "HOME_HTTP: $HOME_CODE"
        echo "ROBOTS_HTTP: $ROBOTS_CODE"
        echo "SITEMAP_HTTP: $SITEMAP_CODE"
    } > "$DEPLOY_LOG"
else
    echo "WARNING: expected deployment backup directory not found; deployment succeeded but record file was not written" >&2
fi

echo ""
echo "=== Deployment complete ==="
echo "DEPLOY_ID: $DEPLOY_ID"
echo "GIT_SHA: $GIT_SHA"
