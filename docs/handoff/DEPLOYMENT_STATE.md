# 部署状态 - Git/部署/备份/回滚

> **验证日期**: 2026-08-10

---

## 一、GitHub 真实状态

| 项目 | 值 |
|------|-----|
| Repository | fdsasaaa/xyptdq |
| Default Branch | main |
| 当前工作Branch | docs/chatgpt-handoff-20260810 |
| main HEAD SHA | 07ece208ebd1bce3ac7fdfad9ffc49f8cb57edbc |
| 短SHA | 07ece20 |
| Tags | v1.0.0-seo-article |
| PR | 无 |
| 工作区Clean | 是 |
| 远程Origin | https://github.com/fdsasaaa/xyptdq.git |

### 认证方式

| 项目 | 状态 |
|------|------|
| 认证方式 | PAT (Fine-grained Personal Access Token) |
| PAT scope | Contents (read/write), Metadata (read) |
| PAT缺少 | workflow scope（无法push GitHub Actions） |
| 服务器能否pull | ❌ 未配置 |
| 服务器能否push | ❌ 未配置 |
| Deploy Key | ❌ 无 |
| GitHub App | ❌ 无 |
| GitHub Secrets | ❌ 无 |
| Actions部署能力 | ❌ NO |

---

## 二、首次 Baseline

| 字段 | 值 |
|------|-----|
| Tag | v1.0.0-seo-article |
| Commit SHA | 1ffce04 |
| 建立时间 | 2026-08-10 |
| 对应服务器状态 | 首页SEO文章板块已部署 |
| 数据库备份 | /root/backups/disaster_recovery_20260810_031958/database_dayrui.sql |
| 文件备份 | /root/backups/disaster_recovery_20260810_031958/ |

> **注意**: 原始 `production-baseline-v1` tag 在Git仓库重建（因Google Drive同步导致对象损坏）时丢失。当前 `v1.0.0-seo-article` 是等效的稳定基线标记。

---

## 三、服务器→网站关系

**当前模式: 人工部署（模式D）**

```
开发者本地Git (G:\我的云端硬盘\BC\信誉平台大全网站)
    ↓ git push
GitHub (fdsasaaa/xyptdq)
    ↓ 无自动化（无GitHub Actions部署）
开发者手动SSH (paramiko + SFTP)
    ↓ 手动上传文件
生产目录 (/www/wwwroot/59.110.217.6)
```

服务器 `/root/xyptdq/` 目录仅存放运维脚本，不是Git仓库。

### 流程图

```
[开发者] → git commit → git push → [GitHub仓库]
                                        ↓ (无自动触发)
[开发者] → SSH连接 → SFTP上传模板 → [生产服务器]
                                        ↓
                                 [清缓存(仅template/data)]
                                        ↓
                                 [验证页面正常]
```

---

## 四、部署系统现状

| 脚本 | EXISTS | TESTED | PRODUCTION VERIFIED | 路径 |
|------|--------|--------|---------------------|------|
| deploy.sh | ✅ | ❌ | ❌ | /root/xyptdq/scripts/deploy.sh |
| rollback.sh | ✅ | ❌ | ❌ | /root/xyptdq/scripts/rollback.sh |
| backup.sh | ✅ | ✅ | ✅ | /root/xyptdq/scripts/backup.sh |
| restore.sh | ✅ | ❌ | ❌ | /root/xyptdq/scripts/restore.sh |
| health-check.sh | ✅ | ✅ | ✅ | /root/xyptdq/scripts/health-check.sh |

### 脚本说明

- **deploy.sh**: backup → git checkout → rsync to webroot → fix permissions → health check
- **rollback.sh**: 从指定backup ID恢复
- **backup.sh**: 创建时间戳备份（文件tar.gz + 数据库dump + nginx配置 + checksums）
- **restore.sh**: 从backup恢复文件和数据库
- **health-check.sh**: 9项检查（Nginx, PHP-FPM, MariaDB, HTTPS 200, HTTP→HTTPS 301, SSL天数, 磁盘, DB连接, Nginx语法）

### .gitignore 排除项

```
config/database.php      # 含数据库密码
.env
*.key
*.pem
*.sql
site/uploadfile/         # 上传文件
site/cache/              # 运行时缓存
.workbuddy/
.github/workflows/       # PAT缺workflow scope
```

---

## 五、GitHub Actions

| 项目 | 状态 |
|------|------|
| `.github/workflows/` | ❌ 被.gitignore排除 |
| CI pipeline | 不存在 |
| 最近运行 | 无 |
| 所需Secrets | 未配置 |

### CI文件（本地存在但未推送）

文件 `.github/workflows/ci.yml` 本地存在，包含:
- PHP lint检查
- Nginx配置语法检查
- Secrets扫描
- HTML检查

**无法推送原因**: PAT缺少 `workflow` scope。

### ChatGPT能否自动部署到服务器?

**答案: NO**

缺少:
1. GitHub PAT的workflow scope
2. GitHub Actions Secrets (DEPLOY_HOST, DEPLOY_USER, DEPLOY_SSH_KEY)
3. 服务器端Deploy Key配置
4. 部署脚本端到端验证

### 最小补齐步骤

1. 生成新的GitHub PAT（包含 `workflow` scope）
2. 在GitHub仓库Settings → Secrets中添加:
   - `DEPLOY_HOST` = 94.103.5.248
   - `DEPLOY_USER` = root
   - `DEPLOY_SSH_KEY` = SSH私钥
3. 创建GitHub Actions workflow使用SSH部署
4. 或: 在服务器配置Deploy Key，设置cron定时 `git pull`

---

## 六、备份系统

| 项目 | 值 |
|------|-----|
| 备份目录 | /root/backups/ |
| 总大小 | 271M |
| 最新备份 | disaster_recovery_20260810_031958/ |
| 数据库备份 | database_dayrui.sql (344KB) |
| 完整数据库 | database_all.sql (2.3MB) |
| 校验文件 | checksums.md5, checksums.sha256 |
| 自动备份 | ❌ 无定时任务 |
| 保留策略 | 无（手动管理） |
| 部署前备份 | backup.sh支持（但需手动触发） |
| 剩余磁盘 | 27G |

### 备份内容

```
/root/backups/disaster_recovery_20260810_031958/
├── certbot_certificates.txt
├── checksums.md5
├── checksums.sha256
├── cron_d_listing.txt
├── crontab_root.txt
├── database_all.sql          # 所有数据库
├── database_dayrui.sql       # dayrui数据库
└── (文件备份在上级目录的tar.gz中)
```

### 能否真正恢复?

**PARTIAL** — 备份存在且checksum完整，但未实际恢复验证。

---

## 七、回滚系统

| 回滚类型 | 方法 | 验证状态 |
|----------|------|----------|
| 代码回滚 | `git checkout v1.0.0-seo-article` | ❌ NOT VERIFIED |
| 数据库回滚 | `mysql < database_dayrui.sql` | ❌ NOT VERIFIED |
| 上传文件回滚 | `tar xzf backup.tar.gz` | ❌ NOT VERIFIED |
| Nginx回滚 | 手动恢复配置 | ❌ NOT VERIFIED |
| 完整灾难恢复 | restore.sh | ❌ NOT VERIFIED |

### 回滚操作命令

```bash
# 代码回滚
cd "G:/我的云端硬盘/BC/信誉平台大全网站"
git checkout v1.0.0-seo-article
# 然后手动SFTP上传模板文件到服务器

# 数据库回滚
ssh root@94.103.5.248
mysql -u dayruiuser -p dayrui < /root/backups/disaster_recovery_20260810_031958/database_dayrui.sql

# 完整恢复
/root/xyptdq/scripts/restore.sh disaster_recovery_20260810_031958
```

---

## 八、HTTPS 最终状态

| 项目 | 值 |
|------|-----|
| 主域名 | https://www.laocaimi.org |
| HTTP→HTTPS | ✅ 301重定向 |
| non-www→www | ✅ 重定向 |
| 证书 | Let's Encrypt |
| 到期 | 2026-11-08 |
| Certbot | 已安装 |
| 自动续期 | ✅ certbot.timer active |
| HSTS | ✅ max-age=31536000 |

**状态: 已解决，仅需验证不需要修改。**
