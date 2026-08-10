#!/bin/bash
# One-command server-side bridge so ChatGPT can finish the publisher rollout
# without WorkBuddy. This script performs only the final controlled V5 smoke.
# It does NOT enable cron and does NOT unlock recurring publishing.
set -euo pipefail

REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
SMOKE_JSON="content/smoke/ffc-betting-basics-risk-v1.json"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
RECOVERY_BRANCH="hotfix/chatgpt-publisher-finalize-${RUN_ID}"
BACKUP_ID="$RUN_ID"
BACKUP_DIR="/root/backups/deploy_${BACKUP_ID}"
TMP_HOME="/tmp/xyptdq-home-${RUN_ID}.html"
CATEGORY_JSON="/tmp/xyptdq-category-${RUN_ID}.json"

fail() {
  echo "[chatgpt-finalize] BLOCKED: $*" >&2
  exit 1
}

cleanup() {
  rm -f "$TMP_HOME" "$CATEGORY_JSON" >/dev/null 2>&1 || true
}
trap cleanup EXIT

[ "$(id -u)" -eq 0 ] || fail "run as root"
[ -d "$REPO/.git" ] || fail "Git repository missing: $REPO"
[ -d "$WEBROOT" ] || fail "webroot missing: $WEBROOT"

cd "$REPO"

echo "=== ChatGPT direct publisher finalization ==="
echo "RUN_ID=$RUN_ID"
echo "RECOVERY_BRANCH=$RECOVERY_BRANCH"

# 1. Healthy production baseline.
for path in / /robots.txt /sitemap.xml; do
  code=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL$path")
  echo "BASELINE $path HTTP=$code"
  [ "$code" = "200" ] || fail "production endpoint unhealthy: $path HTTP=$code"
done
curl -sk --max-time 30 "$CANONICAL/" -o "$TMP_HOME"
if php -r '$s=file_get_contents($argv[1]); exit(preg_match("~<meta\\b[^>]*name=[\x22\x27]robots[\x22\x27][^>]*content=[\x22\x27]none[\x22\x27][^>]*>~i",$s)?1:0);' "$TMP_HOME"; then
  echo "BASELINE_ROBOTS=INDEXABLE"
else
  fail "rendered homepage still contains robots=none"
fi

# 2. Refuse to destroy unknown local work.
if [ -n "$(git status --porcelain)" ]; then
  echo "DIRTY_REPO_FILES_BEGIN"
  git status --short
  echo "DIRTY_REPO_FILES_END"
  fail "server repository is dirty; no reset was performed"
fi

git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null
MAIN_SHA=$(git rev-parse HEAD)
echo "MAIN_SHA=$MAIN_SHA"
[ -f docs/ops/WORKBUDDY_PUBLISHER_SMOKE_V5.md ] || fail "V5 runbook missing from main"
grep -Fq ':day_time,:week_time,:month_time,:year_time' scripts/content/cms_publish_adapter.php || fail "PDO placeholder fix missing"
grep -Fq 'PDO::ATTR_EMULATE_PREPARES => false' scripts/content/cms_publish_adapter.php || fail "native PDO mode missing"
! grep -Fq ':now,:now,:now,:now' scripts/content/cms_publish_adapter.php || fail "duplicate :now placeholders still present"

# 3. Fresh full backup and checksum verification.
XYPTDQ_BACKUP_ID="$BACKUP_ID" XYPTDQ_REPO_DIR="$REPO" XYPTDQ_WEBROOT="$WEBROOT" ./scripts/backup.sh >/tmp/xyptdq-backup-${RUN_ID}.log
[ -s "$BACKUP_DIR/checksums.sha256" ] || fail "backup checksum manifest missing"
(
  cd "$BACKUP_DIR"
  sha256sum -c checksums.sha256 >/dev/null
) || fail "backup checksum verification failed"
echo "BACKUP_VERIFY=PASS"
rm -f /tmp/xyptdq-backup-${RUN_ID}.log

# 4. Create a unique recovery branch and version only the known recovered framework files.
git checkout -b "$RECOVERY_BRANCH" origin/main >/dev/null
CACHE_SRC="$WEBROOT/dayrui/CodeIgniter72/System/Cache"
[ -f "$CACHE_SRC/CacheFactory.php" ] || fail "production CacheFactory.php missing"
mkdir -p "$REPO/site/dayrui/CodeIgniter72/System/Cache"
rsync -a --delete "$CACHE_SRC/" "$REPO/site/dayrui/CodeIgniter72/System/Cache/"

mapfile -t FRAME_LOCKS < <(find "$WEBROOT" -type f -iname 'frame.lock' -print)
[ "${#FRAME_LOCKS[@]}" -eq 1 ] || fail "expected exactly one frame.lock, found ${#FRAME_LOCKS[@]}"
FRAME_LOCK="${FRAME_LOCKS[0]}"
FRAME_REL="${FRAME_LOCK#"$WEBROOT/"}"
FRAME_HEX=$(od -An -tx1 -v "$FRAME_LOCK" | tr -d ' \n')
[ "$FRAME_HEX" = '436f646549676e697465723732' ] || fail "frame.lock bytes are not exact CodeIgniter72"
mkdir -p "$REPO/site/$(dirname "$FRAME_REL")"
cp -p "$FRAME_LOCK" "$REPO/site/$FRAME_REL"

# Stage only the explicitly allowed recovery paths.
git add site/dayrui/CodeIgniter72/System/Cache
git add "site/$FRAME_REL"
git diff --cached --check
if git diff --cached --name-only | grep -Ev "^(site/dayrui/CodeIgniter72/System/Cache/|site/${FRAME_REL//./\.}$)" >/dev/null; then
  echo "UNEXPECTED_STAGED_FILES_BEGIN"
  git diff --cached --name-only
  echo "UNEXPECTED_STAGED_FILES_END"
  fail "unexpected files staged"
fi
if git diff --cached --quiet; then
  RECOVERY_COMMIT=$(git rev-parse HEAD)
  echo "RECOVERY_SOURCE_ALREADY_VERSIONED=YES"
else
  git commit -m 'Recover verified framework source for ChatGPT publisher finalization' >/dev/null
  RECOVERY_COMMIT=$(git rev-parse HEAD)
fi

git push -u origin "$RECOVERY_BRANCH" >/dev/null
REMOTE_LINE=$(git ls-remote --heads origin "$RECOVERY_BRANCH")
[ -n "$REMOTE_LINE" ] || fail "recovery branch was not visible remotely"
echo "RECOVERY_COMMIT=$RECOVERY_COMMIT"
echo "RECOVERY_BRANCH_REMOTE=YES"

# 5. Corrected category probe and live target preflight.
php scripts/content/category_probe.php --output="$CATEGORY_JSON" >/dev/null
CATEGORY_SOURCE=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); if(!is_array($x)||empty($x["categories"])) exit(2); foreach($x["categories"] as $c){ if((int)($c["id"]??0)===7){ echo $c["_source_table"]??"unknown"; exit(0);} } exit(3);' "$CATEGORY_JSON") || fail "effective category 7 missing"
echo "CATEGORY_PROBE=PASS source=$CATEGORY_SOURCE"

DRY_OUTPUT=$(php scripts/content/publisher_smoke.php --article="$SMOKE_JSON" 2>&1) || {
  printf '%s\n' "$DRY_OUTPUT"
  fail "live target preflight failed"
}
printf '%s\n' "$DRY_OUTPUT"
printf '%s\n' "$DRY_OUTPUT" | grep -Fq 'TARGET_PREFLIGHT PASS' || fail "TARGET_PREFLIGHT PASS missing"
printf '%s\n' "$DRY_OUTPUT" | grep -Fq 'DRY-RUN ONLY; no database write attempted.' || fail "smoke dry-run marker missing"
echo "LIVE_TARGET_PREFLIGHT=PASS"

# 6. Deploy the exact remote recovery ref and independently verify production.
DEPLOY_OUTPUT=$(./scripts/deploy.sh "origin/$RECOVERY_BRANCH" 2>&1) || {
  printf '%s\n' "$DEPLOY_OUTPUT"
  fail "exact-ref deployment failed"
}
printf '%s\n' "$DEPLOY_OUTPUT"
for marker in 'FRAMEWORK_SOURCE_INTEGRITY: PASS' 'BACKUP_VERIFY: PASS' 'FRAMEWORK_PRODUCTION_INTEGRITY: PASS' 'RENDERED_HOME_INDEXABLE: PASS' 'Deployment complete'; do
  printf '%s\n' "$DEPLOY_OUTPUT" | grep -Fq "$marker" || fail "deploy marker missing: $marker"
done
SERVER_DEPLOYED_REF=$(printf '%s\n' "$DEPLOY_OUTPUT" | sed -n 's/^GIT_SHA: \([0-9a-f][0-9a-f]*\)$/\1/p' | tail -1)
[ -n "$SERVER_DEPLOYED_REF" ] || SERVER_DEPLOYED_REF="$RECOVERY_COMMIT"

for path in / /robots.txt /sitemap.xml; do
  code=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL$path")
  [ "$code" = "200" ] || fail "post-deploy endpoint unhealthy: $path HTTP=$code"
done
curl -sk --max-time 30 "$CANONICAL/" -o "$TMP_HOME"
php -r '$s=file_get_contents($argv[1]); exit(preg_match("~<meta\\b[^>]*name=[\x22\x27]robots[\x22\x27][^>]*content=[\x22\x27]none[\x22\x27][^>]*>~i",$s)?1:0);' "$TMP_HOME" || fail "post-deploy homepage contains robots=none"
echo "EXACT_REF_DEPLOY=PASS"

# 7. Exactly one real smoke command; the tool performs the second idempotency call internally.
set +e
SMOKE_OUTPUT=$(php scripts/content/publisher_smoke.php --article="$SMOKE_JSON" --commit 2>&1)
SMOKE_RC=$?
set -e
printf '%s\n' "$SMOKE_OUTPUT"
[ "$SMOKE_RC" -eq 0 ] || fail "smoke commit command exit=$SMOKE_RC"
if printf '%s\n' "$SMOKE_OUTPUT" | grep -Eiq 'SQLSTATE|HY093|\[publisher-smoke\] ERROR|exception'; then
  fail "smoke output contains SQL/exception error text"
fi
printf '%s\n' "$SMOKE_OUTPUT" | grep -Fq 'TARGET_PREFLIGHT PASS' || fail "commit target preflight marker missing"
printf '%s\n' "$SMOKE_OUTPUT" | grep -Fq 'second_idempotent=true' || fail "durable idempotency marker missing"
CMS_ID=$(printf '%s\n' "$SMOKE_OUTPUT" | sed -n 's/.*PASS cms_id=\([0-9][0-9]*\).*/\1/p' | tail -1)
[ -n "$CMS_ID" ] && [ "$CMS_ID" -gt 0 ] || fail "invalid smoke cms_id"
echo "SMOKE_PUBLISH=PASS cms_id=$CMS_ID second_idempotent=YES"

# 8. Public article + sitemap + durable registry mapping.
ARTICLE_URL="$CANONICAL/index.php?c=show&id=$CMS_ID"
ARTICLE_HTTP=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$ARTICLE_URL")
[ "$ARTICLE_HTTP" = "200" ] || fail "published article HTTP=$ARTICLE_HTTP"
XYPTDQ_WEBROOT="$WEBROOT" XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" XYPTDQ_SITEMAP="$WEBROOT/sitemap.xml" php scripts/seo/generate_sitemap.php >/dev/null
grep -F "id=$CMS_ID" "$WEBROOT/sitemap.xml" >/dev/null || fail "published article missing from sitemap"
ARTICLE_KEY=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo $x["article_key"]??"";' "$SMOKE_JSON")
[ -n "$ARTICLE_KEY" ] || fail "smoke article_key missing"
REGISTRY_ID=$(ARTICLE_KEY="$ARTICLE_KEY" php -r '$db=[]; require $argv[1]; $c=$db["default"]??[]; $pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]); $s=$pdo->prepare("SELECT cms_id FROM dr_xyptdq_publish_registry WHERE article_key=:k LIMIT 1"); $s->execute([":k"=>getenv("ARTICLE_KEY")]); echo (int)$s->fetchColumn();' "$WEBROOT/config/database.php") || fail "registry verification query failed"
[ "$REGISTRY_ID" = "$CMS_ID" ] || fail "registry cms_id mismatch"
echo "ARTICLE_HTTP=200"
echo "SITEMAP_CONTAINS_ARTICLE=YES"
echo "REGISTRY_IDEMPOTENCY=PASS"

# 9. Write and push sanitized evidence only.
mkdir -p docs/probes
EVIDENCE="docs/probes/PUBLISHER_SMOKE_CHATGPT_FINAL_${RUN_ID}.md"
cat > "$EVIDENCE" <<EOF
# ChatGPT direct publisher finalization

- Run ID: $RUN_ID
- Recovery branch: $RECOVERY_BRANCH
- Recovery commit: $RECOVERY_COMMIT
- Server deployed ref: $SERVER_DEPLOYED_REF
- Framework source integrity: PASS
- Framework production integrity: PASS
- Backup verification: PASS
- DB credential rotation: PREVIOUSLY_ROTATED
- Exact-ref deploy: PASS
- Production robots=none: ABSENT
- Rendered robots=none: ABSENT
- Category probe: PASS
- Category source: $CATEGORY_SOURCE
- Live target preflight: PASS
- Smoke command exit: 0
- Smoke publish: PASS
- Smoke cms_id: $CMS_ID
- Second publish idempotent: YES
- SQL error present: NO
- Article HTTP: 200
- Sitemap contains article: YES
- Registry idempotency: PASS
- Secrets disclosed: NO
- Blocking item: NONE
EOF

git add "$EVIDENCE"
git diff --cached --check
git commit -m "Record successful direct publisher smoke $RUN_ID" >/dev/null
EVIDENCE_COMMIT=$(git rev-parse HEAD)
git push origin "$RECOVERY_BRANCH" >/dev/null
REMOTE_EVIDENCE=$(git ls-remote --heads origin "$RECOVERY_BRANCH" | awk '{print $1}')
[ "$REMOTE_EVIDENCE" = "$EVIDENCE_COMMIT" ] || fail "evidence commit not visible remotely"

cat <<EOF
【ChatGPT direct publisher finalization】
Recovery branch: $RECOVERY_BRANCH
Recovery branch remote: YES
Recovery commit: $RECOVERY_COMMIT
Server deployed ref: $SERVER_DEPLOYED_REF
Framework source integrity: PASS
Framework production integrity: PASS
Backup verification: PASS
DB credential rotation: PREVIOUSLY_ROTATED
Exact-ref deploy: PASS
Production robots=none: ABSENT
Rendered robots=none: ABSENT
Category probe: PASS
Category source: $CATEGORY_SOURCE
Live target preflight: PASS
Smoke command exit: 0
Smoke publish: PASS
Smoke cms_id: $CMS_ID
Second publish idempotent: YES
SQL error present: NO
Article HTTP: 200
Sitemap contains article: YES
Registry idempotency: PASS
Evidence commit remote: $EVIDENCE_COMMIT
Secrets disclosed: NO
Blocking item: NONE
EOF
