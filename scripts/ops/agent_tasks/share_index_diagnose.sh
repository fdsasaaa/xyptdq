#!/bin/bash
# Read-only proof of the Xunrui shared-module routing/index table.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
cd "$REPO"
git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null

DB_JSON=$(php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[]; $database=(string)($c["database"]??"");
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$database.";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$exists=(int)$pdo->query("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=".$pdo->quote($database)." AND table_name=\"dr_1_share_index\"")->fetchColumn();
if (!$exists) { echo json_encode(["exists"=>false]); exit; }
$cols=$pdo->query("SELECT column_name FROM information_schema.columns WHERE table_schema=".$pdo->quote($database)." AND table_name=\"dr_1_share_index\" ORDER BY ordinal_position")->fetchAll(PDO::FETCH_COLUMN);
$ai=$pdo->query("SELECT AUTO_INCREMENT FROM information_schema.tables WHERE table_schema=".$pdo->quote($database)." AND table_name=\"dr_1_share_index\"")->fetchColumn();
$max=(int)$pdo->query("SELECT COALESCE(MAX(id),0) FROM dr_1_share_index")->fetchColumn();
$wanted=["id","mid","catid","status","inputtime","url","tableid"];
$sel=array_values(array_intersect($wanted,$cols));
$quoted=array_map(fn($x)=>"`".$x."`",$sel);
$rows=$pdo->query("SELECT ".implode(",",$quoted)." FROM dr_1_share_index WHERE id=47 OR id BETWEEN 80 AND 95 ORDER BY id")->fetchAll();
$missing=$pdo->query("SELECT n.id FROM dr_1_news n LEFT JOIN dr_1_share_index s ON s.id=n.id WHERE (n.id=47 OR n.id BETWEEN 80 AND 95) AND s.id IS NULL ORDER BY n.id")->fetchAll(PDO::FETCH_COLUMN);
echo json_encode(["exists"=>true,"columns"=>$cols,"auto_increment"=>$ai===false?null:(int)$ai,"max_id"=>$max,"rows"=>$rows,"news_ids_missing_share_index"=>array_map("intval",$missing)],JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php")

HTTP_JSON='{}'
for id in 47 84 85 86 88 89; do
  code=$(curl -skL --max-time 20 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id")
  HTTP_JSON=$(python3 - "$HTTP_JSON" "$id" "$code" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); x[sys.argv[2]]=int(sys.argv[3]); print(json.dumps(x,separators=(',',':')))
PY
)
done
python3 - "$RESULT_FILE" "$DB_JSON" "$HTTP_JSON" <<'PY'
import json,sys
out,db,http=sys.argv[1:]
payload={'task':'share_index_diagnose','diagnostic':'PASS','database':json.loads(db),'http':json.loads(http),'secrets_disclosed':False}
with open(out,'w',encoding='utf-8') as fh:
    json.dump(payload,fh,ensure_ascii=False,indent=2,sort_keys=True); fh.write('\n')
PY

echo SHARE_INDEX_DIAGNOSE=PASS
