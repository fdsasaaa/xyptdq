#!/bin/bash
# Read-only inventory for current news-category architecture.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
PHASE="init"
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -f "$WEBROOT/config/database.php" ] || exit 4
TMP="$(mktemp -d /tmp/xyptdq-cat-arch.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
write_error(){ python3 - "$RESULT_FILE" "$PHASE" "$1" <<'PY'
import json,sys
out,phase,rc=sys.argv[1:]; p={"task":"seo_category_architecture_diagnostic_v1","diagnostic_status":"BLOCKED","phase":phase,"task_exit_code":int(rc),"blocking_item":"runtime_error","production_writes":False,"article_publishing":False,"secrets_disclosed":False}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}
on_err(){ rc=$?; trap - ERR; write_error "$rc" || true; exit "$rc"; }; trap on_err ERR
PHASE="repo_sync"; cd "$REPO"; git fetch --prune origin >/dev/null 2>&1; git checkout main >/dev/null 2>&1; git reset --hard origin/main >/dev/null 2>&1
PHASE="cms_inventory"
php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[]; $pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$cats=$pdo->query("SELECT id,name,dirname,mid,disabled,`show` AS show_flag FROM dr_1_share_category WHERE mid=\"news\" ORDER BY id")->fetchAll(); $out=[];
foreach($cats as $cat){$id=(int)$cat["id"];$q=$pdo->prepare("SELECT status,COUNT(*) n FROM dr_1_news WHERE catid=? GROUP BY status");$q->execute([$id]);$by=[];$total=0;foreach($q as $r){$by[(string)$r["status"]]=(int)$r["n"];$total+=(int)$r["n"];}$latest=$pdo->prepare("SELECT id,title,updatetime FROM dr_1_news WHERE catid=? AND status=9 ORDER BY updatetime DESC,id DESC LIMIT 5");$latest->execute([$id]);$items=[];foreach($latest as $r){$items[]=["id"=>(int)$r["id"],"title"=>(string)$r["title"],"updatetime"=>(int)$r["updatetime"]];}$out[]=["id"=>$id,"name"=>(string)$cat["name"],"dirname"=>(string)$cat["dirname"],"disabled"=>(int)$cat["disabled"],"show_flag"=>(int)$cat["show_flag"],"total_articles"=>$total,"published_articles"=>(int)($by["9"]??0),"nonpublished_articles"=>$total-(int)($by["9"]??0),"status_counts"=>$by,"latest_published"=>$items];}
echo json_encode($out,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);' "$WEBROOT/config/database.php" > "$TMP/categories.json"
PHASE="sitemap_fetch"; code=$(curl -skL --max-time 30 -o "$TMP/sitemap.xml" -w '%{http_code}' "$CANONICAL/sitemap.xml" || true); [ "$code" = 200 ] || exit 5
PHASE="finalize"
python3 - "$TMP/categories.json" "$TMP/sitemap.xml" "$RESULT_FILE" "$CANONICAL" <<'PY'
import json,re,sys
cats=json.load(open(sys.argv[1],encoding='utf-8')); sitemap=open(sys.argv[2],encoding='utf-8',errors='ignore').read(); out=sys.argv[3]; base=sys.argv[4].rstrip('/')
for c in cats:
 d=c['dirname']; u=f'{base}/index.php?c=category&dir={d}' if d else ''; c['canonical_url_in_sitemap']=bool(u and re.search(r'<loc>\s*'+re.escape(u)+r'\s*</loc>',sitemap,re.I))
p={"task":"seo_category_architecture_diagnostic_v1","diagnostic_status":"COMPLETE","phase":"final","category_count":len(cats),"categories":cats,"active_empty_categories":[{"id":c['id'],"name":c['name'],"dirname":c['dirname']} for c in cats if c['disabled']==0 and c['show_flag']==1 and c['total_articles']==0],"blocking_item":"NONE","production_writes":False,"article_publishing":False,"secrets_disclosed":False}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
trap - ERR
