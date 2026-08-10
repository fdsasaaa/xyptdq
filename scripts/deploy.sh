#!/bin/bash
# ============================================================
# deploy.sh - 部署脚本
# 使用: ./deploy.sh [git-ref]
# ============================================================
set -e

GIT_REF="${1:-main}"
DEPLOY_ID=$(date +%Y%m%d_%H%M%S)
REPO_DIR="/root/xyptdq"
WEBROOT="/www/wwwroot/59.110.217.6"

echo "=== 部署开始 ==="
echo "DEPLOY_ID: $DEPLOY_ID"
echo "GIT_REF: $GIT_REF"

# 1. 部署前备份
echo "--- 创建部署前备份 ---"
/root/xyptdq/scripts/backup.sh

# 2. 获取Git版本
echo "--- 获取Git版本: $GIT_REF ---"
cd "$REPO_DIR"
GIT_SHA=$(git rev-parse "$GIT_REF")
echo "GIT_SHA: $GIT_SHA"

# 3. 同步代码（排除敏感文件和运行时目录）
echo "--- 同步代码 ---"
rsync -avz --delete \
    --exclude='.git' \
    --exclude='cache' \
    --exclude='uploadfile' \
    --exclude='config/database.php' \
    --exclude='.user.ini' \
    "$REPO_DIR/site/" "$WEBROOT/"

# 4. 修复权限
echo "--- 修复权限 ---"
chown -R www-data:www-data "$WEBROOT"
find "$WEBROOT" -type d -exec chmod 755 {} \;
find "$WEBROOT" -type f -exec chmod 644 {} \;

# 5. 记录部署
echo "--- 记录部署 ---"
DEPLOY_LOG="/root/backups/deploy_${DEPLOY_ID}/DEPLOY_RECORD.txt"
echo "DEPLOY_ID: $DEPLOY_ID" > "$DEPLOY_LOG"
echo "GIT_SHA: $GIT_SHA" >> "$DEPLOY_LOG"
echo "GIT_REF: $GIT_REF" >> "$DEPLOY_LOG"
echo "DATE: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$DEPLOY_LOG"
echo "RESULT: SUCCESS" >> "$DEPLOY_LOG"

# 6. 健康检查
echo "--- 健康检查 ---"
/root/xyptdq/scripts/health-check.sh

echo ""
echo "=== 部署完成 ==="
echo "DEPLOY_ID: $DEPLOY_ID"
echo "GIT_SHA: $GIT_SHA"
