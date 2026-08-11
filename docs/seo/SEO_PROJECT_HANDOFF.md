# SEO Project Handoff — Canonical Current State

> Mandatory first-read continuity entrypoint for any new ChatGPT/Codex/agent session working on `fdsasaaa/xyptdq` SEO. Read this file first, then check recent PRs/commits and referenced Server Bridge results before changing anything. This file is intentionally updated after meaningful milestones so conversation-length limits do not break continuity.

## 1. Project identity and current scope

- Repository: `fdsasaaa/xyptdq`
- Production site: `https://www.laocaimi.org`
- Current focus: continue SEO optimization and existing-site architecture cleanup.
- Article collection/rewrite/publishing is a later phase.
- Do **not** resume automatic article publishing until the user explicitly approves the draft-first workflow.

## 2. Non-negotiable operating rules

1. `main` is the canonical source.
2. Use isolated branches + PRs for source changes.
3. Production-impacting changes must use the existing Server Bridge / rollback-gated deployment pattern where applicable.
4. Never report a queued/merged Server Bridge task as successful until its `agent/results/<job_id>` evidence is read.
5. Keep article publishing frozen during the current SEO architecture phase.
6. Do not chase technical scores by blindly adding `defer/async` to legacy head scripts; old jQuery/Bootstrap + inline `$()` dependencies are a known regression risk.
7. Future article SEO follows `content/keyword_map.json`; avoid thin near-duplicate pages and keyword cannibalization.
8. At each meaningful SEO milestone, update this handoff and append `docs/seo/SEO_CHANGELOG.md`.
9. Before trusting this document in a new session, inspect recent PRs after the last recorded checkpoint because work may have continued concurrently.

## 3. Technical SEO baseline — closed unless regression occurs

Earlier technical/growth cleanup is considered complete:

- Whole-site technical SEO: 104 identified issues -> 0 in the post-remediation state.
- SEO Growth Audit: 5 opportunities -> 0.
- Missing image intrinsic dimensions: 0 on audited page classes.
- Homepage: 34 images; 33 non-critical images use native lazy loading + async decoding; logo remains priority-loaded.
- Last known post-lazy timing: homepage TTFB about 0.104 s; mobile homepage about 0.0855 s.
- Representative home/category/article/platform routes remained HTTP 200.

Do not restart this phase from scratch unless a real regression or material template change justifies re-audit.

## 4. Article publishing freeze — ACTIVE and verified

Scheduled Publisher cron was discovered active despite the current requirement to pause content publication.

Verified state from `pause-native-publisher-cron-20260811-02`:

- Result: PASS
- `cron_before`: PRESENT
- `cron_after`: ABSENT
- `other_active_publisher_cron_refs`: 0
- `scheduled_queue_json_count`: 11
- queued JSON deleted: false
- article publishing attempted: false

PR #145 added a second fail-closed layer:

- `config/content_publication_policy.json`
- `publishing_enabled=false`
- scheduled runner exits without CMS writes while frozen
- cron installer refuses to reinstall while frozen

The 11 scheduled JSON files are preserved inventory only. Do not publish them automatically in the current phase.

## 5. Keyword architecture — current version

`content/keyword_map.json` = version 1.1.0 (PR #147).

Current rule:

- Same-intent synonyms share one primary target unless SERP/corpus evidence proves separate intent.
- Examples already consolidated:
  - `分分彩技巧` + `分分彩技术` -> `ffc_skills_technology`
  - `分分彩投注技巧` + `分分彩投注方法` -> `ffc_betting_guide`
  - `哈希分分彩技巧` + `哈希分分彩技术` -> `hash_ffc_skills_technology`
  - `奇趣分分彩技巧` + `奇趣分分彩技术` -> `qiqu_ffc_skills_technology`
  - `时时彩技巧` + `时时彩技术` -> `ssc_skills_technology`
  - `彩票下载平台评测` + `彩票下载平台对比` -> `platform_review_hub`

Purpose: prevent the future harvested-article pipeline from generating thin synonym pages or keyword cannibalization.

## 6. Phase 5 content architecture audit — V2 PASSED, fixes underway/completed

Historical V1 (`seo-content-architecture-audit-20260811-01`) failed with exit code 1 and empty payload. Do not use V1 as the current audit truth.

A self-reporting V2 was added/fixed through PRs #152-#157. The successful production audit is:

- Job: `seo-content-architecture-audit-20260811-03`
- Status: PASS
- Audit status: COMPLETE
- Sitemap HTTP: 200
- Sitemap URLs at that time: 75
- Crawled pages: 75
- Published news: 38
- Published platform pages: 30
- Keyword Map keywords: 51
- Keyword owner conflicts: 0
- Existing mapped path targets missing: 0
- Homepage platform internal-link coverage: 30/30
- Opportunity classes at that checkpoint: 9
  - active empty news category
  - canonical mismatch
  - duplicate H1
  - duplicate meta descriptions
  - duplicate titles
  - homepage primary-keyword H1 gap
  - orphan pages
  - planned primary target mapping incomplete
  - sitemap page HTTP errors

Important: several of these nine opportunities have since been fixed in production. The next re-audit must establish the new residual set.

## 7. Confirmed Phase 5 anomaly details

Targeted diagnostic job `seo-content-anomaly-diagnostic-20260811-01` PASS identified the concrete pre-fix anomalies:

- Active empty news category: `跟单日志` (`dir=gdrz`, category id 5).
- Five category canonical mismatches at that time: `gjfa`, `rjxm`, `seo-articles`, `tzjq`, `zyyy`.
- Two sitemap/public HTTP 404 rows: show IDs 85 and 86.
- Orphan category routes at that time: `gdrz`, `gjfa`, `rjxm`, `seo-articles`, `tzjq`, `zyyy`.
- Duplicate description groups included a large platform-page fallback group.
- Duplicate title group came from the two 404 show routes 85/86.
- Duplicate H1 groups included homepage vs `rjxm`, and duplicate platform names for show IDs 74/75.

Do not assume every item above is still present: several were addressed by later deployments below.

## 8. SEO fixes already deployed and independently verified

### A. Homepage -> local platform detail links — RESOLVED

PRs #148/#149.

Server Bridge job `deploy-home-platform-detail-links-v1-20260811-01`: PASS.

- 30 rendered platform detail internal links
- 30 unique platform detail links
- external commercial links without nofollow/sponsored: 0
- representative routes HTTP 200
- framework integrity PASS
- rollback NO

This closes the earlier homepage platform internal-link gap.

### B. Duplicate generic fallback meta descriptions — FIX DEPLOYED

PRs #160-#162.

Server Bridge job `deploy-dynamic-meta-description-v1-20260811-01`: PASS.

- 5 sampled PC platform descriptions all unique and all contain platform title
- 5 sampled mobile descriptions all unique and all contain platform title
- explicit article91 description unchanged
- framework integrity PASS
- rollback NO

### C. Homepage mapped primary keyword in single H1 — RESOLVED

PRs #165-#167.

Server Bridge job `deploy-homepage-primary-h1-v1-20260811-01`: PASS.

- homepage H1 count = 1
- homepage H1 contains `信誉平台大全`
- homepage canonical PASS
- platform detail links still count 30
- representative routes HTTP 200
- framework integrity PASS
- rollback NO

### D. Request-aware canonical metadata — DEPLOYED

PRs #169/#171/#173.

Server Bridge job `deploy-request-aware-canonical-v1-20260811-01`: PASS.

- four substantive news categories self-canonicalize
- `rjxm` duplicate category remains consolidated to homepage canonical
- article91 canonical PASS
- platform19 canonical PASS
- Article/website OG semantics verified
- framework integrity PASS
- rollback NO

### E. Sitemap routing cleanup — DEPLOYED

PRs #168/#170/#172/#175/#176.

Server Bridge job `deploy-sitemap-routing-cleanup-v1-20260811-02`: PASS.

- candidate sitemap URL count = 71 (down from prior 75)
- all 71 candidate URLs returned HTTP 200
- required substantive news categories present = 4
- empty `gdrz` category excluded
- duplicate `rjxm` category excluded
- unroutable show85 excluded
- unroutable show86 excluded
- rollback NO

## 9. Current unresolved checkpoint — DO THIS NEXT

PR #177 is currently OPEN and mergeable:

- Title: `Ops: queue post-routing Phase 5 production re-audit`
- Pending job file: `ops/jobs/pending/seo-content-architecture-audit-20260811-04.json`
- Purpose: run the fixed read-only V2 audit after canonical + sitemap cleanup.
- No production writes or article publishing.

**Immediate next action in a new session:**

1. Re-check PR #177 against current `main`.
2. If still clean/appropriate, merge it.
3. Wait for/read `agent/results/seo-content-architecture-audit-20260811-04`.
4. Record the new residual opportunity classes/count.
5. Only then choose the next SEO fix. Do not assume the old nine-opportunity list is still current.

Expected likely residual work after re-audit may include true content-architecture items such as:

- active empty/obsolete category decisions
- remaining real orphan/internal-link issues
- duplicate content that is not already removed by routing cleanup
- planned symbolic Keyword Map targets that do not yet map to existing content
- category keep/merge/rename decisions

But the re-audit is the source of truth.

## 10. Future article workflow — intentionally not active yet

After existing architecture is cleaned and the user's harvested technique corpus is ready, build this separately:

`harvested source -> rewrite/fact/rule validation -> primary SEO target -> internal-link plan -> duplicate/cannibalization check -> CMS draft -> controlled later daily publication`

The current site must remain publication-frozen until the user explicitly transitions to this phase.

## 11. Key reference PRs/evidence

- #145 publication fail-closed freeze
- #147 Keyword Map V1.1
- #148/#149 homepage platform internal links
- #152-#157 Phase 5 V2 + embedded-Python CI hardening
- #160-#162 dynamic meta-description fallback fix/deploy
- #163/#164 targeted anomaly diagnostic
- #165-#167 homepage primary H1 fix/deploy
- #168/#170/#172/#175/#176 sitemap public-routing cleanup/deploy
- #169/#171/#173 request-aware canonical fix/deploy
- #177 OPEN: post-routing Phase 5 re-audit queue

Important result branches:

- `agent/results/pause-native-publisher-cron-20260811-02`
- `agent/results/seo-content-architecture-audit-20260811-03`
- `agent/results/seo-content-anomaly-diagnostic-20260811-01`
- `agent/results/deploy-home-platform-detail-links-v1-20260811-01`
- `agent/results/deploy-dynamic-meta-description-v1-20260811-01`
- `agent/results/deploy-homepage-primary-h1-v1-20260811-01`
- `agent/results/deploy-request-aware-canonical-v1-20260811-01`
- `agent/results/deploy-sitemap-routing-cleanup-v1-20260811-02`

## 12. New-session takeover protocol

When a conversation hits its limit and a new one starts:

1. Read this file from `main`.
2. Read the latest entries in `docs/seo/SEO_CHANGELOG.md`.
3. Read `config/seo_project_state.json`.
4. Inspect recent PRs/commits after the handoff update.
5. Inspect any open PR named in section 9 and referenced Server Bridge result branches.
6. Continue from the first unresolved checkpoint; do **not** restart technical SEO, publishing setup or earlier solved fixes from scratch.
