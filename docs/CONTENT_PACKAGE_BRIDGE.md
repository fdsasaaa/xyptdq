# Approved Package → 网站草稿 → 迅睿 Native Publisher → Publication Receipt

内容源：`fdsasaaa/caipiaowenzhang`

网站：`fdsasaaa/xyptdq`

当前跨仓库生命周期合同版本：**Content Lifecycle v1 / Publication Receipt v1**。

## 正式流水线

```text
caipiaowenzhang Approved Package
  ↓ 网站侧 defense-in-depth 再校验
Ingress pending / content/ingress
  ↓ convert_approved_to_draft.php
content/drafts/*.json
  ↓ 只有显式 promote_draft.php + publish_at
content/scheduled/*.json
  ↓ 现有 auto_publish_filequeue.php
已验证 cms_publish_native_adapter.php
  ↓
迅睿 CMS
  ↓ filequeue runtime state 明确 status=published
export_publication_receipt.php
  ↓ Publication Receipt v1
caipiaowenzhang publication-receipt importer
  ↓ append-only Registry published state
published_url / cms_id
  ↓
Internal Link Planner 可解析真实 URL
```

**禁止新增第二套直接 SQL CMS 发布器。** `config/publisher_capabilities.json` 已确认正式写入必须使用迅睿原生 `save_content` 生命周期和现有持久幂等注册。

**禁止把 Approved Package 直接自动发布。** Draft、Scheduled、Published 是三个独立状态，状态提升必须显式发生。

## 1. Approved Package 再校验

```bash
php scripts/content/validate_approved_package.php approved.json
```

至少检查：`status=approved`、必填字段、rule/source refs、case_scope、content_hash、slug。

这是网站侧 defense-in-depth，不替代内容引擎 Approval Pipeline。

## 2. 跨仓库 Ingress

```bash
XYPTDQ_CONTENT_QUEUE=/var/lib/xyptdq/content-queue \
php scripts/content/stage_approved_package.php approved.json
```

同 article_id + 同 hash 幂等；同 ID 不同 hash 拒绝覆盖。Ingress 不等于 scheduled，也不写 CMS。

## 3. Approved Package → Draft

```bash
php scripts/content/convert_approved_to_draft.php --input=approved.json
```

转换器要求：

- `content_format=html` 明确存在；
- `site_category_key` 明确存在，禁止猜分类；
- 网站分类映射来自 `config/content_category_map.json`；
- 可见正文不少于180字；
- article_id 稳定映射为小写 article_key；
- content_hash 一致；
- 同 article_key 不同 hash 的草稿拒绝静默覆盖。

输出默认 `content/drafts/<article_key>.json`，且：

- `publication_state=draft`
- **没有 `publish_at`**

因此当前定时发布器不会扫描它。

## 4. Draft SEO Metadata Refresh

如果正文 bytes、`source_article_id`、`source_fingerprint`、`source_content_hash`、`article_key` 全部不变，只需要修正 title / seo_title / primary_keyword 等草稿 SEO 元数据，可显式使用：

```bash
php scripts/content/convert_approved_to_draft.php \
  --input=approved.json \
  --refresh-metadata
```

这是**草稿专用**通道。只有 existing `publication_state=draft` 且没有 `publish_at` 才允许。

以下任一变化都会拒绝 metadata refresh，必须进入正式正文 revision / re-Approval：

- content bytes 改变；
- source fingerprint 改变；
- source content hash 改变；
- source article id 改变；
- article key 改变；
- draft 已经带 `publish_at`。

默认不加 `--refresh-metadata` 时，正文 hash 相同仍维持原来的 `unchanged` 幂等行为。

## 5. 分类映射

网站 canonical 导航当前正式分类：

- `gjfa` → catid 2
- `tzjq` → catid 3
- `zyyy` → catid 4

`seo-articles` 已退出正式分类映射，不再接受新的 Approved Package。当前阶段，所有准备作为 SEO 内容使用的普通文章统一使用：

- `site_category_key=tzjq`
- `catid=3`

Approved Package 仍必须显式提供 `site_category_key`；桥梁不根据标题或关键词猜 catid。

## 6. Website SEO Portfolio Ownership Audit

CI 运行：

```bash
php scripts/content/seo_portfolio_audit.php
php scripts/content/seo_portfolio_audit_test.php
```

对于现代 managed content：

- `source_article_id` 是文章身份；
- exact `primary_keyword` 去 Unicode 空白并统一小写后，只能由一个不同的 article owner 占用；
- 同一 article 可同时存在于 draft + scheduled，因为 promote 当前采用复制语义；
- 同一 article 跨状态必须保持同 primary_keyword 与同 source_fingerprint；
- `source_content_hash` 必须证明实际 content bytes；
- draft 不得带非空 `publish_at`；
- scheduled 必须带 `publish_at`；
- `publication_state` 必须与目录一致。

### Pre-bridge legacy scheduled

网站现有 11 个 SEO 生产金丝雀在 Approved-Package bridge 建立以前创建，缺少现代 provenance 字段。为了不伪造历史，只对这 11 个**固定 article_key manifest** grandfather；不存在前缀或“缺字段即豁免”的通配规则。

当前真实 portfolio 审计基线：

- 总队列 JSON：19
- modern managed files：8
- modern managed drafts：8
- modern managed scheduled：0
- exact keyword owners：8
- keyword conflicts：0
- pre-bridge legacy scheduled exempt：11

因此：**`content/scheduled` 目录存在历史文件，不代表当前新8篇已排期。**

## 7. Draft → Scheduled

必须显式执行：

```bash
php scripts/content/promote_draft.php \
  --input=content/drafts/lcm-xxxx.json \
  --publish-at=2026-08-12T09:00:00+08:00
```

晋级时再次检查 publication_state、schema、article_key、标题、正文、catid、hash 和 publish_at。

输出 `content/scheduled/<article_key>.json`，并设置：

- `publication_state=scheduled`
- `publish_at=<明确时间>`

只有这一步以后，文章才进入网站现有发布系统的扫描范围。

**当前新8篇不得执行本步骤。**

## 8. Native Publisher

继续复用网站已有：

- `scripts/content/auto_publish_filequeue.php`
- `scripts/content/cms_publish_adapter.php`
- `scripts/content/cms_publish_native_adapter.php`
- `config/publisher_capabilities.json`

已验证能力包括 Xunrui native `save_content`、shared-index 路由、HTTP 与 sitemap 一致性、durable article_key idempotency。

Native CMS 成功 URL 当前为：

```text
https://www.laocaimi.org/index.php?c=show&id=<cms_id>
```

## 9. Publication Receipt v1

未来 managed article 真实发布成功后，先从**scheduled JSON + filequeue runtime state**导出回执：

```bash
php scripts/content/export_publication_receipt.php \
  --article=content/scheduled/<article_key>.json \
  --state=/path/to/publisher-state.json \
  --output=/path/to/receipt.json
```

导出器不会调用 publisher，也不会修改 CMS。

必须同时证明：

1. scheduled JSON 是 modern managed contract；
2. `publication_state=scheduled`；
3. source article/fingerprint/body hash 完整；
4. source body hash 与正文 bytes 一致；
5. runtime state 对同 article_key 明确 `status=published`；
6. runtime `cms_id` 为正整数；
7. runtime `published_at` 有效；
8. runtime publisher-level `content_hash` 与 exact scheduled JSON object 一致。

只有 cms_id、但 runtime state 不是 published，**不足以生成回执**。

回执包含：

- `schema_version=1`
- `receipt_type=publication_receipt`
- article_id / article_key
- fingerprint / content_hash
- cms_id / published_url / published_at
- publisher_article_hash
- source_file / site_base_url
- deterministic receipt_id

重复导出相同 publication identity 返回 `unchanged`；不同 identity 拒绝覆盖。

Pre-bridge legacy scheduled 因没有现代 provenance，不能制造 Publication Receipt v1。

### 传输信任边界

Publication Receipt v1 提供的是**字段、身份、hash 与 runtime publication state 的一致性合同**，不是独立的密码学签名。内容引擎端只应从受信任的网站仓库/Server Bridge 流程取得 receipt，再显式 import；不得接受来源不明的手工 JSON 作为生产发布证明。

## 10. 内容引擎反向导入

内容引擎 `caipiaowenzhang` 已实现：

```bash
python -m engine.cli publication-receipt \
  --file receipt.json
```

默认只验证和预览，不改 Registry。

只有经过受信任传输并确认后才显式：

```bash
python -m engine.cli publication-receipt \
  --file receipt.json \
  --record
```

`--record` 采用 append-only Registry lifecycle，写入 `published_url / cms_id / publication_receipt_id`。Importer 还会再次核对 Registry 中已有 fingerprint、content hash 与 website draft path。

## 11. Internal Link 生命周期

当前内容引擎只先规划：

```text
source article_id → target article_id
```

目标没有真实 `published_url` 时：

```text
resolution_status = pending_published_url
url = null
```

因此不会制造 404 链接。

目标经 Publication Receipt 进入 Registry published 状态后，Planner 才能解析真实 URL。即便如此，也**不能直接修改 Approved Package**：必须生成 `draft revision`，正文 hash 改变，再完整通过 Draft Review + Approval Pipeline，才能形成新的 Approved Package。

## 12. Schema Probe

`inspect_xunrui_content_schema.php` 继续保留为只读诊断工具，但不再用于设计新 SQL writer。

## 13. CI / 离线自测

网站 content bridge CI 当前覆盖：

- Approved Package validation；
- ingress 幂等；
- tzjq → catid 3；
- Approved → draft；
- batch1 / batch2 converter 回归；
- metadata refresh 正/负向安全门禁；
- website exact primary keyword ownership audit；
- pre-bridge closed manifest 与未知 legacy 反绕过；
- Publication Receipt exporter 正/负向回归；
- PHP syntax 与 repository safety guards。

## 当前冻结状态（2026-08-11）

- 内容引擎 Registry 新文章：**8 approved**
- 网站 modern managed drafts：**8**
- 网站 modern managed scheduled：**0**
- 网站 modern managed published：**0**
- 新文章真实 Publication Receipt：**0**
- Internal Link Planner：**READY，但当前 URL 全部 pending**
- Internal Link Revision Gate：**READY，但当前8篇因无真实 published_url 而 fail-closed**
- Native Publisher：**EXISTING / VERIFIED / REUSED**
- Direct SQL content writer：**PROHIBITED**
- Approved → direct publish：**PROHIBITED**
- 自动文章发布：**当前继续冻结**

相关已合并能力节点：

- website SEO metadata refresh：`f795fbe944b4758f0fcf5fa367289e452372dce6`
- website SEO portfolio audit：`7dbbe7d9e478cbb1d739b2a75adc554e87147a55`
- website Publication Receipt exporter：`bc59d008ac51c6501b4e07f57249fff95d7baec1`
- content-engine Publication Receipt importer：`69fdeeb987834de675e12decf7fc52ca149620dc`
