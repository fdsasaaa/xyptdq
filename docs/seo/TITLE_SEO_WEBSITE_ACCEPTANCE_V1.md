# Website Title SEO Acceptance Gate V1

## Purpose

`caipiaowenzhang` owns article writing and final article-title generation. `xyptdq` owns the final website-side SEO architecture and therefore performs an independent acceptance check before a Title SEO V1.0 public-r1 revision can become a website Draft.

This gate does **not** rewrite article titles. It decides whether the supplied title is compatible with the website's existing keyword ownership and whether the upstream Title SEO contract is complete.

## Compatibility

Historical Approved/public-r1 packages that predate Title SEO V1.0 remain valid. The gate is fail-closed only when a package declares any Title SEO contract field.

## Required upstream contract

A Title SEO V1.0 revision must provide:

- `title_seo_contract_version = 1.0`
- `title_candidates` with 3–5 unique candidates
- final `title` selected from the candidate set
- `seo_title` equal to the final `title`
- non-empty `title_selection_reason`
- `title_review.passed = true`
- all six required upstream gates present and passed:
  - `TITLE_TOPIC_MATCH`
  - `TITLE_DUPLICATION_CHECK`
  - `TITLE_KEYWORD_DIVERSITY`
  - `TITLE_NUMERIC_CLAIM_VERIFIED`
  - `TITLE_SEARCH_INTENT_CHECK`
  - `TITLE_CLICKABILITY_CHECK`

## Website-specific checks

The website then adds checks that the article-production repository cannot own globally:

1. **Reserved keyword ownership** — any exact Primary Keyword already assigned in `content/keyword_map.json` to home, a category, or a hub remains reserved for that target. An article cannot take that exact Primary Keyword.
2. **Reserved exact title** — an article title cannot be exactly the same as a broad keyword already reserved to another site target.
3. **Sensitive claim qualification** — prohibited profit/guarantee language from the keyword map cannot appear as an unqualified promise. Critical/question framing remains allowed so evidence-based debunking articles are possible.
4. **Draft/Scheduled portfolio uniqueness** — the website portfolio audit continues enforcing one exact Primary Keyword owner per article and now also blocks two different managed articles from having the same normalized final title.

## Draft provenance

When Title SEO V1.0 passes intake, the website Draft keeps:

- `title_seo_contract_version`
- `title_candidates`
- `title_selection_reason`
- `title_review`
- `source_title_seo_site_acceptance`

This allows later website-side audits to verify the title without modifying the immutable article source.

## Explicit non-goals

This change does not:

- modify existing article bodies or historical public-r1 files;
- rename existing published URLs;
- enable or alter Publisher scheduling;
- change Sitemap or Canonical behavior;
- authorize CF50 final-five publication;
- generate replacement titles in the website repository.

The division of responsibility remains: article repository decides the best title for the article; website repository decides whether that title fits the site's total SEO architecture.
