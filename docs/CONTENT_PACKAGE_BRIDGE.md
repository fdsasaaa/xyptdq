# Approved Package → 网站草稿 → 迅睿 Native Publisher

内容源仓库：`fdsasaaa/caipiaowenzhang`

网站仓库：`fdsasaaa/xyptdq`

## 目标

只允许内容引擎中已经通过 Approval Pipeline、`status=approved` 的 JSON Package 进入网站内容流程。

正式方向是：

`Approved Package → 网站侧再校验 → draft article JSON → 显式晋级 scheduled → 现有 filequeue/native publisher → 迅睿CMS`

**禁止另写第二套直接SQL CMS发布器。** 网站已经有经过生产验证的 `scripts/content/cms_publish_native_adapter.php`，通过迅睿原生 `_module_init + content_model->save_content` 生命周期创建内容，并具有持久幂等能力。

## 为什么不能只 INSERT dr_1_news

网站已有生产验证证明，直接SQL只写内容表会漏掉共享模块路由。公开文章至少涉及 `dr_1_share_index` 等结构；孤立的 `dr_1_news.status=9` 记录可能形成404伪发布。

当前 `config/publisher_capabilities.json` 已把 native adapter 标为 verified，并明确 direct SQL writer 已退役。因此本桥梁只负责内容引擎协议适配、草稿隔离和晋级，不重新实现CMS数据模型。

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

## 2. 外部 ingress 队列

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

这个目录是跨仓库 Approved Package 的**接收层**，不是另一套发布队列。下一阶段会把通过映射校验的包转换成网站现有 article schema，并写入 `content/drafts/`。

## 3. 已存在的正式网站发布能力

网站已有：

- `scripts/content/import_articles.php`
- `scripts/content/auto_publish_filequeue.php`
- `scripts/content/cms_publish_adapter.php`
- `scripts/content/cms_publish_native_adapter.php`
- native / compatibility smoke harness
- `config/publisher_capabilities.json`

正式发布必须继续复用这些能力。

现有 native adapter 已验证：

- 迅睿 native `save_content` 生命周期；
- `dr_1_share_index` 路由完整性；
- 持久 article_key 幂等注册；
- 同一文章重复提交返回同一 cms_id；
- 发布后 HTTP、共享索引与 sitemap 一致性。

## 4. 下一阶段：Approved Package → Draft Article JSON

下一版桥梁要做的是**协议转换，不是写数据库**：

1. Approved Package 再校验；
2. `category` 映射成网站真实 `catid`；
3. `article_id` 映射成稳定 `article_key`；
4. title/content/meta/keywords/internal_links 转成网站现有 schema_version=1 article JSON；
5. 输出到 `content/drafts/`，而不是 `content/scheduled/`；
6. draft 不被当前定时发布器扫描；
7. 只有显式 promote 动作才复制/移动到 `content/scheduled/` 并设置 publish_at；
8. 一旦进入 scheduled，继续使用现有 native publisher，不新增CMS写库代码。

这样实现真正的：

`AI生成 ≠ 自动发布`

`Approved ≠ Scheduled`

`Scheduled ≠ Published（仍受现有publisher安全门禁控制）`

## 5. 只读迅睿 Schema 探测

```bash
php scripts/content/inspect_xunrui_content_schema.php > /tmp/xunrui-content-schema.json
```

该脚本继续保留为**诊断工具**，用于排查迅睿字段/路由变化。它读取服务器现有数据库配置，但不会输出账号密码，也不执行 INSERT/UPDATE/DELETE。

它不再是实现新发布器的前置条件，因为正式写入路径已经由 native adapter 验证完成。

## 6. Draft → Scheduled 晋级硬要求

未来 `promote_draft.php` 必须：

1. 只接受已通过网站侧校验的 draft article JSON；
2. category/catid 已有明确映射；
3. article_key、slug 唯一且稳定；
4. 内容长度、SEO字段、publish_at 校验通过；
5. 同 article_key 已 published 时禁止覆盖；
6. 晋级采用原子文件操作；
7. 进入 `content/scheduled/` 后继续由现有 filequeue/native publisher 处理；
8. 发布成功后最终URL、cms_id、published_at 回写 `caipiaowenzhang` Registry。

## 7. 离线自测

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

- Approved Package ingress：**ENABLED BY CODE / NOT AUTOMATICALLY INVOKED**
- Draft article converter：**NEXT PHASE**
- Draft → scheduled promotion：**NEXT PHASE**
- Native CMS publisher：**EXISTING AND VERIFIED**
- 新增直接SQL CMS writer：**PROHIBITED**
