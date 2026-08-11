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

### Current open checkpoint
- PR #177 is OPEN and mergeable: `Ops: queue post-routing Phase 5 production re-audit`.
- It adds pending job `seo-content-architecture-audit-20260811-04` using the fixed read-only V2 audit after canonical/sitemap cleanup.
- Next action: re-check PR #177 against current main, merge if still clean, read the resulting `agent/results/seo-content-architecture-audit-20260811-04`, then choose the next SEO fix from the new residual opportunity set.

### Continuity protocol
- Added `docs/seo/SEO_PROJECT_HANDOFF.md` as the mandatory first-read takeover document.
- Added this append-only changelog and `config/seo_project_state.json` machine-readable state.
- Future meaningful SEO milestones must update the handoff/state and append a short changelog entry before the session is considered complete.
