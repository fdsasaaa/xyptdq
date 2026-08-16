# SEO Project Handoff — Canonical Current State

> Continuity entrypoint for `fdsasaaa/xyptdq`. Read this file, `config/seo_project_state.json`, `config/content_publication_policy.json`, `config/content_inventory_policy.json`, `config/content_source_sync_policy.json`, `content/keyword_map.json`, `content/seo_cluster_registry.json`, Issue #264, newer PRs and `agent/results/*` before changing anything.

## 1. Current phase

- Website repository: `fdsasaaa/xyptdq`
- Production: `https://www.laocaimi.org`
- Upstream article repository: `fdsasaaa/caipiaowenzhang`
- Phase 1 technical SEO: **closed unless a real regression is proven**.
- Article factory: **PRODUCTION / SEALED**.
- Website phase: **first 12 Seed publication active + automatic Draft-only inventory intake healthy/idle**.
- Wave B remains unauthorized until the post-12 Search Discovery checkpoint in Issue #264.

Two independent automations are active:
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

## 3. Current inventory / live watermarks

At the 2026-08-16 17:36 Asia/Singapore checkpoint:

- Upstream formal public-r1: **45**.
- Website repository ingress already known: **12** first-wave revisions.
- Runtime automatic-intake ledger: **33**.
- Remaining new Draft candidates: **0**.
- Current 45 formal public-r1 are fully accounted for as `12 ingress + 33 intake-ledger Drafts`.
- Proven live Seed pages: **4** (`001`, `011`, `021`, `031`).
- Remaining first-wave Scheduled pages: **8**.

The current source manifest `CF50-20260813.json` is a special terminal waiting state: 45 website-ready public-r1 out of 50 Approved parents while the final five remain frozen. Future ordinary daily batches do not inherit this exception and must satisfy the normal complete/formal-batch contract.

## 4. CF50 final five — FROZEN, NOT RETIRED

IDs: `020`, `029`, `038`, `039`, `040`.

They remain immutable Approved audit history and are hard-frozen until Issue #264 records exactly:

`CF50_FINAL_5_RELEASE=AUTHORIZED`

Current authorization: **false / NOT_AUTHORIZED**.

Do not create, merge, intake, schedule or publish public revisions for these five before that exact gate. `inventory_diff.py` enforces this fail-closed.

## 5. Proven live Seed pages

- `001` → CMS `92` → `https://www.laocaimi.org/index.php?c=show&id=92` → Live SEO PASS.
- `011` → CMS `93` → `https://www.laocaimi.org/index.php?c=show&id=93` → scheduler repair + Live SEO PASS.
- `021` → CMS `94` → `https://www.laocaimi.org/index.php?c=show&id=94` → XML-aware Sitemap repair + Live SEO PASS.
- `031` → CMS `95` → `https://www.laocaimi.org/index.php?c=show&id=95` → **normal recurring Publisher slot PASS**.

031 evidence:
- normal-slot read-only probe: `probe-cf50-031-normal-slot-20260816-01`;
- Publisher state status: `published`;
- published_at: `2026-08-16T02:07:03+00:00` (10:07:03 Asia/Singapore);
- Wave1 runtime after 031: `3 published / 8 scheduled / 0 failed` within the 11-item post-canary runtime;
- Publication Receipt exists;
- authoritative live SEO verifier: PASS;
- next `041` remains Scheduled for `2026-08-16T19:00:00+08:00`.

Do not republish `001`, `011`, `021` or `031`.

## 6. CF50-021 root cause — CLOSED

The 021 page/CMS routing was not broken. The blocker was a diagnostic false-negative: raw `grep` compared an unescaped query URL against valid XML where `&` is serialized as `&amp;`.

Durable fix:
- `scripts/seo/sitemap_contains_url.php`;
- XML-aware `<loc>` parsing and entity decoding before URL comparison;
- production repair re-verified through the authoritative Publication Receipt SEO verifier.

Do not reopen this without new production evidence.

## 7. Recurring Publisher — NORMAL SLOT PROVEN

Authoritative policy: `config/content_publication_policy.json`.

Runtime:
- source `/var/lib/xyptdq-content/CF50-20260813-wave1/scheduled`;
- state `/var/lib/xyptdq-publisher/CF50-20260813-wave1/state.json`;
- lock `/var/lib/xyptdq-publisher/CF50-20260813-wave1/publisher.lock`;
- exactly one Publisher cron: `7 * * * *`;
- runner invocation uses `/bin/bash scripts/content/run_scheduled_publish.sh`;
- historical repository `content/scheduled` queue is forbidden as runtime source.

The restored Publisher has proven a normal unattended release through 031. Do not reinstall or duplicate Publisher cron.

## 8. Remaining Seed schedule

Pause-recovery schedule after the proven 031 publication:

1. `041` → 2026-08-16 19:00 +08:00
2. `046` → 2026-08-17 10:00 +08:00
3. `002` → 2026-08-17 19:00 +08:00
4. `012` → 2026-08-18 10:00 +08:00
5. `022` → 2026-08-18 19:00 +08:00
6. `032` → 2026-08-19 10:00 +08:00
7. `037` → 2026-08-19 19:00 +08:00
8. `049` → 2026-08-20 10:00 +08:00

Every actual publication must be proven through Publisher state, Publication Receipt and Live SEO. Clock time alone is not proof.

## 9. Publication stop rule

- target cadence: 2/day;
- timezone: Asia/Singapore;
- editorial slots: 10:00 and 19:00;
- first-wave cap: 12 live Seed pages including 001;
- current proven live Seed count: 4/12;
- after first 12: stop before Wave B and run Issue #264 Search Discovery checkpoint.

## 10. Automatic private-repo Draft intake — FULLY RECONCILED / HEALTHY IDLE

The dedicated read-only Deploy Key registration is complete and proven from production. The private key remains server-only and has never been exported.

Proof chain:
1. `prove-article-repo-ssh-inventory-20260816-01`: PASS — private source `main` readable; upstream formal=45; initial new Draft candidates=33; final-five excluded.
2. `canary-article-repo-draft-ledger-20260816-01`: PASS — `003` became the first isolated Draft + durable ledger record; candidates 33→32.
3. `canary-incremental-intake-runner-004-20260816-01`: PASS — generic runner processed exactly `004`; ledger 1→2; candidates 32→31.
4. `activate-incremental-intake-20260816-01`: PASS — real auto-mode one-shot processed exactly `005`; ledger 2→3; candidates 31→30; exactly one automatic intake cron installed.
5. `audit-first-scheduled-intake-20260816-01`: PASS — first natural 10:23 run processed exactly 25; ledger 3→28; candidates 30→5; Draft-only/idempotent guards PASS.
6. The natural 11:23 run processed the remaining 5 and actually reached ledger 28→33 / candidates 5→0, but the old runner emitted a false failure after successful writes: `post-intake candidate count mismatch expected=0 actual=0`.
7. `diagnose-scheduled-intake-failure-20260816-01`: PASS — proved the 11:23 business writes were complete, current ledger=33, Draft files=33, candidates=0, no frozen-final5 leakage, and no publication-side mutation.
8. PR #417 fixed the exact zero-value verifier bug: Python truthiness had converted a legitimate `0` into `-1`. The fix merged as `cea94bc700c325dcb0ac9eea8f9487fee78b5ae3` after `incremental-intake-ci`, `repository-ci`, `embedded-python-ci` and `content-bridge-test` passed.
9. `audit-idle-intake-after-zero-fix-20260816-01`: PASS — five natural post-fix cron runs at 13:23, 14:23, 15:23, 16:23 and 17:23 Asia/Singapore all ran as healthy `auto` no-ops with `selected=0`, `ledger=33`, `candidates=0`; all 33 runtime Drafts remained Draft-only and the final five remained frozen.

Current automatic intake:
- cron file `/etc/cron.d/xyptdq-intake`;
- schedule `23 * * * *`;
- max 25 candidates/run;
- runtime Draft root `/var/lib/xyptdq-content/intake/drafts`;
- ledger `/var/lib/xyptdq-content/intake/state.json`;
- lock `/var/lib/xyptdq-content/intake/intake.lock`;
- current source commit `e4833ff81a71f6246922ec8992d9ddc8faec1ccf`;
- current ledger records **33**;
- current new Draft candidates **0**;
- operating state: **healthy idle, waiting for new upstream formal public-r1**.

Safety properties:
- read-only SSH transport;
- formal manifest/public-r1/Approved-parent revalidation;
- content-hash/fingerprint linkage;
- exact Primary Keyword and slug conflict gates;
- durable idempotent ledger;
- matching-Draft recovery after interrupted pre-ledger commit;
- Issue #264 final-five freeze gate;
- no `publish_at` creation;
- no Scheduled promotion;
- no CMS write;
- no Publisher invocation;
- no Publisher-cron mutation.

PR #407 scopes the CF50 editorial Cluster map to its explicit batch ID, so `ffc_research` cannot leak into future batches. Future formal batches may use explicit revision Cluster metadata or remain temporarily unassigned at Draft stage; Cluster is never guessed from title.

Do **not** manually replay the five revisions processed at 11:23. The business state is already complete and idempotently reconciled; only the obsolete postcheck falsely failed.

## 11. Hub / Cluster / Search Discovery

- CF50 Primary Cluster: `ffc_research`.
- `ffc_research_hub` remains blueprint-only and not live.
- Do not create a thin/empty Hub before the 12 Seed checkpoint.
- Issue #264 owns post-12 Search Discovery, Hub activation and final-five release conclusions.

All 12 do not need to be indexed before continuing, but a systemic robots/canonical/noindex/Sitemap failure holds Wave B.

## 12. Article reading design

Production reading design remains **PASS / closed unless regression** through the scoped `XYPTDQ_ARTICLE_READING` static CSS block.

## 13. Immediate next actions

1. Let the normal isolated Publisher continue to `041` at 2026-08-16 19:00 and verify the real result afterward through Publisher state, Publication Receipt and Live SEO.
2. Leave the independent `:23` Draft intake cron active as an idempotent inventory watcher. Current formal inventory is fully reconciled at ledger=33 / candidates=0; future new formal public-r1 may be ingested automatically.
3. Do not manually replay the 11:23 five-revision run and do not duplicate either cron.
4. Do not use the historical repository Scheduled queue.
5. Keep `020/029/038/039/040` frozen pending exact Issue #264 authorization.
6. Stop after 12 live Seed pages for Search Discovery; do not start Wave B or live Hub earlier.
7. Keep Phase 1 and article-reading design closed unless a real regression appears.

## 14. New-session takeover protocol

Canonical current facts:
- upstream formal public-r1=45;
- `001/011/021/031` are proven live as CMS `92/93/94/95` with Live SEO PASS;
- 031 is the first post-021 recovery normal unattended Publisher slot proof and published at 10:07:03 Asia/Singapore;
- Wave1 runtime is `3 published / 8 scheduled / 0 failed`; next is `041` at 2026-08-16 19:00;
- Publisher is independent at `:07`;
- automatic private-repo Draft intake is active at `:23`, max 25/run, and current formal inventory is fully reconciled at `ledger=33 / candidates=0`;
- first natural `:23` run processed 25; second processed the remaining 5 but hit a post-write zero-value verifier false failure;
- diagnosis proved all 33 Drafts safe; PR #417 fixed the zero bug with CI PASS;
- five natural post-fix idle `:23` runs through 17:23 all passed with zero selected revisions;
- intake never creates `publish_at` or invokes Publisher;
- final five remain frozen;
- Wave B and live Hub remain blocked by Issue #264.

Continue from the first real unfinished checkpoint: the next production event is CF50-041 at 2026-08-16 19:00 Asia/Singapore. Do not redo Phase 1, rebuild article generation, republish proven Seed pages, reinstall crons, manually replay reconciled Draft intake, publish raw Approved bodies, release the final five, or activate Wave B before Issue #264.
