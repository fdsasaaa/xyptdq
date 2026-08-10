#!/bin/bash
# ============================================================
# backup.sh - 网站完整备份脚本
# 使用: ./backup.sh
# ============================================================
set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/root/backups/deploy_${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"

echo "=== 创建备份: $BACKUP_DIR ==="

# A. 网站文件
echo "--- 网站文件 ---"
tar czf "$BACKUP_DIR/website_files.tar.gz" \
    -C /www/wwwroot/59.110.217.6 \
    --exclude='cache' \
    . 2>/dev/null
echo "OK"

# B. 数据库
echo "--- 数据库 ---"
mysqldump --single-transaction --routines --triggers dayrui > "$BACKUP_DIR/database_dayrui.sql" 2>/dev/null
echo "OK"

# C. Nginx配置
echo "--- Nginx配置 ---"
cp /etc/nginx/sites-enabled/site.conf "$BACKUP_DIR/nginx_site.conf"
echo "OK"

# D. 部署信息
echo "--- 部署信息 ---"
echo "BACKUP_ID: $TIMESTAMP" > "$BACKUP_DIR/MANIFEST.txt"
echo "DATE: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$BACKUP_DIR/MANIFEST.txt"
echo "GIT_SHA: $(cd /root/xyptdq 2>/dev/null && git rev-parse HEAD 2>/dev/null || echo 'N/A')" >> "$BACKUP_DIR/MANIFEST.txt"

# E. 校验值
echo "--- 校验值 ---"
cd "$BACKUP_DIR"
sha256sum * > checksums.sha256
cat checksums.sha256

echo ""
echo "=== 备份完成: $BACKUP_DIR ==="
echo "BACKUP_ID=$TIMESTAMP"
