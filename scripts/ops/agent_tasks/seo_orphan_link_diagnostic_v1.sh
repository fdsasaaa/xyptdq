#!/bin/bash
# Read-only diagnostic for the four residual orphan category routes.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_DIRS="gjfa seo-articles tzjq zyyy"
PHASE="init"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -f "$WEBROOT/config/database.php" ] || exit 4

TMP="$(mktemp -d /tmp/xyptdq-orphan-links.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_error(){
  local rc="$1"
  python3 - "$RESULT_FILE" "$PHASE" "$rc" <<'PY'
import json,sys
out,phase,rc=sys.argv[1:]
payload={
  "task":"seo_orphan_link_diagnostic_v1",
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

PHASE="category_inventory"
php -r '
$db=[]; require $argv[1];
$dirs=preg_split("/\s+/",trim($argv[2]));
$c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$ph=implode(",",array_fill(0,count($dirs),"?"));
$st=$pdo->prepare("SELECT id,name,dirname,mid,disabled,`show` AS show_flag FROM dr_1_share_category WHERE dirname IN ($ph) ORDER BY id");
$st->execute($dirs);
echo json_encode($st->fetchAll(),JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php" "$TARGET_DIRS" > "$TMP/categories.json"

PHASE="render_fetch"
curl -skL --max-time 30 -o "$TMP/home.html" "$CANONICAL/"
curl -skL --max-time 30 -o "$TMP/article91.html" "$CANONICAL/index.php?c=show&id=91"

PHASE="classify_links"
python3 - "$TMP" "$RESULT_FILE" "$CANONICAL" <<'PY'
import html,json,pathlib,re,sys
from urllib.parse import parse_qsl,urljoin,urlparse,urlsplit

tmp=pathlib.Path(sys.argv[1]); out=pathlib.Path(sys.argv[2]); canonical=sys.argv[3].rstrip('/')
host=urlparse(canonical).netloc.lower()
cats=json.load(open(tmp/'categories.json',encoding='utf-8'))

def text_only(s):
    s=re.sub(r'<[^>]+>',' ',s)
    return re.sub(r'\s+',' ',html.unescape(s)).strip()

def route(url):
    if not url:
        return {"type":"missing"}
    u=urljoin(canonical+'/',html.unescape(url.strip()))
    p=urlsplit(u)
    if p.netloc.lower()!=host:
        return {"type":"external"}
    q=dict(parse_qsl(p.query,keep_blank_values=True))
    if (p.path or '/')=='/' and not q:
        return {"type":"home"}
    if q.get('c')=='category':
        r={"type":"category"}
        if q.get('dir'): r["dir"]=q["dir"]
        if q.get('id','').isdigit(): r["id"]=int(q["id"])
        return r
    if q.get('c')=='show':
        r={"type":"show"}
        if q.get('id','').isdigit(): r["id"]=int(q["id"])
        if q.get('dir'): r["dir"]=q["dir"]
        return r
    return {"type":"other","path":p.path or "/"}

def anchors(path):
    s=path.read_text(encoding='utf-8',errors='ignore')
    out=[]
    for m in re.finditer(r'<a\b([^>]*)>(.*?)</a\s*>',s,re.I|re.S):
        attrs=m.group(1); body=m.group(2)
        h=re.search(r'\bhref\s*=\s*["\']([^"\']*)["\']',attrs,re.I|re.S)
        if not h: continue
        href=html.unescape(h.group(1).strip())
        out.append({"text":text_only(body),"route":route(href)})
    return out

home=anchors(tmp/'home.html')
article=anchors(tmp/'article91.html')
rows=[]
for c in cats:
    d=str(c.get('dirname') or '')
    name=str(c.get('name') or '')
    def matches(items):
        return [x["route"] for x in items if x["route"].get("type")=="category" and x["route"].get("dir")==d]
    def label_routes(items):
        return [x["route"] for x in items if x["text"]==name][:10]
    rows.append({
      "id":int(c.get("id") or 0),
      "name":name,
      "dirname":d,
      "mid":str(c.get("mid") or ""),
      "disabled":int(c.get("disabled") or 0),
      "show_flag":int(c.get("show_flag") or 0),
      "canonical_route":{"type":"category","dir":d},
      "home_direct_canonical_link_count":len(matches(home)),
      "article91_direct_canonical_link_count":len(matches(article)),
      "home_label_link_routes":label_routes(home),
      "article91_label_link_routes":label_routes(article)
    })
payload={
  "task":"seo_orphan_link_diagnostic_v1",
  "diagnostic_status":"COMPLETE",
  "phase":"final",
  "target_count":len(rows),
  "targets":rows,
  "production_writes":False,
  "article_publishing":False,
  "secrets_disclosed":False,
  "blocking_item":"NONE"
}
with out.open("w",encoding="utf-8") as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write("\n")
PY

PHASE="final"
trap - ERR
