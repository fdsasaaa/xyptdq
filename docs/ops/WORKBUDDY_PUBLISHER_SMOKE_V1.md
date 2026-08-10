# WorkBuddy publisher smoke v1

This is a narrowly scoped production validation task. Do not optimize the website, create bulk content, install SQLite, or change unrelated server settings.

## Hard rules

- Never output or commit passwords, tokens, cookies, private keys, database DSNs, or config/database.php.
- If a required backup verification fails, STOP. Do not continue as happened in the previous run.
- If exact-ref deployment fails, STOP.
- If DB credential rotation fails and does not explicitly confirm rollback/baseline health, STOP.
- The one smoke article is intentional real content; do not create any other article.

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

## 2. Fresh backup — verification is mandatory

```bash
cd /opt/xyptdq-repo
XYPTDQ_REPO_DIR=/opt/xyptdq-repo ./scripts/backup.sh
```

Locate the backup ID emitted by the script and run `sha256sum -c checksums.sha256` inside that backup directory.

If any checksum fails: STOP and return `BACKUP_VERIFY_FAIL`.

## 3. Retry exposed CMS DB credential rotation with the revised tool

Run dry-run first:

```bash
cd /opt/xyptdq-repo
./scripts/security/rotate_cms_db_password.sh
```

Required before apply:

- `PRECHECK PASS`
- baseline `home=200 article=200`
- `DRY-RUN ONLY`

Then:

```bash
./scripts/security/rotate_cms_db_password.sh --apply
```

Required final output:

`ROTATED AND VERIFIED`

The revised tool reloads php7.4-fpm after changing the config and rolls back on verification failure.

If it reports rollback/blocking, do not improvise another password procedure. Record only the non-secret error.

## 4. Exact-ref deploy latest main and independently verify SEO P0

Only if steps 2-3 are healthy:

```bash
cd /opt/xyptdq-repo
./scripts/deploy.sh origin/main
```

Then independently run:

```bash
if grep -Fq '<meta name="robots" content="none">' /www/wwwroot/59.110.217.6/template/pc/default/home/index.html; then
  echo HOMEPAGE_TEMPLATE_INDEXING_FAIL
  exit 1
else
  echo HOMEPAGE_TEMPLATE_INDEXING_PASS
fi

curl -sk https://www.laocaimi.org/ | grep -i 'name="robots"' | head -5 || true
curl -sk -o /dev/null -w 'home=%{http_code}\n' https://www.laocaimi.org/
curl -sk -o /dev/null -w 'robots=%{http_code}\n' https://www.laocaimi.org/robots.txt
curl -sk -o /dev/null -w 'sitemap=%{http_code}\n' https://www.laocaimi.org/sitemap.xml
```

Required: production file has no `robots=none`, and all HTTP codes are 200.

If the repository source template still contains the legacy tag but the production file is clean, report those as two separate facts. Do not confuse Git source with production WebRoot.

## 5. Capture sanitized news category map

```bash
php /opt/xyptdq-repo/scripts/content/category_probe.php \
  --output=/tmp/xyptdq_category_probe.json
```

This output contains category IDs/names only and is safe to review. Do not hand-write or truncate it.

## 6. Publisher smoke dry-run

```bash
cd /opt/xyptdq-repo
php scripts/content/publisher_smoke.php \
  --article=content/smoke/ffc-betting-basics-risk-v1.json
```

Must print `DRY-RUN ONLY`.

## 7. Publish exactly one real smoke article and prove DB idempotency

Only if all previous steps passed:

```bash
cd /opt/xyptdq-repo
php scripts/content/publisher_smoke.php \
  --article=content/smoke/ffc-betting-basics-risk-v1.json \
  --commit | tee /tmp/xyptdq_publisher_smoke.log
```

Required:

- `PASS`
- one positive `cms_id`
- second invocation inside the smoke tool reports `second_idempotent=true`

The script deliberately submits the same article_key twice. The second call must return the same CMS ID rather than create a duplicate.

Do not manually rerun `--commit` if the script itself reports failure. Stop and preserve the non-secret error.

## 8. Verify the published article and sitemap

Extract only the numeric cms_id from the smoke output, then:

```bash
CMS_ID=<numeric-id-from-smoke>

curl -sk -o /dev/null -w 'article=%{http_code}\n' \
  "https://www.laocaimi.org/index.php?c=show&id=${CMS_ID}"

XYPTDQ_WEBROOT=/www/wwwroot/59.110.217.6 \
XYPTDQ_DB_CONFIG=/www/wwwroot/59.110.217.6/config/database.php \
XYPTDQ_SITEMAP=/www/wwwroot/59.110.217.6/sitemap.xml \
php /opt/xyptdq-repo/scripts/seo/generate_sitemap.php

grep -F "/index.php?c=show&amp;id=${CMS_ID}" /www/wwwroot/59.110.217.6/sitemap.xml >/dev/null \
  || grep -F "/index.php?c=show&id=${CMS_ID}" /www/wwwroot/59.110.217.6/sitemap.xml >/dev/null
```

Required: article HTTP 200 and sitemap contains the article URL.

## 9. Produce exact sanitized smoke evidence

Create branch from current origin/main:

`ops/publisher-smoke-result-20260810`

Add only:

- `docs/probes/category_probe_20260810.json` copied exactly from `/tmp/xyptdq_category_probe.json`
- `docs/probes/PUBLISHER_SMOKE_RESULT.md`

The markdown result may contain only:

```text
server_sha: <sha>
backup_verify: PASS
backup_id: <id>
db_credential_rotation: ROTATED / BLOCKED
exact_ref_deploy: PASS
production_robots_none: ABSENT / PRESENT
home_http: <code>
robots_http: <code>
sitemap_http: <code>
smoke_article_key: ffc-betting-basics-risk-v1
smoke_cms_id: <numeric id>
smoke_first_publish: NEW / IDEMPOTENT
smoke_second_publish: IDEMPOTENT
smoke_article_http: <code>
sitemap_contains_smoke_article: YES / NO
secrets_disclosed: NO
```

Do not commit the raw backup, DB config, database dump, cron, `/tmp` files, full shell history or credentials.

Push the branch. PR is optional; ChatGPT can create it.

## 10. Stop

Do NOT install the publisher cron yet. `durable_idempotency_verified` remains false in Git until ChatGPT reviews this smoke evidence. After ChatGPT verifies it, ChatGPT will unlock the manifest and only then the cron installer can be run.

Return only:

```text
【Publisher smoke】
Server SHA: ...
Backup verification: PASS/FAIL
DB credential rotation: ROTATED/BLOCKED
Exact-ref deploy: PASS/FAIL
Production robots=none: ABSENT/PRESENT
Category probe: PASS/FAIL
Smoke publish: PASS/FAIL
Smoke cms_id: ...
Second publish idempotent: YES/NO
Article HTTP: ...
Sitemap contains article: YES/NO
Evidence branch: ...
Evidence commit: ...
Secrets disclosed: NO
Blocking item: NONE / ...
```
