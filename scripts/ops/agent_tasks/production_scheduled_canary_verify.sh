#!/bin/bash
# Read-only verification for the first real scheduled production article.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
FIXTURE="content/scheduled/seo-ffc-betting-economics-v1.json"
ARTICLE_KEY="seo-ffc-betting-economics-v1"
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
cd "$REPO"
git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null
[ -s "$FIXTURE" ] || exit 4
EXPECTED_TITLE=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo $x["title"]??"";' "$FIXTURE")
EXPECTED_CONTENT_HASH=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo hash("sha256",(string)($x["content"]??""));' "$FIXTURE")
DB=$(ARTICLE_KEY="$ARTICLE_KEY" php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$s=$pdo->prepare("SELECT cms_id,content_hash FROM dr_xyptdq_publish_registry WHERE article_key=:k LIMIT 1"); $s->execute([":k"=>getenv("ARTICLE_KEY")]); $reg=$s->fetch()?:[]; $id=(int)($reg["cms_id"]??0); $main=[];$data=[];$mid=false;
if($id>0){$s=$pdo->prepare("SELECT id,catid,title,status,tableid FROM dr_1_news WHERE id=:id LIMIT 1");$s->execute([":id"=>$id]);$main=$s->fetch()?:[];$tid=(int)($main["tableid"]??0);$table="dr_1_news_data_".$tid;$s=$pdo->prepare("SELECT content FROM `".$table."` WHERE id=:id LIMIT 1");$s->execute([":id"=>$id]);$data=$s->fetch()?:[];$s=$pdo->prepare("SELECT mid FROM dr_1_share_index WHERE id=:id LIMIT 1");$s->execute([":id"=>$id]);$mid=$s->fetchColumn();}
echo json_encode(["registry"=>$reg,"main"=>$main,"content"=>(string)($data["content"]??""),"mid"=>$mid],JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php")
CMS_ID=$(printf '%s' "$DB" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo (int)($x["registry"]["cms_id"]??0);')
TITLE=$(printf '%s' "$DB" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo (string)($x["main"]["title"]??"");')
STATUS=$(printf '%s' "$DB" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo (int)($x["main"]["status"]??0);')
CATID=$(printf '%s' "$DB" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo (int)($x["main"]["catid"]??0);')
MID=$(printf '%s' "$DB" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo (string)($x["mid"]??"");')
CONTENT_HASH=$(printf '%s' "$DB" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo hash("sha256",(string)($x["content"]??""));')
HTTP=0
[ "$CMS_ID" -gt 0 ] && HTTP=$(curl -skL --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$CMS_ID")
SITEMAP=NO
if [ "$CMS_ID" -gt 0 ] && grep -Eq "id(=|&amp;=)$CMS_ID([<&]|$)" "$WEBROOT/sitemap.xml"; then SITEMAP=YES; fi
CRON=NO
if [ -s /etc/cron.d/xyptdq-publisher ] && (systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null); then CRON=PASS; fi
VERIFY=FAIL
if [ "$CMS_ID" -gt 90 ] && [ "$TITLE" = "$EXPECTED_TITLE" ] && [ "$CONTENT_HASH" = "$EXPECTED_CONTENT_HASH" ] && [ "$STATUS" -eq 9 ] && [ "$CATID" -eq 7 ] && [ "$MID" = news ] && [ "$HTTP" -eq 200 ] && [ "$SITEMAP" = YES ] && [ "$CRON" = PASS ]; then VERIFY=PASS; fi
python3 - "$RESULT_FILE" "$VERIFY" "$CMS_ID" "$HTTP" "$STATUS" "$CATID" "$MID" "$SITEMAP" "$CRON" <<'PY'
import json,sys
out,verify,cms_id,http,status,catid,mid,sitemap,cron=sys.argv[1:]
payload={'task':'production_scheduled_canary_verify','verification':verify,'cms_id':int(cms_id),'article_http':int(http),'status':int(status),'catid':int(catid),'share_mid':mid,'sitemap_contains_article':sitemap,'publisher_cron':cron,'secrets_disclosed':False}
with open(out,'w',encoding='utf-8') as fh: json.dump(payload,fh,ensure_ascii=False,indent=2,sort_keys=True); fh.write('\n')
PY
[ "$VERIFY" = PASS ] || exit 1
echo "PRODUCTION_SCHEDULED_CANARY_VERIFY=PASS cms_id=$CMS_ID"
