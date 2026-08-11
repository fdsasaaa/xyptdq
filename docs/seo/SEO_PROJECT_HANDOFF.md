# SEO Project Handoff — Canonical Current State

> Mandatory first-read continuity entrypoint for any new ChatGPT/Codex/agent session working on `fdsasaaa/xyptdq` SEO. Read this file, then `docs/seo/SEO_CHANGELOG.md`, `config/seo_project_state.json`, `content/keyword_map.json`, and `content/seo_target_registry.json`, then inspect commits/PRs after the recorded checkpoint before changing anything.

## 1. Project identity and scope

- Repository: `fdsasaaa/xyptdq`
- Production: `https://www.laocaimi.org`
- Current SEO phase: **keyword ownership and future content-carrier architecture**.
- Existing technical/content-architecture cleanup is closed unless a regression appears.
- The user is still collecting lottery-technique source material. Do not start bulk article publishing.
- `config/content_publication_policy.json` remains authoritative with `publishing_enabled=false`.
- Do not reinstall Publisher cron or consume the preserved scheduled queue unless the user explicitly approves the later publishing phase.

## 2. Non-negotiable operating rules

1. `main` is the only canonical source.
2. Source changes use isolated branch -> PR -> CI.
3. Production changes use independent rollback-gated Server Bridge jobs.
4. Never equate PR merge/job queueing with production success; read `agent/results/<job_id>`.
5. Keep article publishing frozen.
6. Do not mechanically defer/async legacy jQuery/Bootstrap head scripts without proving compatibility.
7. Follow Keyword Map same-intent consolidation; do not create synonym doorway/thin pages.
8. Do not make unverifiable profit/safety promises.
9. Update this handoff, changelog and state after meaningful milestones.

## 3. Technical SEO baseline — closed

Previously completed and not to be restarted without evidence of regression:

- Whole-site technical SEO major cleanup.
- SEO Growth Audit reached 0 opportunity.
- Missing image width/height reached 0 on audited page classes.
- Homepage 33/34 non-critical images lazy-load/async-decode; logo remains priority-loaded.
- Homepage links to all 30 published platform detail pages.
- Homepage single H1 contains `信誉平台大全`.
- Request-aware canonical metadata deployed.
- Sitemap routing cleanup reduced sitemap to 71 verified HTTP-200 URLs.
- Empty/duplicate/unroutable routes were removed from sitemap as appropriate.

## 4. Publishing freeze — ACTIVE

- Scheduled Publisher cron was paused and independently verified.
- 11 scheduled JSON files remain preserved inventory only.
- `config/content_publication_policy.json`: `publishing_enabled=false`, mode `content_preparation_freeze`.
- Publisher remains fail-closed while frozen.
- Draft/Approved-package infrastructure may exist in parallel, but Approved/Draft/Scheduled/Published states must remain distinct and must not bypass this freeze.

## 5. Phase 5 post-fix audit — CURRENT PRODUCTION TRUTH

Latest authoritative audit:

- Job: `seo-content-architecture-audit-20260811-05`
- Result branch: `agent/results/seo-content-architecture-audit-20260811-05`
- Status: PASS / COMPLETE
- Sitemap HTTP: 200
- Sitemap URLs: 71
- Crawled pages: 71
- Published news: 38
- Published platforms: 30
- Homepage platform-link coverage: 30/30
- Keyword-owner conflicts: 0
- Existing mapped path targets missing: 0
- Canonical mismatch: 0
- Duplicate title groups: 0
- Duplicate H1 groups: 0
- Duplicate Description groups: 0
- HTTP errors: 0
- Orphan pages: 0
- Active empty news categories: 0
- Remaining opportunity classes: **1**
  - `planned_primary_target_mapping_incomplete`

This means the previous structural opportunity set is closed. Do not re-open orphan/H1/Description/empty-category work unless a later audit shows regression.

## 6. Important production fixes after the earlier handoff

### Canonical category internal links

The first deploy job `deploy-canonical-category-nav-v1-20260811-01` returned FAIL with an empty payload, so it was not accepted as proof. A separate read-only production diagnostic `seo-orphan-link-diagnostic-20260811-02` then proved that the intended canonical `dir=` links were actually live on shared navigation. The final Phase 5 audit independently confirmed orphan count = 0.

### Duplicate Description closure

A first database-field hypothesis failed closed before writes. A later v2 template deploy used an incorrect `xm` module assumption, detected no effective fix, and rolled back successfully.

Read-only mapping `seo-show-module-mapping-diagnostic-20260811-01` proved all 20 duplicate-Description show pages are `news`.

Final production job:

- `deploy-news-duplicate-description-hash-fallback-v3-20260811-01`
- PASS
- deploy PASS / rollback NO
- 20/20 affected descriptions matched the pre-deploy duplicate hash
- post-deploy PC unique descriptions: 20/20
- post-deploy Mobile unique descriptions: 20/20
- all descriptions contain their page title
- article91 and unaffected platform19 descriptions unchanged
- canonical navigation preserved
- framework integrity PASS

### Duplicate H1 closure

Read-only module mapping proved:

- show 74 = `xm`, software-project page
- show 75 = `news`, category 4 福利资源 page
- they were distinct cross-module pages sharing the same visible H1, not duplicate records

Production job `deploy-show-74-75-h1-v1-20260811-01`: PASS.

Public H1s are now factually distinguished:

- show 74: `长征（送首冲）｜软件项目`
- show 75: `长征（送首冲）｜福利资源`

PC/Mobile verified; canonical and Description unchanged; rollback NO.

### Empty `gdrz` category closure

Category id 5 `跟单日志` / `gdrz` was proven to contain 0 published and 0 nonpublished articles.

Production job `retire-empty-gdrz-category-v1-20260811-01`: PASS.

It was retired with exact identity/zero-content gates. No article publishing occurred.

## 7. Current category decisions

Evidence-based current decisions:

- `gjfa` / 挂机方案: **retain**. It has substantial published content and remains the real automation/挂机 carrier.
- `tzjq`: **retain**. It has real betting-technique content. SEO/public target label should be `投注技巧`; CMS legacy label is still `投注机巧`.
- `zyyy` / 福利资源: **retain** as a distinct resources/downloads carrier.
- `gdrz` / 跟单日志: **retired** because it was empty.
- `rjxm`: duplicate category route remains excluded/consolidated; do not restore it as an indexable duplicate.
- `seo-articles`: **transition-only**. It currently mixes betting-technique and platform-review articles and should not remain the long-term user-facing architecture.

A direct DB rename attempt for `tzjq` (`rename-tzjq-category-v1-20260811-01`) changed the DB but the rendered page stayed stale, so the job correctly rolled back. Do not repeat the DB-only rename. If this label is corrected next, use a presentation/cache-aware approach with live-render verification.

## 8. Keyword architecture — current version 1.1.1

`content/keyword_map.json` is now version **1.1.1**.

V1.1 rules remain intact: same-intent synonyms share targets; split only with SERP/corpus evidence; no thin variations.

PR #211 mapped only symbolic intents that already have justified live carriers:

- `分分彩投注技巧` + `分分彩投注方法` -> `/index.php?c=category&dir=tzjq`
- `分分彩挂机` -> `/index.php?c=category&dir=gjfa`
- `哈希分分彩挂机` -> `/index.php?c=category&dir=gjfa`
- `奇趣分分彩挂机` -> `/index.php?c=category&dir=gjfa`
- `时时彩挂机方案` -> `/index.php?c=category&dir=gjfa`

Do not map the remaining planned intents to unrelated existing pages merely to reduce an audit count.

## 9. Symbolic target registry — current architecture contract

`content/seo_target_registry.json` version 1.0.1 is the planning layer for targets that do not yet have real URLs.

It deliberately does **not** publish pages and does **not** replace Keyword Map targets with nonexistent URLs.

The 43 unique symbolic targets were consolidated into:

### Existing carriers

- automation intents -> `gjfa`
- FFC betting-guide intent -> `tzjq`

### Seven planned Hub groups

1. `ffc_research_hub` — 分分时时彩研究中心
2. `hash_ffc_hub` — 哈希分分彩专题
3. `qiqu_ffc_hub` — 奇趣分分彩专题
4. `ssc_hub` — 时时彩技术中心
5. `racing_hub` — 赛车与飞艇专题
6. `platform_review_hub` — 平台评测与对比
7. `research_lab_hub` — 数据实验室

Hard rule: **do not create empty Hub pages**. A Hub becomes a real URL only when it has a distinct primary intent plus substantive supporting content/internal links, then it must pass HTTP-200/self-canonical/internal-link checks before sitemap inclusion.

## 10. First unresolved SEO breakpoint — DO THIS NEXT

The technical Phase 5 set is closed. The first unresolved work is now **real content-carrier implementation**.

Recommended sequence:

1. Correct the public `tzjq` display label to `投注技巧` using a presentation/cache-aware solution; do not repeat the failed DB-only rename.
2. Reclassify/reframe the four articles currently under `seo-articles` so the transition category no longer mixes betting-technique and platform-review intent.
3. Implement the first real Hub only when existing/supporting content can make it substantive; do not create seven empty shells.
4. Highest-value first Hub candidates:
   - 分分时时彩研究中心
   - 数据实验室
   - 平台评测与对比
5. Once a Hub is actually live and verified, replace the corresponding symbolic Keyword Map targets with that real URL.
6. Hash/Qiqu/SSC/racing Hubs should wait until their supporting corpus is sufficient or SERP evidence justifies separation.

The remaining `planned_primary_target_mapping_incomplete` opportunity is expected until these real carriers exist. Do not chase a zero by assigning keywords to semantically weak pages.

## 11. Future harvested-article workflow — still frozen

Only after the user finishes collecting material and explicitly approves the publishing phase:

`source collection -> deduplication -> rule/fact validation -> rewrite -> SEO optimization -> Primary Target/Supporting Keywords -> cluster -> internal links -> cannibalization gate -> CMS draft -> quality gate -> controlled scheduled publication`

Until explicit approval, drafts/scheduled inventory must not be auto-published.

## 12. Key evidence / recent PRs

Important recent PRs:

- #177 post-routing Phase 5 audit queue
- #179 residual anomaly diagnostic
- #184 canonical category-navigation source fix
- #186 canonical-nav production queue (job result itself failed empty-payload; separate diagnostic proved production state)
- #198 verified `news` Description source correction
- #199 v3 Description deploy wrapper
- #200 H1 74/75 factual-role source fix
- #201 Description v3 production queue
- #202 H1 guarded deploy script
- #204 guarded empty-`gdrz` retirement script
- #206 H1 production queue
- #207 `gdrz` retirement production queue
- #208 `tzjq` DB rename attempt; production rolled back
- #209 final post-fix Phase 5 re-audit
- #210 symbolic target registry
- #211 existing-carrier Keyword Map bindings
- #212 registry sync to Keyword Map 1.1.1

Important result branches:

- `agent/results/seo-content-architecture-audit-20260811-05`
- `agent/results/seo-orphan-link-diagnostic-20260811-02`
- `agent/results/seo-show-module-mapping-diagnostic-20260811-01`
- `agent/results/deploy-news-duplicate-description-hash-fallback-v3-20260811-01`
- `agent/results/deploy-show-74-75-h1-v1-20260811-01`
- `agent/results/retire-empty-gdrz-category-v1-20260811-01`
- `agent/results/rename-tzjq-category-v1-20260811-01` (BLOCKED + rollback; not a successful rename)

## 13. New-session takeover protocol

1. Read this file from `main`.
2. Read the latest changelog and `config/seo_project_state.json`.
3. Read `content/keyword_map.json` and `content/seo_target_registry.json`.
4. Inspect commits/PRs after the recorded checkpoint.
5. Verify publishing freeze remains enabled.
6. Continue from section 10; do not restart technical SEO or old Phase 5 fixes.
