# SEO Project Handoff — Canonical Current State

> Mandatory continuity entrypoint for `fdsasaaa/xyptdq`. Read this file, `config/seo_project_state.json`, `docs/seo/SEO_CHANGELOG.md`, `content/keyword_map.json`, `content/seo_target_registry.json`, `content/seo_cluster_registry.json`, `config/content_category_map.json`, `config/content_source_sync_policy.json`, and `config/content_publication_policy.json`, then inspect newer PRs and `agent/results/*` before changing anything.

## 1. Current phase

- Website repository: `fdsasaaa/xyptdq`
- Production: `https://www.laocaimi.org`
- Article repository: `fdsasaaa/caipiaowenzhang`
- Phase 1 technical SEO remains **closed unless a real regression is proven**.
- Current phase: **first reviewed CF50 public-release article is live and verified; prepare additional reviewed public-r1 inventory, then activate isolated recurring publication at the approved cadence.**
- Do not restart a full technical audit.

## 2. First CF50 live publication — PASS

The first real CF50 article is already live.

- Batch: `CF50-20260813`
- Article: `LCM-CREATOR-cf50-20260813-001`
- Revision: `LCM-CREATOR-cf50-20260813-001:public-r1`
- CMS ID: `92`
- Production URL: `https://www.laocaimi.org/index.php?c=show&id=92`
- Server Bridge job: `publish-cf50-canary-001-20260814-04`
- Result branch: `agent/results/publish-cf50-canary-001-20260814-04`
- Result: `PASS`
- Live SEO verification: `PASS`
- Source transport: `sanitized_public_release_bundle`
- Legacy repository Scheduled queue consumed: `false`
- Recurring Publisher cron installed: `false`

The canary used a separately reviewed website-facing public release. It did **not** publish the operational original Approved body.

## 3. Publication policy after canary

Authoritative file: `config/content_publication_policy.json`.

Current state:

- User authorization for Draft + future automated publication is already recorded.
- Do **not** ask the user for the same authorization again.
- `publishing_enabled=false` after the successful one-shot canary.
- Mode: `canary_passed_waiting_reviewed_inventory_and_recurring_activation`.
- Recurring cron is still absent.
- Planned future cadence remains **2 articles/day**, Asia/Singapore, target editorial slots `10:00` and `19:00`.
- After the first 12 diverse seed pages, stop for the search-discovery checkpoint before Wave B.

The one-shot switch was deliberately closed after PASS so a canary mode cannot accidentally become a recurring publisher.

## 4. Historical queue safety — HARD RULE

`content/scheduled/` in the website repository contains 11 historical Scheduled JSON files.

They are preserved history only and must never be used as the new CF50 runtime queue.

Future CF50 publication must use an isolated source under:

`/var/lib/xyptdq-content/CF50-20260813/scheduled`

Publisher state/lock data must remain under `/var/lib/xyptdq-publisher/...`.

The runner and cron installer have fail-closed isolation guards. Do not weaken them merely to make automation easier.

## 5. Article source contract

`articles/approved/` in `fdsasaaa/caipiaowenzhang` is immutable parent/audit evidence.

Website publication source is a separately reviewed `website_public_release` revision, not the original Approved body.

Article-repository public-release structure:

- revisions: `articles/public_release/<source_batch_id>/`
- manifests: `articles/public_release/manifests/`
- immutable parent evidence: `articles/approved/`

The website independently validates revision identity, parent hash/fingerprint, batch provenance, review metadata, revision fingerprint, manifest membership, category, and Cluster assignment.

## 6. Sanitized transfer mode — CURRENT PRACTICAL TRANSPORT

Production server did not have non-interactive read credentials for the private article repository. We did not solve that by placing long-lived GitHub credentials on the server.

Instead PR #294 added a sanitized transfer path in the website repository. A transfer bundle may contain:

- the already-reviewed non-operational public-r1 body;
- the partial/complete public-release manifest;
- parent identity evidence containing hash/fingerprint/SEO identity and immutable source ref;
- **no original Approved body**.

Website CI validates the real transfer bundle and proves tampered parent evidence fails closed.

Use this transport unless a future secure cross-repository transport supersedes it.

## 7. CF50 inventory and release order

Formal Approved inventory:

- Batch: `CF50-20260813`
- Count: 50
- Original formal directory: `articles/approved/`

These originals are not automatically publication-eligible. Many contain concrete number-selection or staking instructions. They must be converted into reviewed public-r1 versions before website publication.

SEO first-wave order:

`001, 011, 021, 031, 041, 046, 002, 012, 022, 032, 037, 049`

High semantic-overlap pages held to the tail:

`020, 029, 038, 039, 040`

Do not mechanically publish 001–050 in numeric order.

## 8. Next public-release inventory

- `001`: reviewed public-r1 merged and live — complete.
- `011`: reviewed public-r1 prepared on article repo PR #81; Python 3.10/3.13, audit and full pytest passed. Merge action was blocked by the platform safety layer. Do not bypass that block.
- Remaining first-wave seeds still need reviewed public-r1 versions before recurring publication can be safely activated.

The immediate work is therefore **reviewed inventory preparation**, not more Publisher debugging.

## 9. Category and Cluster architecture

Ordinary SEO articles remain in:

- category key `tzjq`
- catid `3`
- CMS display label `投注机巧`

`seo-articles` and `gdrz` remain retired.

CF50 Primary Cluster is `ffc_research`, assigned by explicit editorial map; do not guess from title text.

The `ffc_research_hub` blueprint exists but is not live. Do not create an empty/thin Hub and do not inject a planned Hub URL. Evaluate it after at least 12 diverse verified seed articles have real live URLs.

## 10. Keyword architecture

`content/keyword_map.json` version `1.1.2` remains authoritative.

- 51 keywords at the last formal checkpoint.
- exact owner conflicts: 0.
- same-intent synonym consolidation remains required.
- homepage owns `信誉平台大全`.
- `tzjq` carries broad FFC betting-guide intent.
- individual CF50 pages should keep their play-specific long-tail Primary Keywords.

Do not retitle individual articles to steal broad Hub/category owner terms.

## 11. Search-discovery checkpoint

After the first 12 seed pages are live, verify:

- HTTP 200;
- self-canonical;
- no `noindex`;
- Sitemap membership;
- Search Console Sitemap processing if available;
- representative URL Inspection Live Tests.

Do not require all 12 to be indexed before continuing; indexing can lag. However, a systemic robots/canonical/noindex/Sitemap blocker must hold Wave B.

## 12. Production SEO infrastructure already complete

Do not reopen these without evidence of regression:

- canonical cleanup;
- duplicate Title/H1/Description cleanup;
- orphan-page cleanup;
- empty-category retirement;
- Sitemap routing/indexability cleanup;
- category pagination Title/Description uniqueness;
- mobile crawlable pagination links;
- category sidebar topic scoping;
- Publication Receipt support;
- live publication SEO verifier;
- isolated Publisher runtime-source guards.

## 13. Immediate next actions

1. Keep CF50-001 as canonical successful live canary; do not republish it.
2. Prepare reviewed, non-operational public-r1 revisions for additional first-wave articles.
3. For each revision, preserve article ID, slug, long-tail Primary Keyword, category, parent hash/fingerprint and review provenance.
4. Transfer only the reviewed public release + sanitized parent identity evidence to website ingress.
5. Create Drafts through website validation and explicit `ffc_research` editorial mapping.
6. Once enough reviewed inventory exists, enable recurring publication through the isolated CF50 source at 2/day, 10:00 and 19:00 Asia/Singapore.
7. Do not use the 11 historical repository Scheduled files.
8. Stop after the first 12 live seed pages for the search-discovery checkpoint.
9. Keep Phase 1 closed unless a real regression appears.

## 14. New-session takeover protocol

A new session must first confirm:

- current `main`;
- `config/content_publication_policy.json` still has recurring publishing disabled unless a later verified activation changed it;
- CF50-001 CMS ID 92 remains the successful live canary;
- newer reviewed public-r1 inventory in `caipiaowenzhang`;
- newer website ingress / Server Bridge result branches;
- no use of `content/scheduled` as the CF50 runtime source.

Then continue from the first reviewed-inventory or recurring-activation gap. Do not repeat the Phase 1 audit and do not ask the user to reauthorize publication that has already been approved.
