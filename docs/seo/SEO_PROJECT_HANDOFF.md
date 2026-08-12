# SEO Project Handoff — Canonical Current State

> Mandatory first-read continuity entrypoint for any new ChatGPT/Codex/agent session working on `fdsasaaa/xyptdq` SEO. Read this file, then `docs/seo/SEO_CHANGELOG.md`, `config/seo_project_state.json`, `content/keyword_map.json`, `content/seo_target_registry.json`, `config/content_category_map.json`, `config/content_source_sync_policy.json`, and inspect newer commits/PRs/results before changing anything.

## 1. Project identity and current phase

- Repository: `fdsasaaa/xyptdq`
- Production: `https://www.laocaimi.org`
- Current SEO phase: **keyword ownership, substantive content-carrier architecture, and future cross-repo content contract preparation**.
- The earlier technical/content-architecture cleanup is closed unless a regression is proven.
- The user is still collecting/producing lottery-technique source material; do not start bulk article publishing.
- Future ordinary SEO articles use the single CMS article carrier `tzjq` / catid 3 / CMS label `投注机巧`.
- The retired `seo-articles` category must not be recreated.
- Independent content engine: `fdsasaaa/caipiaowenzhang`; its Approved inventory is the planned future content source, but automatic transport is currently disabled.

## 2. Non-negotiable operating rules

1. `main` is the only canonical source.
2. Source changes use isolated branch -> PR -> CI.
3. Production changes use rollback-gated Server Bridge jobs.
4. Never equate merge/job queueing with production success; read `agent/results/<job_id>`.
5. Keep article publishing frozen until the user explicitly approves the publishing phase.
6. Keep cross-repo transport separately gated from publishing; enabling one must never imply enabling the other.
7. Do not create synonym doorway/thin pages or duplicate article categories for SEO wording variants.
8. Same-intent synonyms should share carriers unless SERP/corpus evidence justifies a split.
9. Do not make unverifiable profit, safety, or guaranteed-result claims.
10. Do not mechanically defer/async legacy jQuery/Bootstrap head scripts without compatibility proof.
11. Update this handoff, changelog and `config/seo_project_state.json` after meaningful SEO milestones.

## 3. Publishing freeze — ACTIVE

- `config/content_publication_policy.json`: `publishing_enabled=false`.
- Scheduled Publisher cron is absent and previously verified paused.
- 11 historical scheduled JSON files remain preserved inventory only.
- Publisher remains fail-closed while frozen.
- Approved/Draft/Scheduled/Published states must remain distinct and must not bypass the freeze.
- No SEO category-consolidation job published an article, changed the publisher cron, or consumed the scheduled queue.

## 4. Technical SEO baseline — closed unless regression

The earlier whole-site technical remediation is complete for the audited page classes:

- canonical mismatch: 0
- duplicate title groups: 0
- duplicate H1 groups: 0
- duplicate Description groups: 0
- orphan pages: 0
- active empty news categories: 0
- HTTP errors in the Phase 5 crawl: 0
- missing audited intrinsic image dimensions: 0
- homepage links to all 30 published platform detail pages
- homepage H1 contains `信誉平台大全`
- request-aware canonical metadata deployed
- canonical `dir=` category navigation deployed and independently verified

Latest full Phase 5 baseline audit remains:

- job `seo-content-architecture-audit-20260811-05`
- result `agent/results/seo-content-architecture-audit-20260811-05`
- PASS / COMPLETE
- 71 sitemap URLs / 71 crawled pages **at that audit checkpoint**
- 38 published news / 30 published platform pages at that checkpoint
- only remaining opportunity class: `planned_primary_target_mapping_incomplete`

The sitemap was regenerated again during the later `seo-articles` consolidation, so do not treat the old total of 71 as a guaranteed current total without a fresh audit.

## 5. Category architecture — CURRENT PRODUCTION TRUTH

### Retained

- `gjfa` / catid 2 / 挂机方案: retain as the automation/挂机 carrier.
- `tzjq` / catid 3 / CMS label `投注机巧`: retain as the **single ordinary SEO article + betting-guide carrier**.
- `zyyy` / catid 4 / 福利资源: retain as a distinct resources/download carrier.

### Retired / consolidated

- `gdrz` / 跟单日志: retired because it contained zero content.
- `rjxm`: duplicate category route remains consolidated/excluded; do not restore as an indexable duplicate.
- `seo-articles` / former catid 7: **retired in production**. It has zero remaining articles and both its `dir=seo-articles` and legacy `id=7` routes 301 to `tzjq`.

### Naming rule

The CMS/public category label may remain `投注机巧`. Keyword targeting can naturally use the user-facing SEO intent wording `投注技巧` in titles, copy, metadata and Hub architecture. Do not repeat the failed DB-only rename attempt merely to force the synonym into the CMS category name.

## 6. `SEO文章` -> `投注机巧` production closure — COMPLETE

Authoritative production job:

- job: `consolidate-seo-articles-into-tzjq-v7-20260812-01`
- result branch: `agent/results/consolidate-seo-articles-into-tzjq-v7-20260812-01`
- status: **PASS**
- deploy: PASS
- DB migration: PASS
- rollback: NO
- blocking item: NONE

Migrated historical article IDs: 85, 86, 88, 91.

Verified production result:

- main rows migrated: 4
- data rows migrated: 4
- missing `share_index` rows repaired for 85/86: 2
- missing `news_hits` rows repaired for 85/86: 2
- category 7 remaining articles: 0
- category 7 retired: PASS
- old `dir=seo-articles` route -> 301 `tzjq`: PASS
- old `id=7` route -> 301 `tzjq`: PASS
- old-nav link count PC/Mobile: 0 / 0
- article HTTP 200: 4/4
- article self-canonical: 4/4
- migrated articles present in regenerated sitemap: 4/4
- old category present in sitemap: 0
- `tzjq` category present in sitemap: 1
- article 91 Description unchanged: PASS
- H1 controls for show 74/75: PASS
- framework integrity: PASS
- article publishing attempted: false
- publisher cron changed: false
- scheduled queue consumed: false

Earlier V1-V6 attempts are diagnostic history only. V7 is the authoritative final state.

## 7. Content category policy for all future SEO articles

`config/content_category_map.json` is the machine contract:

- `seo_article_category_key = tzjq`
- `seo-articles` is listed as retired
- unknown category keys fail closed
- packages must explicitly supply a valid site category key

Therefore: **Future SEO articles -> `tzjq` / 投注机巧.**

Do not recreate an `SEO文章` category and do not make separate categories for `技巧`, `技术`, `方法`, `投注技巧` or other same-intent synonyms merely for keyword targeting.

## 8. Keyword architecture — current version 1.1.2

`content/keyword_map.json` is version **1.1.2**.

Core rules remain:

- one primary keyword / one primary owner page
- no keyword stuffing
- no thin variation pages
- preserve existing article URLs
- consolidate same-intent synonyms
- require SERP/corpus evidence before splitting same-intent targets

Verified live carrier examples:

- `分分彩投注技巧` + `分分彩投注方法` -> `/index.php?c=category&dir=tzjq`
- `分分彩挂机` -> `/index.php?c=category&dir=gjfa`
- `哈希分分彩挂机` -> `/index.php?c=category&dir=gjfa`
- `奇趣分分彩挂机` -> `/index.php?c=category&dir=gjfa`
- `时时彩挂机方案` -> `/index.php?c=category&dir=gjfa`
- `信誉平台大全` -> homepage `/`

Do not map remaining planned intents to weak/unrelated pages simply to make an audit counter reach zero.

## 9. Hub architecture — planning layer, not extra article categories

`content/seo_target_registry.json` version **1.0.2** is the planning contract for targets without justified live URLs. It does not publish pages.

Seven planned Hub groups remain:

1. `ffc_research_hub` — 分分时时彩研究中心
2. `hash_ffc_hub` — 哈希分分彩专题
3. `qiqu_ffc_hub` — 奇趣分分彩专题
4. `ssc_hub` — 时时彩技术中心
5. `racing_hub` — 赛车与飞艇专题
6. `platform_review_hub` — 平台评测与对比
7. `research_lab_hub` — 数据实验室

Architectural rule after the category consolidation:

- underlying ordinary SEO articles remain in `tzjq`
- a Hub is a substantive topic aggregation/landing page, **not another synonym article category**
- do not create an empty Hub
- a Hub becomes a real keyword owner only after it has substantive copy/supporting content/internal links and passes HTTP-200/self-canonical/internal-link checks

## 10. First unresolved SEO work — DO THIS NEXT

The `SEO文章` consolidation is closed. The next SEO work is **content-carrier + internal-link architecture**, while the separate article engine accumulates approved content.

Recommended order:

1. Define the single-category article taxonomy/metadata rules for `tzjq` so future harvested articles can be clustered without creating more CMS article categories.
2. Define internal-link rules between articles and future Hubs, including primary-owner and cannibalization gates.
3. Prepare the first substantive Hub only when enough existing/supporting content exists.
4. Highest-value first Hub candidates remain: 分分时时彩研究中心, 数据实验室, 平台评测与对比.
5. After a Hub is live and verified, replace only its corresponding symbolic Keyword Map targets with the real URL.
6. Hash/Qiqu/SSC/racing Hubs should wait until the supporting corpus or SERP evidence justifies them.

Do not restart the already-closed orphan/H1/Description/canonical/empty-category work unless a new audit proves regression.

## 10A. Cross-repo Approved -> Draft contract — PREPARED / DISABLED

Content engine: `fdsasaaa/caipiaowenzhang`.

The future automatic source is only:

`caipiaowenzhang@main:articles/approved/`

Website machine gate:

- `config/content_source_sync_policy.json`
- `sync_enabled=false`
- destination state = `draft`
- no `publish_at`
- no promotion to Scheduled
- no Publisher invocation
- no cron change
- no scheduled-queue consumption

Design document: `docs/CROSS_REPO_CONTENT_SYNC.md`.

The article-engine publishing contract is being synchronized so `seo_topic` routes to `tzjq` and `seo-articles` is treated as retired. Transport and publication remain two separate approvals. A future transport implementation must fail closed while `sync_enabled=false`.

## 11. Future harvested-article workflow — still frozen

Current intended lifecycle:

`source collection / generation -> deduplication -> rule/fact validation -> rewrite -> SEO optimization -> Approval -> cross-repo Approved→Draft transport (future, separately gated) -> CMS draft -> quality/portfolio gate -> explicit scheduling -> controlled Native Publisher -> Publication Receipt`

Until explicit approval, cross-repo transport and automatic publication remain disabled.

## 12. Key current evidence

Most important production results:

- `agent/results/seo-content-architecture-audit-20260811-05`
- `agent/results/deploy-news-duplicate-description-hash-fallback-v3-20260811-01`
- `agent/results/deploy-show-74-75-h1-v1-20260811-01`
- `agent/results/retire-empty-gdrz-category-v1-20260811-01`
- `agent/results/consolidate-seo-articles-into-tzjq-v7-20260812-01`
- `agent/results/bridge-healthcheck-20260812-11`

Important closure PRs include #215 and #237-#245. The cross-repo content contract preparation follows after that closure and does not modify production.

## 13. New-session takeover protocol

1. Read this file from `main`.
2. Read `docs/seo/SEO_CHANGELOG.md` and `config/seo_project_state.json`.
3. Read `content/keyword_map.json`, `content/seo_target_registry.json`, `config/content_category_map.json`, and `config/content_source_sync_policy.json`.
4. Read `docs/CROSS_REPO_CONTENT_SYNC.md` before implementing any automatic article retrieval.
5. Inspect commits/PRs/results newer than this checkpoint.
6. Verify publishing freeze remains enabled and cross-repo `sync_enabled=false` unless explicitly changed later.
7. Treat `seo-articles` as retired and `tzjq` as the single future SEO article carrier.
8. Continue from section 10; do not restart closed technical SEO phases without regression evidence.
