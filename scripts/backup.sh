#!/bin/bash
# ============================================================
# backup.sh - full production backup
# Usage: ./backup.sh
# Optional: XYPTDQ_BACKUP_ID=YYYYMMDD_HHMMSS to pin the backup directory.
# ============================================================
set -euo pipefail

TIMESTAMP="${XYPTDQ_BACKUP_ID:-$(date +%Y%m%d_%H%M%S)}"
[[ "$TIMESTAMP" =~ ^[0-9]{8}_[0-9]{6}$ ]] || { echo "ERROR: invalid XYPTDQ_BACKUP_ID" >&2; exit 2; }
BACKUP_ROOT="${XYPTDQ_BACKUP_ROOT:-/root/backups}"
BACKUP_DIR="$BACKUP_ROOT/deploy_${TIMESTAMP}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
REPO_DIR="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"

if [ ! -d "$REPO_DIR/.git" ] && [ -d /root/xyptdq/.git ]; then
    REPO_DIR=/root/xyptdq
fi
if [ ! -d "$WEBROOT" ]; then
    echo "ERROR: webroot not found: $WEBROOT" >&2
    exit 1
fi
if [ ! -f "$WEBROOT/config/database.php" ]; then
    echo "ERROR: CMS database config not found" >&2
    exit 1
fi
if [ -e "$BACKUP_DIR" ]; then
    echo "ERROR: backup directory already exists: $BACKUP_DIR" >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

echo "=== Create backup: $BACKUP_DIR ==="

# A. Website files. Cache is intentionally excluded; uploads and runtime config
# are included because this is a recovery backup, not a Git source snapshot.
echo "--- Website files ---"
tar czf "$BACKUP_DIR/website_files.tar.gz" \
    -C "$WEBROOT" \
    --exclude='cache' \
    . 2>/dev/null
chmod 600 "$BACKUP_DIR/website_files.tar.gz"
echo "OK"

# B. Resolve database name without printing credentials.
DB_NAME=$(php -r '$db=[]; require $argv[1]; $c=$db["default"]??[]; echo $c["database"]??"";' "$WEBROOT/config/database.php")
if [ -z "$DB_NAME" ] || ! [[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "ERROR: invalid database name resolved from CMS config" >&2
    exit 1
fi

# C. Database dump using the server's local administrative authentication.
echo "--- Database ---"
mysqldump --single-transaction --routines --triggers "$DB_NAME" > "$BACKUP_DIR/database_${DB_NAME}.sql"
chmod 600 "$BACKUP_DIR/database_${DB_NAME}.sql"
echo "OK"

# D. Nginx configuration.
echo "--- Nginx config ---"
cp /etc/nginx/sites-enabled/site.conf "$BACKUP_DIR/nginx_site.conf"
chmod 600 "$BACKUP_DIR/nginx_site.conf"
echo "OK"

# E. Deployment metadata. Never write secrets into the manifest.
GIT_SHA="N/A"
if [ -d "$REPO_DIR/.git" ]; then
    GIT_SHA=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo 'N/A')
fi
{
    echo "BACKUP_ID: $TIMESTAMP"
    echo "DATE: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "GIT_SHA: $GIT_SHA"
    echo "WEBROOT: $WEBROOT"
    echo "DB_NAME: $DB_NAME"
} > "$BACKUP_DIR/MANIFEST.txt"
chmod 600 "$BACKUP_DIR/MANIFEST.txt"

# F. Integrity hashes.
echo "--- Checksums ---"
(
    cd "$BACKUP_DIR"
    sha256sum website_files.tar.gz "database_${DB_NAME}.sql" nginx_site.conf MANIFEST.txt > checksums.sha256
)
chmod 600 "$BACKUP_DIR/checksums.sha256"
cat "$BACKUP_DIR/checksums.sha256"

echo ""
echo "=== Backup complete ==="
echo "BACKUP_ID=$TIMESTAMP"
echo "BACKUP_DIR=$BACKUP_DIR"
