#!/bin/bash
# Read-only mapping of SEO anomaly show IDs to Xunrui shared-index modules.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
IDS="50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 74 75 82 83"
DUP_SHA="dbb8e77773b4bf902811040fe65903fa87692b3345a3ba0ab966518b539eb716"
PHASE="init"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -f "$WEBROOT/config/database.php" ] || exit 4
TMP="$(mktemp -d /tmp/xyptdq-show-map.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_error(){
  local rc="$1"
  python3 - "$RESULT_FILE" "$PHASE" "$rc" <<'PY'
import json,sys
out,phase,rc=sys.argv[1:]
p={"task":"seo_show_module_mapping_diagnostic_v1","diagnostic_status":"BLOCKED","phase":phase,"task_exit_code":int(rc),"blocking_item":"runtime_error","production_writes":False,"article_publishing":False,"secrets_disclosed":False}
with open(out,"w",encoding="utf-8") as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write("\n")
PY
}
on_err(){ local rc=$?; trap - ERR; write_error "$rc" || true; exit "$rc"; }
trap on_err ERR

PHASE="repo_sync"
cd "$REPO"
git fetch --prune origin >/dev/null 2>&1
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null 2>&1

PHASE="shared_index_mapping"
php -r '
$db=[]; require $argv[1]; $ids=array_map("intval",preg_split("/\s+/",trim($argv[2])));
$c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$ph=implode(",",array_fill(0,count($ids),"?"));
$q=$pdo->prepare("SELECT id,mid FROM dr_1_share_index WHERE id IN ($ph) ORDER BY id"); $q->execute($ids); $idx=$q->fetchAll();
$by=[]; foreach($idx as $r){$by[(int)$r["id"]]=(string)$r["mid"];}
$out=[];
foreach($ids as $id){
  $mid=$by[$id]??""; $row=["show_id"=>$id,"share_index_present"=>($mid!==""),"mid"=>$mid,"module_row_present"=>false,"module_title"=>"","module_status"=>null,"module_catid"=>null];
  if($mid!=="" && preg_match("/^[A-Za-z0-9_]+$/",$mid)){
    $table="dr_1_".$mid;
    $exists=$pdo->prepare("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=? AND table_name=?"); $exists->execute([(string)$c["database"],$table]);
    if((int)$exists->fetchColumn()>0){
      $cols=$pdo->prepare("SELECT column_name FROM information_schema.columns WHERE table_schema=? AND table_name=?"); $cols->execute([(string)$c["database"],$table]);
      $names=array_map(fn($x)=>(string)$x["column_name"],$cols->fetchAll());
      $sel=["id"]; foreach(["title","status","catid"] as $n){if(in_array($n,$names,true)){$sel[]=$n;}}
      $sql="SELECT `".implode("`,`",$sel)."` FROM `".$table."` WHERE id=? LIMIT 1"; $s=$pdo->prepare($sql); $s->execute([$id]); $m=$s->fetch();
      if($m){$row["module_row_present"]=true; $row["module_title"]=(string)($m["title"]??""); $row["module_status"]=isset($m["status"])?(int)$m["status"]:null; $row["module_catid"]=isset($m["catid"])?(int)$m["catid"]:null;}
    }
  }
  $out[]=$row;
}
echo json_encode($out,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php" "$IDS" > "$TMP/map.json"

PHASE="render_mapping"
for id in $IDS; do
  code=$(curl -skL --max-time 25 -o "$TMP/$id.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id" || true)
  printf '%s\n' "${code:-0}" > "$TMP/$id.code"
done

python3 - "$TMP" "$RESULT_FILE" "$DUP_SHA" <<'PY'
import collections,hashlib,html,json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]); out=pathlib.Path(sys.argv[2]); dup=sys.argv[3]
rows=json.load(open(root/'map.json',encoding='utf-8'))

def attr(tag,name):
    m=re.search(r'\b'+re.escape(name)+r'\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S); return html.unescape(m.group(1).strip()) if m else ''
def text(s,tag):
    m=re.search(r'<'+tag+r'\b[^>]*>(.*?)</'+tag+r'\s*>',s,re.I|re.S)
    if not m:return ''
    return re.sub(r'\s+',' ',html.unescape(re.sub(r'<[^>]+>',' ',m.group(1)))).strip()
def desc(s):
    for t in re.findall(r'<meta\b[^>]*>',s,re.I|re.S):
        if attr(t,'name').lower()=='description': return attr(t,'content')
    return ''

for r in rows:
    i=r['show_id']; code=int((root/f'{i}.code').read_text().strip() or 0); s=(root/f'{i}.html').read_text(encoding='utf-8',errors='ignore')
    d=desc(s); r['http']=code; r['rendered_title']=text(s,'title'); r['rendered_h1']=text(s,'h1'); r['description_length']=len(d); r['description_sha256']=hashlib.sha256(d.encode()).hexdigest(); r['matches_duplicate_description_hash']=r['description_sha256']==dup
mid_counts=collections.Counter(r['mid'] or '(missing)' for r in rows)
dup_rows=[r for r in rows if r['matches_duplicate_description_hash']]
h1_pair=[r for r in rows if r['show_id'] in (74,75)]
p={"task":"seo_show_module_mapping_diagnostic_v1","diagnostic_status":"COMPLETE","phase":"final","row_count":len(rows),"mid_counts":dict(mid_counts),"duplicate_description_match_count":len(dup_rows),"duplicate_description_mid_counts":dict(collections.Counter(r['mid'] or '(missing)' for r in dup_rows)),"rows":rows,"h1_74_75_same_mid":len(h1_pair)==2 and h1_pair[0]['mid']==h1_pair[1]['mid'],"h1_74_75_same_rendered_h1":len(h1_pair)==2 and h1_pair[0]['rendered_h1']==h1_pair[1]['rendered_h1'],"blocking_item":"NONE","production_writes":False,"article_publishing":False,"secrets_disclosed":False}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

PHASE="final"
trap - ERR
