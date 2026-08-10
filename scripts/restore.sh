#!/bin/bash
# ============================================================
# restore.sh - 网站恢复脚本
# 使用: ./restore.sh <backup_dir>
# ============================================================
set -e

BACKUP_DIR="${1:-}"

if [ -z "$BACKUP_DIR" ]; then
    echo "使用方法: $0 <backup_dir>"
    echo "示例: $0 /root/backups/deploy_20260810_031958"
    exit 1
fi

if [ ! -d "$BACKUP_DIR" ]; then
    echo "错误: 备份目录不存在: $BACKUP_DIR"
    exit 1
fi

echo "===⚠️ 警告: 即将恢复备份 ==="
echo "备份目录: $BACKUP_DIR"
echo "目标: 生产环境"
echo "按 Ctrl+C 取消，按回车继续..."
read

# A. 恢复网站文件
echo "--- 恢复网站文件 ---"
cd /www/wwwroot/59.110.217.6
tar xzf "$BACKUP_DIR/website_files.tar.gz"
echo "OK"

# B. 恢复数据库
echo "--- 恢复数据库 ---"
mysql dayrui < "$BACKUP_DIR/database_dayrui.sql"
echo "OK"

# C. 恢复Nginx配置
echo "--- 恢复Nginx配置 ---"
cp "$BACKUP_DIR/nginx_site.conf" /etc/nginx/sites-enabled/site.conf
nginx -t && systemctl reload nginx
echo "OK"

echo ""
echo "=== 恢复完成 ==="
echo "请运行: $0/health-check.sh 验证"
