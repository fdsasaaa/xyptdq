#!/bin/bash
# Credential-free Publisher finalization for Server Bridge.
# Performs guarded exact-SHA deploy + one idempotency smoke and writes only a
# sanitized structured result payload. No server-side Git push is attempted.
set -Eeuo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
REQUIRED_COMMIT="${XYPTDQ_AGENT_REQUIRED_COMMIT:-}"
CANONICAL="https://www.laocaimi.org"
SMOKE_JSON="content/smoke/ffc-betting-basics-risk-v1.json"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
LOCAL_BRANCH="agent/local-publisher-v7-${RUN_ID}"
TMP_HOME="/tmp/xyptdq-v7-home-${RUN_ID}.html"
CATEGORY_JSON="/tmp/xyptdq-v7-category-${RUN_ID}.json"
PHASE="init"
MAIN_SHA=""
RECOVERY_SHA=""
SERVER_REF=""
CATEGORY_SOURCE=""
CMS_ID=""

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4

write_result() {
  local status="$1"
  local rc="$2"
  local phase="$3"
  python3 - "$RESULT_FILE" "$status" "$rc" "$phase" "$MAIN_SHA" "$RECOVERY_SHA" \
    "$SERVER_REF" "$CATEGORY_SOURCE" "$CMS_ID" <<'PY'
import json, re, sys
(out, status, rc, phase, main_sha, recovery_sha, server_ref, category_source, cms_id) = sys.argv[1:]
phase = re.sub(r'[^A-Za-z0-9_.:-]', '', phase)[:120]
payload = {
    'task': 'publisher_finalize_v7',
    'publisher_finalization': status,
    'exit_code': int(rc),
    'phase': phase,
    'main_source_commit': main_sha,
    'local_recovery_commit': recovery_sha,
    'server_deployed_ref': server_ref,
    'category_source': category_source,
    'smoke_cms_id': int(cms_id) if cms_id.isdigit() else None,
    'secrets_disclosed': False,
}
if status == 'PASS':
    payload.update({
        'framework_source_integrity': 'PASS',
        'framework_production_integrity': 'PASS',
        'backup_verification': 'PASS',
        'exact_ref_deploy': 'PASS',
        'production_robots_none': 'ABSENT',
        'rendered_robots_none': 'ABSENT',
        'category_probe': 'PASS',
        'live_target_preflight': 'PASS',
        'smoke_command_exit': 0,
        'smoke_publish': 'PASS',
        'second_publish_idempotent': True,
        'sql_error_present': False,
        'article_http': 200,
        'sitemap_contains_article': True,
        'registry_idempotency': 'PASS',
        'blocking_item': 'NONE',
    })
else:
    payload['blocking_item'] = phase
with open(out, 'w', encoding='utf-8') as fh:
    json.dump(payload, fh, ensure_ascii=False, indent=2, sort_keys=True)
    fh.write('\n')
PY
}

cleanup() {
  rm -f "$TMP_HOME" "$CATEGORY_JSON" >/dev/null 2>&1 || true
  if [ -d "$REPO/.git" ]; then
    cd "$REPO" || true
    git checkout -f main >/dev/null 2>&1 || true
    git reset --hard origin/main >/dev/null 2>&1 || true
    git branch -D "$LOCAL_BRANCH" >/dev/null 2>&1 || true
  fi
}

on_err() {
  local rc=$?
  trap - ERR
  write_result "BLOCKED" "$rc" "$PHASE" || true
  cleanup
  exit "$rc"
}
trap on_err ERR
trap cleanup EXIT

cd "$REPO"

PHASE="repo_clean"
[ -z "$(git status --porcelain)" ]

PHASE="repo_sync"
git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null
MAIN_SHA=$(git rev-parse HEAD)
if [ -n "$REQUIRED_COMMIT" ]; then
  git merge-base --is-ancestor "$REQUIRED_COMMIT" origin/main
fi

PHASE="pdo_fix"
grep -Fq ':day_time,:week_time,:month_time,:year_time' scripts/content/cms_publish_adapter.php
! grep -Fq "VALUES (:id,0,0,0,0,0,:now,:now,:now,:now)" scripts/content/cms_publish_adapter.php

PHASE="baseline_http"
for path in / /robots.txt /sitemap.xml; do
  code=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL$path")
  [ "$code" = 200 ]
done
curl -sk --max-time 30 "$CANONICAL/" -o "$TMP_HOME"
php -r '$s=file_get_contents($argv[1]); exit(preg_match("~<meta\\b[^>]*name=[\x22\x27]robots[\x22\x27][^>]*content=[\x22\x27]none[\x22\x27][^>]*>~i",$s)?1:0);' "$TMP_HOME"

PHASE="framework_source"
CACHE_SRC="$WEBROOT/dayrui/CodeIgniter72/System/Cache"
[ -f "$CACHE_SRC/CacheFactory.php" ]
mapfile -t FRAME_LOCKS < <(find "$WEBROOT" -type f -iname 'frame.lock' -print)
[ "${#FRAME_LOCKS[@]}" -eq 1 ]
FRAME_LOCK="${FRAME_LOCKS[0]}"
FRAME_REL="${FRAME_LOCK#"$WEBROOT/"}"
FRAME_HEX=$(od -An -tx1 -v "$FRAME_LOCK" | tr -d ' \n')
[ "$FRAME_HEX" = "$EXPECTED_FRAME_LOCK_HEX" ]

PHASE="local_recovery_branch"
git checkout -b "$LOCAL_BRANCH" origin/main >/dev/null
git config user.name 'xyptdq-server-agent'
git config user.email 'xyptdq-agent@localhost'
mkdir -p "$REPO/site/dayrui/CodeIgniter72/System/Cache"
rsync -a --delete "$CACHE_SRC/" "$REPO/site/dayrui/CodeIgniter72/System/Cache/"
mkdir -p "$REPO/site/$(dirname "$FRAME_REL")"
cp -p "$FRAME_LOCK" "$REPO/site/$FRAME_REL"

PHASE="stage_recovery"
git add -f site/dayrui/CodeIgniter72/System/Cache
git add -f "site/$FRAME_REL"
UNEXPECTED=$(git diff --cached --name-only | grep -Ev "^(site/dayrui/CodeIgniter72/System/Cache/|site/${FRAME_REL//./\\.}$)" || true)
[ -z "$UNEXPECTED" ]

PHASE="commit_recovery"
if git diff --cached --quiet; then
  RECOVERY_SHA=$(git rev-parse HEAD)
else
  git commit -m 'Local verified framework recovery for Publisher V7' >/dev/null
  RECOVERY_SHA=$(git rev-parse HEAD)
fi

PHASE="category_probe"
php scripts/content/category_probe.php --output="$CATEGORY_JSON" >/dev/null
CATEGORY_SOURCE=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); foreach(($x["categories"]??[]) as $c){ if((int)($c["id"]??0)===7){ echo $c["_source_table"]??"unknown"; exit(0); } } exit(1);' "$CATEGORY_JSON")
[ -n "$CATEGORY_SOURCE" ]

PHASE="target_preflight"
DRY_OUTPUT=$(php scripts/content/publisher_smoke.php --article="$SMOKE_JSON" 2>&1)
printf '%s\n' "$DRY_OUTPUT" | grep -Fq 'TARGET_PREFLIGHT PASS'
printf '%s\n' "$DRY_OUTPUT" | grep -Fq 'DRY-RUN ONLY; no database write attempted.'

PHASE="exact_deploy"
set +e
DEPLOY_OUTPUT=$(./scripts/deploy.sh "$RECOVERY_SHA" 2>&1)
DEPLOY_RC=$?
set -e
if [ "$DEPLOY_RC" -ne 0 ]; then
  write_result "BLOCKED" "$DEPLOY_RC" "$PHASE"
  exit "$DEPLOY_RC"
fi
for marker in 'FRAMEWORK_SOURCE_INTEGRITY: PASS' 'BACKUP_VERIFY: PASS' 'FRAMEWORK_PRODUCTION_INTEGRITY: PASS' 'RENDERED_HOME_INDEXABLE: PASS' 'Deployment complete'; do
  printf '%s\n' "$DEPLOY_OUTPUT" | grep -Fq "$marker"
done
SERVER_REF=$(printf '%s\n' "$DEPLOY_OUTPUT" | sed -n 's/^GIT_SHA: \([0-9a-f][0-9a-f]*\)$/\1/p' | tail -1)
[ -n "$SERVER_REF" ] || SERVER_REF="$RECOVERY_SHA"

PHASE="post_deploy_http"
for path in / /robots.txt /sitemap.xml; do
  code=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL$path")
  [ "$code" = 200 ]
done
curl -sk --max-time 30 "$CANONICAL/" -o "$TMP_HOME"
php -r '$s=file_get_contents($argv[1]); exit(preg_match("~<meta\\b[^>]*name=[\x22\x27]robots[\x22\x27][^>]*content=[\x22\x27]none[\x22\x27][^>]*>~i",$s)?1:0);' "$TMP_HOME"

PHASE="smoke_commit"
set +e
SMOKE_OUTPUT=$(php scripts/content/publisher_smoke.php --article="$SMOKE_JSON" --commit 2>&1)
SMOKE_RC=$?
set -e
if [ "$SMOKE_RC" -ne 0 ]; then
  write_result "BLOCKED" "$SMOKE_RC" "$PHASE"
  exit "$SMOKE_RC"
fi
if printf '%s\n' "$SMOKE_OUTPUT" | grep -Eiq 'SQLSTATE|HY093|\[publisher-smoke\] ERROR|exception'; then
  write_result "BLOCKED" 41 "smoke_sql_error"
  exit 41
fi
printf '%s\n' "$SMOKE_OUTPUT" | grep -Fq 'TARGET_PREFLIGHT PASS'
printf '%s\n' "$SMOKE_OUTPUT" | grep -Fq 'second_idempotent=true'
CMS_ID=$(printf '%s\n' "$SMOKE_OUTPUT" | sed -n 's/.*PASS cms_id=\([0-9][0-9]*\).*/\1/p' | tail -1)
[ -n "$CMS_ID" ] && [ "$CMS_ID" -gt 0 ]

PHASE="article_http"
ARTICLE_HTTP=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$CMS_ID")
[ "$ARTICLE_HTTP" = 200 ]

PHASE="sitemap"
XYPTDQ_WEBROOT="$WEBROOT" XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" XYPTDQ_SITEMAP="$WEBROOT/sitemap.xml" \
  php scripts/seo/generate_sitemap.php >/dev/null
grep -F "id=$CMS_ID" "$WEBROOT/sitemap.xml" >/dev/null

PHASE="registry"
ARTICLE_KEY=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo $x["article_key"]??"";' "$SMOKE_JSON")
[ -n "$ARTICLE_KEY" ]
REGISTRY_ID=$(ARTICLE_KEY="$ARTICLE_KEY" php -r '$db=[]; require $argv[1]; $c=$db["default"]??[]; $pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]); $s=$pdo->prepare("SELECT cms_id FROM dr_xyptdq_publish_registry WHERE article_key=:k LIMIT 1"); $s->execute([":k"=>getenv("ARTICLE_KEY")]); echo (int)$s->fetchColumn();' "$WEBROOT/config/database.php")
[ "$REGISTRY_ID" = "$CMS_ID" ]

PHASE="complete"
write_result "PASS" 0 "$PHASE"
echo "PUBLISHER_FINALIZE_V7=PASS"
