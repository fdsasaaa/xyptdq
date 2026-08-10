#!/bin/bash
# ============================================================
# rollback.sh - 回滚脚本
# 使用: ./rollback.sh <deploy-id>
# ============================================================
set -e

DEPLOY_ID="${1:-}"

if [ -z "$DEPLOY_ID" ]; then
    echo "使用方法: $0 <deploy-id>"
    echo "示例: $0 20260810_031958"
    echo ""
    echo "可用备份:"
    ls -1 /root/backups/ | grep deploy_
    exit 1
fi

BACKUP_DIR="/root/backups/deploy_${DEPLOY_ID}"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "错误: 备份目录不存在: $BACKUP_DIR"
    exit 1
fi

echo "===⚠️ 回滚警告 ==="
echo "即将回滚到备份: $BACKUP_DIR"
echo "按 Ctrl+C 取消，按回车继续..."
read

# 执行恢复
/root/xyptdq/scripts/restore.sh "$BACKUP_DIR"

echo ""
echo "=== 回滚完成 ==="
echo "回滚到备份: $DEPLOY_ID"
