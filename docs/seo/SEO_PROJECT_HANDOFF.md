# SEO Project Handoff — Canonical Current State

This checkpoint is current as of **2026-10-31 09:00:03 +08:00**. Read `config/seo_project_state.json`, `docs/seo/ORDINARY_SEO_RECOVERY_20261031.md`, the current publication/inventory/source-sync policies, Issue #264 and newer Server Bridge results before changing production.

## Current phase

Website: `fdsasaaa/xyptdq`, production `https://www.laocaimi.org`. Upstream article production: `fdsasaaa/caipiaowenzhang`. This website project owns intake, SEO, scheduling, Publisher, Sitemap and search feedback; upstream owns article creation, quality and public-release revisions.

**Ordinary SEO runtime recovery: PASS. CF50 search discovery: HOLD.**

- First CF50 wave: **12/12 live** (CMS 92–103). The previous 4/12 figure was an August checkpoint and must not be reused.
- Upstream formal manifests contain 97 public-release records (45 CF50 + 52 DAILY). Pre-recovery website intake ledger=85, plus 12 first-wave ingress records. Inventory is not publication authorization.
- CMS 104 was already published; its ledger is now repaired and its exact receipt/current live SEO checks pass.
- One ordinary article is scheduled for **2026-10-31 10:00 +08:00**. First new natural publication after recovery is still pending observation; expected Publisher poll is 10:07.
- Page 106 now redirects to 105 on PC/mobile, with matching visible content/download evidence and the duplicate removed from Sitemap. No CMS article was deleted.

## Automation and publication boundaries

- Draft intake: one independent `23 * * * *` watcher; it never creates publication authorization.
- Ordinary promotion: one `5 * * * *` watcher. The runner works without bridge-only environment and has durable results, an execution lock and one unfinished-item horizon.
- Publisher: one `7 * * * *` poll, isolated to `/var/lib/xyptdq-content/ordinary-seo/scheduled` and its own ordinary-seo state/lock.
- Editorial cadence: Tuesday/Thursday/Saturday, 10:00 +08:00, maximum three per calendar week. Hourly polling does not mean hourly publication.
- Exact Scheduled/Published lifecycle is reconciled into the intake ledger using shared locking, source/receipt identity checks and atomic writes. Preserve immutable Scheduled source and receipts.
- Never consume the historical repository Scheduled queue, publish raw Approved bodies, duplicate cron entries or replay already reconciled inventory.

## CF50 and Search Console

[Issue #264](https://github.com/fdsasaaa/xyptdq/issues/264) still records Search Discovery **HOLD**, Hub **HOLD**, final-five **NOT_AUTHORIZED**. Final IDs 020/029/038/039/040, Wave B and live Hub activation remain blocked. These CF50 gates must not disable ordinary DAILY SEO.

Current Search Console evidence is missing. Public HTTP/Sitemap checks and `site:` searches cannot establish clicks, rankings, indexing totals or completion of the GSC-dependent gate.

## Evidence and next checkpoint

The detailed recovery report links CI and the final server result `repair-ordinary-seo-runtime-20261031-04` (PASS). It confirms idempotent scheduling, live CMS 104 proof, duplicate redirect/Sitemap checks, cron singletons and unchanged CF50/legacy/framework-lock hashes.

Next: observe the scheduled ordinary article through durable Publisher state, receipt, exact ledger record and live SEO; obtain current Search Console evidence for #264. Keep the earlier technical foundation closed unless a concrete regression appears. This scoped recovery is not a new full-site zero-defect audit.

Historical August handoff and detailed proof chains are preserved at commit `aa112291efef3accabd07e463b07184da81d4fac`. Their old inventory counts and next-Seed slots are superseded by this checkpoint.
