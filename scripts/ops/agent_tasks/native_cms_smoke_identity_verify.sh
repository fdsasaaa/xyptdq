#!/bin/bash
# Read-only verification that the native CMS smoke registry points to the exact
# fixture content rather than merely to an unrelated public CMS id.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
FIXTURE="content/smoke/native-cms-lifecycle-v1.json"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
cd "$REPO"
git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null

ARTICLE_KEY=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo $x["article_key"]??"";' "$FIXTURE")
EXPECTED_TITLE=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo $x["title"]??"";' "$FIXTURE")
EXPECTED_CONTENT_HASH=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo hash("sha256",(string)($x["content"]??""));' "$FIXTURE")
EXPECTED_REGISTRY_HASH=$(php -r 'require $argv[1]; $x=json_decode(file_get_contents($argv[2]),true); echo xyptdq_article_hash($x);' scripts/content/cms_publish_adapter.php "$FIXTURE")

DB_JSON=$(ARTICLE_KEY="$ARTICLE_KEY" php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$s=$pdo->prepare("SELECT cms_id,content_hash FROM dr_xyptdq_publish_registry WHERE article_key=:k LIMIT 1"); $s->execute([":k"=>getenv("ARTICLE_KEY")]); $reg=$s->fetch()?:[];
$id=(int)($reg["cms_id"]??0);
$main=[]; $data=[];
if ($id>0) {
 $q=$pdo->prepare("SELECT id,catid,title,status,url,tableid,inputtime,updatetime FROM dr_1_news WHERE id=:id LIMIT 1"); $q->execute([":id"=>$id]); $main=$q->fetch()?:[];
 $tableid=(int)($main["tableid"]??0);
 if ($tableid>=0 && $tableid<10000) {
   $table="dr_1_news_data_".$tableid;
   $q=$pdo->prepare("SELECT id,catid,content FROM `".$table."` WHERE id=:id LIMIT 1"); $q->execute([":id"=>$id]); $data=$q->fetch()?:[];
 }
}
$t=$pdo->prepare("SELECT id FROM dr_1_news WHERE title=:title ORDER BY id"); $t->execute([":title"=>getenv("EXPECTED_TITLE")]); $titleIds=$t->fetchAll(PDO::FETCH_COLUMN);
$max=(int)$pdo->query("SELECT MAX(id) FROM dr_1_news")->fetchColumn();
echo json_encode(["registry"=>$reg,"main"=>$main,"data"=>$data,"title_ids"=>array_map("intval",$titleIds),"max_id"=>$max],JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php" EXPECTED_TITLE="$EXPECTED_TITLE")

# The environment assignment after argv is not portable for php -r; repeat the
# exact-title lookup safely if the first command did not receive it.
DB_JSON=$(ARTICLE_KEY="$ARTICLE_KEY" EXPECTED_TITLE="$EXPECTED_TITLE" php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$s=$pdo->prepare("SELECT cms_id,content_hash FROM dr_xyptdq_publish_registry WHERE article_key=:k LIMIT 1"); $s->execute([":k"=>getenv("ARTICLE_KEY")]); $reg=$s->fetch()?:[];
$id=(int)($reg["cms_id"]??0); $main=[]; $data=[];
if ($id>0) {
 $q=$pdo->prepare("SELECT id,catid,title,status,url,tableid,inputtime,updatetime FROM dr_1_news WHERE id=:id LIMIT 1"); $q->execute([":id"=>$id]); $main=$q->fetch()?:[];
 $tableid=(int)($main["tableid"]??0);
 if ($tableid>=0 && $tableid<10000) { $table="dr_1_news_data_".$tableid; $q=$pdo->prepare("SELECT id,catid,content FROM `".$table."` WHERE id=:id LIMIT 1"); $q->execute([":id"=>$id]); $data=$q->fetch()?:[]; }
}
$t=$pdo->prepare("SELECT id FROM dr_1_news WHERE title=:title ORDER BY id"); $t->execute([":title"=>getenv("EXPECTED_TITLE")]); $titleIds=$t->fetchAll(PDO::FETCH_COLUMN);
$max=(int)$pdo->query("SELECT MAX(id) FROM dr_1_news")->fetchColumn();
echo json_encode(["registry"=>$reg,"main"=>$main,"data"=>$data,"title_ids"=>array_map("intval",$titleIds),"max_id"=>$max],JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php")

CMS_ID=$(printf '%s' "$DB_JSON" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo (int)($x["registry"]["cms_id"]??0);')
ACTUAL_TITLE=$(printf '%s' "$DB_JSON" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo (string)($x["main"]["title"]??"");')
ACTUAL_CONTENT_HASH=$(printf '%s' "$DB_JSON" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo hash("sha256",(string)($x["data"]["content"]??""));')
ACTUAL_REGISTRY_HASH=$(printf '%s' "$DB_JSON" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo (string)($x["registry"]["content_hash"]??"");')
TITLE_COUNT=$(printf '%s' "$DB_JSON" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo count($x["title_ids"]??[]);')
MAX_ID=$(printf '%s' "$DB_JSON" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo (int)($x["max_id"]??0);')
STATUS=$(printf '%s' "$DB_JSON" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo (int)($x["main"]["status"]??0);')
CATID=$(printf '%s' "$DB_JSON" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo (int)($x["main"]["catid"]??0);')

HTTP47=$(curl -skL --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=47")
HTTP84=$(curl -skL --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=84")
HTTP88=$(curl -skL --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=88")
HTTP89=$(curl -skL --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=89")
HTTP_REG=0
if [ "$CMS_ID" -gt 0 ]; then HTTP_REG=$(curl -skL --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$CMS_ID"); fi

TITLE_MATCH=NO; CONTENT_MATCH=NO; REGISTRY_HASH_MATCH=NO
[ "$ACTUAL_TITLE" = "$EXPECTED_TITLE" ] && TITLE_MATCH=YES
[ "$ACTUAL_CONTENT_HASH" = "$EXPECTED_CONTENT_HASH" ] && CONTENT_MATCH=YES
[ "$ACTUAL_REGISTRY_HASH" = "$EXPECTED_REGISTRY_HASH" ] && REGISTRY_HASH_MATCH=YES
IDENTITY=FAIL
if [ "$CMS_ID" -gt 0 ] && [ "$TITLE_MATCH" = YES ] && [ "$CONTENT_MATCH" = YES ] && [ "$REGISTRY_HASH_MATCH" = YES ] && [ "$TITLE_COUNT" -eq 1 ] && [ "$STATUS" -eq 9 ] && [ "$HTTP_REG" -eq 200 ]; then IDENTITY=PASS; fi

python3 - "$RESULT_FILE" "$IDENTITY" "$CMS_ID" "$MAX_ID" "$CATID" "$STATUS" "$TITLE_COUNT" "$TITLE_MATCH" "$CONTENT_MATCH" "$REGISTRY_HASH_MATCH" "$HTTP_REG" "$HTTP47" "$HTTP84" "$HTTP88" "$HTTP89" <<'PY'
import json,sys
(out,identity,cms_id,max_id,catid,status,title_count,title_match,content_match,registry_hash_match,http_reg,http47,http84,http88,http89)=sys.argv[1:]
payload={
 'task':'native_cms_smoke_identity_verify',
 'identity_verification':identity,
 'cms_id':int(cms_id),
 'max_news_id':int(max_id),
 'catid':int(catid),
 'status':int(status),
 'exact_title_row_count':int(title_count),
 'title_matches_fixture':title_match,
 'content_matches_fixture':content_match,
 'registry_hash_matches_fixture':registry_hash_match,
 'http_registry_id':int(http_reg),
 'http_reference_47':int(http47),
 'http_84':int(http84),
 'http_88':int(http88),
 'http_89':int(http89),
 'secrets_disclosed':False,
}
with open(out,'w',encoding='utf-8') as fh:
 json.dump(payload,fh,ensure_ascii=False,indent=2,sort_keys=True); fh.write('\n')
PY

[ "$IDENTITY" = PASS ] || exit 1
echo "NATIVE_CMS_SMOKE_IDENTITY=PASS cms_id=$CMS_ID"
