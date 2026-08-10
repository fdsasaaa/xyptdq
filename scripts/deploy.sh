#!/bin/bash
# ============================================================
# deploy.sh - production deployment with exact-ref and SEO guards
# Usage: ./deploy.sh [git-ref]
# ============================================================
set -euo pipefail

GIT_REF="${1:-main}"
DEPLOY_ID=$(date +%Y%m%d_%H%M%S)
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
REPO_DIR="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
BACKUP_ROOT="${XYPTDQ_BACKUP_ROOT:-/root/backups}"

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

TMP_PARENT=""
TMP_WORKTREE=""
cleanup() {
    if [ -n "${TMP_WORKTREE:-}" ] && [ -e "$TMP_WORKTREE" ]; then
        git -C "$REPO_DIR" worktree remove --force "$TMP_WORKTREE" >/dev/null 2>&1 || true
    fi
    if [ -n "${TMP_PARENT:-}" ] && [ -d "$TMP_PARENT" ]; then
        rm -rf "$TMP_PARENT"
    fi
}
trap cleanup EXIT

echo "=== Deployment start ==="
echo "DEPLOY_ID: $DEPLOY_ID"
echo "GIT_REF: $GIT_REF"
echo "REPO_DIR: $REPO_DIR"
echo "WEBROOT: $WEBROOT"

# 1. Refresh refs and resolve the exact immutable commit to deploy.
echo "--- Refresh Git refs ---"
git -C "$REPO_DIR" fetch --prune origin
GIT_SHA=$(git -C "$REPO_DIR" rev-parse "$GIT_REF^{commit}")
echo "GIT_SHA: $GIT_SHA"

# 2. Materialize that exact commit in an isolated, read-only deployment worktree.
# Never rsync the canonical working tree merely because GIT_REF resolved to a SHA.
echo "--- Create exact-ref deployment worktree ---"
TMP_PARENT=$(mktemp -d /tmp/xyptdq-deploy.XXXXXX)
TMP_WORKTREE="$TMP_PARENT/worktree"
git -C "$REPO_DIR" worktree add --detach "$TMP_WORKTREE" "$GIT_SHA" >/dev/null

BACKUP_SCRIPT="$TMP_WORKTREE/scripts/backup.sh"
HEALTH_SCRIPT="$TMP_WORKTREE/scripts/health-check.sh"
ROBOTS_PATCH="$TMP_WORKTREE/scripts/seo/patch_homepage_noindex.php"
SITEMAP_SCRIPT="$TMP_WORKTREE/scripts/seo/generate_sitemap.php"

for required in "$BACKUP_SCRIPT" "$HEALTH_SCRIPT" "$ROBOTS_PATCH" "$SITEMAP_SCRIPT"; do
    if [ ! -f "$required" ]; then
        echo "ERROR: required deployment component missing at target ref: $required" >&2
        exit 1
    fi
done

# 3. Pre-deploy backup with the same deployment ID so logs and recovery material
# cannot drift by one second into different directory names.
echo "--- Pre-deploy backup ---"
XYPTDQ_BACKUP_ID="$DEPLOY_ID" \
XYPTDQ_BACKUP_ROOT="$BACKUP_ROOT" \
XYPTDQ_REPO_DIR="$REPO_DIR" \
XYPTDQ_WEBROOT="$WEBROOT" \
"$BACKUP_SCRIPT"

# 4. Sync target-ref site code, preserving runtime/secrets/uploads.
echo "--- Sync exact-ref site code ---"
rsync -avz --delete \
    --exclude='.git' \
    --exclude='cache' \
    --exclude='uploadfile' \
    --exclude='uploads' \
    --exclude='config/database.php' \
    --exclude='.user.ini' \
    "$TMP_WORKTREE/site/" "$WEBROOT/"

# 5. Enforce the P0 indexing guard after every deploy. The repository still has a
# legacy concatenated homepage template; until that source is cleaned, this guard
# prevents robots=none from reaching production.
echo "--- Enforce homepage indexing guard ---"
php "$ROBOTS_PATCH" --file="$WEBROOT/template/pc/default/home/index.html" --apply

# 6. Generate fresh sitemap from live CMS data.
echo "--- Generate sitemap ---"
XYPTDQ_WEBROOT="$WEBROOT" \
XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" \
XYPTDQ_SITEMAP="$WEBROOT/sitemap.xml" \
php "$SITEMAP_SCRIPT"

# 7. Permissions. Do not modify the Git working copy or deployment worktree.
echo "--- Repair web permissions ---"
chown -R www-data:www-data "$WEBROOT"
find "$WEBROOT" -type d -exec chmod 755 {} \;
find "$WEBROOT" -type f -exec chmod 644 {} \;

# 8. SEO deployment assertions.
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

# 9. Service/HTTP health check.
echo "--- Health check ---"
XYPTDQ_WEBROOT="$WEBROOT" "$HEALTH_SCRIPT"

HOME_CODE=$(curl -sk -o /dev/null -w '%{http_code}' https://www.laocaimi.org/)
ROBOTS_CODE=$(curl -sk -o /dev/null -w '%{http_code}' https://www.laocaimi.org/robots.txt)
SITEMAP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' https://www.laocaimi.org/sitemap.xml)
if [ "$HOME_CODE" != "200" ] || [ "$ROBOTS_CODE" != "200" ] || [ "$SITEMAP_CODE" != "200" ]; then
    echo "ERROR: endpoint verification failed home=$HOME_CODE robots=$ROBOTS_CODE sitemap=$SITEMAP_CODE" >&2
    exit 24
fi

# 10. Record deployment only after all guards pass.
echo "--- Record deployment ---"
DEPLOY_LOG="$BACKUP_ROOT/deploy_${DEPLOY_ID}/DEPLOY_RECORD.txt"
if [ ! -d "$(dirname "$DEPLOY_LOG")" ]; then
    echo "ERROR: deterministic backup directory disappeared: $(dirname "$DEPLOY_LOG")" >&2
    exit 25
fi
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
chmod 600 "$DEPLOY_LOG"

echo ""
echo "=== Deployment complete ==="
echo "DEPLOY_ID: $DEPLOY_ID"
echo "GIT_SHA: $GIT_SHA"
