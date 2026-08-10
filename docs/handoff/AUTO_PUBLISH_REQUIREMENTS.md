# 自动发布系统需求分析

> **日期**: 2026-08-10  
> **目标**: 一次准备100篇文章 → 网站每天自动发布若干篇

---

## 一、当前定时任务现状

| 类型 | 状态 |
|------|------|
| Linux cron | 空（no crontab for root） |
| systemd timer | 仅系统默认（certbot等） |
| CMS内部计划任务 | 未发现原生定时发布功能 |
| GitHub Actions | 不行（PAT缺workflow scope） |

**结论: 当前无任何文章自动发布能力。**

---

## 二、文章发布链路分析

### 当前发布方式

```
CMS后台 (admin879acdb00a10.php)
    ↓ 手动填写文章
数据库 INSERT (dr_1_news + dr_1_news_data_0)
    ↓ 手动清缓存
首页文章列表自动更新
```

### 发布后必要动作

1. ✅ 文章列表自动显示（首页PHP直接查询）
2. ⚠️ 需手动清缓存 `cache/template/*` 和 `cache/data/*`
3. ❌ 无sitemap自动更新
4. ❌ 无搜索索引自动更新

### CMS内部API调查结果

| 入口 | 状态 | 说明 |
|------|------|------|
| CMS后台API | ⚠️ 未找到 | 需深入调查Fcms核心 |
| Service层 | ⚠️ 部分可用 | `\Phpcmf\Service::L('cache')->system()` 可重建缓存 |
| Model层 | ⚠️ 未定位 | `dayrui/Fcms/Model/` 下有文件 |
| CLI | ❌ 无 | 无CLI发布工具 |
| 计划发布 | ❌ 无 | CMS无原生定时发布 |

---

## 三、自动发布系统设计方案

### Article Queue 数据模型

| 字段 | 类型 | 说明 | CMS映射 |
|------|------|------|---------|
| id | int auto | 队列ID | 独立表 |
| title | varchar(255) | 标题 | dr_1_news.title |
| slug | varchar(255) | URL slug | dr_1_news.url |
| content | longtext | 正文HTML | dr_1_news_data_0.content |
| excerpt | text | 摘要 | dr_1_news.description |
| seo_title | varchar(255) | SEO标题 | dr_1_news.title |
| meta_description | text | Meta描述 | dr_1_news.description |
| primary_keyword | varchar(100) | 主关键词 | dr_1_news.keywords |
| secondary_keywords | varchar(500) | 副关键词 | (可拼入keywords) |
| category | int | 栏目ID | dr_1_news.catid (=7) |
| tags | varchar(500) | 标签 | (当前无tag系统) |
| thumbnail | varchar(255) | 缩略图 | dr_1_news.thumb |
| internal_links | text | 内链配置 | (正文HTML中) |
| publish_at | datetime | 计划发布时间 | 独立字段 |
| status | enum | Draft/Scheduled/Published/Failed | 独立状态 |
| cms_id | int | 发布后的CMS文章ID | dr_1_news.id |
| created_at | datetime | 入队时间 | 独立字段 |
| published_at | datetime | 实际发布时间 | 独立字段 |
| error_log | text | 失败日志 | 独立字段 |

---

## 四、推荐发布架构

### 方案对比

| 方案 | 描述 | 优点 | 缺点 | 推荐 |
|------|------|------|------|------|
| A | Markdown/JSON在GitHub，服务器读取发布 | 版本控制、可审计 | 需服务器git pull | ⚠️ |
| B | 文章提前导入CMS，未来时间发布 | 简单 | CMS无原生定时功能 | ❌ |
| C | 独立Article Queue数据库表 | 完整控制 | 需开发 | ✅ |
| D | 迅睿CMS原生定时发布 | 最标准 | 不存在此功能 | ❌ |

### 推荐方案: C + A 混合

```
GitHub: content/scheduled/
    ├── article_001.json    # 文章库存
    ├── article_002.json
    └── ...
    
服务器: auto_publish.php
    ├── 读取 content/queue.db (SQLite, Article Queue)
    ├── 检查 publish_at <= NOW()
    ├── INSERT into dr_1_news + dr_1_news_data_0
    ├── 清缓存
    ├── 标记 status=Published
    └── 记录日志

Cron: 每天定时运行 auto_publish.php
```

### 详细流程

```
1. [ChatGPT] 批量生成100篇文章 → JSON文件 → push GitHub
2. [服务器] git pull → 导入queue.db
3. [Cron] 每天运行 auto_publish.php
4. [Publisher] 检查待发布文章
5. [Publisher] INSERT数据库 → 清缓存
6. [Publisher] 更新queue状态
7. [首页] 文章列表自动显示
```

---

## 五、定时任务推荐

### 最佳方案: Linux Cron

| 方案 | 推荐 | 原因 |
|------|------|------|
| A. Linux cron | ✅ 推荐 | 简单、稳定、无需额外组件 |
| B. systemd timer | ⚠️ 可用 | 更现代但复杂度更高 |
| C. CMS原生 | ❌ 不可用 | 无此功能 |
| D. GitHub Actions | ⚠️ 备选 | 需修复PAT scope + 配置SSH |

### Cron 配置示例

```bash
# 每天早上8:00发布文章
0 8 * * * /usr/bin/php /www/wwwroot/59.110.217.6/auto_publish.php >> /var/log/auto_publish.log 2>&1

# 每天凌晨3:00备份
0 3 * * * /root/xyptdq/scripts/backup.sh >> /var/log/backup.log 2>&1

# 每周一凌晨4:00更新sitemap
0 4 * * 1 /usr/bin/php /www/wwwroot/59.110.217.6/generate_sitemap.php >> /var/log/sitemap.log 2>&1
```

---

## 六、幂等性设计

### 必须保证

同一篇文章不会因为以下原因发布两次:
- Cron重复运行
- 服务器重启
- 任务异常重试

### 实现方式

1. **Article ID唯一性**: queue表中每篇文章有唯一id
2. **Slug唯一性**: CMS中url字段唯一
3. **Status状态机**: Draft → Scheduled → Published → (Failed可重试)
4. **Lock机制**: 发布时获取文件锁 `/tmp/auto_publish.lock`
5. **CMS ID记录**: 发布成功后记录 `cms_id`，再次运行时检查
6. **重试限制**: Failed状态最多重试3次

### 数据库设计

```sql
CREATE TABLE article_queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    content TEXT NOT NULL,
    excerpt TEXT,
    keywords VARCHAR(255),
    description TEXT,
    thumbnail VARCHAR(255),
    catid INT DEFAULT 7,
    publish_at DATETIME NOT NULL,
    status ENUM('draft','scheduled','published','failed') DEFAULT 'draft',
    cms_id INT DEFAULT NULL,  -- 发布后的CMS文章ID
    retry_count INT DEFAULT 0,
    error_log TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    published_at DATETIME
);

CREATE INDEX idx_status ON article_queue(status);
CREATE INDEX idx_publish_at ON article_queue(publish_at);
CREATE UNIQUE INDEX idx_slug ON article_queue(slug);
```

---

## 七、文章库存架构推荐

### 推荐: 方案A + C 混合

```
content/
├── scheduled/           # 待发布文章 (JSON格式, 在GitHub中)
│   ├── 001_信誉平台选择指南.json
│   ├── 002_2026平台排行榜.json
│   └── ...
├── queue.db             # SQLite Article Queue (运行时生成)
├── keyword_map.json     # 关键词映射表
└── style_guide.md       # 内容格式指南

auto_publish.php         # 发布脚本 (在服务器上)
generate_sitemap.php      # Sitemap生成脚本 (在服务器上)
```

### JSON文章格式

```json
{
  "title": "信誉平台选择指南：如何识别可靠的平台",
  "slug": "xinyong-pingtai-xuanze-zhinan",
  "content": "<p>正文HTML...</p>",
  "excerpt": "本文详细介绍如何从多个维度识别和选择信誉良好的平台",
  "keywords": "信誉平台,平台选择,安全可靠",
  "description": "本文详细介绍如何从多个维度识别和选择信誉良好的平台，确保您的资金安全。",
  "thumbnail": "/uploadfile/202608/xxx.jpg",
  "catid": 7,
  "publish_at": "2026-08-15T08:00:00+08:00"
}
```

---

## 八、开发任务清单

### ChatGPT 需要开发的组件

| 组件 | 说明 | 优先级 |
|------|------|--------|
| auto_publish.php | 服务器端发布脚本 | P0 |
| article_queue.db | SQLite队列数据库 | P0 |
| import_articles.php | 从JSON导入queue | P0 |
| generate_sitemap.php | Sitemap生成 | P1 |
| clear_cache_safe.sh | 安全清缓存脚本 | P0 |
| cron配置 | 定时任务 | P0 |
| 文章生成工具 | ChatGPT生成100篇文章 | P1 |

### 安全清缓存脚本

```bash
#!/bin/bash
# safe_clear_cache.sh - 安全清缓存，不删关键文件
CACHE_DIR="/www/wwwroot/59.110.217.6/cache"

# 只清模板和数据缓存
rm -rf "$CACHE_DIR/template/"*
rm -rf "$CACHE_DIR/data/"*

# 确保关键文件存在
test -f "$CACHE_DIR/install.lock" || echo "2026-02-03 04:14:00" > "$CACHE_DIR/install.lock"
echo "CodeIgniter72" > "$CACHE_DIR/frame.lock"
mkdir -p "$CACHE_DIR/config"
cat > "$CACHE_DIR/config/system.php" << 'EOF'
<?php
return [
    'SYS_HTTPS' => 1,
    'SYS_301' => 0,
];
EOF

echo "Cache cleared safely."
```
