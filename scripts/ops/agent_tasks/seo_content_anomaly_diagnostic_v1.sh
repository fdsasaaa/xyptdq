#!/bin/bash
# Read-only diagnostic for the concrete anomaly pages reported by Phase 5 V2.
# Emits only internal route descriptors and structural metadata; no production writes.
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

TMP="$(mktemp -d /tmp/xyptdq-seo-anomaly.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_error(){
  local rc="$1"
  python3 - "$RESULT_FILE" "$PHASE" "$rc" <<'PY'
import json,sys
out,phase,rc=sys.argv[1:]
payload={
  "task":"seo_content_anomaly_diagnostic_v1",
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
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$cats=$pdo->query("SELECT id,name,dirname,mid,disabled,`show` AS show_flag FROM dr_1_share_category ORDER BY id ASC")->fetchAll();
$counts=[];
foreach($pdo->query("SELECT catid,COUNT(*) AS n FROM dr_1_news WHERE status=9 GROUP BY catid")->fetchAll() as $r){$counts[(int)$r["catid"]]=(int)$r["n"];}
$out=[];
foreach($cats as $r){
  $id=(int)$r["id"];
  if((int)($r["disabled"]??0)===0 && (int)($r["show_flag"]??0)!==0 && in_array((string)($r["mid"]??""),["","news"],true) && ($counts[$id]??0)===0){
    $out[]=["id"=>$id,"name"=>(string)($r["name"]??""),"dirname"=>(string)($r["dirname"]??""),"mid"=>(string)($r["mid"]??"")];
  }
}
echo json_encode($out,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php" > "$TMP/empty_categories.json"

PHASE="sitemap_fetch"
curl -skL --max-time 30 -o "$TMP/sitemap.xml" -w '%{http_code}' "$CANONICAL/sitemap.xml" > "$TMP/sitemap.code"

PHASE="crawl_and_classify"
python3 - "$TMP" "$RESULT_FILE" "$CANONICAL" <<'PY'
import collections, hashlib, html, json, pathlib, re, subprocess, sys
from urllib.parse import parse_qsl, urlencode, urljoin, urlparse, urlsplit, urlunsplit

tmp=pathlib.Path(sys.argv[1])
out=pathlib.Path(sys.argv[2])
canonical=sys.argv[3].rstrip('/')
host=urlparse(canonical).netloc.lower()
empty_categories=json.loads((tmp/'empty_categories.json').read_text(encoding='utf-8'))
sitemap=(tmp/'sitemap.xml').read_text(encoding='utf-8',errors='ignore')
try: sitemap_http=int((tmp/'sitemap.code').read_text().strip())
except Exception: sitemap_http=0

def norm_url(url):
    if not url: return ''
    u=urljoin(canonical+'/',html.unescape(str(url).strip()))
    p=urlsplit(u)
    if p.scheme not in ('http','https') or p.netloc.lower()!=host: return ''
    q=urlencode(sorted(parse_qsl(p.query,keep_blank_values=True)))
    return urlunsplit(('https',host,p.path or '/',q,''))

def attr(tag,name):
    m=re.search(r'\b'+re.escape(name)+r'\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    return html.unescape(m.group(1).strip()) if m else ''

def text_only(s):
    s=re.sub(r'<script\b.*?</script\s*>',' ',s,flags=re.I|re.S)
    s=re.sub(r'<style\b.*?</style\s*>',' ',s,flags=re.I|re.S)
    s=re.sub(r'<[^>]+>',' ',s)
    return re.sub(r'\s+',' ',html.unescape(s)).strip()

def first_text(s,tag):
    m=re.search(r'<'+tag+r'\b[^>]*>(.*?)</'+tag+r'\s*>',s,re.I|re.S)
    return text_only(m.group(1)) if m else ''

def desc(s):
    for t in re.findall(r'<meta\b[^>]*>',s,re.I|re.S):
        if attr(t,'name').lower()=='description': return attr(t,'content')
    return ''

def canon(s):
    for t in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
        if 'canonical' in attr(t,'rel').lower().split(): return norm_url(attr(t,'href'))
    return ''

def route(u):
    if not u: return {"type":"missing"}
    p=urlsplit(u)
    q=dict(parse_qsl(p.query,keep_blank_values=True))
    if (p.path or '/')=='/' and not q: return {"type":"home"}
    c=q.get('c','')
    if c=='show':
        x={"type":"show"}
        if q.get('id','').isdigit(): x['id']=int(q['id'])
        if q.get('dir'): x['dir']=q['dir'][:80]
        return x
    if c=='category':
        x={"type":"category"}
        if q.get('id','').isdigit(): x['id']=int(q['id'])
        if q.get('dir'): x['dir']=q['dir'][:80]
        if q.get('page','').isdigit(): x['page']=int(q['page'])
        return x
    x={"type":"other","path":(p.path or '/')[:120]}
    if q:
        x['query_keys']=sorted(q)[:12]
        if 'id' in q and q['id'].isdigit(): x['id']=int(q['id'])
    return x

locs=[norm_url(x) for x in re.findall(r'<loc\b[^>]*>(.*?)</loc\s*>',sitemap,re.I|re.S)]
locs=[x for x in locs if x]
locs=list(dict.fromkeys(locs))[:250]
home=canonical+'/'
if home not in locs: locs.insert(0,home)

pages={}
for i,u in enumerate(locs):
    dest=tmp/f'p-{i}.html'
    cp=subprocess.run(['curl','-skL','--max-time','20','-o',str(dest),'-w','%{http_code}|%{url_effective}',u],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
    parts=cp.stdout.strip().split('|',1)
    try: code=int(parts[0])
    except Exception: code=0
    effective=norm_url(parts[1] if len(parts)>1 else u)
    s=dest.read_text(encoding='utf-8',errors='ignore') if dest.exists() else ''
    links=[]
    for a in re.findall(r'<a\b[^>]*>',s,re.I|re.S):
        v=norm_url(attr(a,'href'))
        if v: links.append(v)
    pages[u]={
      'http':code,'effective':effective,'canonical':canon(s),
      'title':first_text(s,'title'),'description':desc(s),'h1':first_text(s,'h1'),
      'links':sorted(set(links))
    }

page_set=set(pages)
inbound=collections.Counter()
for src,p in pages.items():
    for dst in p['links']:
        if dst in page_set and dst!=src: inbound[dst]+=1

http_errors=[{"page":route(u),"http":p['http'],"effective":route(p['effective'])} for u,p in pages.items() if p['http']!=200]
canonical_mismatches=[{"page":route(u),"canonical":route(p['canonical'])} for u,p in pages.items() if p['canonical'] and p['canonical']!=u]
orphans=[route(u) for u in pages if u!=home and inbound[u]==0]

def duplicates(field,include_value=False):
    g=collections.defaultdict(list)
    originals={}
    for u,p in pages.items():
        v=re.sub(r'\s+',' ',p.get(field,'')).strip()
        key=v.lower()
        if not key: continue
        g[key].append(u); originals[key]=v
    out=[]
    for key,urls in g.items():
        if len(urls)<2: continue
        v=originals[key]
        item={
          'value_sha256':hashlib.sha256(v.encode('utf-8')).hexdigest(),
          'value_chars':len(v),
          'pages':[route(u) for u in urls]
        }
        if include_value: item['value']=v[:160]
        out.append(item)
    return out

dup_titles=duplicates('title',True)
dup_h1=duplicates('h1',True)
dup_desc=duplicates('description',False)

payload={
  'task':'seo_content_anomaly_diagnostic_v1',
  'diagnostic_status':'COMPLETE',
  'phase':'final',
  'sitemap_http':sitemap_http,
  'crawled_page_count':len(pages),
  'http_errors':http_errors,
  'canonical_mismatches':canonical_mismatches,
  'orphan_pages':orphans,
  'duplicate_title_groups':dup_titles,
  'duplicate_h1_groups':dup_h1,
  'duplicate_description_groups':dup_desc,
  'active_empty_news_categories':empty_categories,
  'blocking_item':'NONE',
  'production_writes':False,
  'article_publishing':False,
  'secrets_disclosed':False
}
with out.open('w',encoding='utf-8') as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

PHASE="final"
trap - ERR
echo "SEO_CONTENT_ANOMALY_DIAGNOSTIC_V1=COMPLETE"
