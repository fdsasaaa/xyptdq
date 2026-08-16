# SEO Change Log

Append-only milestone log for the `fdsasaaa/xyptdq` SEO project. The canonical current state is `docs/seo/SEO_PROJECT_HANDOFF.md`.

## 2026-08-11

### Technical SEO baseline closed
- Whole-site technical SEO remediation reached 0 known issues in the post-remediation state.
- SEO Growth Audit reached 0 remaining opportunity classes.
- Missing image intrinsic dimensions reduced to 0 on audited page classes.
- Homepage native lazy loading added to 33 non-critical images; logo kept priority-loaded.
- Legacy blocking JS intentionally left unchanged because old jQuery/Bootstrap + inline `$()` dependencies make blind defer/async changes unsafe.

### Publishing paused for content-preparation phase
- Discovered the native scheduled Publisher cron was active while the current plan requires article publication to wait.
- First guarded pause attempt stopped safely because cron bytes differed from the overly narrow expectation; no deletion or publishing occurred.
- V2 reconstructed the installer-generated cron exactly, verified it byte-for-byte, removed it, and confirmed no alternate publisher cron references.
- PASS evidence: `agent/results/pause-native-publisher-cron-20260811-02`.
- 11 scheduled JSON files preserved; no publishing attempted.
- Added fail-closed `config/content_publication_policy.json` with `publishing_enabled=false` and blocked cron install/run paths until deliberate future approval.

### Keyword Map V1.1
- PR #147 merged.
- Consolidated same-intent synonym targets to reduce future thin pages and cannibalization.
- Added explicit rule: require SERP or corpus evidence before splitting same-intent synonyms into separate primary pages.

### Homepage platform internal-link closure
- PR #148 added one local platform-detail link per PC homepage platform card without changing the external register/login/contact buttons.
- PR #149 deployed through rollback-gated Server Bridge.
- PASS evidence: `deploy-home-platform-detail-links-v1-20260811-01`.
- Production verified 30 platform-detail links / 30 unique platform-detail links; representative routes HTTP 200; no commercial-link rel regression; rollback NO.

### Phase 5 V1 failure -> self-reporting V2
- V1 architecture audit failed with an empty payload; its original job pin also required correction.
- PR #152 introduced a self-reporting read-only V2 audit.
- PR #155 added CI compilation for embedded Python heredocs after `bash -n` proved insufficient.
- PR #156 fixed the exact embedded-Python syntax error caught by the new CI gate.
- PR #157 queued the fixed V2 retry.
- PASS evidence: `seo-content-architecture-audit-20260811-03`.
- V2 checkpoint inventory: 75 sitemap/crawled pages, 38 published news, 30 platform pages, 51 mapped keywords, 30/30 homepage platform-link coverage.
- V2 reported 9 opportunity classes: active empty news category, canonical mismatch, duplicate H1, duplicate meta descriptions, duplicate titles, homepage primary-keyword H1 gap, orphan pages, planned primary target mapping incomplete, sitemap HTTP errors.

### Targeted anomaly diagnosis
- PRs #163/#164 added and ran a read-only anomaly diagnostic.
- PASS evidence: `seo-content-anomaly-diagnostic-20260811-01`.
- It identified: empty `gdrz` news category, five category canonical mismatches, sitemap 404 show IDs 85/86, six orphan category routes, duplicate fallback-description groups, duplicate H1 groups, and a duplicate 404 title group.

### Dynamic fallback meta descriptions deployed
- PRs #160-#162 rebuilt and deployed page-specific fallback descriptions.
- PASS evidence: `deploy-dynamic-meta-description-v1-20260811-01`.
- Five sampled PC platform descriptions and five mobile descriptions were unique and included the platform title; explicit article description remained unchanged; rollback NO.

### Homepage primary keyword H1 deployed
- PRs #165-#167 changed the single homepage H1 to include `信誉平台大全` and deployed it through rollback gates.
- PASS evidence: `deploy-homepage-primary-h1-v1-20260811-01`.
- Production H1 count = 1; primary keyword present; homepage canonical PASS; 30 platform-detail links preserved; rollback NO.

### Request-aware canonical metadata deployed
- PR #169 fixed shared canonical/OG route logic; PRs #171/#173 deployed it.
- PASS evidence: `deploy-request-aware-canonical-v1-20260811-01`.
- Four substantive news categories self-canonicalize; `rjxm` remains intentionally consolidated to homepage; article/platform canonicals and OG semantics PASS; rollback NO.

### Sitemap public-routing cleanup deployed
- PRs #168/#170 tightened sitemap generation to visible/indexable news categories and shared-index-routable content.
- PRs #172/#175/#176 delivered the guarded production regeneration after verifier hardening.
- PASS evidence: `deploy-sitemap-routing-cleanup-v1-20260811-02`.
- Sitemap candidate count reduced from 75 to 71; all 71 returned HTTP 200; empty `gdrz`, duplicate `rjxm`, and unroutable show85/show86 were excluded; rollback NO.

### Post-routing Phase 5 re-audit and residual detail closure
- PR #177 was merged and `seo-content-architecture-audit-20260811-04` returned PASS with five residual opportunity classes.
- A second anomaly detail diagnostic identified the remaining concrete rows: empty `gdrz`, duplicate H1 show 74/75, one 20-page duplicate Description hash group, and four canonical category orphans.
- Canonical shared-navigation links were changed from alternate `id=` forms to the canonical `dir=` forms. The first deploy result was an empty failure payload, so it was not accepted as proof; read-only `seo-orphan-link-diagnostic-20260811-02` independently proved the canonical links were live.

### Duplicate Description root-cause correction and production closure
- A database-field cleanup attempt failed closed before writes because the duplicate value was not uniquely attributable to a CMS field.
- A first template v2 attempt scoped the hash fallback to `xm`; post-write verification proved the old hash persisted and the script rolled templates back successfully.
- Read-only `seo-show-module-mapping-diagnostic-20260811-01` proved all 20 affected show IDs were `news`.
- PRs #198/#199/#201 delivered the corrected v3 `news`-scoped hash fallback through full 20-page PC/mobile verification.
- PASS evidence: `deploy-news-duplicate-description-hash-fallback-v3-20260811-01`.
- Production result: 20 unique PC Descriptions, 20 unique Mobile Descriptions, all title-bearing; article91 and unaffected platform19 unchanged; rollback NO.

### Duplicate H1 74/75 resolved by factual role
- Module mapping proved show 74 (`xm`, software project) and show 75 (`news`, 福利资源) were distinct pages, not duplicate records.
- PR #200 introduced role-qualified display H1s and PRs #202/#206 delivered a guarded production deployment.
- PASS evidence: `deploy-show-74-75-h1-v1-20260811-01`.
- Public H1s now distinguish `长征（送首冲）｜软件项目` and `长征（送首冲）｜福利资源` on PC and Mobile while preserving canonical/Description metadata.

### Empty gdrz category retired
- Read-only category inventory proved `跟单日志` / `gdrz` had 0 published and 0 nonpublished articles.
- PR #204 added exact identity/zero-content guards; PR #207 queued the production retirement.
- PASS evidence: `retire-empty-gdrz-category-v1-20260811-01`.
- Category was retired with no publishing attempt.

### tzjq rename attempt safely rolled back
- Evidence supports retaining `tzjq` as the betting-technique carrier and using SEO intent wording `投注技巧` while the CMS legacy label is `投注机巧`.
- A DB-only rename attempt was deliberately live-render gated.
- Result `rename-tzjq-category-v1-20260811-01`: BLOCKED because the rendered page did not update after the DB change; rollback YES.
- Do not repeat the DB-only approach merely to force a synonym into the CMS category name.

### Final post-fix Phase 5 audit: structural issues closed
- PR #209 queued `seo-content-architecture-audit-20260811-05` using the already verified read-only V2 audit.
- PASS evidence: `agent/results/seo-content-architecture-audit-20260811-05`.
- 71 sitemap URLs / 71 crawled pages / HTTP errors 0 at that checkpoint.
- Canonical mismatch 0; duplicate titles 0; duplicate H1 0; duplicate Descriptions 0; orphan pages 0; active empty news categories 0.
- Keyword owner conflicts 0; mapped path targets missing 0; homepage platform-link coverage 30/30.
- Only remaining opportunity class: `planned_primary_target_mapping_incomplete`.

### Symbolic target architecture started
- PR #210 added `content/seo_target_registry.json` as a non-publishing architecture layer.
- 43 unique symbolic targets are consolidated into existing carriers plus seven planned Hub groups rather than 43 pages.
- Planned Hubs: 分分时时彩研究中心, 哈希分分彩专题, 奇趣分分彩专题, 时时彩技术中心, 赛车与飞艇专题, 平台评测与对比, 数据实验室.
- Registry prohibits empty/thin Hub creation and requires real content/internal links before a Hub can become an indexable sitemap URL.

### Keyword Map live-carrier bindings
- PR #211 upgraded `content/keyword_map.json` and bound only symbolic intents with justified current carriers.
- FFC betting guide -> `tzjq`; FFC/hash/qiqu/ssc automation -> `gjfa`.
- Remaining planned intents were intentionally not assigned to semantically weak pages.
- Keyword Map later reached version **1.1.2**; continuity files must use that current version.

### Current checkpoint before category consolidation
- Technical/content-architecture Phase 5 was closed except the expected future-Hub mapping class.
- Work moved to content-carrier architecture, not bulk article publishing.
- `seo-articles` remained a temporary mixed-intent category pending a safe consolidation.
- Publishing freeze remained active.

## 2026-08-12

### `SEO文章` -> `投注机巧` production consolidation complete
- User decision: retire `SEO文章`; future ordinary SEO articles use `tzjq` / catid 3 / CMS label `投注机巧`.
- Source policy was changed so `config/content_category_map.json` uses `seo_article_category_key=tzjq` and treats `seo-articles` as retired; navigation no longer exposes the old category.
- Read-only production diagnostics proved IDs 85/86/88/91 were the only four catid-7 articles. IDs 85/86 were valid published `news` content missing `share_index` and `news_hits`; IDs 88/91 were already fully routed.
- Multiple guarded iterations failed closed while refining exact production assumptions; V7 is authoritative.
- Authoritative PASS evidence: `agent/results/consolidate-seo-articles-into-tzjq-v7-20260812-01`.
- V7 production result: deploy PASS / DB migration PASS / rollback NO / blocker NONE; 4 main + 4 data rows migrated; 85/86 share/hits repaired; catid 7 retired; both old category routes 301 to `tzjq`; 4/4 article HTTP 200 and self-canonical; sitemap migrated article count 4; no publishing/cron/queue changes.
- Independent Bridge healthcheck `agent/results/bridge-healthcheck-20260812-11` returned PASS during closure.
- The former `SEO文章` category is now closed production history, not a future content carrier.

### Cross-repo content contract prepared
- Confirmed independent article engine `fdsasaaa/caipiaowenzhang` is already v2.2.0 and has Approved Package, SEO ownership, quality gates and Publication Receipt lifecycle support.
- Found and fixed contract drift: article-engine `seo_topic` now routes to `tzjq`; `seo-articles` is retired.
- Future automatic source inventory is `articles/approved/`.
- Added website machine gate `config/content_source_sync_policy.json` with `sync_enabled=false` and design doc `docs/CROSS_REPO_CONTENT_SYNC.md`.
- Even after future activation, transport may only move `approved` packages into website `draft`; it cannot create `publish_at`, schedule, invoke Native Publisher, alter cron, or consume the scheduled queue.
- Stable identity/dedup contract requires `article_id`, `source_fingerprint`, and `content_hash`; same id/different hash fails closed and requires revision + re-Approval.
- Corrected continuity state to actual `content/seo_target_registry.json` version **1.0.2**.
- No production CMS/database write and no article publication is part of this milestone.

### tzjq logical clusters and internal-link architecture prepared
- Added `content/seo_cluster_registry.json` version **1.0.0** as a logical SEO layer above the single `tzjq` CMS category.
- Defined seven logical clusters matching the planned Hub families: FFC research, Hash FFC, Qiqu FFC, SSC, racing/飞艇, platform review, and research lab.
- Cluster assignment must be explicit or editorially mapped; title-only guessing is prohibited. Unassigned is safer than guessed assignment.
- Multiple cluster membership is allowed when real, with one primary cluster when assigned; cluster membership never changes `site_category_key=tzjq` and never authorizes publication.
- Added `docs/seo/SEO_INTERNAL_LINK_ARCHITECTURE.md`.
- Planned Hub URLs may never be injected. Article→Hub requires a real HTTP-200/self-canonical Hub; Article→Article requires the target's real published URL; unresolved targets remain URL-null in planning.
- No self-links or automatic all-to-all cluster linking; natural contextual anchors are preferred over repeated exact-match anchors.
- Any body-link change changes the content hash and must go through revision + re-Approval.
- Homepage remains the primary owner for `信誉平台大全`; a future platform-review Hub must target comparison/review intent instead of taking the homepage's primary owner term.
- This milestone is source/configuration architecture only; it creates no Hub page and publishes no article.

### Portable SEO cluster metadata completed across both repositories
- Article engine PR #42 merged after CI passed. Approved Packages may now optionally carry `primary_seo_cluster_id` and `secondary_seo_cluster_ids` from immutable/editorial contract data; the body-writing model cannot invent cluster ownership.
- Article-engine validation is fail-closed for unknown, duplicate or structurally invalid cluster assignments. Existing approved articles without cluster metadata remain valid for backward compatibility.
- The stale semantic package label `SEO文章` for `seo_topic` was removed; the unified semantic/article carrier is now `投注机巧` / `tzjq`.
- Website PR #250 merged after `repository-ci`, `embedded-python-ci`, and `content-bridge-test` all passed.
- Website Approved→Draft conversion validates optional cluster IDs against `content/seo_cluster_registry.json`, permits them only with the `tzjq` carrier, preserves valid cluster metadata into Draft, and rejects invalid assignments without creating a draft.
- The website still never infers cluster identity from article title or keywords and never injects planned Hub URLs.
- This metadata path does not enable cross-repo transport, scheduling or publishing. `sync_enabled=false` and `publishing_enabled=false` remain authoritative.

### Next SEO stage
- Let the article engine accumulate a substantive Approved corpus while cross-repo sync and publishing remain disabled.
- Then inventory logical cluster coverage and assess which planned Hub has enough real supporting material.
- Preferred first readiness assessment: `ffc_research_hub`, then `research_lab_hub`, then `platform_review_hub`.
- Create no empty Hub and do not map symbolic targets to nonexistent URLs.

### Continuity protocol
- `docs/seo/SEO_PROJECT_HANDOFF.md`, this changelog and `config/seo_project_state.json` are the required continuity files.
- Future meaningful SEO milestones must update all three before the stage is considered closed.

## 2026-08-13

### Formal Hub readiness inventory audit added
- Article engine PR #49 merged with CI PASS, commit `ce2d7d0f6f8dd5c59184bbf58d44c5b7fa656c28`.
- Added read-only `engine/hub_readiness.py`, CLI `scripts/audit_hub_readiness.py`, tests, and `docs/HUB_READINESS_AUDIT.md`.
- The audit fixes an important state distinction: effective Registry records with `status=approved` are lifecycle memory and may include smoke/validation articles; they are **not** automatically formal cross-repository Approved Package inventory.
- Only real `articles/approved/*.json` files count as the future transport inventory used for Hub corpus coverage.
- At this checkpoint `articles/approved/` contains only `.gitkeep`, so formal transportable Approved Package count is **0** even though approved lifecycle records exist separately in the Registry.
- The audit reports explicit primary/secondary cluster coverage and validation errors but never infers clusters from titles and never auto-authorizes Hub creation.
- Article count/coverage alone cannot make a Hub ready; editorial intent, useful Hub copy/navigation, real internal links, HTTP 200 and self-canonical live verification are still required.
- Cross-repo sync and publication remain disabled; no production CMS/database write occurred.

### Formal Approved Package inventory staging added
- Article engine PR #50 merged with full CI PASS, commit `5f6dee70962cd1cc502afb0d4aa5bfdb83f095f2`.
- Added `engine/formal_approved_inventory.py`, `scripts/stage_formal_approved_package.py`, tests and `docs/FORMAL_APPROVED_INVENTORY.md`.
- Single-article and ranked-batch generation commands now support explicit `--stage-approved` after normal Approval succeeds.
- Approval alone still does not populate `articles/approved/`; staging remains a separate explicit action so smoke/test approvals cannot silently become future website inventory.
- Formal staging validates `status=approved`, stable article identity, exact content hash, fingerprint, content-type/category contract and optional SEO cluster metadata.
- Exact repeat staging is idempotent (`unchanged`). Same article ID with a different content hash fails closed and requires revision + re-Approval; same content hash with different approved metadata also fails closed rather than silently overwriting inventory.
- This closes the prior gap where approved artifacts could exist only in caller-selected output paths or `runs/.../<article_id>/approved.json` while the canonical future transport source stayed empty.
- Immediately after capability merge the formal inventory remained **0** until real production-approved articles are intentionally staged.
- Staging does not enable cross-repo sync, create website Drafts, schedule content or publish anything; `sync_enabled=false` and `publishing_enabled=false` remain authoritative.

### Article Production Controller added
- Article engine PR #53 merged after Python 3.10 / Python 3.13 CI PASS, merge commit `d5cb557aa71199fcb95bfa0bdca25cd5a70144f6`.
- Added `policies/ARTICLE_PRODUCTION_CONTROLLER.json`, `engine/production_controller.py`, `scripts/produce_articles_total.py`, `tests/test_production_controller.py`, and `docs/ARTICLE_PRODUCTION_CONTROLLER.md`.
- Natural-language requests such as “目标生成200篇正式文章” or “帮我生成500篇高质量文章” now map to a machine production target rather than a single uncontrolled model batch.
- Quantity means NEW formal Approved Package target, not raw generations. Default target is 200; recommended range 50–300; ordinary max 500; 501–2000 is large mode; over 2000 requires explicit ultra opt-in.
- Internal execution defaults to 25 articles per batch and policy limits normal internal batches to 20–30.
- Capacity preflight is mandatory and measures current executable content space after verified mechanics, knowledge-family, identity, exact Primary Keyword, structural novelty and SEO eligibility gates.
- The controller may stop below the requested target when current defensible content space is exhausted; it is explicitly forbidden from lowering evidence, quality, deduplication, SEO or compliance gates merely to fill the requested count.
- Generation/Approval/terminology/inventory failures do not count toward the formal target.
- CLI default is plan-only; explicit `--execute` is required before model calls and formal staging.
- Passing packages terminate at `caipiaowenzhang/articles/approved/*.json`; website sync, website Draft writes, scheduling, Publisher/cron operations and publication are not controller capabilities.
- Cross-repo transport and website publication therefore remain independently disabled after this milestone.

## 2026-08-16 — Draft intake reconciliation follow-up

### Automatic Draft intake fully reconciled and zero-count verifier fixed
- First natural `:23` intake run (`audit-first-scheduled-intake-20260816-01`) passed at 10:23 Asia/Singapore: 25 revisions were processed, ledger `3→28`, remaining candidates `30→5`, and all Draft-only/idempotency guards passed.
- The 11:23 run processed the remaining five revisions and actually completed ledger `28→33` / candidates `5→0`, but the old post-intake verifier falsely reported `expected=0 actual=0` as a failure after the durable writes had already succeeded.
- Read-only diagnosis `diagnose-scheduled-intake-failure-20260816-01` proved the production business state was complete and safe: ledger=33, runtime Draft files=33, candidates=0, final five absent, and no CMS/Scheduled/Publisher/cron mutation.
- Root cause was Python truthiness in `incremental_inventory_intake.py`: `int(after.get("new_draft_candidates") or -1)` converted legitimate zero to `-1`.
- PR #417 fixed zero-value handling and added regression coverage; merge `cea94bc700c325dcb0ac9eea8f9487fee78b5ae3` passed `incremental-intake-ci`, `repository-ci`, `embedded-python-ci`, and `content-bridge-test`.
- Read-only `audit-idle-intake-after-zero-fix-20260816-01` then passed across five natural post-fix cron slots (13:23, 14:23, 15:23, 16:23, 17:23 Asia/Singapore): every run was an `auto` no-op with selected=0, ledger=33, candidates=0.
- Current intake state is **healthy idle / fully reconciled**. All 45 current formal public-r1 are accounted for as 12 website-ingress revisions + 33 intake-ledger Drafts. The `:23` cron remains active only as an idempotent watcher for future upstream formal public-r1.
- The intake never created `publish_at`, promoted content to Scheduled, wrote CMS content, invoked Publisher, altered Publisher cron, or released CF50 final-five `020/029/038/039/040`.
- Do not manually replay the five revisions from 11:23; their business writes are already complete.
