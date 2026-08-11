# SEO Project Handoff — Canonical Current State

> This file is the canonical continuity entrypoint for any new ChatGPT/Codex/agent session working on `fdsasaaa/xyptdq` SEO. Read this file first before making changes. Then verify the referenced GitHub/Server Bridge evidence because this document may lag by one change if a session ended abruptly.

## 1. Project identity

- Repository: `fdsasaaa/xyptdq`
- Production site: `https://www.laocaimi.org`
- Current project focus: continue SEO optimization only.
- Article collection/rewrite/publishing is a later phase. Do **not** resume scheduled publishing until the user explicitly approves it after the draft-first workflow is ready.

## 2. Operating rules

1. Treat `main` as the canonical source.
2. Use isolated branches and PRs for changes; do not make unreviewed production edits.
3. Production-impacting work must use the existing Server Bridge / rollback-gated deployment pattern where applicable.
4. Never report a queued or merged Server Bridge task as successful until its `agent/results/<job_id>` evidence is read.
5. Keep production article publishing frozen during the current SEO architecture phase.
6. Do not chase technical scores by aggressively deferring old jQuery/Bootstrap scripts; the site has legacy inline `$()` dependencies and this is a known regression risk.
7. Future article SEO must follow `content/keyword_map.json`, avoiding thin near-duplicate pages and keyword cannibalization.
8. At the end of each meaningful SEO milestone, update this handoff and append a short entry to `docs/seo/SEO_CHANGELOG.md`.

## 3. Completed technical SEO baseline

The earlier technical SEO phase is considered closed unless a regression is detected:

- Whole-site technical SEO: 104 identified issues reduced to 0 in the post-remediation state.
- SEO Growth Audit: 5 opportunities reduced to 0.
- Image intrinsic dimensions: missing `width/height` reduced to 0 on audited page classes.
- Homepage: 34 images, 33 non-critical images use native `loading="lazy"` and `decoding="async"`; logo remains priority-loaded.
- Last known post-lazy performance audit: homepage TTFB about 0.104 s; mobile homepage about 0.0855 s; representative home/category/article/platform pages HTTP 200.
- Known remaining performance observation: legacy head-blocking scripts exist, but they are deliberately not being changed without dependency-safe proof.

Do not repeat these audits from scratch unless a regression, deployment, or material template change justifies it.

## 4. Publishing freeze — ACTIVE

Scheduled article publishing was found to be active even though the current workflow requires publishing to pause.

Resolved state:

- Server Bridge job: `pause-native-publisher-cron-20260811-02`
- Result: PASS
- `cron_before`: PRESENT
- `cron_after`: ABSENT
- `other_active_publisher_cron_refs`: 0
- `scheduled_queue_json_count`: 11
- `queued_articles_deleted`: false
- `article_publishing_attempted`: false

Additional fail-closed protection was merged in PR #145:

- `config/content_publication_policy.json`
- `publishing_enabled=false`
- `scripts/content/run_scheduled_publish.sh` exits without CMS writes while policy is frozen.
- `scripts/content/install_publisher_cron.sh` refuses to install the cron while policy is frozen.

The 11 scheduled JSON files are inventory only; they must not be automatically published during the current phase.

## 5. Keyword architecture — current version

`content/keyword_map.json` is now version 1.1.0 (PR #147).

Important rule change:

- Same-intent synonyms should share one primary target unless SERP/corpus evidence proves they deserve separate pages.
- Examples consolidated:
  - `分分彩技巧` + `分分彩技术` -> `ffc_skills_technology`
  - `分分彩投注技巧` + `分分彩投注方法` -> `ffc_betting_guide`
  - `哈希分分彩技巧` + `哈希分分彩技术` -> `hash_ffc_skills_technology`
  - `奇趣分分彩技巧` + `奇趣分分彩技术` -> `qiqu_ffc_skills_technology`
  - `时时彩技巧` + `时时彩技术` -> `ssc_skills_technology`
  - `彩票下载平台评测` + `彩票下载平台对比` -> `platform_review_hub`

Reason: avoid manufacturing thin variation pages and future keyword cannibalization from harvested article material.

## 6. Current SEO architecture audit status — NOT PASSED

Phase 5 content-architecture audit V1 was merged and executed through Server Bridge:

- Job: `seo-content-architecture-audit-20260811-01`
- Script: `scripts/ops/agent_tasks/seo_content_architecture_audit_v1.sh`
- Result: FAIL
- Exit code: 1
- Payload: empty
- Production writes: none were intended by this audit.

Do **not** treat Phase 5 V1 as completed. Immediate next engineering action is to create/execute a self-reporting diagnostic/V2 audit that always returns a safe phase/blocker payload for DB/crawl/schema failures, then use the successful inventory to drive fixes.

## 7. Important SEO finding already confirmed manually from source

PC homepage platform cards currently emphasize external register/login/QQ/Telegram links but do not provide a clear internal link from each platform card to that platform's own site detail page.

The platform detail template already contains useful internal navigation back to research/risk content. Therefore a likely high-value internal-link fix, after audit confirmation, is:

`Homepage platform card -> local platform detail page -> research/risk content`

This should be implemented without removing or changing the existing external buttons, and with rollback-gated production deployment.

Mobile homepage currently focuses on news/article links and does not mirror the PC platform grid; do not assume PC/mobile templates can receive identical changes.

## 8. Current sequence of work

Proceed in this order unless new evidence changes priority:

1. Diagnose Phase 5 V1 audit failure and produce a self-reporting V2.
2. Obtain a complete live inventory of CMS categories, published news, platform pages, sitemap URLs, duplicate titles/H1s, orphan pages and internal-link gaps.
3. Reconcile the live inventory against `content/keyword_map.json` V1.1.
4. Fix existing site architecture/internal linking before creating new article pages.
5. Review current category names/roles and decide keep/merge/rename based on actual inventory and keyword intent.
6. Define the future article intake contract: harvested source -> rewrite -> SEO target -> internal links -> draft -> later scheduled release.
7. Only after the user explicitly approves the publishing phase: design draft-first CMS import and controlled daily publication; then deliberately unfreeze publishing.

## 9. Known reference PRs / evidence

- PR #141 — Phase 5 content architecture audit V1 infrastructure.
- PR #142 — first publisher pause attempt; safely blocked by strict cron content guard.
- PR #144 — publisher pause V2; merged and later Server Bridge PASS.
- PR #145 — fail-closed content publication policy freeze.
- PR #147 — Keyword Map V1.1 same-intent consolidation.
- Result branch: `agent/results/pause-native-publisher-cron-20260811-02`
- Result branch: `agent/results/seo-content-architecture-audit-20260811-01` (FAIL; must diagnose)

## 10. New-session takeover instruction

When a new conversation/session starts, the correct first action is:

1. Read `docs/seo/SEO_PROJECT_HANDOFF.md` from `main`.
2. Read `docs/seo/SEO_CHANGELOG.md` for the last few entries.
3. Check recent commits/PRs after the handoff's last update.
4. Check any referenced pending/result Server Bridge jobs.
5. Continue from the first unresolved item in section 8; do not restart technical SEO or publishing work from scratch.
