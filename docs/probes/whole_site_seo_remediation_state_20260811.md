# Whole-site SEO remediation state — 2026-08-11

## Production audit baseline

Read-only Server Bridge audit `whole-site-seo-audit-20260811-01` identified 15 structural/indexability issues across the public homepage, SEO category, article rendering and legacy source templates. robots.txt and sitemap.xml were already healthy.

## Remediation already merged to canonical Git

- PC public content templates (`article.html`, `list.html`, `show.html`, `category.html`) now use clean single-document SEO header/footer partials.
- PC public content pages have index/follow robots, canonical URLs, non-empty description fallback, one semantic H1, Open Graph metadata and JSON-LD; news article pages add Article JSON-LD.
- Legacy external demo-template dependencies were removed from those public content templates.
- Mobile homepage/list/category/show routes now use an indexable SEO header with canonical/robots/Open Graph/JSON-LD; article pages add Article JSON-LD.
- CI guards prevent these indexable templates from regressing to `robots=none`, missing canonical/schema/H1, or the legacy external demo domains.
- Exact production CodeIgniter72 System/Cache source and the recovered 13-byte `site/cache/frame.lock` are now versioned in Git so exact-ref deployment can be made safe.

## Production deployment state

Phase 1 template changes remain rollback-gated until a Server Bridge deployment passes all PC/mobile render assertions. Earlier attempts were automatically rolled back on failure. `deploy-seo-template-phase1-v4-20260811-01` is the classified verification pass for this stage.

## Deliberately deferred Phase 2

The custom PC homepage remains a separate change because its legacy source contains multiple complete HTML documents and site-specific navigation/platform/popup behavior. Phase 2 will replace it with one semantic document while preserving required business/navigation functionality, then deploy it under an independent rollback/visual/SEO gate.

No production secrets are recorded in this document.
