# WorkBuddy publisher smoke v5 — native PDO placeholder fix + final proof

This runbook replaces V4 for the next server pass. V4 confirmed production health, framework recovery, shared category resolution, and live target preflight, but the write transaction failed with `SQLSTATE[HY093]: Invalid parameter number`.

Root cause in Git has now been fixed: `cms_publish_adapter.php` runs with `PDO::ATTR_EMULATE_PREPARES=false`, but the hits-row INSERT reused the same named placeholder `:now` four times. Native PDO/MySQL prepared statements require each named placeholder occurrence to be unique. V5 uses `:day_time`, `:week_time`, `:month_time`, and `:year_time` instead.

This task does **not** enable recurring publishing or generate bulk content.

## Hard rules

- Never print, paste, commit, or log passwords, tokens, cookies, private keys, database DSNs, `config/database.php`, database dumps, or other secrets.
- Do not force-push.
- Do not rerun DB credential rotation. Record `PREVIOUSLY_ROTATED` only.
- Do not call a smoke publish `PASS` if any SQL exception occurs.
- Publish only the existing repository smoke article.
- `publisher_smoke.php --commit` submits the same `article_key` twice internally. Do not run a second manual commit command.
- Do not enable the scheduled publisher cron.
- If any STOP condition occurs, stop immediately and report it.

## 1. Verify healthy production before changes

```bash
for u in \
  https://www.laocaimi.org/ \
  https://www.laocaimi.org/robots.txt \
  https://www.laocaimi.org/sitemap.xml; do
  code=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$u")
  echo "$u $code"
  [ "$code" = 200 ] || exit 1
done
```

Verify rendered homepage has no `robots=none`. Failure => STOP.

## 2. Sync latest main and confirm the PDO fix exists

```bash
cd /opt/xyptdq-repo
git status --short
git fetch --prune origin
git checkout main
git reset --hard origin/main
git rev-parse HEAD
```

The latest main must contain this V5 runbook and the fixed hits INSERT.

Verify:

```bash
grep -F ':day_time,:week_time,:month_time,:year_time' scripts/content/cms_publish_adapter.php
grep -F 'PDO::ATTR_EMULATE_PREPARES => false' scripts/content/cms_publish_adapter.php
! grep -Fq ':now,:now,:now,:now' scripts/content/cms_publish_adapter.php
```

Any failure => STOP.

## 3. Fresh verified backup

```bash
cd /opt/xyptdq-repo
XYPTDQ_REPO_DIR=/opt/xyptdq-repo ./scripts/backup.sh
```

Run `sha256sum -c checksums.sha256` inside the emitted backup directory. Any failure => STOP.

## 4. Version the already-recovered framework source on a fresh remote branch

Current Git `main` still must not be deployed unless the recovered CodeIgniter source is also present in the exact ref. Create a new branch from the latest `origin/main`:

```bash
cd /opt/xyptdq-repo
git checkout -b hotfix/production-framework-recovery-v5-20260810 origin/main
```

Production webroot:

```bash
WEBROOT=/www/wwwroot/59.110.217.6
REPO=/opt/xyptdq-repo
```

Require the recovered framework source:

```bash
test -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" || { echo CACHE_FACTORY_MISSING; exit 1; }
mkdir -p "$REPO/site/dayrui/CodeIgniter72/System/Cache"
rsync -a --delete \
  "$WEBROOT/dayrui/CodeIgniter72/System/Cache/" \
  "$REPO/site/dayrui/CodeIgniter72/System/Cache/"
```

Locate the unique `frame.lock` and verify exact bytes:

```bash
mapfile -t FRAME_LOCKS < <(find "$WEBROOT" -type f -iname 'frame.lock' -print)
[ "${#FRAME_LOCKS[@]}" -eq 1 ] || { echo FRAME_LOCK_COUNT_INVALID; exit 1; }
FRAME_LOCK="${FRAME_LOCKS[0]}"
FRAME_REL="${FRAME_LOCK#"$WEBROOT/"}"
FRAME_HEX=$(od -An -tx1 -v "$FRAME_LOCK" | tr -d ' \n')
[ "$FRAME_HEX" = '436f646549676e697465723732' ] || { echo FRAME_LOCK_BYTES_INVALID; exit 1; }
mkdir -p "$REPO/site/$(dirname "$FRAME_REL")"
cp -p "$FRAME_LOCK" "$REPO/site/$FRAME_REL"
```

Do not copy runtime cache, logs, sessions, uploads, secrets, database configuration, or private keys.

Commit only the recovered framework source:

```bash
git add site/dayrui/CodeIgniter72/System/Cache
git add "site/$FRAME_REL"
git diff --cached --check
git diff --cached --name-only
git commit -m 'Recover required CodeIgniter framework source for publisher v5'
git push -u origin hotfix/production-framework-recovery-v5-20260810
```

Confirm the remote branch really exists:

```bash
git ls-remote --heads origin hotfix/production-framework-recovery-v5-20260810
```

No output => STOP. Never force-push.

## 5. Re-run corrected category probe and live target preflight

```bash
cd /opt/xyptdq-repo
php scripts/content/category_probe.php --output=/tmp/category_probe_v5.json
```

Require `catid=7` in the effective category set, expected from `dr_1_share_category` with the news module marker.

Then:

```bash
php scripts/content/publisher_smoke.php \
  --article=content/smoke/ffc-betting-basics-risk-v1.json
```

Required output:

- `TARGET_PREFLIGHT PASS category_source=...`
- `DRY-RUN ONLY; no database write attempted.`

Failure => STOP before write.

## 6. Deploy the exact remote recovery-v5 branch

```bash
cd /opt/xyptdq-repo
./scripts/deploy.sh origin/hotfix/production-framework-recovery-v5-20260810
```

Required:

- `FRAMEWORK_SOURCE_INTEGRITY: PASS`
- `BACKUP_VERIFY: PASS`
- `FRAMEWORK_PRODUCTION_INTEGRITY: PASS`
- `RENDERED_HOME_INDEXABLE: PASS`
- `Deployment complete`

Then independently verify homepage, robots.txt, sitemap.xml are all HTTP 200 and rendered homepage contains no `robots=none`.

Any failure => STOP before publishing.

## 7. Run exactly one real smoke command

```bash
cd /opt/xyptdq-repo
SMOKE_OUTPUT=$(php scripts/content/publisher_smoke.php \
  --article=content/smoke/ffc-betting-basics-risk-v1.json \
  --commit 2>&1)
SMOKE_RC=$?
printf '%s\n' "$SMOKE_OUTPUT"
[ "$SMOKE_RC" -eq 0 ] || { echo SMOKE_COMMAND_FAILED; exit 1; }
```

Required output includes all of:

- `TARGET_PREFLIGHT PASS category_source=...`
- `PASS cms_id=<positive id>`
- `second_idempotent=true`

The output must contain **no** `SQLSTATE`, `ERROR`, `HY093`, or exception text.

Extract the ID:

```bash
CMS_ID=$(printf '%s\n' "$SMOKE_OUTPUT" | sed -n 's/.*PASS cms_id=\([0-9][0-9]*\).*/\1/p' | tail -1)
[ -n "$CMS_ID" ] && [ "$CMS_ID" -gt 0 ] || { echo SMOKE_CMS_ID_INVALID; exit 1; }
```

If the command errors, do not call it PASS.

## 8. Verify article, durable idempotency evidence, and sitemap

```bash
ARTICLE_URL="https://www.laocaimi.org/index.php?c=show&id=$CMS_ID"
ARTICLE_HTTP=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$ARTICLE_URL")
[ "$ARTICLE_HTTP" = 200 ] || { echo "ARTICLE_HTTP_FAIL=$ARTICLE_HTTP"; exit 1; }
```

Regenerate sitemap:

```bash
XYPTDQ_WEBROOT=/www/wwwroot/59.110.217.6 \
XYPTDQ_DB_CONFIG=/www/wwwroot/59.110.217.6/config/database.php \
XYPTDQ_SITEMAP=/www/wwwroot/59.110.217.6/sitemap.xml \
php scripts/seo/generate_sitemap.php

grep -F "id=$CMS_ID" /www/wwwroot/59.110.217.6/sitemap.xml >/dev/null || { echo SITEMAP_ARTICLE_MISSING; exit 1; }
```

Also confirm the publisher registry maps the existing smoke `article_key` to the same CMS ID, without printing credentials or article body. Do not dump the database.

## 9. Push sanitized evidence to the same branch

Create/update only non-secret evidence under `docs/probes/`, for example:

- `docs/probes/category_probe_after_v5.json`
- `docs/probes/PUBLISHER_SMOKE_V5_RESULT.md`

The report must state only non-secret facts:

- recovery branch + remote commit;
- framework source/production integrity;
- backup verification;
- DB rotation `PREVIOUSLY_ROTATED`;
- exact-ref deploy;
- robots states;
- category source;
- live preflight;
- smoke command exit status;
- CMS ID;
- `second_idempotent=true`;
- article HTTP 200;
- sitemap inclusion;
- no SQL error;
- no secrets disclosed.

Commit and push normally. Verify the evidence commit is visible remotely. Do not force-push.

## 10. Final response

Return only:

```text
【Publisher smoke v5】
Recovery branch: hotfix/production-framework-recovery-v5-20260810
Recovery branch remote: YES/NO
Recovery commit: <sha/N/A>
Server deployed ref: <sha/N/A>
Framework source integrity: PASS/FAIL
Framework production integrity: PASS/FAIL
Backup verification: PASS/FAIL
DB credential rotation: PREVIOUSLY_ROTATED
Exact-ref deploy: PASS/FAIL
Production robots=none: ABSENT/PRESENT
Rendered robots=none: ABSENT/PRESENT
Category probe: PASS/FAIL
Category source: <table/N/A>
Live target preflight: PASS/FAIL
Smoke command exit: 0/<nonzero/N/A>
Smoke publish: PASS/FAIL
Smoke cms_id: <id/N/A>
Second publish idempotent: YES/NO/N/A
SQL error present: NO/YES
Article HTTP: <code/N/A>
Sitemap contains article: YES/NO/N/A
Evidence commit remote: <sha/N/A>
Secrets disclosed: NO
Blocking item: NONE / <one concise non-secret blocker>
```

After this response, STOP. Do not merge the recovery branch, enable cron, or generate bulk content. ChatGPT will review the evidence and decide whether to unlock automation.
