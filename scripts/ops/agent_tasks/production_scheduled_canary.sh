#!/bin/bash
# One-time production canary for the real scheduled queue after native publisher
# activation. It publishes exactly one reviewed due article through the same
# run_scheduled_publish.sh path used by cron and verifies public identity.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
FIXTURE="content/scheduled/seo-ffc-betting-economics-v1.json"
ARTICLE_KEY="seo-ffc-betting-economics-v1"
PHASE="init"
PUBLISH="NO"
HTTP=0
CMS_ID=0
REGISTRY="NO"
SHARE_INDEX="NO"
SITEMAP="NO"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3

write_payload(){
  local status="$1" blocker="$2"
  python3 - "$RESULT_FILE" "$status" "$blocker" "$PHASE" "$PUBLISH" "$HTTP" "$CMS_ID" "$REGISTRY" "$SHARE_INDEX" "$SITEMAP" <<'PY'
import json,sys
(out,status,blocker,phase,publish,http,cms_id,registry,share,sitemap)=sys.argv[1:]
payload={
 'task':'production_scheduled_canary',
 'canary_status':status,
 'phase':phase,
 'blocking_item':blocker,
 'scheduled_publish':publish,
 'cms_id':int(cms_id),
 'article_http':int(http),
 'registry_verification':registry,
 'share_index_verification':share,
 'sitemap_contains_article':sitemap,
 'secrets_disclosed':False,
}
with open(out,'w',encoding='utf-8') as fh:
 json.dump(payload,fh,ensure_ascii=False,indent=2,sort_keys=True); fh.write('\n')
PY
}
block(){ write_payload BLOCKED "$1"; echo "[production-canary] BLOCKED: $1" >&2; exit 1; }

cd "$REPO"
PHASE="repo_sync"
[ -z "$(git status --porcelain)" ] || block production_repo_dirty
git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null
[ -s "$FIXTURE" ] || block canary_fixture_missing
[ -s scripts/content/run_scheduled_publish.sh ] || block scheduled_runner_missing
[ -s scripts/content/cms_publish_native_adapter.php ] || block native_adapter_missing

PHASE="queue_preflight"
COUNT=$(find content/scheduled -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')
[ "$COUNT" -eq 1 ] || block scheduled_queue_not_exactly_one_json
KEY=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo $x["article_key"]??"";' "$FIXTURE")
[ "$KEY" = "$ARTICLE_KEY" ] || block article_key_mismatch
DUE=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); $t=strtotime($x["publish_at"]??""); echo ($t!==false && $t<=time())?"1":"0";' "$FIXTURE")
[ "$DUE" = 1 ] || block canary_not_due

PHASE="preexisting_registry"
EXISTING=$(ARTICLE_KEY="$ARTICLE_KEY" php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$s=$pdo->prepare("SELECT cms_id FROM dr_xyptdq_publish_registry WHERE article_key=:k LIMIT 1"); $s->execute([":k"=>getenv("ARTICLE_KEY")]); echo (int)$s->fetchColumn();
' "$WEBROOT/config/database.php")
[ "$EXISTING" -eq 0 ] || block canary_article_already_registered

PHASE="scheduled_publish"
OUT=$(mktemp /tmp/xyptdq-production-canary.XXXXXX.log)
trap 'rm -f "$OUT"' EXIT
if ! XYPTDQ_PUBLISH_LIMIT=2 bash scripts/content/run_scheduled_publish.sh >"$OUT" 2>&1; then
  block scheduled_runner_failed
fi
grep -Fq 'result=PASS' "$OUT" || block scheduled_runner_pass_marker_missing
PUBLISH="PASS"

PHASE="registry"
CMS_ID=$(ARTICLE_KEY="$ARTICLE_KEY" php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$s=$pdo->prepare("SELECT cms_id FROM dr_xyptdq_publish_registry WHERE article_key=:k LIMIT 1"); $s->execute([":k"=>getenv("ARTICLE_KEY")]); echo (int)$s->fetchColumn();
' "$WEBROOT/config/database.php")
[ "$CMS_ID" -gt 90 ] || block registry_cms_id_invalid
REGISTRY="PASS"

PHASE="identity"
EXPECTED_TITLE=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo $x["title"]??"";' "$FIXTURE")
VERIFY=$(CMS_ID="$CMS_ID" EXPECTED_TITLE="$EXPECTED_TITLE" php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$s=$pdo->prepare("SELECT title,status FROM dr_1_news WHERE id=:id LIMIT 1"); $s->execute([":id"=>(int)getenv("CMS_ID")]); $n=$s->fetch()?:[];
$s=$pdo->prepare("SELECT mid FROM dr_1_share_index WHERE id=:id LIMIT 1"); $s->execute([":id"=>(int)getenv("CMS_ID")]); $mid=$s->fetchColumn();
$ok=($n["title"]??"")===getenv("EXPECTED_TITLE") && (int)($n["status"]??0)===9 && $mid==="news";
echo $ok?"1":"0";
' "$WEBROOT/config/database.php")
[ "$VERIFY" = 1 ] || block cms_identity_failed
SHARE_INDEX="PASS"

PHASE="http"
HTTP=$(curl -skL --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$CMS_ID")
[ "$HTTP" = 200 ] || block article_http_not_200

PHASE="sitemap"
grep -Eq "id(=|&amp;=)$CMS_ID([<&]|$)" "$WEBROOT/sitemap.xml" || block sitemap_missing_canary
SITEMAP="YES"

PHASE="final"
write_payload PASS NONE
echo "PRODUCTION_SCHEDULED_CANARY=PASS cms_id=$CMS_ID"
