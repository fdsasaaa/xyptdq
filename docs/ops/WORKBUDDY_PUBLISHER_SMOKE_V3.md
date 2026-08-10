# WorkBuddy publisher smoke v3 — source recovery + one-article proof

This runbook replaces V2 for the next server pass. The production site is currently healthy after manual recovery, but the recovered framework files must first be versioned in Git so a future `rsync --delete` cannot recreate the HTTP 500 incident. This task does **not** enable recurring publishing.

## Hard rules

- Never print, paste, commit, or log passwords, tokens, cookies, private keys, database DSNs, `config/database.php`, database dumps, or other secrets.
- Do not force-push.
- Do not copy the whole production webroot back into Git.
- Do not rerun DB credential rotation if the previous run already returned `ROTATED AND VERIFIED`; record the already-completed status only.
- If backup verification fails, STOP.
- If the recovered framework source cannot be safely committed, STOP before deployment.
- Publish exactly one repository smoke article. The smoke tool itself submits the same `article_key` twice in commit mode to prove idempotency.
- Do not install or enable the scheduled publisher cron.

## 1. Sync the canonical repository cleanly

```bash
cd /opt/xyptdq-repo
[ -z "$(git status --porcelain)" ] || { echo 'BLOCKED_DIRTY_REPO'; git status --short; exit 1; }
git fetch --prune origin
git checkout main
git reset --hard origin/main
git rev-parse HEAD
```

The latest main must contain `docs/ops/WORKBUDDY_PUBLISHER_SMOKE_V3.md` before continuing.

## 2. Create a fresh verified backup

```bash
cd /opt/xyptdq-repo
XYPTDQ_REPO_DIR=/opt/xyptdq-repo ./scripts/backup.sh
```

Enter the emitted backup directory and run:

```bash
sha256sum -c checksums.sha256
```

Any failure => STOP.

## 3. Version the production recovery files — do not deploy main yet

Create a new branch from current `origin/main`:

```bash
cd /opt/xyptdq-repo
git checkout -b hotfix/production-framework-recovery-20260810 origin/main
```

Production webroot:

```bash
WEBROOT=/www/wwwroot/59.110.217.6
REPO=/opt/xyptdq-repo
```

### 3A. Recover CodeIgniter Cache framework source into Git

The incident evidence identified the missing directory as:

`dayrui/CodeIgniter72/System/Cache/`

Verify the production copy contains the class file:

```bash
test -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" || { echo CACHE_FACTORY_MISSING; exit 1; }
```

Copy only this framework source directory into the mirrored repository site tree:

```bash
mkdir -p "$REPO/site/dayrui/CodeIgniter72/System/Cache"
rsync -a --delete \
  "$WEBROOT/dayrui/CodeIgniter72/System/Cache/" \
  "$REPO/site/dayrui/CodeIgniter72/System/Cache/"
```

Do **not** copy runtime cache directories named simply `cache`, uploads, logs, sessions, or configuration secrets.

### 3B. Recover frame.lock exactly

Locate it without guessing the path:

```bash
mapfile -t FRAME_LOCKS < <(find "$WEBROOT" -type f -iname 'frame.lock' -print)
printf 'frame_lock_count=%s\n' "${#FRAME_LOCKS[@]}"
[ "${#FRAME_LOCKS[@]}" -eq 1 ] || { echo FRAME_LOCK_COUNT_INVALID; exit 1; }
FRAME_LOCK="${FRAME_LOCKS[0]}"
FRAME_REL="${FRAME_LOCK#"$WEBROOT/"}"
printf 'frame_lock_rel=%s\n' "$FRAME_REL"
```

Verify the exact expected bytes for `CodeIgniter72` with **no trailing newline**:

```bash
FRAME_HEX=$(od -An -tx1 -v "$FRAME_LOCK" | tr -d ' \n')
[ "$FRAME_HEX" = '436f646549676e697465723732' ] || { echo FRAME_LOCK_BYTES_INVALID; exit 1; }
```

Copy only that one file to its matching repository-relative path:

```bash
mkdir -p "$REPO/site/$(dirname "$FRAME_REL")"
cp -p "$FRAME_LOCK" "$REPO/site/$FRAME_REL"
```

Recheck the repository copy has the exact same hex bytes.

### 3C. Confirm the canonical Nginx template is corrected

The Git repository template must contain:

```nginx
try_files $uri $uri/ /index.php?$query_string;
```

and must not use `/site/index.php` as the front-controller fallback.

Verify:

```bash
grep -F 'try_files $uri $uri/ /index.php?$query_string;' "$REPO/infra/nginx_site.conf"
! grep -Fq 'try_files $uri $uri/ /site/index.php?$query_string;' "$REPO/infra/nginx_site.conf"
```

Also verify the currently loaded production Nginx configuration is healthy:

```bash
nginx -t
nginx -T 2>/dev/null | grep -F 'try_files $uri $uri/ /index.php?$query_string;' >/dev/null || { echo ACTIVE_NGINX_FALLBACK_INVALID; exit 1; }
```

Do not change unrelated Nginx settings.

## 4. Review and push only the recovery source

Before commit:

```bash
cd /opt/xyptdq-repo
git status --short
git diff --check
```

The intended source changes are limited to:

- `site/dayrui/CodeIgniter72/System/Cache/**`
- the single discovered `site/<matching frame.lock path>`
- any already-versioned non-secret recovery file that is demonstrably required by the same incident.

Explicitly confirm the following remain untracked/unchanged:

- `site/config/database.php`
- `.env`
- uploads/uploadfile
- runtime cache/log/session directories
- private keys or certificates containing private key material.

Then:

```bash
git add site/dayrui/CodeIgniter72/System/Cache
# Add the exact mirrored frame.lock path discovered above:
git add "site/$FRAME_REL"
git diff --cached --check
git diff --cached --name-only
git commit -m 'Recover required CodeIgniter framework files from verified production backup'
git push -u origin hotfix/production-framework-recovery-20260810
```

If remote says the branch already exists, STOP and report it rather than force-pushing.

## 5. Deploy the exact recovery branch, not stale main

The updated deployer now refuses to deploy when `CacheFactory.php` or the exact `frame.lock` bytes are missing.

```bash
cd /opt/xyptdq-repo
./scripts/deploy.sh origin/hotfix/production-framework-recovery-20260810
```

Required output includes all of:

- `FRAMEWORK_SOURCE_INTEGRITY: PASS`
- `BACKUP_VERIFY: PASS`
- `FRAMEWORK_PRODUCTION_INTEGRITY: PASS`
- `RENDERED_HOME_INDEXABLE: PASS`
- `Deployment complete`

Then verify:

```bash
curl -sk -o /dev/null -w '%{http_code}\n' https://www.laocaimi.org/
curl -sk -o /dev/null -w '%{http_code}\n' https://www.laocaimi.org/robots.txt
curl -sk -o /dev/null -w '%{http_code}\n' https://www.laocaimi.org/sitemap.xml
```

All must be `200`.

Verify rendered homepage indexing state:

```bash
curl -sk https://www.laocaimi.org/ -o /tmp/xyptdq-home-v3.html
php -r '$s=file_get_contents($argv[1]); exit(preg_match("~<meta\\b[^>]*name=[\x22\x27]robots[\x22\x27][^>]*content=[\x22\x27]none[\x22\x27][^>]*>~i",$s)?1:0);' /tmp/xyptdq-home-v3.html
rm -f /tmp/xyptdq-home-v3.html
```

A zero exit status means no `robots=none` is present. Any failure => STOP.

## 6. Run the category probe

```bash
cd /opt/xyptdq-repo
php scripts/content/category_probe.php --output=/tmp/category_probe_v3.json
php -r '$x=json_decode(file_get_contents($argv[1]),true); if(!is_array($x)||empty($x["categories"])) exit(1); echo "CATEGORY_PROBE_PASS count=".count($x["categories"]).PHP_EOL;' /tmp/category_probe_v3.json
```

Confirm the SEO article category used by the repository smoke article is valid. The repository smoke JSON currently uses `catid=7`.

Do not hand-edit the probe output.

## 7. Validate the repository smoke JSON — exact file and command

The valid smoke article already exists in Git:

`content/smoke/ffc-betting-basics-risk-v1.json`

First run a no-write validation:

```bash
cd /opt/xyptdq-repo
php scripts/content/publisher_smoke.php \
  --article=content/smoke/ffc-betting-basics-risk-v1.json
```

Required:

`DRY-RUN ONLY; no database write attempted.`

If this command says the JSON is missing or invalid, STOP and report the exact non-secret error. Do not create a replacement article.

## 8. Publish exactly one real smoke article and prove idempotency

Run **one** commit command:

```bash
cd /opt/xyptdq-repo
SMOKE_OUTPUT=$(php scripts/content/publisher_smoke.php \
  --article=content/smoke/ffc-betting-basics-risk-v1.json \
  --commit)
printf '%s\n' "$SMOKE_OUTPUT"
```

Important: `publisher_smoke.php --commit` already invokes the adapter twice internally. Do not run another manual second publish command.

Extract the CMS ID:

```bash
CMS_ID=$(printf '%s\n' "$SMOKE_OUTPUT" | sed -n 's/.*PASS cms_id=\([0-9][0-9]*\).*/\1/p' | tail -1)
[ -n "$CMS_ID" ] && [ "$CMS_ID" -gt 0 ] || { echo SMOKE_CMS_ID_INVALID; exit 1; }
echo "SMOKE_CMS_ID=$CMS_ID"
```

The smoke output must contain:

- `PASS cms_id=<positive id>`
- `second_idempotent=true`

That is the durable duplicate-protection proof.

## 9. Verify public article and sitemap

Verify the canonical show route:

```bash
ARTICLE_URL="https://www.laocaimi.org/index.php?c=show&id=$CMS_ID"
ARTICLE_HTTP=$(curl -sk -o /dev/null -w '%{http_code}' "$ARTICLE_URL")
[ "$ARTICLE_HTTP" = '200' ] || { echo "ARTICLE_HTTP_FAIL=$ARTICLE_HTTP"; exit 1; }
```

Regenerate sitemap from live CMS data:

```bash
cd /opt/xyptdq-repo
XYPTDQ_WEBROOT=/www/wwwroot/59.110.217.6 \
XYPTDQ_DB_CONFIG=/www/wwwroot/59.110.217.6/config/database.php \
XYPTDQ_SITEMAP=/www/wwwroot/59.110.217.6/sitemap.xml \
php scripts/seo/generate_sitemap.php
```

Because XML escapes `&` as `&amp;`, verify by CMS ID rather than matching an unescaped URL:

```bash
grep -F "id=$CMS_ID" /www/wwwroot/59.110.217.6/sitemap.xml >/dev/null || { echo SITEMAP_ARTICLE_MISSING; exit 1; }
```

## 10. Commit sanitized evidence to the same recovery branch

Create/update only non-secret evidence under `docs/probes/`, for example:

- `docs/probes/category_probe_after_recovery.json`
- `docs/probes/PUBLISHER_SMOKE_V3_RESULT.md`

The Markdown result must include only:

- recovery branch + commit SHA;
- framework source integrity PASS;
- backup verification PASS;
- DB rotation status already achieved in prior run (`ROTATED`) or prior safe status if applicable;
- exact-ref deploy PASS;
- production/rendered robots state;
- category probe PASS;
- smoke article key;
- CMS ID;
- idempotency PASS;
- article HTTP 200;
- sitemap inclusion YES;
- no secrets disclosed.

Do not include raw DB configuration, SQL credential statements, secrets, server cookies, or private logs.

Commit and push normally to the same branch. Do not force-push.

## 11. Final response

Return only:

```text
【Publisher smoke v3】
Recovery branch: hotfix/production-framework-recovery-20260810
Recovery commit: <sha>
Server deployed ref: <sha>
Framework source integrity: PASS/FAIL
Framework production integrity: PASS/FAIL
Backup verification: PASS/FAIL
DB credential rotation: ROTATED / PREVIOUSLY_ROTATED / BLOCKED_SAFE_ROLLBACK
Exact-ref deploy: PASS/FAIL
Production robots=none: ABSENT/PRESENT
Rendered robots=none: ABSENT/PRESENT
Category probe: PASS/FAIL
Smoke fixture dry-run: PASS/FAIL
Smoke publish: PASS/FAIL
Smoke cms_id: <id/N/A>
Second publish idempotent: YES/NO/N/A
Article HTTP: <code/N/A>
Sitemap contains article: YES/NO/N/A
Evidence commit: <sha/N/A>
Secrets disclosed: NO
Blocking item: NONE / <one concise non-secret blocker>
```

After this response, STOP. Do not merge the recovery branch, do not enable cron, and do not generate bulk content. ChatGPT will review, merge, then unlock scheduled publishing.
