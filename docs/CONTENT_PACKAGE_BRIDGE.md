# Approved Package → 迅睿CMS 草稿桥梁

内容源仓库：`fdsasaaa/caipiaowenzhang`

网站仓库：`fdsasaaa/xyptdq`

## 目标

只允许内容引擎中已经通过 Approval Pipeline、`status=approved` 的 JSON Package 进入网站内容流程。

当前 v0.1 **不直接写生产数据库**。先建立：

`Approved Package → 再校验 → 外部pending队列 → 只读Schema探测 → 待确认的CMS Draft Importer`

这样避免在不了解迅睿实际字段和共享路由结构时猜SQL。

## 为什么不能只INSERT dr_1_news

网站的 sitemap 逻辑已经明确要求公开内容同时存在于共享路由索引 `dr_1_share_index`；只有 `dr_1_news.status=9` 的孤立记录可能形成404页面。因此未来导入器必须按迅睿真实数据模型事务性创建完整记录，而不是只写一个内容表。

相关现有代码：`scripts/seo/generate_sitemap.php`。

## 1. Package 再校验

```bash
php scripts/content/validate_approved_package.php approved.json
```

检查：

- `status=approved`；
- article_id/title/slug/meta/keyword/search_intent/category/content 等必填字段；
- rule_refs/source_refs 数组结构；
- case_scope；
- content_hash 与正文一致；
- slug 为单路径段；
- fingerprint 缺失时给出警告。

这不是替代内容引擎审核，而是网站侧 defense-in-depth。

## 2. 外部草稿队列

```bash
XYPTDQ_CONTENT_QUEUE=/var/lib/xyptdq/content-queue \
php scripts/content/stage_approved_package.php approved.json
```

默认目录：

`/var/lib/xyptdq/content-queue/pending/`

特性：

- 队列位于webroot之外；
- 原子写入；
- 同 article_id + 同 content_hash 重复执行为幂等；
- 同 article_id 已有不同hash待处理时拒绝覆盖，要求显式解决版本冲突；
- 不写CMS数据库。

## 3. 只读迅睿Schema探测

在服务器执行：

```bash
php scripts/content/inspect_xunrui_content_schema.php > /tmp/xunrui-content-schema.json
```

脚本读取服务器已有的 `config/database.php`，但不会输出账号密码，也不执行INSERT/UPDATE/DELETE。

当前探测：

- `<prefix>1_news`
- `<prefix>1_share_index`
- `<prefix>1_share_category`

输出：

- 表是否存在；
- 行数；
- 列名/类型/nullable/default/key/extra；
- 无默认值的必填字段。

只有拿到真实Schema后，才允许实现下一版事务型 `import_to_xunrui_draft.php`。

## 4. 下一版 Draft Importer 的硬要求

未来写库版本必须：

1. 只消费 pending 队列中的已验证 Package；
2. 先确认 category 到 `catid` 的映射；
3. 创建完整 Xunrui 内容与共享路由结构；
4. 默认写为**后台草稿/非公开状态**，不能直接 status=9 上线；
5. 全程数据库事务，任一步失败全部 rollback；
6. article_id/content_hash 建立幂等关联，禁止重复插入；
7. 导入后用CMS路由或本地请求确认草稿对象真实存在；
8. 发布仍需独立动作；
9. 发布成功后 sitemap 重新生成；
10. 最终URL与发布时间回写 `caipiaowenzhang` Registry。

## 5. 离线自测

```bash
php scripts/content/self_test.php
```

CI 会检查：

- 所有 content bridge PHP 文件语法；
- 正确Approved Package可通过；
- draft状态被拒绝；
- content_hash篡改被拒绝；
- 同一Approved Package重复入队只有一份pending文件。

## 当前状态

**CMS DB write：DISABLED**

这是刻意的安全门禁。只有Schema和迅睿草稿状态语义被实际确认后才会开启。
