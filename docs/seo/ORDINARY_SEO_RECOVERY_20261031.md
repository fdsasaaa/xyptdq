# Ordinary SEO recovery — 2026-10-31

Production recovery is **PASS** at 09:00:03 +08:00. This checkpoint replaces the August inventory and publication watermarks; historical implementation details remain in Git history at `aa112291efef3accabd07e463b07184da81d4fac`.

## Resulting behavior

- The unattended promotion runner has a durable default result path and reports failures. The installed hourly cron also provides that path explicitly.
- Exactly one promotion cron (`5 * * * *`) and one Publisher (`7 * * * *`) are installed. Editorial slots remain Tuesday/Thursday/Saturday at 10:00 +08:00, maximum three per calendar week.
- A separate promotion lock, one-pending-item horizon and overdue-item backpressure prevent duplicate scheduling and catch-up backlogs.
- The ledger now follows the exact source revision through Scheduled and Published. Reconciliation shares the intake lock, validates body/fingerprint and the exact Publisher state/receipt identity, rejects conflicting CMS IDs and downgrade, and commits atomically. Published CMS content is not republished during recovery.
- CMS 104 is proven published in its ledger and receipt, and passes fresh HTTP/canonical/indexability/Title/H1/Description/Sitemap checks.
- The first cron-environment run scheduled exactly one ordinary article. The repeated run added zero. The next target is `LCM-ANGLE-11c1d01b80765af0`, scheduled for **2026-10-31 10:00 +08:00**; the first new natural publication has not yet been observed.
- Page 106 redirects to 105 with HTTP 301 on PC and mobile. Their visible article text and exact download link were rechecked equal. The redirect is in the front controller before CMS rendering; the later entry is omitted from Sitemap. Both CMS records and the download bytes remain intact.

## Production evidence

- Read-only preflight: `audit-ordinary-seo-runtime-20261031-01`, 2026-10-31 08:40:58 +08:00. Intake ledger=85, ordinary Publisher published=1, but all 85 ledger entries were still Draft. Draft batches: CF50=33, DAILY-20260817=23, DAILY-20260901=14, DAILY-20260904=7, DAILY-20260905=8.
- Final repair: [`repair-ordinary-seo-runtime-20261031-04`](https://www.laocaimi.org/uploadfile/xyptdq-agent-results/repair-ordinary-seo-runtime-20261031-04.json), **PASS**, completed 09:00:03 +08:00. Exact script commit `a6e91f61fe510c1edd3ad06dcfee1521ec5ffc95` / SHA-256 `f053897b6c8e08cc51c7c3ff51d3e518c0ee2c5679fc65df9e4ec420f565c8f2`.
- Final ledger dry-run reports `changed_count=0`, proving idempotent reconciliation after the repair.
- Root-only backups were created before deployment. Earlier blocked attempts remain recorded; templates/cron were rolled back on failure and valid ledger recovery was preserved.
- CF50/legacy Publisher state and the framework lock hashes were unchanged.

## Validation

- [PR #504](https://github.com/fdsasaaa/xyptdq/pull/504): repository-ci, content-bridge-test, embedded-python-ci and website-v3-contract passed. All nine lifecycle/cron regressions ran successfully, including PHP compatibility and the actual root service identity.
- [PR #506](https://github.com/fdsasaaa/xyptdq/pull/506): actual front-controller prefix HTTP coverage added for PC/mobile, canonical destination and unaffected routes; checks passed.
- [PR #507](https://github.com/fdsasaaa/xyptdq/pull/507): exact public verification phase diagnostics, checks passed, followed by final production PASS.

## Independent gates and remaining evidence

CF50 first wave is 12/12 live. Issue #264 remains `CF50_SEARCH_DISCOVERY_GATE=HOLD`, `FFC_RESEARCH_HUB_GATE=HOLD`, `CF50_FINAL_5_RELEASE=NOT_AUTHORIZED`. Wave B, the live Hub and final-five IDs 020/029/038/039/040 remain blocked. Ordinary DAILY publication is independent of those gates.

Current Search Console Sitemap-processing, representative URL Inspection, clicks, impressions and rankings are not available. No organic-growth conclusion is asserted. A successful result collector is transport evidence, not publication or SEO-growth evidence. A fresh full-site crawl was not performed in this scoped repair.
