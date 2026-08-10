# WorkBuddy publisher smoke v2

This is a narrowly scoped production validation task after the 2026-08-10 smoke blockers were fixed in Git. Do not optimize the website, create bulk content, install SQLite, change unrelated server settings, or enable the recurring publisher cron.

## Hard rules

- Never output or commit passwords, tokens, cookies, private keys, database DSNs, or `config/database.php`.
- If backup verification fails, STOP.
- If exact-ref deployment does not explicitly print both `BACKUP_VERIFY: PASS` and `RENDERED_HOME_INDEXABLE: PASS`, STOP.
- If production homepage template or rendered HTML still contains `robots=none`, STOP.
- Publish exactly one smoke article and then submit the same `article_key` a second time only to prove idempotency.
- Do not mark scheduled publishing enabled. ChatGPT will do that after reviewing the evidence.

## 1. Sync canonical repo

```bash
cd /opt/xyptdq-repo
[ -z "$(git status --porcelain)" ] || { echo 'BLOCKED_DIRTY_REPO'; exit 1; }
git fetch --prune origin
git checkout main
git reset --hard origin/main
git rev-parse HEAD
```

Record SHA only.

## 2. Fresh backup and mandatory verification

```bash
cd /opt/xyptdq-repo
XYPTDQ_REPO_DIR=/opt/xyptdq-repo ./scripts/backup.sh
```

Inside the emitted backup directory run:

```bash
sha256sum -c checksums.sha256
```

Any failure => STOP.

## 3. Retry CMS DB credential rotation with the corrected script

The corrected script now preserves the original owner/group/mode of `config/database.php` and prints the parsed mode.

Dry-run:

```bash
cd /opt/xyptdq-repo
bash scripts/security/rotate_cms_db_password.sh --dry-run
```

Required:

- `PRECHECK PASS`
- `MODE=DRY_RUN`
- `DRY-RUN ONLY`

Apply:

```bash
bash scripts/security/rotate_cms_db_password.sh --apply
```

Required when successful:

- `MODE=APPLY`
- `APPLY CONFIRMED`
- `ROTATED AND VERIFIED`
- homepage/article HTTP 200.

If apply fails but the script explicitly confirms automatic rollback and the homepage + known article are both back to HTTP 200, record `BLOCKED_SAFE_ROLLBACK` and continue to Step 4. Do not improvise another password change. If rollback health is not confirmed, STOP.

## 4. Deploy exact latest main

```bash
cd /opt/xyptdq-repo
./scripts/deploy.sh origin/main
```

Required output includes:

- `BACKUP_VERIFY: PASS`
- `RENDERED_HOME_INDEXABLE: PASS`
- `Deployment complete`

Then independently verify:

```bash
if grep -Fq '<meta name="robots" content="none">' /www/wwwroot/59.110.217.6/template/pc/default/home/index.html; then
  echo TEMPLATE_ROBOTS_FAIL
  exit 1
fi
curl -sk https://www.laocaimi.org/ -o /tmp/xyptdq-home-check.html
php -r '$s=file_get_contents($argv[1]); exit(preg_match("~<meta\\b[^>]*name=[\x22\x27]robots[\x22\x27][^>]*content=[\x22\x27]none[\x22\x27][^>]*>~i",$s)?1:0);' /tmp/xyptdq-home-check.html || { echo RENDERED_ROBOTS_FAIL; exit 1; }
rm -f /tmp/xyptdq-home-check.html
```

If any check fails: STOP.

## 5. Run fixed category probe

```bash
php /opt/xyptdq-repo/scripts/content/category_probe.php --output=/tmp/category_probe.json
```

The previous MariaDB error involving reserved word `show` has been fixed by quoting identifiers.

Verify the JSON is valid and contains the category intended for SEO articles. Do not hand-edit the result.

## 6. One real article smoke test

Use the repository smoke article:

`content/smoke/ffc-betting-basics-risk-v1.json`

Run the production smoke tool exactly as documented by the repository script. The test must publish only this one article through `cms_publish_adapter.php`.

Required result:

- first submission returns a positive CMS ID;
- HTTP for the resulting article URL is 200;
- article appears in `sitemap.xml` after sitemap regeneration.

Do not create any other test content.

## 7. Prove durable idempotency

Submit the exact same smoke JSON again using the same smoke tool and same `article_key`.

Required:

- second submission returns the same CMS ID as the first;
- no second article row is created;
- registry maps the `article_key` to that same CMS ID.

If the CMS IDs differ or duplicate content exists: STOP and report `IDEMPOTENCY_FAIL`.

## 8. Capture sanitized evidence

Create a branch from current `origin/main`, for example:

`ops/publisher-smoke-evidence-20260810`

Commit only sanitized evidence, such as:

- `docs/probes/category_probe_after_fix.json`
- `docs/probes/PUBLISHER_SMOKE_RESULT.md`

The result file should record only non-secret facts:

- server SHA;
- backup verification;
- DB rotation status (`ROTATED`, `BLOCKED_SAFE_ROLLBACK`, or `FAIL`);
- deploy/indexing status;
- category probe status;
- first CMS ID;
- second CMS ID;
- idempotency pass/fail;
- article HTTP status;
- sitemap inclusion;
- no secrets disclosed.

Do not commit runtime config, DB dumps, logs containing credentials, cookies, or server secrets.

## 9. Final response

Return only:

```text
【Publisher smoke v2】
Server SHA: <sha>
Backup verification: PASS/FAIL
DB credential rotation: ROTATED / BLOCKED_SAFE_ROLLBACK / FAIL
Exact-ref deploy: PASS/FAIL
Production template robots=none: ABSENT/PRESENT
Rendered homepage robots=none: ABSENT/PRESENT
Category probe: PASS/FAIL
Smoke publish: PASS/FAIL
Smoke cms_id first: <id/N/A>
Smoke cms_id second: <id/N/A>
Second publish idempotent: YES/NO/N/A
Article HTTP: <code/N/A>
Sitemap contains article: YES/NO/N/A
Evidence branch: <branch/N/A>
Evidence commit: <sha/N/A>
Secrets disclosed: NO
Blocking item: NONE / <one concise non-secret blocker>
```

After this response, stop. Do not install/enable scheduled publisher cron. ChatGPT will review the evidence and decide whether to unlock automation.
