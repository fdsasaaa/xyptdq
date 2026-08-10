# WorkBuddy publisher smoke v4 — shared-category fix + final one-article proof

This runbook replaces V3 for the next server pass. Production is currently healthy after recovery, but the V3 recovery branch/commit was not successfully published to GitHub, and the publisher adapter incorrectly assumed category metadata lived only in `dr_1_news_category`. V4 fixes both issues. This task does **not** enable recurring publishing.

## Hard rules

- Never print, paste, commit, or log passwords, tokens, cookies, private keys, database DSNs, `config/database.php`, database dumps, or other secrets.
- Do not force-push.
- Do not copy the whole production webroot back into Git.
- Do not rerun DB credential rotation; the previous run already reported it rotated. Record `PREVIOUSLY_ROTATED` only.
- If backup verification fails, STOP.
- If production is not HTTP 200 before changes, STOP and report the non-secret health failure.
- If the recovered framework source cannot be safely committed to GitHub, STOP before deployment.
- Publish exactly one repository smoke article. `publisher_smoke.php --commit` submits the same `article_key` twice internally to prove durable idempotency.
- Do not install or enable the scheduled publisher cron.

## 1. Preserve the currently healthy production baseline

Before touching Git, verify:

```bash
curl -sk -o /dev/null -w '%{http_code}\n' https://www.laocaimi.org/
curl -sk -o /dev/null -w '%{http_code}\n' https://www.laocaimi.org/robots.txt
curl -sk -o /dev/null -w '%{http_code}\n' https://www.laocaimi.org/sitemap.xml
```

All three must be `200`.

Verify homepage is indexable:

```bash
curl -sk https://www.laocaimi.org/ -o /tmp/xyptdq-home-v4-before.html
php -r '$s=file_get_contents($argv[1]); exit(preg_match("~<meta\\b[^>]*name=[\x22\x27]robots[\x22\x27][^>]*content=[\x22\x27]none[\x22\x27][^>]*>~i",$s)?1:0);' /tmp/xyptdq-home-v4-before.html
rm -f /tmp/xyptdq-home-v4-before.html
```

A zero exit status means PASS. Otherwise STOP.

## 2. Sync canonical Git and discard no unknown work

Canonical repo:

`/opt/xyptdq-repo`

Inspect first:

```bash
cd /opt/xyptdq-repo
git status --short
git branch --show-current
git log -1 --oneline
```

If tracked local changes exist, do not reset them blindly. Save a non-secret patch or commit only known V3 recovery source first if necessary. Do not include runtime config/secrets.

Then establish a clean new branch from the latest remote main:

```bash
cd /opt/xyptdq-repo
git fetch --prune origin
git checkout main
git reset --hard origin/main
git checkout -b hotfix/production-framework-recovery-v4-20260810 origin/main
```

The latest main must contain:

- `docs/ops/WORKBUDDY_PUBLISHER_SMOKE_V4.md`
- the shared-category-aware `scripts/content/cms_publish_adapter.php`
- the shared/dedicated `scripts/content/category_probe.php`
- `publisher_smoke.php` with live `TARGET_PREFLIGHT PASS` support.

## 3. Fresh verified backup

```bash
cd /opt/xyptdq-repo
XYPTDQ_REPO_DIR=/opt/xyptdq-repo ./scripts/backup.sh
```

Inside the emitted backup directory:

```bash
sha256sum -c checksums.sha256
```

Any failure => STOP.

## 4. Re-version the production recovery source into this fresh branch

Production webroot:

```bash
WEBROOT=/www/wwwroot/59.110.217.6
REPO=/opt/xyptdq-repo
```

### 4A. Required CodeIgniter Cache framework source

Verify:

```bash
test -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" || { echo CACHE_FACTORY_MISSING; exit 1; }
```

Copy only this framework source directory:

```bash
mkdir -p "$REPO/site/dayrui/CodeIgniter72/System/Cache"
rsync -a --delete \
  "$WEBROOT/dayrui/CodeIgniter72/System/Cache/" \
  "$REPO/site/dayrui/CodeIgniter72/System/Cache/"
```

Do not copy runtime `cache`, logs, sessions, uploads, or secrets.

### 4B. Exact frame.lock

Locate the single file:

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

Verify the Git copy has the same exact bytes.

### 4C. Canonical Nginx template

Verify repository config contains:

```nginx
try_files $uri $uri/ /index.php?$query_string;
```

and not `/site/index.php`.

Also verify currently loaded Nginx config:

```bash
nginx -t
nginx -T 2>/dev/null | grep -F 'try_files $uri $uri/ /index.php?$query_string;' >/dev/null || { echo ACTIVE_NGINX_FALLBACK_INVALID; exit 1; }
```

## 5. Commit and PUSH the recovery source before any deployment

Inspect exactly what will be committed:

```bash
cd /opt/xyptdq-repo
git status --short
git diff --check
```

Intended recovery additions are limited to:

- `site/dayrui/CodeIgniter72/System/Cache/**`
- the single discovered `site/<frame.lock relative path>`

Explicitly verify these are not staged/tracked accidentally:

- `site/config/database.php`
- `.env`
- uploads/uploadfile
- runtime cache/log/session directories
- private keys/cert private material.

Then:

```bash
git add site/dayrui/CodeIgniter72/System/Cache
git add "site/$FRAME_REL"
git diff --cached --check
git diff --cached --name-only
git commit -m 'Recover required CodeIgniter framework source for production'
git push -u origin hotfix/production-framework-recovery-v4-20260810
```

**Do not continue until `git ls-remote --heads origin hotfix/production-framework-recovery-v4-20260810` proves the branch exists remotely.**

Do not reuse the unpushed V3 SHA as evidence. Do not force-push.

## 6. Run the corrected category probe before publishing

The production site uses a shared Xunrui category model for SEO category 7. The corrected probe checks both:

- `dr_1_news_category`
- `dr_1_share_category` filtered by module marker such as `mid=news` when available.

Run:

```bash
cd /opt/xyptdq-repo
php scripts/content/category_probe.php --output=/tmp/category_probe_v4.json
php -r '$x=json_decode(file_get_contents($argv[1]),true); if(!is_array($x)||empty($x["categories"])) exit(1); $found=false; foreach($x["categories"] as $c){ if((int)($c["id"]??0)===7){$found=true; echo "CATEGORY_7_PASS source=".($c["_source_table"]??"unknown")." name=".($c["name"]??"").PHP_EOL; break;}} if(!$found) exit(2);' /tmp/category_probe_v4.json
```

Required: category 7 is present in the **effective** categories list. Expected production source is `dr_1_share_category`; a dedicated source is also acceptable if the live DB actually returns it.

If category 7 is absent, STOP. Do not hand-edit JSON or change catid.

## 7. Live smoke dry-run — must validate the database target now

Use the existing fixture only:

`content/smoke/ffc-betting-basics-risk-v1.json`

Run:

```bash
cd /opt/xyptdq-repo
php scripts/content/publisher_smoke.php \
  --article=content/smoke/ffc-betting-basics-risk-v1.json
```

Required output includes both:

- `TARGET_PREFLIGHT PASS category_source=...`
- `DRY-RUN ONLY; no database write attempted.`

If target preflight fails, STOP before any write.

## 8. Deploy the exact remote recovery branch

Only after the branch is confirmed on GitHub:

```bash
cd /opt/xyptdq-repo
./scripts/deploy.sh origin/hotfix/production-framework-recovery-v4-20260810
```

Required output:

- `FRAMEWORK_SOURCE_INTEGRITY: PASS`
- `BACKUP_VERIFY: PASS`
- `FRAMEWORK_PRODUCTION_INTEGRITY: PASS`
- `RENDERED_HOME_INDEXABLE: PASS`
- `Deployment complete`

Then independently verify homepage, robots and sitemap are all HTTP 200 and rendered homepage has no `robots=none`.

If deploy or verification fails, STOP before publishing.

## 9. Publish exactly one real smoke article and prove idempotency

Run one commit command only:

```bash
cd /opt/xyptdq-repo
SMOKE_OUTPUT=$(php scripts/content/publisher_smoke.php \
  --article=content/smoke/ffc-betting-basics-risk-v1.json \
  --commit)
printf '%s\n' "$SMOKE_OUTPUT"
```

Required output includes:

- `TARGET_PREFLIGHT PASS category_source=...`
- `PASS cms_id=<positive id>`
- `second_idempotent=true`

The tool invokes the adapter twice internally. Do not run a separate second commit command.

Extract ID:

```bash
CMS_ID=$(printf '%s\n' "$SMOKE_OUTPUT" | sed -n 's/.*PASS cms_id=\([0-9][0-9]*\).*/\1/p' | tail -1)
[ -n "$CMS_ID" ] && [ "$CMS_ID" -gt 0 ] || { echo SMOKE_CMS_ID_INVALID; exit 1; }
```

## 10. Verify public article and sitemap

```bash
ARTICLE_URL="https://www.laocaimi.org/index.php?c=show&id=$CMS_ID"
ARTICLE_HTTP=$(curl -sk -o /dev/null -w '%{http_code}' "$ARTICLE_URL")
[ "$ARTICLE_HTTP" = '200' ] || { echo "ARTICLE_HTTP_FAIL=$ARTICLE_HTTP"; exit 1; }

XYPTDQ_WEBROOT=/www/wwwroot/59.110.217.6 \
XYPTDQ_DB_CONFIG=/www/wwwroot/59.110.217.6/config/database.php \
XYPTDQ_SITEMAP=/www/wwwroot/59.110.217.6/sitemap.xml \
php scripts/seo/generate_sitemap.php

grep -F "id=$CMS_ID" /www/wwwroot/59.110.217.6/sitemap.xml >/dev/null || { echo SITEMAP_ARTICLE_MISSING; exit 1; }
```

## 11. Commit sanitized evidence to the same remote branch

Add only non-secret evidence such as:

- `docs/probes/category_probe_after_v4.json`
- `docs/probes/PUBLISHER_SMOKE_V4_RESULT.md`

The result must include:

- remote recovery branch and commit SHA;
- framework source/production integrity PASS;
- backup verification PASS;
- DB rotation `PREVIOUSLY_ROTATED`;
- exact-ref deploy PASS;
- robots states;
- category probe PASS and category source table;
- live target preflight PASS and category source;
- smoke article key + CMS ID;
- idempotency PASS;
- article HTTP 200;
- sitemap inclusion YES;
- no secrets disclosed.

Commit and push normally to the same branch. Confirm the evidence commit is visible remotely. Do not force-push.

## 12. Final response

Return only:

```text
【Publisher smoke v4】
Recovery branch: hotfix/production-framework-recovery-v4-20260810
Recovery branch remote: YES/NO
Recovery commit: <sha>
Server deployed ref: <sha>
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
Smoke publish: PASS/FAIL
Smoke cms_id: <id/N/A>
Second publish idempotent: YES/NO/N/A
Article HTTP: <code/N/A>
Sitemap contains article: YES/NO/N/A
Evidence commit remote: <sha/N/A>
Secrets disclosed: NO
Blocking item: NONE / <one concise non-secret blocker>
```

After this response, STOP. Do not merge the recovery branch, do not enable cron, and do not generate bulk content. ChatGPT will review, merge, then unlock scheduled publishing.
