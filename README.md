# xyptdq / laocaimi.org 网站总控

> 由 WorkBuddy 网站运营与研发总控系统管理

## 网站信息

| 项目 | 值 |
|------|------|
| 主域名 (Canonical) | `https://www.laocaimi.org` |
| 备用域名 | `laocaimi.org` |
| xyptdq.com 状态 | NXDOMAIN（公共DNS中不存在） |
| CMS | 迅睿CMS (Xunrui CMS) - 基于CodeIgniter框架 |
| 服务器 | 94.103.5.248 (Ubuntu 20.04.6 LTS) |
| Web Server | Nginx 1.18.0 + PHP-FPM 7.4 |
| 数据库 | MariaDB 10.3.39 |
| 网站根目录 | `/www/wwwroot/59.110.217.6` |

## 仓库结构

```
/
├── README.md              # 本文件
├── .gitignore             # Git忽略规则
├── .gitattributes         # Git属性
├── site/                  # 网站源码（迅睿CMS）
├── infra/                 # 基础设施配置模板
│   ├── nginx_site.conf    # Nginx站点配置
│   ├── nginx.conf         # Nginx主配置
│   ├── php-fpm-www.conf   # PHP-FPM配置
│   └── mariadb-server.cnf # MariaDB配置
├── scripts/               # 运维脚本
│   ├── backup.sh          # 备份脚本
│   ├── restore.sh         # 恢复脚本
│   ├── deploy.sh          # 部署脚本
│   ├── rollback.sh        # 回滚脚本
│   └── health-check.sh    # 健康检查
├── config/                # 配置模板（脱敏）
│   └── database.php.template
├── docs/                  # 文档
│   ├── CURRENT_PRODUCTION_BASELINE.md
│   ├── RECOVERY.md
│   ├── DEPLOYMENT.md
│   └── CONTENT_STYLE_GUIDE.md
├── .github/workflows/     # GitHub Actions
└── backups-manifest/      # 备份索引
```

## 版本管理

- `main` - 正式稳定分支
- `feature/*` - 新功能开发
- `hotfix/*` - 紧急修复
- `content/*` - 内容更新

### Tag 规则

- `production-baseline-v1` - 首次接管基线
- `production-vX.Y.Z` - 正式版本
- `hotfix-https-fix-v1` - HTTPS修复版本

## SSL证书

- 证书颁发机构: Let's Encrypt
- 证书路径: `/etc/letsencrypt/live/laocaimi.org/`
- 自动续期: Certbot + systemd timer
- 续期验证: ACME HTTP-01 challenge

## 部署流程

```
新任务 → 新branch → 修改 → 检查 → commit → push → PR → 验收 → merge → deploy
```

## 安全说明

- 服务器密码、数据库密码、SSL私钥 **绝不会** 提交到本仓库
- 所有敏感配置使用 `.env` 或配置模板（脱敏后）
- 部署前必须执行备份
- 每次部署产生独立的部署记录

## 接管历史

- 2026-08-10: WorkBuddy 首次接管，创建 production-baseline-v1
- 2026-08-10: 修复HTTPS（SSL证书过期问题）
