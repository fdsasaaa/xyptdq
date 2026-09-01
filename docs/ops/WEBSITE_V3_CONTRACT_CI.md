# Website V3 Contract CI

This repository has a dedicated GitHub Actions check at `.github/workflows/website-v3-contract.yml`.

It runs `python3 scripts/ops/validate_website_v3_contract.py` on every pull request and every push to `main`.

The check exists to prevent recurrence of the #474 class of policy regression:

- formal public-r1 retention minimum must remain 1;
- operational minimum remains 10;
- ordinary `DAILY-*` SEO publication is independent from Issue #264;
- `DAILY-20260901` remains eligible for the ordinary SEO canary path;
- `DAILY-20260817` remains pending Title SEO review;
- the CF50 Final Five remain frozen until their own Issue #264 authorization.

A failing `website-v3-contract` check must be treated as a merge blocker even if other repository CI jobs are green.
