# SEO Project Handoff — Canonical Current State

> Mandatory continuity entrypoint for `fdsasaaa/xyptdq`. Read this file, `config/seo_project_state.json`, `docs/seo/SEO_CHANGELOG.md`, `content/keyword_map.json`, `content/seo_target_registry.json`, `content/seo_cluster_registry.json`, `config/content_category_map.json`, `config/content_source_sync_policy.json`, and `config/content_publication_policy.json`, then inspect newer PRs and `agent/results/*` before changing anything.

## 1. Current phase

- Website repository: `fdsasaaa/xyptdq`
- Production: `https://www.laocaimi.org`
- Article repository: `fdsasaaa/caipiaowenzhang`
- Phase 1 technical SEO remains **closed unless a real regression is proven**.
- Current phase: **CF50 first-wave recurring publication is active in production.**
- Do not restart the technical SEO audit and do not ask the user to reauthorize publication.

## 2. Content safety contract

`articles/approved/` in the private article repository is immutable parent/audit evidence. Raw Approved bodies are not the website publication body when a public-release revision is required.

Website-facing content must be a separately reviewed `website_public_release` revision that preserves article identity, slug, Primary Keyword, category/content type, parent hash/fingerprint and batch provenance, while using a non-operational public-facing body. The website independently validates the revision and uses sanitized transfer when needed. Never bulk-publish raw Approved bodies.

## 3. CF50 inventory and first wave

- Batch: `CF50-20260813`
- Formal Approved inventory: 50
- Reviewed first wave: 12
- First-wave order: `001, 011, 021, 031, 041, 046, 002, 012, 022, 032, 037, 049`
- High-overlap tail: `020, 029, 038, 039, 040`

CF50-001 is already live:
- revision `LCM-CREATOR-cf50-20260813-001:public-r1`
- CMS ID `92`
- URL `https://www.laocaimi.org/index.php?c=show&id=92`
- canary Server Bridge PASS
- live SEO PASS

Do not republish 001.

## 4. Recurring Publisher — PRODUCTION PASS

Authoritative policy: `config/content_publication_policy.json`.

Recurring activation v5 is the canonical production result:
- Server Bridge job: `activate-cf50-wave1-recurring-20260814-05`
- result branch: `agent/results/activate-cf50-wave1-recurring-20260814-05`
- status: **PASS**
- Publisher cron count: `1`
- cron schedule: `7 * * * *`
- source: `/var/lib/xyptdq-content/CF50-20260813-wave1/scheduled`
- state: `/var/lib/xyptdq-publisher/CF50-20260813-wave1/state.json`
- lock: `/var/lib/xyptdq-publisher/CF50-20260813-wave1/publisher.lock`
- historical repository Scheduled queue consumed: `false`
- CMS write during activation: `false`
- Wave B authorized: `false`

Do **not** reinstall or duplicate this cron. The hourly cron processes articles whose `publish_at` is due; planned editorial slots remain 10:00 and 19:00 Asia/Singapore, so the hourly job normally processes a due item around minute 07 after the hour.

At activation, the remaining 11 first-wave articles existed as exactly 11 isolated Draft + 11 isolated Scheduled files. Their schedule/category/Cluster/public-r1 provenance passed the read-only runtime probe.

## 5. Historical queue safety — HARD RULE

The website repository still contains 11 historical JSON files under `content/scheduled/`. They are preserved history only and are forbidden as the CF50 runtime source.

Do not weaken:
- isolated source guard;
- realpath guard;
- isolated state/lock guard;
- durable Publisher idempotency;
- legacy queue prohibition.

## 6. Publication cadence

- target: 2 articles/day
- timezone: Asia/Singapore
- editorial slots: 10:00 and 19:00
- first-wave cap: 12 total pages including 001
- after 12 live pages: mandatory search-discovery checkpoint before Wave B

The clock times are operating cadence, not claimed as a Google ranking signal.

## 7. Post-publication SEO is automatic

The scheduled runner now performs, for **new pages actually published in the current cron run**:

1. Native Publisher writes the CMS page through the existing idempotent adapter.
2. Sitemap is regenerated.
3. A Publication Receipt is exported for the new CMS ID.
4. `verify_publication_seo.php` verifies the live page and Sitemap.
5. PASS/WARN evidence is stored under the isolated Publisher state parent.

The live verifier checks the established contract including HTTP status, final URL/canonical, noindex, Title, H1, Description and Sitemap membership. A live-SEO verification failure is warning-gated: it does not roll back an already committed CMS page or corrupt Publisher idempotency.

## 8. New article inventory monitoring

An hourly condition-watch is active for `fdsasaaa/caipiaowenzhang`.

When new content appears:
- reviewed public-rN inventory may continue through website intake and future release planning;
- Approved-only inventory must first receive a separately reviewed public-release revision;
- raw Approved bodies are never sent directly to production;
- existing release-order/Cluster/search-discovery gates remain authoritative.

This removes the need for the user to manually announce new article inventory.

## 9. Category / keyword / Cluster rules

Ordinary SEO articles:
- category key `tzjq`
- catid `3`
- CMS display label `投注机巧`

Retired categories remain `seo-articles` and `gdrz`.

`content/keyword_map.json` v1.1.2 remains authoritative (51 keywords at formal checkpoint; exact owner conflicts 0). CF50 Primary Cluster is `ffc_research`, assigned explicitly/editorially, never guessed from title text.

`ffc_research_hub` remains blueprint-only and not live. Evaluate it only after the 12 diverse live seeds pass the required gates; do not create an empty/thin Hub.

## 10. Search-discovery checkpoint after first 12

Before Wave B, verify:
- HTTP 200;
- self-canonical;
- no noindex;
- Sitemap membership;
- Search Console Sitemap processing if available;
- representative URL Inspection Live Tests.

Do not require all 12 pages to be indexed before continuing; indexing can lag. A systemic robots/canonical/noindex/Sitemap blocker must hold Wave B.

## 11. Article-page visual design — NON-BLOCKING ENHANCEMENT

The user approved a professional research/blog reading style: restrained typography, clearer heading hierarchy, comfortable line-height, paragraph rhythm, lists/blockquote/table/image/link styling, and responsive mobile readability. Do not use rainbow keyword colors or exaggerated font-size SEO styling.

Three template/cache deployment attempts were rollback-safe and proved that final production HTML is controlled by an additional application/page cache layer. Android mobile UA also renders the responsive PC shell, not the separate mobile show template.

Therefore do **not** keep deleting template caches. Current strategy:
- read-only job `probe-live-article-css-assets-20260814-01` identifies the stylesheet URLs and exact production static CSS files used by article 92;
- then add a managed, tightly scoped CSS block to the actual live static stylesheet, targeting only the article main-body container;
- deploy with exact-file backup/rollback and verify HTTP/Title/canonical/cron remain unchanged.

Visual design must not block publication.

## 12. Immediate next actions

1. Let the active isolated cron continue the remaining first-wave publication; do not reinstall cron.
2. Confirm each real publication only after Publisher state/live URL evidence exists.
3. Use automatic post-publication Sitemap + receipt + live SEO evidence for each new page.
4. Finish the scoped static-CSS visual enhancement after exact live CSS path evidence; do not reopen template-cache attempts.
5. Continue hourly new-inventory monitoring; never publish raw Approved bodies directly.
6. Stop after the first 12 live seed articles and perform the search-discovery checkpoint before Wave B.
7. Keep Phase 1 closed unless a real regression appears.

## 13. New-session takeover protocol

A new session must first confirm current `main`, `config/content_publication_policy.json`, newer `agent/results/*`, Publisher state and current live article count. Canonical facts at this handoff are:
- CF50-001 is live as CMS ID 92 and passed live SEO;
- recurring activation v5 is production PASS with exactly one isolated Publisher cron;
- post-publication Sitemap/receipt/live SEO verification is merged;
- Wave B is not authorized;
- visual design is a non-blocking static-CSS enhancement in progress.

Continue from the first real publication/visual/checkpoint gap. Do not repeat Phase 1 and do not ask the user for publication authorization already recorded.
