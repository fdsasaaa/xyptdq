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

CF50-001 is live:
- revision `LCM-CREATOR-cf50-20260813-001:public-r1`
- CMS ID `92`
- URL `https://www.laocaimi.org/index.php?c=show&id=92`
- canary Server Bridge PASS
- live SEO PASS

CF50-011 is also live after the 2026-08-14 scheduler repair test:
- article `LCM-CREATOR-cf50-20260813-011`
- CMS ID `93`
- URL `https://www.laocaimi.org/index.php?c=show&id=93`
- Server Bridge job `repair-test-cf50-011-cron-20260814-02`
- result branch `agent/results/repair-test-cf50-011-cron-20260814-02`
- status **PASS**
- live SEO **PASS**
- Wave1 state after publication: `1 published / 10 scheduled / 0 failed`
- next article: `LCM-CREATOR-cf50-20260813-021`
- next publish_at: `2026-08-15T10:00:00+08:00`

Do not republish 001 or 011.

## 4. Recurring Publisher — REPAIRED PRODUCTION PASS

Authoritative policy: `config/content_publication_policy.json`.

Recurring activation v5 originally installed the isolated production scheduler:
- Server Bridge job: `activate-cf50-wave1-recurring-20260814-05`
- source: `/var/lib/xyptdq-content/CF50-20260813-wave1/scheduled`
- state: `/var/lib/xyptdq-publisher/CF50-20260813-wave1/state.json`
- lock: `/var/lib/xyptdq-publisher/CF50-20260813-wave1/publisher.lock`
- historical repository Scheduled queue consumed: `false`
- Wave B authorized: `false`

A real production regression was then proven when CF50-011 missed its 2026-08-14 19:00 Asia/Singapore slot. The deeper read-only diagnostic `diagnose-cf50-011-cron-runtime-20260814-02` proved:
- `cron` daemon active and enabled;
- `/etc/cron.d/xyptdq-publisher` existed with correct root ownership/mode, `7 * * * *` schedule, root user and correct isolated source/state/lock bindings;
- deployed `scripts/content/run_scheduled_publish.sh` was mode `0600`, Bash syntax valid, but not executable;
- no Wave1 state had been created and no article had been consumed or published.

Root cause: cron directly executed the non-executable checkout of `run_scheduled_publish.sh`.

Durable fix: `scripts/content/install_publisher_cron.sh` now writes the cron command using **`/bin/bash <runner>`**, so scheduler execution no longer depends on the Git checkout executable bit. Do not replace this with a direct runner invocation.

The first repair test `repair-test-cf50-011-cron-20260814-01` failed safely before publication because the test harness incorrectly required `systemctl reload cron`; this host's cron service does not accept that reload operation. No CMS write occurred, state remained absent, all 11 isolated Scheduled files and all 11 historical repository Scheduled files remained intact, and the Publisher cron stayed disabled.

The corrected test `repair-test-cf50-011-cron-20260814-02` removed only that reload dependency and then:
1. confirmed exactly one due Wave1 item and that it was 011;
2. kept recurring Publisher cron absent;
3. waited 10 seconds as explicitly requested by the user;
4. ran one Publisher invocation with `XYPTDQ_PUBLISH_LIMIT=1`;
5. published only 011 as CMS ID 93;
6. regenerated Sitemap, exported the Publication Receipt and passed live SEO verification;
7. confirmed state `1 published / 10 scheduled / 0 failed`;
8. confirmed both physical Scheduled inventories still contain 11 JSON files, as intended for idempotency/history;
9. reinstalled the recurring Publisher cron only after all checks passed;
10. confirmed the restored cron uses the durable `/bin/bash .../run_scheduled_publish.sh` invocation.

Current recurring cron state is **PASS / installed**:
- cron schedule: `7 * * * *`
- editorial cadence: `10:00` and `19:00` Asia/Singapore
- next scheduled article: 021 at `2026-08-15T10:00:00+08:00`

Important queue semantics: the isolated Scheduled JSON files are retained for idempotency. “11 → 10” means the number of **remaining unpublished state entries** fell from 11 to 10; it does not mean a Scheduled JSON file is physically deleted.

Do **not** reinstall or duplicate the cron. The hourly cron is only a poller; each article's `publish_at` controls actual release eligibility. Planned editorial slots remain 10:00 and 19:00 Asia/Singapore, so a due item is normally processed around minute 07 after the hour.

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

The scheduled runner performs, for **new pages actually published in the current cron run**:

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

The CF50 high-overlap final five `020, 029, 038, 039, 040` remain hard-frozen until Issue #264 explicitly records `CF50_FINAL_5_RELEASE=AUTHORIZED`.

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

## 11. Article-page visual design — PRODUCTION PASS

The user approved a professional research/blog reading style: restrained typography, clearer heading hierarchy, comfortable line-height, paragraph rhythm, lists/blockquote/table/image/link styling, and responsive mobile readability. Do not use rainbow keyword colors or exaggerated font-size SEO styling.

Template/cache deployment attempts were rollback-safe and established that production mobile requests render the responsive PC shell. The final implementation therefore uses a tightly scoped managed block in the live static stylesheet rather than repeated template-cache mutation.

Authoritative production result:
- Server Bridge job: `deploy-article-reading-static-css-20260814-03`
- result branch: `agent/results/deploy-article-reading-static-css-20260814-03`
- status: **PASS**
- CSS path: `static/default/pc/css/style.bundle.css`
- managed block: `XYPTDQ_ARTICLE_READING`
- public CSS marker: PASS
- PC HTTP: 200
- mobile HTTP: 200
- Title/canonical stable: PASS
- Publisher cron before/after: `1 / 1`
- Publisher queue consumed: false
- templates mutated: false
- template cache mutated: false
- whole cache cleared: false
- database changed: false
- article publishing attempted: false

Evidence: `docs/seo/ARTICLE_READING_DESIGN_PRODUCTION_PASS_20260814.md`.

This visual work is **closed unless a real production regression is observed**. Do not reopen template-cache deployment attempts.

## 12. Immediate next actions

1. Do not make further scheduler changes unless a new production regression is proven; the cron repair is now production PASS.
2. Let 021 reach `2026-08-15T10:00:00+08:00` and confirm the normal recurring cron publishes it without a manual one-shot invocation.
3. Confirm each real publication only after Publisher state/live URL evidence exists.
4. Use automatic post-publication Sitemap + receipt + live SEO evidence for each new page.
5. Continue hourly new-inventory monitoring; never publish raw Approved bodies directly.
6. Keep `020, 029, 038, 039, 040` frozen until Issue #264 explicitly authorizes release.
7. Stop after the first 12 live seed articles and perform the search-discovery checkpoint before Wave B.
8. Keep article-page visual design closed unless a real production regression appears.
9. Keep Phase 1 closed unless a real regression appears.

## 13. New-session takeover protocol

A new session must first confirm current `main`, `config/content_publication_policy.json`, newer `agent/results/*`, Publisher state and current live article count. Canonical facts at this handoff are:
- CF50-001 is live as CMS ID 92 and passed live SEO;
- CF50-011 is live as CMS ID 93 and passed live SEO after the controlled 10-second repair test;
- the missed-011 root cause was direct cron execution of a mode-0600 runner;
- the durable cron fix is explicit `/bin/bash .../run_scheduled_publish.sh` invocation;
- corrected repair job `repair-test-cf50-011-cron-20260814-02` is production PASS;
- Wave1 state is `1 published / 10 scheduled / 0 failed` for the 11 post-canary runtime items;
- next item is 021 at `2026-08-15T10:00:00+08:00`;
- recurring cron is installed and bound only to the isolated Wave1 source/state/lock;
- post-publication Sitemap/receipt/live SEO verification is active;
- article-page reading design is production PASS through the scoped `XYPTDQ_ARTICLE_READING` static CSS block and is closed unless regression;
- CF50 final five `020, 029, 038, 039, 040` remain frozen;
- Wave B is not authorized before the Issue #264 post-12 checkpoint.

Continue from the first real publication/checkpoint gap. Do not repeat Phase 1, do not reopen completed visual work, do not republish 001/011, do not reinstall the Publisher cron, and do not ask the user for publication authorization already recorded.
