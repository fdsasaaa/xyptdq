# Cross-Repo Content Sync — Public Release → Draft Contract

Source repository: `fdsasaaa/caipiaowenzhang`

Website repository: `fdsasaaa/xyptdq`

This document defines the future automatic transport boundary between the independent article-production repository and the website repository. It is **not** authorization to schedule or publish articles.

## 1. Source of truth

The content engine now has two distinct layers and the website must not confuse them:

- Immutable parent/audit inventory: `fdsasaaa/caipiaowenzhang@main:articles/approved/`
- Website-facing reviewed revisions: `fdsasaaa/caipiaowenzhang@main:articles/public_release/`
- Public-release manifests: `fdsasaaa/caipiaowenzhang@main:articles/public_release/manifests/`

`articles/approved/` remains the parent evidence used to verify provenance. Its body bytes are not the automatic website Draft source when a separately reviewed public-release revision is required.

The website Draft source must be a validated revision with `revision_kind=website_public_release`, selected through the corresponding public-release manifest.

The transport layer must ignore drafts, rejected content, temporary outputs and any revision that fails the website's own parent/revision validation.

## 2. Destination state

A successfully transported revision may only enter the website as:

`publication_state=draft`

The transport layer must not:

- create `publish_at`;
- copy a revision into `content/scheduled`;
- invoke the Native Publisher;
- alter Publisher cron;
- consume the preserved scheduled queue;
- write directly to the production CMS database.

A validated public-release revision is permission to create/reconcile a website Draft. It is not permission to publish.

## 3. Public-release and parent verification

Before Draft creation the website must independently verify both the immutable parent and the website-facing revision.

Required revision checks include:

- revision and parent pass the normal Approved Package structural/integrity checks;
- identical `article_id`;
- `revision_kind=website_public_release`;
- positive `release_revision` and exact `revision_id=<article_id>:public-rN`;
- `parent_content_hash` and `parent_fingerprint` match the immutable parent;
- revision content hash matches the revised body and differs from the parent body hash;
- `slug`, `primary_keyword`, `site_category_key`, and `content_type` remain aligned with the parent contract;
- `creator_batch_id` is preserved from the parent;
- `source_batch_id` matches the same parent `creator_batch_id`;
- `public_release_review.status=approved` with review time and review contract;
- deterministic public-release fingerprint is recomputed and verified.

A partial manifest may authorize only a controlled canary when `canary_ingestion_allowed=true`. Full-batch intake requires `status=complete` and `website_batch_ingestion_allowed=true`.

## 4. Category and Cluster contract

Website numeric catids remain owned by `config/content_category_map.json`.

Current ordinary SEO article carrier:

- `site_category_key=tzjq`
- catid 3
- CMS label `投注机巧`

`seo-articles` is retired and must be rejected. The website must never infer a category or SEO Cluster from title text or keywords.

If a public-release revision has no portable Cluster metadata, the website may apply a separate explicit editorial batch contract such as the CF50 mapping. A package/map conflict fails closed.

## 5. Identity and duplicate protection

Each revision must preserve stable source and revision identity. The website must track at least:

- `article_id`
- `revision_id`
- `creator_batch_id`
- `source_batch_id`
- `fingerprint`
- `content_hash`
- `parent_content_hash`
- `parent_fingerprint`

Rules:

- same article + same revision + same hash → idempotent / unchanged;
- changed body → requires a new validated public-release revision;
- missing provenance → reject;
- no silent replacement of an existing Draft with different source body bytes.

The existing website SEO portfolio audit remains a second gate for exact primary-keyword ownership and cross-state consistency.

## 6. SEO ownership

Transport does not bypass SEO controls.

Before a new Draft becomes part of the managed portfolio, the website must continue to enforce:

- one exact Primary Keyword owner per distinct article;
- stable article identity across states;
- no silent body replacement;
- no retired category key;
- no synonym category proliferation;
- `tzjq` as the single ordinary SEO article CMS carrier;
- future Hub association as metadata/internal-link architecture rather than extra article categories;
- no planned Hub URL injection before a real live URL is verified.

## 7. Publication remains a separate lifecycle

The website lifecycle is:

`Immutable Approved parent → reviewed Public Release → Website Draft → explicit Scheduled → Native Publisher → Publication Receipt`

Cross-repo transport automates only the movement from a validated public-release revision into Website Draft.

It does not merge Draft, Scheduled and Published into one state.

## 8. Publication Receipt and reverse synchronization

After a future article is actually published by the existing Native Publisher, the website exports Publication Receipt v1. The content engine may then explicitly import that receipt and record the real:

- CMS id;
- published URL;
- published timestamp;
- receipt id.

Internal-link planning must continue to use real published URLs only. If internal links modify article body bytes, that is a new content revision and must pass Approval/public-release review again.

## 9. Activation sequence

Current state: **contract-ready, transport disabled**.

Before enabling automatic cross-repo retrieval:

1. Public-release revision and manifest capability must be present on the article repository `main`.
2. Configure a trusted private-repository transport mechanism without committing credentials to either repository.
3. Verify source contract, category policy, batch identity and public-release manifest semantics.
4. Run a read-only inventory/deduplication dry-run.
5. Run one controlled Public Release → Draft canary.
6. Re-run website package validation, Cluster assignment checks and SEO portfolio audit.
7. Keep scheduling/publishing as a separate operational gate.

Enabling transport alone must never publish anything.

## 10. Machine policy

The authoritative machine-readable gate is:

`config/content_source_sync_policy.json`

Any future sync implementation must fail closed if that file has `sync_enabled=false`.
