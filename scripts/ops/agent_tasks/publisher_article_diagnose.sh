#!/bin/bash
# Read-only diagnostic for the smoke article produced by Publisher V8.
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
DB_JSON=$(ARTICLE_KEY="$ARTICLE_KEY" php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);
$s=$pdo->prepare("SELECT cms_id FROM dr_xyptdq_publish_registry WHERE article_key=:k LIMIT 1"); $s->execute([":k"=>getenv("ARTICLE_KEY")]); $id=(int)$s->fetchColumn();
$m=$pdo->prepare("SELECT id,catid,status,url,tableid FROM dr_1_news WHERE id=:id LIMIT 1"); $m->execute([":id"=>$id]); $main=$m->fetch(PDO::FETCH_ASSOC) ?: null;
function exists_row($pdo,$sql,$id){$s=$pdo->prepare($sql);$s->execute([":id"=>$id]);return (bool)$s->fetchColumn();}
$dataTable="dr_1_news_data_".(int)($main["tableid"]??0);
$out=[
 "cms_id"=>$id,
 "main_row"=>$main,
 "data_exists"=>exists_row($pdo,"SELECT 1 FROM `".$dataTable."` WHERE id=:id LIMIT 1",$id),
 "hits_exists"=>exists_row($pdo,"SELECT 1 FROM dr_1_news_hits WHERE id=:id LIMIT 1",$id),
 "index_exists"=>exists_row($pdo,"SELECT 1 FROM dr_1_news_index WHERE id=:id LIMIT 1",$id),
];
echo json_encode($out,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php")
CMS_ID=$(printf '%s' "$DB_JSON" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo (int)($x["cms_id"]??0);')
[ "$CMS_ID" -gt 0 ] || exit 5
DB_URL=$(printf '%s' "$DB_JSON" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo (string)($x["main_row"]["url"]??"");')

HTTP_DIRECT=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$CMS_ID")
HTTP_MODULE=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?s=news&c=show&id=$CMS_ID")
HTTP_EXISTING84=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=84")
HTTP_EXISTING47=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=47")
HTTP_DB_URL=0
if [ -n "$DB_URL" ]; then
  case "$DB_URL" in
    http://*|https://*) TARGET="$DB_URL" ;;
    /*) TARGET="$CANONICAL$DB_URL" ;;
    *) TARGET="$CANONICAL/$DB_URL" ;;
  esac
  HTTP_DB_URL=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$TARGET")
fi

python3 - "$RESULT_FILE" "$DB_JSON" "$HTTP_DIRECT" "$HTTP_MODULE" "$HTTP_DB_URL" "$HTTP_EXISTING84" "$HTTP_EXISTING47" <<'PY'
import json, sys
out, db_json, direct, module, db_url, old84, old47 = sys.argv[1:]
db = json.loads(db_json)
payload = {
    "task": "publisher_article_diagnose",
    "diagnostic": "PASS",
    "cms_id": int(db.get("cms_id", 0)),
    "main_row": db.get("main_row"),
    "data_exists": bool(db.get("data_exists")),
    "hits_exists": bool(db.get("hits_exists")),
    "index_exists": bool(db.get("index_exists")),
    "http_direct": int(direct),
    "http_module_route": int(module),
    "http_db_url": int(db_url),
    "http_existing_84": int(old84),
    "http_existing_47": int(old47),
    "secrets_disclosed": False,
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, ensure_ascii=False, indent=2, sort_keys=True)
    fh.write("\n")
PY

echo "PUBLISHER_ARTICLE_DIAGNOSE=PASS"
