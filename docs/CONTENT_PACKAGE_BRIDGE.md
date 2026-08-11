# Approved Package → 网站草稿 → 迅睿 Native Publisher

内容源：`fdsasaaa/caipiaowenzhang`

网站：`fdsasaaa/xyptdq`

## 正式流水线

```text
Approved Package
  ↓ 网站侧再校验
Ingress pending（可选跨仓库接收层）
  ↓ convert_approved_to_draft.php
content/drafts/*.json
  ↓ 显式 promote_draft.php + publish_at
content/scheduled/*.json
  ↓ 现有 auto_publish_filequeue.php
已验证 cms_publish_native_adapter.php
  ↓
迅睿CMS
```

**禁止新增第二套直接SQL CMS发布器。** `config/publisher_capabilities.json` 已确认正式写入必须使用迅睿原生 `save_content` 生命周期和现有持久幂等注册。

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

同 article_id + 同 hash 幂等；同ID不同hash拒绝覆盖。Ingress 不等于 scheduled，也不写CMS。

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
- 同article_key不同hash的草稿拒绝静默覆盖。

输出默认 `content/drafts/<article_key>.json`，且：

- `publication_state=draft`
- **没有 `publish_at`**

因此当前定时发布器不会扫描它。

## 4. 分类映射

网站 canonical 导航当前正式分类：

- `gjfa` → catid 2
- `tzjq` → catid 3
- `zyyy` → catid 4

`seo-articles` 已退出正式分类映射，不再接受新的 Approved Package。当前阶段，所有准备作为 SEO 内容使用的普通文章统一使用：

- `site_category_key=tzjq`
- `catid=3`

Approved Package 仍必须显式提供 `site_category_key`；桥梁不根据标题或关键词猜 catid。若继续传入已退役的 `seo-articles`，转换器按 unknown category fail-closed，不会自动改写或发布。

后续如果平台评测、数据实验等内容积累到足以形成独立且有实质内容的 Hub，再通过新的架构变更显式分流；在此之前不创建空栏目。

## 5. Draft → Scheduled

必须显式执行：

```bash
php scripts/content/promote_draft.php \
  --input=content/drafts/lcm-xxxx.json \
  --publish-at=2026-08-12T09:00:00+08:00
```

晋级时再次检查 publication_state、schema、article_key、标题、正文、catid、hash和publish_at。

输出 `content/scheduled/<article_key>.json`，并设置：

- `publication_state=scheduled`
- `publish_at=<明确时间>`

只有这一步以后，文章才进入网站现有发布系统的扫描范围。

## 6. Native Publisher

继续复用网站已有：

- `scripts/content/auto_publish_filequeue.php`
- `scripts/content/cms_publish_adapter.php`
- `scripts/content/cms_publish_native_adapter.php`
- `config/publisher_capabilities.json`

已验证能力包括 Xunrui native save_content、shared-index路由、HTTP与sitemap一致性、durable article_key idempotency。

## 7. Schema Probe

`inspect_xunrui_content_schema.php` 继续保留为只读诊断工具，但不再用于设计新SQL writer。

## 8. 离线自测

```bash
php scripts/content/self_test.php
```

当前CI覆盖：Approved Package正常/错误状态/hash篡改、ingress幂等、缺site_category_key失败、`tzjq → catid 3`、convert只生成draft且无publish_at、promote才生成scheduled并保留source_content_hash。

## 当前状态

- Approved Package validation：**READY**
- Ingress staging：**READY**
- Approved → Draft conversion：**READY**
- Draft → Scheduled promotion：**READY**
- Native CMS publisher：**EXISTING / VERIFIED / REUSED**
- SEO文章正式分类：**RETIRED; NEW SEO ARTICLES USE tzjq/catid=3**
- Direct SQL content writer：**PROHIBITED**
- 自动把Approved直接发布：**PROHIBITED**
