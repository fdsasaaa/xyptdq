# FFC Research Hub Readiness — 2026-08-14

## Decision

`ffc_research_hub` is **CONTENT_READY / PUBLICATION_NOT_READY**.

The formal `CF50-20260813` inventory provides a substantive supporting corpus for the planned hub, but the hub must not be created as a live/sitemap target until supporting articles have verified public URLs and the hub itself can satisfy the existing live-link, HTTP 200 and self-canonical gates.

## Evidence

Source article repository: `fdsasaaa/caipiaowenzhang`

Formal batch: `articles/batches/CF50-20260813.json`

Formal inventory pattern: `articles/approved/LCM-CREATOR-cf50-20260813-*.json`

Formal article count: **50**

All 50 packages belong to the `分分彩` subject family and provide enough breadth to justify a distinct research-navigation experience rather than an empty or synonym-only hub.

## Corpus coverage

| Topic group | Article count | Article IDs |
| --- | ---: | --- |
| 后二直选 | 10 | 001-010 |
| 后三直选 | 10 | 011-020 |
| 五星直选 | 10 | 021-030 |
| 定位胆 | 8 | 031-036, 039-040 |
| 一星直选 | 2 | 037-038 |
| 后二组选 | 5 | 041-045 |
| 后三组选6 | 3 | 046-048 |
| 后三组选3 | 2 | 049-050 |

## Hub intent

Proposed label: **分分彩研究中心**

Primary intent: **分分彩玩法研究、技术方法、数据验证与风险分析的综合入口**

The hub must be an editorial navigation page, not a duplicate category page and not a thin keyword-variation page.

Recommended sections after supporting articles become live:

1. 后二玩法研究
2. 后三玩法研究
3. 五星结构研究
4. 定位与一星研究
5. 组选研究
6. 数据实验与风险控制

## SEO ownership

The hub should own the broad research/navigation intent already reserved by `ffc_research_hub` in `content/seo_target_registry.json`.

It must not take over the existing `ffc_betting_guide` carrier intent or mechanically create separate pages for every synonym.

Symbolic keyword-map targets must remain symbolic until the hub has a verified live URL.

## Internal-link gate

Before the hub is allowed to become live:

- supporting article URLs must exist and return HTTP 200;
- article URLs used by the hub must be verified public URLs, not draft or planned URLs;
- the hub must provide curated navigation rather than all-to-all linking;
- article-to-hub links may only be added after the hub URL is live and verified;
- any body-link change that alters an approved article must follow the existing reapproval/content-hash rule;
- the hub must return HTTP 200 and self-canonical before sitemap inclusion;
- only after live verification may corresponding symbolic keyword-map targets be replaced by the real hub URL.

## Current blocker

The `CF50-20260813` packages are formal inventory, but website publication eligibility is not yet satisfied. Therefore:

- do not create a live hub yet;
- do not inject planned hub URLs into articles;
- do not change the keyword map to a nonexistent hub URL;
- do not restore the legacy scheduled queue or publisher as a workaround.

## Next transition

When a meaningful first tranche of CF50 public-release articles has verified live URLs, rerun this readiness check using live evidence. At that point the preferred implementation order is:

1. build the hub from the six navigation sections above;
2. link only to verified live articles;
3. verify HTTP 200 and self-canonical;
4. add the hub to sitemap;
5. update the `ffc_research_hub` status from planned to live;
6. replace only the corresponding symbolic keyword-map targets with the verified hub URL.
