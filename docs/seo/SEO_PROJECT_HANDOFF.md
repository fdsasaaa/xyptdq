# SEO Project Handoff — Canonical Current State

> Continuity entrypoint for `fdsasaaa/xyptdq`. Read this file, `config/seo_project_state.json`, `config/content_publication_policy.json`, `config/content_inventory_policy.json`, `config/content_source_sync_policy.json`, `content/keyword_map.json`, `content/seo_cluster_registry.json`, Issue #264, newer PRs and `agent/results/*` before changing anything.

## 1. Current phase

- Website repository: `fdsasaaa/xyptdq`
- Production: `https://www.laocaimi.org`
- Upstream article repository: `fdsasaaa/caipiaowenzhang`
- Phase 1 technical SEO: **closed unless a real regression is proven**.
- Article factory: **PRODUCTION / SEALED**. Do not rebuild article generation in this repository.
- Website phase: **first 12 Seed publication resumed + inventory-driven intake pre-activation**.
- Wave B remains unauthorized until the post-12 Search Discovery checkpoint in Issue #264.

## 2. Repository boundary

`caipiaowenzhang` owns article creation, rule/quality checks, Approval, immutable Approved parent, website-public-release/public-r1, audit and CI.

`xyptdq` owns formal public-r1 intake, final SEO ownership, Draft inventory, Cluster/Hub/internal links, scheduling, Publisher, Sitemap and search feedback.

Hard rules:
- never publish raw Approved parent bodies;
- website body comes only from validated `website_public_release` revision;
- website must not silently rewrite article mechanics/identity;
- upstream production volume never directly determines website publication volume;
- intake is Draft-only and cannot create `publish_at`, invoke Publisher or alter cron.

## 3. Current inventory watermarks

As of 2026-08-16 morning Asia/Singapore:

- **A — upstream formal public-r1: 45**
  - `caipiaowenzhang/main` currently has only formal manifest `CF50-20260813.json`.
  - 2026-08-15 automated production produced no formal new batch because final public-r1 count stayed below the minimum batch gate.
- Website-synced first wave: **12**.
- Website live Seed pages: **3** (`001`, `011`, `021`).
- Website Scheduled but not live: **9**.
- Upstream formal public-r1 not yet synchronized to website: **33**.

Do not interpret 45 as “publish 45 now”. The first-wave Seed/Search Discovery discipline remains authoritative.

## 4. CF50 final five — FROZEN, NOT RETIRED

IDs:
- `020`
- `029`
- `038`
- `039`
- `040`

They remain immutable Approved audit history and are **hard-frozen** until Issue #264 records the exact machine conclusion:

`CF50_FINAL_5_RELEASE=AUTHORIZED`

Current authorization: **false / NOT_AUTHORIZED**.

Do not create, merge, intake, schedule or publish public revisions for these five before that exact gate. PR #395 aligned `inventory_diff.py` with this freeze semantics; the obsolete “retired_without_public_release” interpretation must not return.

## 5. Live Seed pages

### CF50-001
- revision `LCM-CREATOR-cf50-20260813-001:public-r1`
- CMS ID `92`
- URL `https://www.laocaimi.org/index.php?c=show&id=92`
- live SEO: **PASS**

### CF50-011
- CMS ID `93`
- URL `https://www.laocaimi.org/index.php?c=show&id=93`
- scheduler repair job `repair-test-cf50-011-cron-20260814-02`: **PASS**
- live SEO: **PASS**

### CF50-021
- CMS ID `94`
- URL `https://www.laocaimi.org/index.php?c=show&id=94`
- final repair job `repair-cf50-021-sitemap-20260816-03`: **PASS**
- temporary Sitemap membership: PASS
- production Sitemap membership: PASS
- live Sitemap membership: PASS
- self-canonical: PASS
- Publication Receipt live SEO verification exit code: `0`

Do not republish `001`, `011` or `021`.

## 6. CF50-021 root cause — CLOSED

The page and CMS routing were not broken. CMS 94 was status 9, present in `share_index` with `mid=news`, and present in the durable Publisher registry.

The false blocker came from a diagnostic Gate using raw `grep` against the literal URL containing `&id=94`, while valid XML serializes the query separator as `&amp;id=94`. The authoritative live SEO library already decoded XML entities correctly.

Durable fix:
- `scripts/seo/sitemap_contains_url.php`
- XML-aware `<loc>` parsing and entity decoding before normalized URL comparison
- CF50-021 repair task now uses that check for temporary, production and live Sitemap validation.

Do not reopen “CMS94 is missing from Sitemap” unless new production evidence proves a regression.

## 7. Recurring Publisher — RESUMED

Authoritative policy: `config/content_publication_policy.json`.

Current runtime:
- source: `/var/lib/xyptdq-content/CF50-20260813-wave1/scheduled`
- state: `/var/lib/xyptdq-publisher/CF50-20260813-wave1/state.json`
- lock: `/var/lib/xyptdq-publisher/CF50-20260813-wave1/publisher.lock`
- historical repository `content/scheduled` queue: **forbidden runtime source**
- recurring cron: exactly one
- schedule: `7 * * * *`
- runner invocation: `/bin/bash scripts/content/run_scheduled_publish.sh`
- Publisher limit: 2, but per-article `publish_at` is the eligibility gate.

Do not reinstall or duplicate cron. The explicit `/bin/bash` invocation is the durable fix for the earlier mode-0600 runner regression.

## 8. Pause recovery schedule — PASS

Read-only probe `probe-wave1-remaining-schedule-20260816-01` proved the isolated state was:
- 2 published / 9 scheduled / 0 failed within the 11-item post-canary runtime;
- only `031` was overdue at the checkpoint.

Blind resume was rejected because the Publisher can process up to two overdue items per run and could compress the intended cadence.

Server Bridge job `rebase-cf50-wave1-after-021-20260816-01` therefore shifted all nine remaining `publish_at` values exactly one editorial slot, changing no article body, identity or order:

1. `031` → `2026-08-16 10:00 +08:00`
2. `041` → `2026-08-16 19:00 +08:00`
3. `046` → `2026-08-17 10:00 +08:00`
4. `002` → `2026-08-17 19:00 +08:00`
5. `012` → `2026-08-18 10:00 +08:00`
6. `022` → `2026-08-18 19:00 +08:00`
7. `032` → `2026-08-19 10:00 +08:00`
8. `037` → `2026-08-19 19:00 +08:00`
9. `049` → `2026-08-20 10:00 +08:00`

Rebase status: **PASS**. Publication policy was then resumed through PR #396.

## 9. Publication cadence / stop rule

- target cadence: 2 articles/day
- timezone: Asia/Singapore
- editorial slots: 10:00 and 19:00
- first-wave cap: 12 live Seed pages including 001
- after first 12: **stop before Wave B and run Issue #264 Search Discovery checkpoint**

Clock time is an operating cadence, not claimed as a Google ranking signal.

For every new real publication, the existing runner must:
1. publish through Native Publisher/idempotent adapter;
2. regenerate Sitemap;
3. export Publication Receipt;
4. verify HTTP, canonical, noindex, Title, H1, Description and XML-aware Sitemap membership;
5. preserve evidence under isolated Publisher state.

## 10. Inventory-driven intake — CODE READY, TRANSPORT NOT YET ACTIVATED

Merged website-side components:
- `config/content_inventory_policy.json`
- `config/content_source_sync_policy.json`
- `scripts/content/inventory_diff.py`

They implement:
- formal source = `caipiaowenzhang/main` + formal public-release manifest;
- variable 10–25 quality-first daily supply, not fixed 20;
- sub-minimum 1–9 failed daily batch = zero formal new inventory;
- Draft-only destination;
- durable ledger `/var/lib/xyptdq-content/intake/state.json`;
- same revision/hash = idempotent NOOP;
- changed hash, duplicate slug or Primary Keyword conflict = fail closed;
- final-five freeze enforcement tied to Issue #264.

**Automatic intake is still disabled.**

Production probes proved no reusable HTTPS GitHub credential or credential helper exists on the server. A dedicated Ed25519 read-only keypair has now been provisioned server-side:
- fingerprint: `SHA256:qgkoW70e+CTTmZ+AQOxM/kcpHu5i0WsinMMSXoMKD7E`
- private key remains only on production server and was never exported.

One manual GitHub repository action remains:
- `fdsasaaa/caipiaowenzhang` → Settings → Deploy keys → Add deploy key
- paste the provisioned public key
- **Allow write access must remain OFF**.

After registration, next gates are:
1. prove SSH read of `caipiaowenzhang/main`;
2. run `inventory_diff.py` read-only against the formal source;
3. prove A=45 and currently known website ingress=12 without duplicate/drift;
4. create durable intake-ledger canary;
5. run one Draft-only public-r1 canary;
6. only then enable unattended incremental intake.

Intake activation must not change Publisher cadence.

## 11. Hub / Cluster / Search Discovery

- CF50 Primary Cluster: `ffc_research`.
- `ffc_research_hub` is blueprint-only and **not live**.
- Do not create a thin/empty Hub before the 12 Seed checkpoint.
- Issue #264 owns the post-12 Search Discovery / Hub / final-five release conclusions.

Checkpoint should review:
- HTTP 200;
- self-canonical;
- no noindex;
- Sitemap membership;
- Search Console Sitemap processing if available;
- representative URL Inspection Live Tests.

Do not require all 12 to be indexed before continuing; indexing can lag. A systemic robots/canonical/noindex/Sitemap blocker must hold Wave B.

## 12. Article reading design

Production reading design remains **PASS / closed unless regression** through the scoped `XYPTDQ_ARTICLE_READING` static CSS block. Do not reopen template-cache experiments without a real regression.

## 13. Immediate next actions

1. Let the resumed isolated first-wave schedule continue from `031` at `2026-08-16T10:00:00+08:00`.
2. Verify every actual publication through Publisher state + Sitemap + Receipt + live SEO; do not infer success from clock time.
3. Do not duplicate cron and do not use the historical repository Scheduled queue.
4. Register the dedicated public key as a read-only Deploy Key on `caipiaowenzhang`; then prove SSH transport and Draft-only intake canaries.
5. Keep `020/029/038/039/040` frozen pending exact Issue #264 authorization.
6. Stop after 12 live Seed pages for Search Discovery; do not start Wave B or live Hub earlier.
7. Keep Phase 1 and article-reading design closed unless a real regression appears.

## 14. New-session takeover protocol

A new session must first inspect current `main`, this handoff, `config/seo_project_state.json`, publication/inventory/source-sync policies, Issue #264, recent PRs and newer `agent/results/*`.

Canonical current facts:
- upstream formal website-ready inventory = 45;
- website synced first wave = 12;
- live Seed pages = 3 (`001/011/021`), CMS IDs `92/93/94`, all live SEO PASS;
- remaining nine Seed pages are rebased one slot and Publisher policy is resumed;
- next = `031` at 2026-08-16 10:00 Asia/Singapore;
- first-wave final scheduled Seed = `049` at 2026-08-20 10:00;
- automatic upstream intake remains disabled only because the dedicated server public key still needs one read-only Deploy Key registration plus SSH/diff/ledger/Draft canaries;
- final five remain frozen and Wave B/Hub remain blocked by Issue #264.

Continue from the first real unfinished checkpoint. Do not redo Phase 1, rebuild article generation, republish 001/011/021, reinstall cron, bypass the final-five gate, or activate Wave B before Issue #264.
