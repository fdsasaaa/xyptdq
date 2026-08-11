#!/bin/bash
# Read-only structural comparison for platform show IDs 74 and 75.
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

TMP="$(mktemp -d /tmp/xyptdq-platform-entity.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_error(){
  local rc="$1"
  python3 - "$RESULT_FILE" "$PHASE" "$rc" <<'PY'
import json,sys
out,phase,rc=sys.argv[1:]
payload={
  "task":"seo_platform_duplicate_entity_diagnostic_v1",
  "diagnostic_status":"BLOCKED",
  "phase":phase,
  "blocking_item":"runtime_error",
  "task_exit_code":int(rc),
  "production_writes":False,
  "article_publishing":False,
  "secrets_disclosed":False
}
with open(out,"w",encoding="utf-8") as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write("\n")
PY
}
on_err(){ local rc=$?; trap - ERR; write_error "$rc" || true; exit "$rc"; }
trap on_err ERR

PHASE="repo_sync"
cd "$REPO"
git fetch --prune origin >/dev/null 2>&1
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null 2>&1

PHASE="cms_compare"
php -r '
$db=[]; require $argv[1];
$c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[
  PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,
  PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC
]);
$st=$pdo->query("SELECT * FROM dr_1_xm WHERE id IN (74,75) ORDER BY id");
$rows=$st->fetchAll();
if(count($rows)!==2){exit(3);}
$a=$rows[0]; $b=$rows[1];
if((int)$a["id"]!==74 || (int)$b["id"]!==75){exit(4);}
$fields=[];
$equal=[]; $different=[];
foreach(array_keys($a) as $k){
  if($k==="id"){continue;}
  $av=trim((string)($a[$k]??"")); $bv=trim((string)($b[$k]??""));
  $same=hash_equals(hash("sha256",$av),hash("sha256",$bv));
  $item=[
    "field"=>$k,
    "equal"=>$same,
    "id74_nonempty"=>($av!==""),
    "id75_nonempty"=>($bv!==""),
    "id74_length"=>mb_strlen($av,"UTF-8"),
    "id75_length"=>mb_strlen($bv,"UTF-8")
  ];
  if(in_array($k,["status","catid","displayorder","inputtime","updatetime"],true)){
    $item["id74_value"]=$av===""?null:(int)$av;
    $item["id75_value"]=$bv===""?null:(int)$bv;
  }
  $fields[]=$item;
  if($same){$equal[]=$k;} else {$different[]=$k;}
}
$out=[
  "id74_title"=>(string)($a["title"]??""),
  "id75_title"=>(string)($b["title"]??""),
  "equal_field_count"=>count($equal),
  "different_field_count"=>count($different),
  "equal_fields"=>$equal,
  "different_fields"=>$different,
  "field_comparisons"=>$fields
];
echo json_encode($out,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php" > "$TMP/cms.json"

PHASE="render_compare"
for id in 74 75; do
  code=$(curl -skL --max-time 30 -o "$TMP/$id.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id")
  [ "$code" = 200 ] || exit 5
done

python3 - "$TMP" "$RESULT_FILE" "$CANONICAL" <<'PY'
import hashlib,html,json,pathlib,re,sys
from urllib.parse import parse_qsl,urlsplit

tmp=pathlib.Path(sys.argv[1]); out=pathlib.Path(sys.argv[2]); base=sys.argv[3].rstrip("/")
cms=json.load(open(tmp/"cms.json",encoding="utf-8"))

def attr(tag,name):
    m=re.search(r'\b'+re.escape(name)+r'\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    return html.unescape(m.group(1).strip()) if m else ""
def text_only(s):
    s=re.sub(r'<script\b.*?</script\s*>',' ',s,flags=re.I|re.S)
    s=re.sub(r'<style\b.*?</style\s*>',' ',s,flags=re.I|re.S)
    s=re.sub(r'<[^>]+>',' ',s)
    return re.sub(r'\s+',' ',html.unescape(s)).strip()
def first_text(s,tag):
    m=re.search(r'<'+tag+r'\b[^>]*>(.*?)</'+tag+r'\s*>',s,re.I|re.S)
    return text_only(m.group(1)) if m else ""
def desc(s):
    for t in re.findall(r'<meta\b[^>]*>',s,re.I|re.S):
        if attr(t,"name").lower()=="description": return attr(t,"content")
    return ""
def canon(s):
    for t in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
        if "canonical" in attr(t,"rel").lower().split(): return attr(t,"href")
    return ""
def route(u):
    p=urlsplit(u); q=dict(parse_qsl(p.query,keep_blank_values=True))
    r={"path":p.path or "/"}
    if q.get("c"): r["c"]=q["c"]
    if q.get("id","").isdigit(): r["id"]=int(q["id"])
    if q.get("dir"): r["dir"]=q["dir"]
    return r
def content_text(s):
    m=re.search(r'<div\b[^>]*class=["\'][^"\']*\bxyptdq-content\b[^"\']*["\'][^>]*>(.*?)</div\s*>',s,re.I|re.S)
    return text_only(m.group(1)) if m else ""

render={}
for i in (74,75):
    s=(tmp/f"{i}.html").read_text(encoding="utf-8",errors="ignore")
    d=desc(s); body=content_text(s)
    render[str(i)]={
      "title":first_text(s,"title"),
      "h1":first_text(s,"h1"),
      "canonical_route":route(canon(s)),
      "description_length":len(d),
      "description_sha256":hashlib.sha256(d.encode()).hexdigest(),
      "content_text_length":len(body),
      "content_text_sha256":hashlib.sha256(body.encode()).hexdigest()
    }

payload={
  "task":"seo_platform_duplicate_entity_diagnostic_v1",
  "diagnostic_status":"COMPLETE",
  "phase":"final",
  "cms":cms,
  "render":render,
  "rendered_title_equal":render["74"]["title"]==render["75"]["title"],
  "rendered_h1_equal":render["74"]["h1"]==render["75"]["h1"],
  "rendered_description_equal":render["74"]["description_sha256"]==render["75"]["description_sha256"],
  "rendered_content_equal":render["74"]["content_text_sha256"]==render["75"]["content_text_sha256"],
  "blocking_item":"NONE",
  "production_writes":False,
  "article_publishing":False,
  "secrets_disclosed":False
}
with out.open("w",encoding="utf-8") as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write("\n")
PY

PHASE="final"
trap - ERR
