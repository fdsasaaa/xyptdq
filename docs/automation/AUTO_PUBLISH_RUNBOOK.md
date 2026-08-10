# 自动文章发布运行手册

## 设计目标

一次性把文章库存保存到 GitHub，服务器只做确定性的导入、排程、发布、Sitemap 更新和日志记录。日常定时发布不调用任何大模型，也不依赖 WorkBuddy 在线。

## 架构

```text
ChatGPT
  ↓ 生成/审校文章 JSON
GitHub content/scheduled/
  ↓ 一次性同步到服务器
import_articles.php
  ↓
SQLite Article Queue
  ↓ cron（确定性任务）
auto_publish.php
  ↓
迅睿 CMS 发布适配器
  ↓
safe_clear_cache.sh
  ↓
generate_sitemap.php
  ↓
HTTP/SEO 验证
```

## 当前安全状态

自动发布目前处于 **WRITE LOCKED**。

原因：已确认文章主表 `dr_1_news` 与正文表 `dr_1_news_data_0`，但尚未通过一个已由 CMS 后台正常发布的文章确认 `news_index/news_time/news_search` 等辅助表的全部写入语义。直接假设“INSERT 两张表就等于正确发布”风险过高。

因此：

- `import_articles.php` 可以安全使用，只写本地 SQLite 队列。
- `auto_publish.php` 默认只做 dry-run。
- `--commit` 在 capability manifest 未验证时强制失败。
- `publisher_probe.php` 只读数据库，用于完成最后一次发布链路逆向。

## 文章文件

文章存放于：

`content/scheduled/*.json`

每篇文章必须有唯一 `article_key`。Git 中的文章是内容权威源；运行时 SQLite 只保存排程状态和 CMS 发布 ID，不进入 Git。

## 建议发布频率

第一阶段不要立即每天大量发布。

推荐：

- 前 14 天：每天 1–2 篇；
- 确认索引、页面质量、内链和技术 SEO 稳定后：每天 2–3 篇；
- 不为了“保持频率”发布低价值换皮稿。

发布频率本身不是排名保证，质量、独立搜索意图和内容价值优先。

## 启用发布前必须完成

1. 生产网站完整备份。
2. `publisher_probe.php --article-id=<一篇后台正常发布文章ID>`。
3. 审核 probe 输出，确认所有需要维护的辅助表。
4. 完成 CMS write adapter。
5. 在测试文章上执行一次真实发布。
6. 验证：文章页 200、栏目页可发现、首页可发现、缓存正常、Sitemap 收录新 URL。
7. 验证重复运行不会重复发布。
8. 才允许把 `publisher_capabilities.json` 设置为 verified。

## Cron（最终状态示例，当前不要直接安装）

```cron
# 导入 Git 中的新文章库存
10 7 * * * /usr/bin/php /root/xyptdq/scripts/content/import_articles.php >> /var/log/xyptdq-import.log 2>&1

# 发布到期文章（只有发布适配器验收后才加 --commit）
20 9 * * * /usr/bin/php /root/xyptdq/scripts/content/auto_publish.php --limit=1 --commit >> /var/log/xyptdq-publish.log 2>&1
20 17 * * * /usr/bin/php /root/xyptdq/scripts/content/auto_publish.php --limit=1 --commit >> /var/log/xyptdq-publish.log 2>&1

# 每日备份
0 3 * * * /root/xyptdq/scripts/backup.sh >> /var/log/xyptdq-backup.log 2>&1
```

发布器应在单篇文章成功后立即更新 Sitemap，因此不依赖每周一次 Sitemap cron。

## 失败处理

- 导入失败：文章留在 Git，修正 JSON 后重新导入。
- 发布失败：保留 scheduled/failed 状态和错误日志，不删除源文章。
- CMS 验证失败：不得把文章标记为 Published。
- Sitemap 失败：文章可暂时保留 Published，但必须发出错误并重试 Sitemap。
- 数据库或网站异常：停止后续文章发布，不连续重试冲击生产数据库。
