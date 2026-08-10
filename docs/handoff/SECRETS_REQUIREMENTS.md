# 脱敏 Secrets 需求文档

> **核心原则: ChatGPT 通常不需要知道 Secret 的值。需要的是 Secret 已经安全放在执行环境里。**

---

## 一、Secrets 总览

| Secret | 是否存在 | 用途 | 放置位置 | ChatGPT是否需要值 |
|--------|----------|------|----------|-------------------|
| SSH密码 | ✅ YES | 服务器root SSH登录 | 运行时由用户提供 | NO |
| DB_PASSWORD | ✅ YES | 网站数据库认证 | 服务器 database.php | NO |
| GITHUB_TOKEN | ✅ YES | GitHub仓库push/pull | 本地git remote URL | NO |
| SSL_PRIVATE_KEY | ✅ YES | HTTPS证书 | /etc/letsencrypt/live/ | NO |
| DEPLOY_SSH_KEY | ❌ NO | GitHub Actions部署 | GitHub Secrets | NO |
| DEPLOY_HOST | ❌ NO | 部署目标服务器IP | GitHub Secrets | NO |
| DEPLOY_USER | ❌ NO | 部署SSH用户 | GitHub Secrets | NO |

---

## 二、详细说明

### SSH密码

| 项目 | 值 |
|------|-----|
| 是否存在 | YES (CONFIGURED) |
| 用途 | 服务器root SSH登录 |
| 放置位置 | 运行时由用户提供，不存储在GitHub或文件中 |
| ChatGPT是否需要值 | NO — 需要时由用户提供 |
| 使用方式 | `paramiko.connect(host, username='root', password=***)` |

### 数据库密码

| 项目 | 值 |
|------|-----|
| 是否存在 | YES (CONFIGURED) |
| 用途 | 网站数据库认证 |
| 放置位置 | /www/wwwroot/59.110.217.6/config/database.php |
| ChatGPT是否需要值 | NO — PHP自动读取config |
| 使用方式 | CMS自动加载database.php配置 |

#### 数据库连接信息（非敏感）

| 项目 | 值 |
|------|-----|
| 类型 | MariaDB |
| 主机 | 127.0.0.1 |
| 端口 | 3306 |
| 数据库名 | dayrui |
| 用户名 | dayruiuser |
| 表前缀 | dr_ |

### GitHub Token

| 项目 | 值 |
|------|-----|
| 是否存在 | YES (CONFIGURED) |
| 用途 | GitHub仓库push/pull |
| 放置位置 | 本地git remote URL |
| Token类型 | Fine-grained PAT |
| 权限 | Contents (read/write), Metadata (read) |
| 缺少权限 | workflow scope |
| ChatGPT是否需要值 | NO — 需用户生成新token |
| 使用方式 | `git push origin <branch>` |

### SSL私钥

| 项目 | 值 |
|------|-----|
| 是否存在 | YES (CONFIGURED) |
| 用途 | HTTPS证书 |
| 放置位置 | /etc/letsencrypt/live/laocaimi.org/privkey.pem |
| ChatGPT是否需要值 | NO — certbot自动管理 |
| 使用方式 | Nginx配置引用，certbot自动续期 |

### DEPLOY_SSH_KEY

| 项目 | 值 |
|------|-----|
| 是否存在 | NO (MISSING) |
| 用途 | GitHub Actions SSH部署到服务器 |
| 放置位置 | GitHub Actions Secret |
| ChatGPT是否需要值 | NO — 需用户在GitHub配置 |
| 配置步骤 | 1. 生成SSH key对 2. 公钥加到服务器authorized_keys 3. 私钥存入GitHub Secrets |

### DEPLOY_HOST

| 项目 | 值 |
|------|-----|
| 是否存在 | NO (MISSING) |
| 用途 | 部署目标服务器IP |
| 放置位置 | GitHub Actions Secret |
| 值 | 94.103.5.248 |
| ChatGPT是否需要值 | NO — 已知公开IP |

### DEPLOY_USER

| 项目 | 值 |
|------|-----|
| 是否存在 | NO (MISSING) |
| 用途 | 部署SSH用户名 |
| 放置位置 | GitHub Actions Secret |
| 值 | root |
| ChatGPT是否需要值 | NO — 已知 |

---

## 三、环境变量方式

如后续脚本需要数据库认证，使用环境变量:

```bash
export DB_HOST=127.0.0.1
export DB_NAME=dayrui
export DB_USER=dayruiuser
export DB_PASSWORD=***  # 从database.php读取，不硬编码
```

### 报告格式

| 环境变量 | 是否已配置 |
|----------|----------|
| DB_HOST | YES |
| DB_NAME | YES |
| DB_USER | YES |
| DB_PASSWORD | YES |
| GITHUB_TOKEN | YES (但缺workflow scope) |
| DEPLOY_SSH_KEY | NO |

---

## 四、安全规则

1. **绝对不在** GitHub、Issue、PR、文档、聊天输出中打印:
   - root密码
   - 数据库密码
   - GitHub Token
   - SSH私钥
   - SSL私钥
   - API Secret

2. **可以报告** Secret的名称和状态（true/false/configured/missing），但禁止报告值。

3. 如果ChatGPT需要某项GitHub权限，只说明需要什么权限和最小Scope，不要生成或展示Token。

4. 敏感配置文件已通过 `.gitignore` 排除:
   - `config/database.php`
   - `.env`
   - `*.key`
   - `*.pem`
   - `*.sql`
