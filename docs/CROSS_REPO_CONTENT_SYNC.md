# Cross-Repo Content Sync — Approved → Draft Contract

Source repository: `fdsasaaa/caipiaowenzhang`

Website repository: `fdsasaaa/xyptdq`

This document defines the future automatic transport boundary between the independent article-production repository and the website repository. It is **not** authorization to schedule or publish articles.

## 1. Source of truth

The only future automatic source is the content engine's approved inventory:

`fdsasaaa/caipiaowenzhang@main:articles/approved/`

The transport layer must ignore drafts, rejected content, published archives, temporary run outputs and any package whose lifecycle status is not exactly `approved`.

## 2. Destination state

A successfully transported package may only enter the website as:

`publication_state=draft`

The transport layer must not:

- create `publish_at`;
- copy a package into `content/scheduled`;
- invoke the Native Publisher;
- alter Publisher cron;
- consume the preserved scheduled queue;
- write directly to the production CMS database.

Approved content is permission to create/reconcile a website draft, not permission to publish.

## 3. Category contract

Website numeric catids remain owned by `config/content_category_map.json`.

Current ordinary SEO article carrier:

- `site_category_key=tzjq`
- catid 3
- CMS label `投注机巧`

`seo-articles` is retired and must be rejected. The website must never infer a category from title text or keywords.

The article-production repository must keep its `publishing/LAOCAIMI_SITE_CONTRACT.json` aligned with this rule before transport can be enabled.

## 4. Identity and duplicate protection

Each package must have stable identity/provenance sufficient to verify at least:

- `article_id`
- `source_fingerprint`
- `content_hash`

Rules:

- same article_id + same hash → idempotent / unchanged;
- same article_id + different hash → reject; requires content revision and re-Approval;
- missing identity/provenance → reject;
- source package must pass the existing website Approved Package validator before draft creation.

The existing website SEO portfolio audit remains a second gate for exact primary-keyword ownership and cross-state consistency.

## 5. SEO ownership

Transport does not bypass SEO controls.

Before a new draft becomes part of the managed portfolio, the website must continue to enforce:

- one exact primary keyword owner per distinct article;
- stable article identity across states;
- no silent body replacement;
- no retired category key;
- no synonym category proliferation;
- `tzjq` as the single ordinary SEO article CMS carrier;
- future Hub association as metadata/internal-link architecture rather than extra article categories.

## 6. Publication remains a separate lifecycle

The existing website lifecycle remains:

`Approved Package → ingress → Draft → explicit Scheduled → Native Publisher → Publication Receipt`

Cross-repo transport adds only the first automated movement:

`caipiaowenzhang Approved → xyptdq Draft`

It does not merge Draft, Scheduled and Published into one state.

## 7. Publication Receipt and reverse synchronization

After a future article is actually published by the existing Native Publisher, the website exports Publication Receipt v1. The content engine may then explicitly import that receipt and record the real:

- CMS id;
- published URL;
- published timestamp;
- receipt id.

Internal-link planning must continue to use real published URLs only. If internal links modify article body bytes, that is a new content revision and must pass Approval again.

## 8. Activation sequence

Current state: **contract-ready, transport disabled**.

Before enabling automatic cross-repo retrieval:

1. Explicit user approval to enable transport.
2. Verify the source repository contract points all ordinary SEO content to `tzjq` and contains no active `seo-articles` route.
3. Configure a trusted private-repository transport mechanism without committing credentials to either repository.
4. Run read-only inventory/deduplication dry-run.
5. Run a small Approved → Draft smoke batch.
6. Re-run website package validation and SEO portfolio audit.
7. Keep scheduling/publishing disabled unless separately and explicitly approved.

A later decision to enable daily publication must be a separate change to the publication policy and scheduler; enabling transport alone must never publish anything.

## 9. Machine policy

The authoritative machine-readable gate is:

`config/content_source_sync_policy.json`

Any future sync implementation must fail closed if that file has `sync_enabled=false`.
