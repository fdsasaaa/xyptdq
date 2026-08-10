# 部署说明 (DEPLOYMENT)

## 部署流程

```
GitHub (main) → backup → deploy → verify → health-check
```

## 部署步骤

### 1. 部署前备份
```bash
# 在服务器上执行
/root/xyptdq/scripts/backup.sh
```

### 2. 部署代码
```bash
# 从GitHub同步到生产
/root/xyptdq/scripts/deploy.sh <git-tag-or-commit>
```

### 3. 验证
```bash
/root/xyptdq/scripts/health-check.sh
```

### 4. 如需回滚
```bash
/root/xyptdq/scripts/rollback.sh <deploy-id>
```

## 部署记录

每次部署生成记录:
- DEPLOY_ID
- Git SHA
- 时间
- 备份编号
- 部署结果

## 安全门

任何重大修改必须满足:
1. **BACKUP** - 已创建备份
2. **VERIFY** - 已验证备份完整性
3. **ROLLBACK** - 已确认回滚路径可用

## 禁止事项

没有备份和验证不得:
- `rm -rf` 网站目录
- `DROP DATABASE`
- 全量数据库替换
- 大版本升级PHP/MySQL/CMS
- 系统重装
- 防火墙大改
- SSH认证大改
