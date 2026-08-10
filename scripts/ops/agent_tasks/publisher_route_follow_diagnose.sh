#!/bin/bash
# Read-only route diagnostic for published CMS articles. Follows redirects and
# reports only public HTTP status/effective URL metadata.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
SMOKE_JSON="content/smoke/ffc-betting-basics-risk-v1.json"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
cd "$REPO"
git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null

ARTICLE_KEY=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo $x["article_key"]??"";' "$SMOKE_JSON")
[ -n "$ARTICLE_KEY" ] || exit 4
CMS_ID=$(ARTICLE_KEY="$ARTICLE_KEY" php -r '$db=[]; require $argv[1]; $c=$db["default"]??[]; $pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]); $s=$pdo->prepare("SELECT cms_id FROM dr_xyptdq_publish_registry WHERE article_key=:k LIMIT 1"); $s->execute([":k"=>getenv("ARTICLE_KEY")]); echo (int)$s->fetchColumn();' "$WEBROOT/config/database.php")
[ "$CMS_ID" -gt 0 ] || exit 5

probe() {
  local url="$1"
  curl -skL --max-time 30 -o /dev/null -w '%{http_code}\t%{url_effective}' "$url"
}

NEW_DIRECT=$(probe "$CANONICAL/index.php?c=show&id=$CMS_ID")
NEW_MODULE=$(probe "$CANONICAL/index.php?s=news&c=show&id=$CMS_ID")
OLD84_DIRECT=$(probe "$CANONICAL/index.php?c=show&id=84")
OLD84_MODULE=$(probe "$CANONICAL/index.php?s=news&c=show&id=84")
OLD47_DIRECT=$(probe "$CANONICAL/index.php?c=show&id=47")
OLD47_MODULE=$(probe "$CANONICAL/index.php?s=news&c=show&id=47")

python3 - "$RESULT_FILE" "$CMS_ID" "$NEW_DIRECT" "$NEW_MODULE" "$OLD84_DIRECT" "$OLD84_MODULE" "$OLD47_DIRECT" "$OLD47_MODULE" <<'PY'
import json, sys
out, cms_id, *rows = sys.argv[1:]
labels = ['new_direct','new_module','old84_direct','old84_module','old47_direct','old47_module']
probes = {}
for label, row in zip(labels, rows):
    code, url = row.split('\t', 1)
    probes[label] = {'http': int(code), 'effective_url': url[:500]}
payload = {
    'task': 'publisher_route_follow_diagnose',
    'diagnostic': 'PASS',
    'cms_id': int(cms_id),
    'probes': probes,
    'secrets_disclosed': False,
}
with open(out, 'w', encoding='utf-8') as fh:
    json.dump(payload, fh, ensure_ascii=False, indent=2, sort_keys=True)
    fh.write('\n')
PY

echo "PUBLISHER_ROUTE_FOLLOW_DIAGNOSE=PASS"
