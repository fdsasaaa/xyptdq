# SEO Project Handoff — Canonical Current State

> Mandatory continuity entrypoint for `fdsasaaa/xyptdq`. New sessions must read this file, `docs/seo/SEO_CHANGELOG.md`, `config/seo_project_state.json`, `content/keyword_map.json`, `content/seo_target_registry.json`, `content/seo_cluster_registry.json`, `config/content_category_map.json`, `config/content_source_sync_policy.json`, `docs/CROSS_REPO_CONTENT_SYNC.md`, and `docs/seo/SEO_INTERNAL_LINK_ARCHITECTURE.md`, then inspect newer PRs/results before changing anything.

## 1. Current phase

- Website repository: `fdsasaaa/xyptdq`
- Production: `https://www.laocaimi.org`
- Independent article engine: `fdsasaaa/caipiaowenzhang`
- Current phase: **let the article engine accumulate real transportable Approved Package files before creating Hubs or enabling cross-repo transport**.
- Earlier technical SEO remediation is closed unless a regression is proven.
- Ordinary future SEO articles use one CMS carrier: `tzjq` / catid 3 / display label `投注机巧`.
- `seo-articles` is retired and must not be recreated.

## 2. Hard operating rules

1. `main` is canonical.
2. Source changes: isolated branch -> PR -> CI -> merge.
3. Production writes: rollback-gated Server Bridge only; never equate a merge or queued job with production success.
4. Article publishing remains frozen until explicit user approval.
5. Cross-repo transport is a separate gate and also remains disabled until explicit user approval.
6. Approved, Draft, Scheduled and Published remain distinct lifecycle states.
7. Do not create synonym CMS categories for `技巧`, `技术`, `方法`, `投注技巧` or similar same-intent wording.
8. Logical SEO clusters do not change the CMS category and do not authorize publication.
9. Never infer cluster identity from title text alone.
10. Never inject planned Hub URLs; real URLs require live verification or Publication Receipt evidence.
11. Internal-link body changes alter content hash and require revision + re-Approval.
12. **Registry status `approved` is not equivalent to a transportable Approved Package file in `articles/approved/`.**
13. Formal inventory staging is explicit; Approval alone must not silently stage an article.
14. Do not restart closed technical SEO work without regression evidence.

## 3. Publishing freeze — ACTIVE

Authoritative policy: `config/content_publication_policy.json`.

Current state:

- `publishing_enabled=false`
- Publisher cron absent
- 11 historical scheduled JSON files remain preserved inventory only
- automatic publication not allowed
- resume requires explicit user approval

The SEO/category/contract work completed on 2026-08-12/13 did not publish articles, restore cron, or consume the scheduled queue.

## 4. Cross-repo transport — PREPARED / DISABLED

Machine policy: `config/content_source_sync_policy.json`.

Future automatic source:

`fdsasaaa/caipiaowenzhang@main:articles/approved/`

Current state:

- `sync_enabled=false`
- only source status `approved` is eligible
- destination state is `draft`
- transport cannot create `publish_at`
- transport cannot promote to Scheduled
- transport cannot invoke Native Publisher
- transport cannot alter Publisher cron
- transport cannot consume the scheduled queue

Design: `docs/CROSS_REPO_CONTENT_SYNC.md`.

Transport activation and publication activation must remain two separate future approvals.

## 5. Category architecture — CURRENT PRODUCTION TRUTH

Retained:

- `gjfa` / catid 2 / 挂机方案 — automation/挂机 carrier
- `tzjq` / catid 3 / 投注机巧 — **single ordinary SEO article + betting-guide carrier**
- `zyyy` / catid 4 / 福利资源 — resources/download carrier

Retired/consolidated:

- `gdrz` — retired empty category
- `rjxm` — duplicate route remains consolidated/excluded
- `seo-articles` / former catid 7 — retired; zero remaining articles; old `dir=seo-articles` and `id=7` routes 301 to `tzjq`

CMS label `投注机巧` may remain. SEO wording such as `投注技巧` belongs naturally in titles, metadata, copy and Hub architecture rather than requiring a category rename.

## 6. `SEO文章` -> `投注机巧` production closure — COMPLETE

Authoritative production result:

- job `consolidate-seo-articles-into-tzjq-v7-20260812-01`
- result branch `agent/results/consolidate-seo-articles-into-tzjq-v7-20260812-01`
- PASS
- deploy PASS
- DB migration PASS
- rollback NO

Migrated IDs: 85, 86, 88, 91.

Verified:

- 4 main + 4 data rows migrated to catid 3
- missing share/hits rows for 85/86 repaired
- category 7 remaining content = 0
- both old category routes 301 to `tzjq`
- old nav links PC/Mobile = 0/0
- 4/4 article HTTP 200
- 4/4 self-canonical
- 4/4 migrated articles in regenerated sitemap
- old category absent from sitemap
- framework integrity PASS
- no publishing/cron/queue side effect

V7 is authoritative; V1-V6 are diagnostic history only.

## 7. Technical SEO baseline — CLOSED UNLESS REGRESSION

Latest full structural audit checkpoint:

- `seo-content-architecture-audit-20260811-05`
- PASS / COMPLETE
- canonical mismatch 0
- duplicate title groups 0
- duplicate H1 groups 0
- duplicate Description groups 0
- HTTP errors 0
- orphan pages 0
- active empty news categories 0
- homepage platform coverage 30/30
- only remaining opportunity class: `planned_primary_target_mapping_incomplete`

The old 71 sitemap total belongs to that checkpoint; sitemap was regenerated after category consolidation, so do not assume the same count without a new audit.

## 8. Keyword and target architecture

### Keyword Map

`content/keyword_map.json` version **1.1.2**.

Core rules:

- one exact primary keyword owner per distinct article/page
- same-intent synonyms share carriers unless SERP/corpus evidence justifies separation
- no thin variation pages
- no keyword stuffing
- preserve existing URLs
- do not map planned intents to weak pages merely to reduce an audit counter

Examples of current live carriers:

- `分分彩投注技巧` + `分分彩投注方法` -> `tzjq`
- FFC/hash/qiqu/ssc automation intents -> `gjfa`
- `信誉平台大全` -> homepage

### Symbolic target registry

`content/seo_target_registry.json` version **1.0.2**.

Seven planned Hub families:

1. `ffc_research_hub` — 分分时时彩研究中心
2. `hash_ffc_hub` — 哈希分分彩专题
3. `qiqu_ffc_hub` — 奇趣分分彩专题
4. `ssc_hub` — 时时彩技术中心
5. `racing_hub` — 赛车与飞艇专题
6. `platform_review_hub` — 平台评测与对比
7. `research_lab_hub` — 数据实验室

These are planning identities, not permission to create empty pages.

## 9. Logical SEO clusters — READY

Machine registry: `content/seo_cluster_registry.json` version **1.0.0**.

All ordinary articles still remain in `tzjq`. Logical clusters are:

- `ffc_research`
- `hash_ffc`
- `qiqu_ffc`
- `ssc`
- `racing`
- `platform_review`
- `research_lab`

Rules:

- assignment is explicit/editorial, not title-only guessing
- unassigned legacy/new content is allowed
- multiple membership is allowed when real
- one primary cluster when assigned
- planned Hub URL injection prohibited
- article-to-article links require real published URLs
- Hub links require a real HTTP-200/self-canonical Hub
- no self links or automatic all-to-all cluster linking
- natural contextual anchors preferred over repeated exact-match anchors

Design: `docs/seo/SEO_INTERNAL_LINK_ARCHITECTURE.md`.

Homepage remains the primary owner for `信誉平台大全`; a future `platform_review` Hub must target review/comparison intent instead of duplicating the homepage owner term.

## 10. Portable cluster metadata across both repositories — COMPLETE

Portable optional fields:

- `primary_seo_cluster_id`
- `secondary_seo_cluster_ids`

Article-engine PR `fdsasaaa/caipiaowenzhang#42` merged, commit `7ff5b09bb25ac477855150526994ee56df7576b4`.

Website PR `fdsasaaa/xyptdq#250` merged, commit `00c400f2b0fea062b8a3b5390c9d5a1edafcc447`.

Result:

- valid explicit cluster metadata can travel from article-engine immutable/editorial contract into Approved Package and website Draft
- unknown/duplicate/invalid assignments fail closed
- legacy packages without cluster metadata remain compatible
- website never guesses cluster from title/keyword text
- cluster metadata does not enable transport, scheduling, publication or Hub creation

CI gates PASS on both repositories.

## 11. Formal Hub readiness audit — READY

Article-engine PR `fdsasaaa/caipiaowenzhang#49` merged, commit `ce2d7d0f6f8dd5c59184bbf58d44c5b7fa656c28`.

Files:

- `engine/hub_readiness.py`
- `scripts/audit_hub_readiness.py`
- `docs/HUB_READINESS_AUDIT.md`

The audit deliberately distinguishes:

- Registry lifecycle state: `registry/articles.jsonl`
- Formal transport inventory: `articles/approved/*.json`

At audit introduction, `articles/approved/` contained only `.gitkeep`, so formal transportable Approved Package count was **0** even though Registry-approved lifecycle records existed separately.

The audit reports explicit cluster coverage but does not infer clusters from titles and never automatically declares a Hub ready.

## 12. Formal Approved Package inventory staging — READY / EXPLICIT

Article-engine PR `fdsasaaa/caipiaowenzhang#50` merged, commit `5f6dee70962cd1cc502afb0d4aa5bfdb83f095f2`.

Files/capabilities:

- `engine/formal_approved_inventory.py`
- `scripts/stage_formal_approved_package.py`
- `docs/FORMAL_APPROVED_INVENTORY.md`
- single generator supports explicit `--stage-approved`
- batch generator supports explicit `--stage-approved`

This closes the gap where successful Approval previously wrote only to a caller-chosen file or `runs/.../<article_id>/approved.json` and did not populate the canonical future transport source.

Formal staging validates:

- `status=approved`
- stable `article_id`
- non-empty content
- `content_hash` exactly matching content bytes
- fingerprint
- content type → website category mapping
- optional SEO cluster metadata

Idempotency/overwrite rules:

- exact same package -> `unchanged`
- same article ID with different content hash -> reject; revision + re-Approval required
- same article ID/content hash with different approved metadata -> reject; explicit inventory revision path required

**Staging is opt-in and is not website sync.** Approval alone still does not automatically stage. Staging does not create Drafts on the website, does not schedule, and does not publish.

Immediately after this capability merged, formal inventory remained 0 until real production-approved articles are intentionally staged.

## 13. Hub readiness rules

A Hub becomes eligible only when all relevant evidence exists:

- real formal Approved Package corpus is substantive
- primary intent is distinct
- useful explanatory copy and navigation exist
- real internal links exist
- live URL returns HTTP 200
- page self-canonicalizes
- sitemap inclusion is justified

Article count alone is not enough. The readiness audit is evidence, not authorization.

Preferred readiness order once formal corpus is large enough:

1. `ffc_research_hub`
2. `research_lab_hub`
3. `platform_review_hub`
4. Hash/Qiqu/SSC/racing only when corpus or SERP evidence supports them

Only after live verification may corresponding symbolic Keyword Map targets be replaced by the real URL.

## 14. Current next action — ACCUMULATE REAL APPROVED PACKAGES

The useful architecture work that can be done safely in advance is now complete.

For real production article batches that should join the future website corpus, use the article engine's validated `--stage-approved` path. Do **not** stage smoke/test approvals merely because Registry status says `approved`.

Next meaningful SEO work begins when:

- real Approved Package files accumulate under `caipiaowenzhang/articles/approved/`, allowing Hub readiness cluster coverage to become substantive; or
- the user explicitly approves enabling cross-repo Approved→Draft transport; or
- the user separately approves scheduling/publication.

Until then:

- keep `sync_enabled=false`
- keep `publishing_enabled=false`
- leave uncertain cluster assignments unassigned rather than guessing
- do not count Registry-only smoke approvals as transport inventory
- do not create empty Hub pages

## 15. Future end-to-end lifecycle

`source/generation -> dedupe -> rule/fact/evidence validation -> rewrite -> SEO optimization -> Approval -> explicit formal inventory staging -> articles/approved -> Hub readiness inventory -> future cross-repo Approved→Draft transport -> website Draft -> cluster/internal-link planning -> portfolio gate -> explicit scheduling -> Native Publisher -> Publication Receipt -> article Registry`

## 16. New-session takeover protocol

1. Read this handoff and the changelog/state files.
2. Read keyword, target and cluster registries.
3. Read category and cross-repo sync policies.
4. Inspect newer PRs/results.
5. Confirm both transport and publication are still disabled unless explicitly changed.
6. Treat `seo-articles` as retired and `tzjq` as the single ordinary SEO article carrier.
7. Distinguish Registry `approved` lifecycle records from formal `articles/approved/*.json` inventory.
8. Remember formal inventory staging is available but explicit; it does not imply transport or publication.
9. Do not build Hubs or activate automation until formal corpus/readiness evidence or explicit user approval justifies the next step.
