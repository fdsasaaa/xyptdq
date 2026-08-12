# SEO Internal Link Architecture — tzjq Single-Category Model

## 1. Objective

All ordinary SEO articles remain in the single CMS category `tzjq` / `投注机巧`. Topic separation is handled by logical SEO clusters and future Hub pages rather than by creating more CMS article categories.

Machine contract: `content/seo_cluster_registry.json`.

## 2. Logical clusters

Current planned clusters map one-to-one to the planned Hub groups already defined in `content/seo_target_registry.json`:

- `ffc_research` → 分分时时彩研究中心
- `hash_ffc` → 哈希分分彩专题
- `qiqu_ffc` → 奇趣分分彩专题
- `ssc` → 时时彩技术中心
- `racing` → 赛车与飞艇专题
- `platform_review` → 平台评测与对比
- `research_lab` → 数据实验室

These are logical SEO identities. They do not change `site_category_key=tzjq` and do not create a CMS category.

## 3. Assignment rules

Cluster assignment must come from explicit article metadata or an editorial/contract mapping. The website must not classify an article merely because a word appears in its title.

An article may belong to more than one logical cluster when the relationship is real, but one assigned cluster should be designated primary for ownership/navigation purposes.

Examples:

- A general 分分时时彩投注技巧 article may primarily belong to `ffc_research`.
- A 分分时时彩历史回测实验 may primarily belong to `research_lab` and secondarily to `ffc_research`.
- A 哈希分分彩数据验证 article may primarily belong to `hash_ffc` and secondarily to `research_lab`.

Unassigned articles are allowed. It is safer to leave an article unassigned than to guess and create a wrong SEO relationship.

## 4. Internal-link lifecycle

### Article → Hub

Do not insert a Hub link while the Hub is only symbolic/planned.

A Hub link becomes eligible only after the Hub:

- exists at a real URL;
- returns HTTP 200;
- self-canonicalizes;
- has substantive content;
- is internally linked and approved for sitemap inclusion.

### Hub → Article

A Hub may link only to real published article URLs. Draft or scheduled article IDs are not sufficient.

### Article → Article

Prefer links that genuinely continue the reader's task: prerequisite explanation, deeper method, related validation, risk/cost analysis, or a closely related example.

Do not create all-to-all links just because two articles share a cluster.

The target must have a real published URL. If the target is not published, the planner may keep an article-id relationship with `url=null` until Publication Receipt resolves it.

## 5. Anchor-text rules

- Natural contextual anchor text is preferred.
- Exact primary-keyword anchor repetition is not required.
- Do not force the same exact-match anchor across many articles.
- Anchor wording must accurately describe the target page.
- Avoid linking two pages with nearly identical intent in a way that suggests both are primary owners of the same keyword.

## 6. Keyword ownership and cannibalization

The existing exact primary-keyword ownership audit remains authoritative.

Clusters do not create a second owner for the same primary keyword. A Hub only becomes the owner of its intended Hub-level keyword after it is actually live and the Keyword Map is updated to that verified URL.

Until then, symbolic Hub targets remain symbolic and current live carriers continue to own their existing mapped intents.

Special rule for `platform_review`: the homepage keeps the primary owner intent `信誉平台大全`. A future platform-review Hub should target comparison/review intent rather than duplicate the homepage's primary keyword.

## 7. Body revisions and Approval

Internal links are part of article body bytes. Adding or changing a contextual link changes the body hash.

Therefore a planned internal-link revision must follow:

`published URL becomes available → planner resolves target → draft revision → new content hash → review/Approval → new Approved Package`

Do not directly mutate an Approved Package or a published body merely to inject links.

## 8. Hub readiness

Do not create a Hub to satisfy an audit counter.

A Hub is ready only when its supporting corpus is substantial enough to provide a useful organized landing page with distinct search intent, useful explanatory copy and real article navigation.

Current preferred implementation order remains:

1. 分分时时彩研究中心
2. 数据实验室
3. 平台评测与对比
4. 哈希分分彩 / 奇趣分分彩 when corpus is ready
5. 时时彩 / 赛车与飞艇 when corpus is ready

## 9. Future automation boundary

When the content engine and website repository are eventually connected automatically, cluster metadata should travel with the Approved Package or through an explicit editorial mapping. The cross-repo transport must not infer clusters from title text and must not use planned Hub URLs.

Publication and transport remain separately gated by `config/content_source_sync_policy.json` and `config/content_publication_policy.json`.
