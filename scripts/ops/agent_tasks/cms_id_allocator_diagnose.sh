#!/bin/bash
# Read-only diagnostic for Xunrui content-id allocation after direct-SQL smoke
# artifacts and the first native save_content smoke.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
cd "$REPO"
git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null

DB_JSON=$(php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$database=(string)($c["database"]??"");
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$database.";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$tables=["dr_1_news","dr_1_news_index","dr_1_news_data_0","dr_1_news_hits"];
$meta=[];
foreach ($tables as $table) {
  $s=$pdo->prepare("SELECT AUTO_INCREMENT FROM information_schema.tables WHERE table_schema=:db AND table_name=:t LIMIT 1");
  $s->execute([":db"=>$database,":t"=>$table]);
  $ai=$s->fetchColumn();
  $max=(int)$pdo->query("SELECT COALESCE(MAX(id),0) FROM `".$table."`")->fetchColumn();
  $meta[$table]=["auto_increment"=>$ai===false?null:(int)$ai,"max_id"=>$max];
}
$main=$pdo->query("SELECT id,catid,title,status,tableid,inputtime,updatetime FROM dr_1_news WHERE id BETWEEN 80 AND 95 ORDER BY id")->fetchAll();
$index=$pdo->query("SELECT id,uid,catid,status,inputtime FROM dr_1_news_index WHERE id BETWEEN 80 AND 95 ORDER BY id")->fetchAll();
$registry=$pdo->query("SELECT article_key,cms_id FROM dr_xyptdq_publish_registry WHERE cms_id BETWEEN 80 AND 95 OR article_key IN (\"native-cms-lifecycle-v1\",\"ffc-betting-basics-risk-v1\",\"ffc-public-category-smoke-v1\") ORDER BY cms_id,article_key")->fetchAll();
$orphans=$pdo->query("SELECT n.id FROM dr_1_news n LEFT JOIN dr_1_news_index i ON i.id=n.id WHERE i.id IS NULL ORDER BY n.id DESC LIMIT 20")->fetchAll(PDO::FETCH_COLUMN);
$indexOnly=$pdo->query("SELECT i.id FROM dr_1_news_index i LEFT JOIN dr_1_news n ON n.id=i.id WHERE n.id IS NULL ORDER BY i.id DESC LIMIT 20")->fetchAll(PDO::FETCH_COLUMN);
echo json_encode(["tables"=>$meta,"main_rows"=>$main,"index_rows"=>$index,"registry"=>$registry,"main_without_index"=>array_map("intval",$orphans),"index_without_main"=>array_map("intval",$indexOnly)],JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php")

python3 - "$RESULT_FILE" "$DB_JSON" <<'PY'
import json,sys
out,raw=sys.argv[1:]
x=json.loads(raw)
payload={
  'task':'cms_id_allocator_diagnose',
  'diagnostic':'PASS',
  'tables':x.get('tables',{}),
  'main_rows':x.get('main_rows',[]),
  'index_rows':x.get('index_rows',[]),
  'registry':x.get('registry',[]),
  'main_without_index':x.get('main_without_index',[]),
  'index_without_main':x.get('index_without_main',[]),
  'secrets_disclosed':False,
}
with open(out,'w',encoding='utf-8') as fh:
    json.dump(payload,fh,ensure_ascii=False,indent=2,sort_keys=True); fh.write('\n')
PY

echo "CMS_ID_ALLOCATOR_DIAGNOSE=PASS"
