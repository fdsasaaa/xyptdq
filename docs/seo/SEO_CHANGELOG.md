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
- Evidence supports retaining `tzjq` as the betting-technique carrier and using public label `投注技巧` instead of legacy `投注机巧`.
- A DB-only rename attempt was deliberately live-render gated.
- Result `rename-tzjq-category-v1-20260811-01`: BLOCKED because the rendered page did not update after the DB change; rollback YES.
- Do not repeat the DB-only approach. A presentation/cache-aware correction is the next safe route.

### Final post-fix Phase 5 audit: structural issues closed
- PR #209 queued `seo-content-architecture-audit-20260811-05` using the already verified read-only V2 audit.
- PASS evidence: `agent/results/seo-content-architecture-audit-20260811-05`.
- 71 sitemap URLs / 71 crawled pages / HTTP errors 0.
- Canonical mismatch 0; duplicate titles 0; duplicate H1 0; duplicate Descriptions 0; orphan pages 0; active empty news categories 0.
- Keyword owner conflicts 0; mapped path targets missing 0; homepage platform-link coverage 30/30.
- Only remaining opportunity class: `planned_primary_target_mapping_incomplete`.

### Symbolic target architecture started
- PR #210 added `content/seo_target_registry.json` as a non-publishing architecture layer.
- 43 unique symbolic targets are consolidated into existing carriers plus seven planned Hub groups rather than 43 pages.
- Planned Hubs: 分分时时彩研究中心, 哈希分分彩专题, 奇趣分分彩专题, 时时彩技术中心, 赛车与飞艇专题, 平台评测与对比, 数据实验室.
- Registry prohibits empty/thin Hub creation and requires real content/internal links before a Hub can become an indexable sitemap URL.

### Keyword Map 1.1.1 live-carrier bindings
- PR #211 upgraded `content/keyword_map.json` to 1.1.1.
- Only five symbolic intents with justified current carriers were resolved to live paths: FFC betting guide -> `tzjq`; FFC/hash/qiqu/ssc automation -> `gjfa`.
- Remaining planned intents were intentionally not assigned to semantically weak pages.
- PR #212 synchronized `content/seo_target_registry.json` to Keyword Map 1.1.1.

### Current checkpoint
- Technical/content-architecture Phase 5 is closed except the expected future-Hub mapping class.
- Current work moves to content-carrier architecture, not bulk article publishing.
- First unresolved items: public `tzjq` label correction via a cache/presentation-aware method; cleanup/reclassification of the mixed `seo-articles` transition category; then substantive Hub implementation as supporting content becomes available.
- Publishing freeze remains active.

### Continuity protocol
- `docs/seo/SEO_PROJECT_HANDOFF.md`, this changelog and `config/seo_project_state.json` are the required continuity files.
- Future meaningful SEO milestones must update all three before the stage is considered closed.
