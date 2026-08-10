#!/bin/bash
# Final publisher proof in an already-public category (catid 2).
# No deployment is performed. The task verifies DB idempotency plus public HTTP,
# sitemap inclusion and registry consistency, then emits a sanitized payload.
set -Eeuo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
REQUIRED_COMMIT="${XYPTDQ_AGENT_REQUIRED_COMMIT:-}"
CANONICAL="https://www.laocaimi.org"
SMOKE_JSON="content/smoke/ffc-hangup-validation-v1.json"
PHASE="init"
CMS_ID=""
CATEGORY_SOURCE=""

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4

write_result() {
  local status="$1"
  local rc="$2"
  local phase="$3"
  python3 - "$RESULT_FILE" "$status" "$rc" "$phase" "$CMS_ID" "$CATEGORY_SOURCE" <<'PY'
import json, re, sys
out, status, rc, phase, cms_id, category_source = sys.argv[1:]
phase = re.sub(r'[^A-Za-z0-9_.:-]', '', phase)[:120]
payload = {
    'task': 'publisher_catid2_final_smoke',
    'publisher_finalization': status,
    'exit_code': int(rc),
    'phase': phase,
    'smoke_cms_id': int(cms_id) if cms_id.isdigit() else None,
    'category_source': category_source,
    'secrets_disclosed': False,
}
if status == 'PASS':
    payload.update({
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

on_err() {
  local rc=$?
  trap - ERR
  write_result "BLOCKED" "$rc" "$PHASE" || true
  exit "$rc"
}
trap on_err ERR

cd "$REPO"

PHASE="repo_clean"
[ -z "$(git status --porcelain)" ]

PHASE="repo_sync"
git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null
if [ -n "$REQUIRED_COMMIT" ]; then
  git merge-base --is-ancestor "$REQUIRED_COMMIT" origin/main
fi
[ -s "$SMOKE_JSON" ]

PHASE="baseline_http"
for path in / /robots.txt /sitemap.xml; do
  code=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL$path")
  [ "$code" = 200 ]
done

PHASE="target_preflight"
DRY_OUTPUT=$(php scripts/content/publisher_smoke.php --article="$SMOKE_JSON" 2>&1)
printf '%s\n' "$DRY_OUTPUT" | grep -Fq 'TARGET_PREFLIGHT PASS'
printf '%s\n' "$DRY_OUTPUT" | grep -Fq 'DRY-RUN ONLY; no database write attempted.'
CATEGORY_SOURCE=$(printf '%s\n' "$DRY_OUTPUT" | sed -n 's/.*TARGET_PREFLIGHT PASS category_source=\([^ ]*\).*/\1/p' | tail -1)
[ -n "$CATEGORY_SOURCE" ]

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
  PHASE="smoke_sql_error"
  write_result "BLOCKED" 41 "$PHASE"
  exit 41
fi
printf '%s\n' "$SMOKE_OUTPUT" | grep -Fq 'TARGET_PREFLIGHT PASS'
printf '%s\n' "$SMOKE_OUTPUT" | grep -Fq 'second_idempotent=true'
CMS_ID=$(printf '%s\n' "$SMOKE_OUTPUT" | sed -n 's/.*PASS cms_id=\([0-9][0-9]*\).*/\1/p' | tail -1)
[ -n "$CMS_ID" ] && [ "$CMS_ID" -gt 0 ]

PHASE="article_http"
ARTICLE_HTTP=$(curl -skL --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$CMS_ID")
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
echo "PUBLISHER_CATID2_FINAL_SMOKE=PASS"
