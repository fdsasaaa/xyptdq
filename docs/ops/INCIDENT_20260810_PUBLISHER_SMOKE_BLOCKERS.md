# Publisher smoke blockers — 2026-08-10

The production smoke run stopped before publishing any article.

## Diagnosed blockers

1. **DB credential rotation HTTP 500** — the previous atomic rewrite of `config/database.php` created a new root-owned file instead of preserving the original owner/group/mode. PHP-FPM can then lose read access and return HTTP 500 even when the new DB password itself is valid. The revised rotator preserves metadata before rename, reloads PHP-FPM, verifies DB + HTTP, and automatically rolls back if any verification changes.
2. **Homepage `robots=none` persisted** — relying on a post-rsync patch alone was not sufficiently observable in the prior run. The revised deployer sanitizes the exact-ref temporary worktree before rsync, sanitizes production again after rsync, validates the production template, validates the rendered homepage body, and cannot record deployment success while the directive remains.
3. **Category probe SQL syntax error** — the probe selected the MariaDB keyword `show` without quoting it. The revised query quotes every selected identifier.

## Safety state

- Bulk publishing remains disabled.
- Scheduled publisher cron remains disabled.
- The one-article smoke test must be re-run after this hotfix is deployed.
- No production publisher capability may be marked durable/idempotent until the same `article_key` is submitted twice and returns the same CMS ID.
