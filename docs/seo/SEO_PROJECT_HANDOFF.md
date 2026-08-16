# SEO Project Handoff — Canonical Current State

> Continuity entrypoint for `fdsasaaa/xyptdq`. Read this file, `config/seo_project_state.json`, `config/content_publication_policy.json`, `config/content_inventory_policy.json`, `config/content_source_sync_policy.json`, `content/keyword_map.json`, `content/seo_cluster_registry.json`, Issue #264, newer PRs and `agent/results/*` before changing anything.

## 1. Current phase

- Website repository: `fdsasaaa/xyptdq`
- Production: `https://www.laocaimi.org`
- Upstream article repository: `fdsasaaa/caipiaowenzhang`
- Phase 1 technical SEO: **closed unless a real regression is proven**.
- Article factory: **PRODUCTION / SEALED**. Do not rebuild article generation here.
- Website phase: **first 12 Seed publication active + automatic Draft-only inventory intake active**.
- Wave B remains unauthorized until the post-12 Search Discovery checkpoint in Issue #264.

The two automations are deliberately separate:
- Publisher poller: `7 * * * *` — may publish only pre-authorized Scheduled Seed content according to `publish_at`.
- Inventory intake: `23 * * * *` — may only reconcile formal public-r1 into isolated Draft state; it cannot create `publish_at`, Scheduled entries, CMS pages or Publisher state.

## 2. Repository boundary

`caipiaowenzhang` owns article creation, rule/quality checks, Approval, immutable Approved parent, website-public-release/public-r1, audit and CI.

`xyptdq` owns formal public-r1 intake, final SEO ownership, Draft inventory, Cluster/Hub/internal links, scheduling, Publisher, Sitemap and search feedback.

Hard rules:
- never publish raw Approved parent bodies;
- website body comes only from validated `website_public_release` revision;
- website must not silently rewrite article mechanics/identity;
- upstream production volume never directly determines website publication volume;
- Draft intake is not publication authorization;
- only the website publication gate may create `publish_at` or promote content to Scheduled.

## 3. Current inventory watermarks

At the automatic-intake activation checkpoint on 2026-08-16:

- **A — upstream formal public-r1: 45**.
- Website repository ingress already known: **12** first-wave revisions.
- Runtime intake ledger: **3** revisions (`003`, `004`, `005`).
- Remaining new Draft candidates after activation: **30**.
- Live Seed pages proven so far: **3** (`001`, `011`, `021`).
- Remaining first-wave Scheduled pages before 031 proof: **9**.

Do not add repository-ingress 12 and ledger 3 as 15 unique upstream articles without accounting for lifecycle semantics. The ledger records the new runtime Draft intake layer; publication remains a separate state machine.

The current formal source manifest is still `CF50-20260813.json`. It is a special terminal waiting state:
- `status=partial`;
- 45 website-ready public-r1 out of 50 Approved parents;
- `canary_ingestion_allowed=true`;
- `website_batch_ingestion_allowed=false`;
- the website inventory policy explicitly permits this exact 45/50 CF50 terminal state while the final five remain frozen.

Future ordinary daily batches do **not** inherit this exception: they must satisfy the normal complete/formal-batch contract.

## 4. CF50 final five — FROZEN, NOT RETIRED

IDs: `020`, `029`, `038`, `039`, `040`.

They remain immutable Approved audit history and are hard-frozen until Issue #264 records exactly:

`CF50_FINAL_5_RELEASE=AUTHORIZED`

Current authorization: **false / NOT_AUTHORIZED**.

Do not create, merge, intake, schedule or publish public revisions for these five before that exact gate. `inventory_diff.py` enforces this fail-closed.

## 5. Proven live Seed pages

### 001
- CMS ID `92`
- URL `https://www.laocaimi.org/index.php?c=show&id=92`
- live SEO: **PASS**

### 011
- CMS ID `93`
- URL `https://www.laocaimi.org/index.php?c=show&id=93`
- scheduler repair job `repair-test-cf50-011-cron-20260814-02`: **PASS**
- live SEO: **PASS**

### 021
- CMS ID `94`
- URL `https://www.laocaimi.org/index.php?c=show&id=94`
- repair job `repair-cf50-021-sitemap-20260816-03`: **PASS**
- temporary / production / live Sitemap membership: PASS
- self-canonical: PASS
- Publication Receipt live SEO verification: PASS

Do not republish `001`, `011` or `021`.

## 6. CF50-021 root cause — CLOSED

The page and CMS routing were not broken. The blocker was a diagnostic false-negative: raw `grep` compared an unescaped query URL against valid XML where `&` is serialized as `&amp;`.

Durable fix:
- `scripts/seo/sitemap_contains_url.php`;
- XML-aware `<loc>` parsing and entity decoding before URL comparison;
- production 021 repair re-verified through the authoritative Publication Receipt SEO verifier.

Do not reopen “CMS94 missing from Sitemap” without new production evidence.

## 7. Recurring Publisher — ACTIVE

Authoritative policy: `config/content_publication_policy.json`.

Runtime:
- source `/var/lib/xyptdq-content/CF50-20260813-wave1/scheduled`;
- state `/var/lib/xyptdq-publisher/CF50-20260813-wave1/state.json`;
- lock `/var/lib/xyptdq-publisher/CF50-20260813-wave1/publisher.lock`;
- exactly one Publisher cron: `7 * * * *`;
- runner invocation uses `/bin/bash scripts/content/run_scheduled_publish.sh`;
- historical repository `content/scheduled` queue is forbidden as runtime source.

The explicit `/bin/bash` invocation is the durable fix for the earlier mode-0600 runner regression. Do not reinstall or duplicate Publisher cron.

## 8. Remaining Seed schedule

The 021 pause recovery rebase job `rebase-cf50-wave1-after-021-20260816-01` passed and shifted the nine remaining Seed items exactly one editorial slot without changing content, revision identity or order:

1. `031` → 2026-08-16 10:00 +08:00
2. `041` → 2026-08-16 19:00 +08:00
3. `046` → 2026-08-17 10:00 +08:00
4. `002` → 2026-08-17 19:00 +08:00
5. `012` → 2026-08-18 10:00 +08:00
6. `022` → 2026-08-18 19:00 +08:00
7. `032` → 2026-08-19 10:00 +08:00
8. `037` → 2026-08-19 19:00 +08:00
9. `049` → 2026-08-20 10:00 +08:00

At this handoff timestamp the clock had reached 10:00 but **the :07 Publisher poll had not yet occurred**, so 031 must not be assumed live. A read-only normal-slot verifier is already merged at `scripts/ops/agent_tasks/probe_cf50_031_normal_slot_v1.sh`. Run it only after the :07 poll.

## 9. Publication stop rule

- target cadence: 2/day;
- timezone: Asia/Singapore;
- editorial slots: 10:00 and 19:00;
- first-wave cap: 12 live Seed pages including 001;
- after first 12: stop before Wave B and run Issue #264 Search Discovery checkpoint.

Every actual publication must be proven through Publisher state, Sitemap refresh, Publication Receipt and live SEO. Clock time alone is not proof.

## 10. Automatic private-repo Draft intake — PRODUCTION PASS / ACTIVE

The manual Deploy Key registration is complete and fully proven. The private key remains only on the production server and has never been exported.

Transport proof:
- job `prove-article-repo-ssh-inventory-20260816-01`: **PASS**;
- dedicated read-only SSH access to `caipiaowenzhang/main`: PASS;
- source commit at proof/activation: `e4833ff81a71f6246922ec8992d9ddc8faec1ccf`;
- upstream formal public-r1=45;
- repository ingress known=12;
- initial ledger=0;
- initial new Draft candidates=33;
- final-five gate remained unauthorized and excluded.

Canary chain:
1. `003` — `canary-article-repo-draft-ledger-20260816-01`: **PASS**. First real isolated Draft + durable ledger record; candidates 33→32.
2. `004` — `canary-incremental-intake-runner-004-20260816-01`: **PASS**. Real generic runner in canary mode; ledger 1→2, candidates 32→31.
3. `005` — `activate-incremental-intake-20260816-01`: **PASS**. Real auto-mode one-shot; ledger 2→3, candidates 31→30; then automatic cron installed.

Current automatic intake:
- policy `automatic_intake_enabled=true`;
- source sync `sync_enabled=true`;
- cron file `/etc/cron.d/xyptdq-intake`;
- exactly one intake cron;
- schedule `23 * * * *`;
- max 25 candidates/run;
- runtime Draft root `/var/lib/xyptdq-content/intake/drafts`;
- ledger `/var/lib/xyptdq-content/intake/state.json`;
- lock `/var/lib/xyptdq-content/intake/intake.lock`.

Safety properties:
- read-only private-repository SSH transport;
- formal manifest + public-r1 + immutable Approved parent revalidation;
- exact content hash/fingerprint linkage;
- exact Primary Keyword and slug cross-article conflict gates;
- idempotent durable ledger;
- recovery of a matching Draft if a process stops between Draft and ledger commit;
- final-five Issue #264 freeze gate;
- no `publish_at` creation;
- no Scheduled promotion;
- no CMS write;
- no Publisher invocation;
- no Publisher cron mutation.

PR #407 additionally scopes the CF50 editorial Cluster map to its explicit batch ID. It cannot leak `ffc_research` into future batches. Future formal batches may use explicit revision Cluster metadata or remain temporarily unassigned at Draft stage; Cluster is never guessed from title.

The first scheduled `:23` cron run had not yet occurred at this handoff timestamp. Its observation is useful health evidence but is not a publication gate.

## 11. Hub / Cluster / Search Discovery

- CF50 Primary Cluster: `ffc_research`.
- `ffc_research_hub` remains blueprint-only and not live.
- Do not create a thin/empty Hub before the 12 Seed checkpoint.
- Issue #264 owns post-12 Search Discovery, Hub activation and final-five release conclusions.

Checkpoint includes HTTP 200, self-canonical, no noindex, Sitemap membership, Search Console Sitemap processing if available, and representative URL Inspection Live Tests. All 12 do not need to be indexed before continuing, but a systemic technical blocker holds Wave B.

## 12. Article reading design

Production reading design remains **PASS / closed unless regression** through the scoped `XYPTDQ_ARTICLE_READING` static CSS block. Do not reopen template-cache experiments without a real regression.

## 13. Immediate next actions

1. After 2026-08-16 10:07 Asia/Singapore, run the merged read-only 031 normal-slot verifier; do not infer success from time.
2. Allow the separate :23 Draft intake cron to reconcile formal inventory; do not treat its Drafts as publication authorization.
3. Verify every actual Seed publication through state + Receipt + live SEO.
4. Do not duplicate either cron and do not use the historical repository Scheduled queue.
5. Keep `020/029/038/039/040` frozen pending exact Issue #264 authorization.
6. Stop after 12 live Seed pages for Search Discovery; do not start Wave B or live Hub earlier.
7. Keep Phase 1 and article-reading design closed unless a real regression appears.

## 14. New-session takeover protocol

A new session must first inspect current `main`, this handoff, `config/seo_project_state.json`, publication/inventory/source-sync policies, Issue #264, recent PRs and newer `agent/results/*`.

Canonical current facts at this handoff:
- upstream formal public-r1=45;
- 001/011/021 are proven live as CMS 92/93/94 with live SEO PASS;
- 031 is scheduled for 2026-08-16 10:00 and still awaits post-:07 proof at this timestamp;
- Publisher is independent at :07;
- automatic private-repo Draft intake is active and production-PASS at :23, max 25/run;
- 003/004/005 proved Draft-only intake, generic runner and auto-mode activation respectively;
- intake ledger=3 and remaining new Draft candidates=30 after activation;
- intake never creates `publish_at` or invokes Publisher;
- final five remain frozen;
- Wave B and live Hub remain blocked by Issue #264.

Continue from the first real unfinished checkpoint. Do not redo Phase 1, rebuild article generation, republish proven Seed pages, reinstall crons, publish raw Approved bodies, release the final five, or activate Wave B before Issue #264.
