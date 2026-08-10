# ChatGPT 接管所需条件 - 待完成清单

> **日期**: 2026-08-10

---

## 一、真正缺失项

如果从现在开始完全停止 WorkBuddy 网站日常工作，ChatGPT 要继续完成 SEO、代码修改、GitHub、文章生产、自动文章发布系统，还缺以下条件:

### P0 - 必须完成

| # | 缺失项 | 说明 | 解决方式 |
|---|--------|------|----------|
| 1 | GitHub PAT with workflow scope | 当前PAT无法push GitHub Actions | 用户生成新token，勾选workflow scope |
| 2 | 服务器Git认证 | 服务器无法git pull | 配置SSH key或Deploy Key |
| 3 | 自动发布脚本 | 无文章自动发布能力 | 开发 auto_publish.php |
| 4 | Article Queue系统 | 无文章队列管理 | 开发SQLite队列 |
| 5 | 安全清缓存脚本 | 当前无标准化的安全清缓存方式 | 开发 safe_clear_cache.sh |
| 6 | robots.txt | 不存在 | 创建并部署 |
| 7 | sitemap.xml | 不存在 | 开发生成脚本 |

### P1 - 重要

| # | 缺失项 | 说明 | 解决方式 |
|---|--------|------|----------|
| 8 | 首页Meta标签 | keywords和description为空 | 在CMS后台设置或修改模板 |
| 9 | 文章生成工具 | 需要批量生成100+文章 | ChatGPT使用模板+关键词生成 |
| 10 | 关键词映射表 | 无正式Keyword Map | 创建 content/keyword_map.json |
| 11 | 定时备份 | 无自动备份 | 配置cron定时backup.sh |
| 12 | 部署脚本验证 | deploy.sh未端到端验证 | 在测试环境验证 |
| 13 | 回滚验证 | rollback.sh未实际验证 | 测试回滚流程 |

### P2 - 可选

| # | 缺失项 | 说明 | 解决方式 |
|---|--------|------|----------|
| 14 | GitHub Actions CI/CD | 无自动化CI/CD | 配置workflow |
| 15 | Canonical标签 | 文章页无canonical | 修改模板 |
| 16 | Open Graph | 无OG标签 | 修改模板 |
| 17 | 内链系统 | 无自动内链 | 开发内链组件 |
| 18 | 统一Link Registry | 注册链接硬编码在文章中 | 开发配置文件 |
| 19 | Google Search Console | 未验证是否接入 | 域名验证+提交sitemap |
| 20 | 百度搜索资源平台 | 未验证是否接入 | 域名验证 |
| 21 | URL伪静态 | 参数式URL不利于SEO | Nginx rewrite配置 |
| 22 | Schema.org | 无结构化数据 | 模板添加JSON-LD |

---

## 二、不需要的

| 项目 | 原因 |
|------|------|
| WorkBuddy常驻 | 自动发布通过服务器cron运行，不需要WorkBuddy在线 |
| 额外服务器 | 当前服务器足够（2GB RAM, 27GB磁盘） |
| 数据库迁移 | MariaDB 10.3 足够用 |
| PHP升级 | 7.4虽然EOL但CMS兼容 |
| CMS更换 | 迅睿CMS功能足够 |

---

## 三、最小补齐步骤

### 步骤1: 获取GitHub完整权限

```
用户操作:
1. GitHub → Settings → Developer settings → Fine-grained tokens
2. 创建新token，勾选:
   - Contents (read/write)
   - Metadata (read)
   - Workflows (read/write)
3. 替换本地git remote URL中的旧token
```

### 步骤2: 配置服务器Git认证

```bash
# 在服务器上生成SSH key
ssh root@94.103.5.248
ssh-keygen -t ed25519 -f ~/.ssh/deploy_key -N ""
cat ~/.ssh/deploy_key.pub

# 在GitHub仓库Settings → Deploy keys添加公钥
```

### 步骤3: 开发自动发布系统

```
ChatGPT任务:
1. 开发 auto_publish.php
2. 开发 article_queue SQLite
3. 开发 import_articles.php
4. 开发 safe_clear_cache.sh
5. 配置cron
```

### 步骤4: 创建SEO基础设施

```
ChatGPT任务:
1. 创建 robots.txt
2. 开发 generate_sitemap.php
3. 配置sitemap cron
4. 优化首页Meta标签
```

### 步骤5: 生成文章库存

```
ChatGPT任务:
1. 建立keyword_map.json
2. 批量生成100篇文章JSON
3. 导入article_queue
4. 配置发布计划
```

---

## 四、移交后 WorkBuddy 的角色

WorkBuddy以后仅保留为:

**服务器故障、SSH层故障、复杂生产环境事故时的特殊维修工具。**

不参与日常SEO、文章生成、代码修改、GitHub操作。
