#!/bin/bash
# Read-only SEO content architecture audit.
# Compares the production CMS/sitemap/internal-link graph with content/keyword_map.json.
# No production writes, no article publishing, no template changes.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -f "$WEBROOT/config/database.php" ] || exit 4

TMP="$(mktemp -d /tmp/xyptdq-seo-content-arch.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

cd "$REPO"
git fetch --prune origin >/dev/null 2>&1
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null 2>&1
[ -s content/keyword_map.json ] || exit 5

# Read public CMS inventory only. Credentials stay server-side and are never emitted.
php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO(
  "mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",
  $c["username"],$c["password"],
  [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]
);
$out=["categories"=>[],"news"=>[],"platforms"=>[]];

$cats=$pdo->query("SELECT id,name,dirname,mid,disabled,`show` AS show_flag FROM dr_1_share_category ORDER BY id ASC")->fetchAll();
foreach($cats as $r){
  $out["categories"][]=[
    "id"=>(int)$r["id"],
    "name"=>(string)($r["name"]??""),
    "dirname"=>(string)($r["dirname"]??""),
    "mid"=>(string)($r["mid"]??""),
    "disabled"=>(int)($r["disabled"]??0),
    "show_flag"=>(int)($r["show_flag"]??0),
  ];
}

$news=$pdo->query("SELECT id,catid,title,url,updatetime,status,tableid FROM dr_1_news WHERE status=9 ORDER BY id ASC")->fetchAll();
$byTable=[];
foreach($news as $r){ $byTable[(int)($r["tableid"]??0)][]=(int)$r["id"]; }
$content=[];
foreach($byTable as $tid=>$ids){
  if($tid<0 || $tid>9999) continue;
  $table="dr_1_news_data_".$tid;
  $s=$pdo->prepare("SELECT id,content FROM `".$table."` WHERE id IN (".implode(",",array_fill(0,count($ids),"?")).")");
  $s->execute($ids);
  foreach($s->fetchAll() as $d){ $content[(int)$d["id"]]=(string)($d["content"]??""); }
}
foreach($news as $r){
  $id=(int)$r["id"];
  $out["news"][]=[
    "id"=>$id,
    "catid"=>(int)($r["catid"]??0),
    "title"=>(string)($r["title"]??""),
    "url"=>(string)($r["url"]??""),
    "updatetime"=>(int)($r["updatetime"]??0),
    "tableid"=>(int)($r["tableid"]??0),
    "content"=>(string)($content[$id]??""),
  ];
}

$platforms=$pdo->query("SELECT id,title,url,status FROM dr_1_xm WHERE status=9 ORDER BY id ASC")->fetchAll();
foreach($platforms as $r){
  $out["platforms"][]=[
    "id"=>(int)$r["id"],
    "title"=>(string)($r["title"]??""),
    "url"=>(string)($r["url"]??""),
  ];
}
echo json_encode($out,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php" > "$TMP/cms.json"

curl -skL --max-time 30 -o "$TMP/sitemap.xml" -w '%{http_code}' "$CANONICAL/sitemap.xml" > "$TMP/sitemap.code"

python3 - "$TMP" "$RESULT_FILE" "$REPO/content/keyword_map.json" "$CANONICAL" <<'PY'
import collections, html, json, pathlib, re, subprocess, sys, urllib.parse

tmp=pathlib.Path(sys.argv[1])
out=pathlib.Path(sys.argv[2])
keyword_path=pathlib.Path(sys.argv[3])
canonical=sys.argv[4].rstrip("/")
host=urllib.parse.urlparse(canonical).netloc.lower()

cms=json.loads((tmp/"cms.json").read_text(encoding="utf-8"))
kw=json.loads(keyword_path.read_text(encoding="utf-8"))
sitemap=(tmp/"sitemap.xml").read_text(encoding="utf-8",errors="ignore")
try:
    sitemap_http=int((tmp/"sitemap.code").read_text().strip())
except Exception:
    sitemap_http=0

def norm_url(url):
    if not url:
        return ""
    u=urllib.parse.urljoin(canonical+"/", html.unescape(url.strip()))
    p=urllib.parse.urlsplit(u)
    if p.scheme not in ("http","https") or p.netloc.lower()!=host:
        return ""
    q=urllib.parse.parse_qsl(p.query,keep_blank_values=True)
    q=urllib.parse.urlencode(sorted(q))
    path=p.path or "/"
    return urllib.parse.urlunsplit(("https",host,path,q,""))

def visible(s):
    s=re.sub(r"<script\b.*?</script\s*>"," ",s,flags=re.I|re.S)
    s=re.sub(r"<style\b.*?</style\s*>"," ",s,flags=re.I|re.S)
    s=re.sub(r"<!--.*?-->"," ",s,flags=re.S)
    s=re.sub(r"<[^>]+>"," ",s)
    return re.sub(r"\s+"," ",html.unescape(s)).strip()

def first_text(s,tag):
    m=re.search(r"<"+tag+r"\b[^>]*>(.*?)</"+tag+r"\s*>",s,re.I|re.S)
    return visible(m.group(1)) if m else ""

def attr(tag,name):
    m=re.search(r"\b"+re.escape(name)+r"\s*=\s*[\"']([^\"']*)[\"']",tag,re.I|re.S)
    return html.unescape(m.group(1).strip()) if m else ""

locs=[norm_url(x) for x in re.findall(r"<loc\b[^>]*>(.*?)</loc\s*>",sitemap,re.I|re.S)]
locs=[x for x in locs if x]
locs=list(dict.fromkeys(locs))
if canonical+"/" not in locs:
    locs.insert(0,canonical+"/")
locs=locs[:500]

pages={}
for i,url in enumerate(locs):
    dest=tmp/f"page-{i}.html"
    proc=subprocess.run(
        ["curl","-skL","--max-time","20","-o",str(dest),"-w","%{http_code}|%{url_effective}",url],
        stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True
    )
    raw=proc.stdout.strip().split("|",1)
    try: code=int(raw[0])
    except Exception: code=0
    effective=norm_url(raw[1] if len(raw)>1 else url)
    s=dest.read_text(encoding="utf-8",errors="ignore") if dest.exists() else ""
    title=first_text(s,"title")
    h1=first_text(s,"h1")
    robots=""
    canonical_tag=""
    hrefs=[]
    for t in re.findall(r"<meta\b[^>]*>",s,re.I|re.S):
        if attr(t,"name").lower()=="robots":
            robots=attr(t,"content").lower()
            break
    for t in re.findall(r"<link\b[^>]*>",s,re.I|re.S):
        if "canonical" in attr(t,"rel").lower().split():
            canonical_tag=norm_url(attr(t,"href"))
            break
    for t in re.findall(r"<a\b[^>]*>",s,re.I|re.S):
        u=norm_url(attr(t,"href"))
        if u: hrefs.append(u)
    pages[url]={
        "http":code,
        "effective":effective,
        "title":title,
        "h1":h1,
        "robots":robots,
        "canonical":canonical_tag,
        "links":sorted(set(hrefs)),
    }

page_set=set(pages)
inbound=collections.Counter()
for src,p in pages.items():
    for dst in p["links"]:
        if dst in page_set and dst!=src:
            inbound[dst]+=1

orphan_urls=[u for u in pages if u!=canonical+"/" and inbound[u]==0]
http_fail=[u for u,p in pages.items() if p["http"]!=200]
noindex=[u for u,p in pages.items() if "noindex" in p["robots"] or "none" in p["robots"]]
canonical_mismatch=[u for u,p in pages.items() if p["canonical"] and p["canonical"]!=u]

def dup_groups(field):
    g=collections.defaultdict(list)
    for u,p in pages.items():
        v=re.sub(r"\s+"," ",p[field]).strip().lower()
        if v: g[v].append(u)
    return [v for v in g.values() if len(v)>1]

dup_titles=dup_groups("title")
dup_h1=dup_groups("h1")

cats=cms.get("categories",[])
news=cms.get("news",[])
platforms=cms.get("platforms",[])
active_cats=[c for c in cats if c.get("disabled",0)==0 and c.get("show_flag",0)!=0]
news_by_cat=collections.Counter(int(n.get("catid",0)) for n in news)
empty_active=[c for c in active_cats if news_by_cat[int(c["id"])]==0 and str(c.get("mid","")) in ("","news")]

def hrefs_from_html(s):
    found=[]
    for t in re.findall(r"<a\b[^>]*>",s or "",re.I|re.S):
        u=norm_url(attr(t,"href"))
        if u: found.append(u)
    return sorted(set(found))

news_zero_internal=[]
for n in news:
    links=hrefs_from_html(n.get("content",""))
    if not links:
        news_zero_internal.append(int(n["id"]))

existing_targets=kw.get("existing_targets",{})
existing_target_status={}
for name,path in existing_targets.items():
    target=norm_url(path)
    existing_target_status[name]={
        "target":path,
        "in_sitemap":target in page_set,
        "http":pages.get(target,{}).get("http",0),
    }

flat=[]
keyword_owner=collections.defaultdict(set)
target_keywords=collections.defaultdict(list)
for cluster in kw.get("clusters",[]):
    for item in cluster.get("keywords",[]):
        k=str(item.get("keyword","")).strip()
        t=str(item.get("target","")).strip()
        if not k or not t: continue
        flat.append({
            "cluster":cluster.get("id",""),
            "keyword":k,
            "target":t,
            "priority":item.get("priority",""),
            "intent":item.get("intent",""),
        })
        keyword_owner[k].add(t)
        target_keywords[t].append(k)

map_keyword_conflicts={k:sorted(v) for k,v in keyword_owner.items() if len(v)>1]
same_target_multi_keywords={t:v for t,v in target_keywords.items() if len(v)>1}

symbolic=[x for x in flat if not x["target"].startswith("/")]
path_targets=[x for x in flat if x["target"].startswith("/")]
path_target_missing=[]
for item in path_targets:
    u=norm_url(item["target"])
    if u not in page_set or pages.get(u,{}).get("http")!=200:
        path_target_missing.append(item)

# Symbolic targets are design placeholders. Search for plausible existing owner pages,
# but do not treat a text match as authoritative mapping.
symbolic_candidates=[]
for item in symbolic:
    k=item["keyword"].lower()
    candidates=[]
    for u,p in pages.items():
        hay=(p["title"]+" "+p["h1"]).lower()
        if k and k in hay:
            candidates.append(u)
    symbolic_candidates.append({
        "keyword":item["keyword"],
        "target":item["target"],
        "priority":item["priority"],
        "candidate_count":len(candidates),
    })

resolved_symbolic_candidates=sum(1 for x in symbolic_candidates if x["candidate_count"]==1)
no_candidate_symbolic=sum(1 for x in symbolic_candidates if x["candidate_count"]==0)
multi_candidate_symbolic=sum(1 for x in symbolic_candidates if x["candidate_count"]>1)

opportunities=[]
if sitemap_http!=200: opportunities.append("sitemap_http")
if http_fail: opportunities.append("sitemap_page_http_error")
if noindex: opportunities.append("sitemap_page_noindex")
if canonical_mismatch: opportunities.append("canonical_mismatch")
if orphan_urls: opportunities.append("sitemap_orphan_pages")
if dup_titles: opportunities.append("duplicate_page_titles")
if dup_h1: opportunities.append("duplicate_page_h1")
if empty_active: opportunities.append("active_category_without_published_news")
if news_zero_internal: opportunities.append("article_body_internal_link_gap")
if path_target_missing: opportunities.append("keyword_map_path_target_missing")
if map_keyword_conflicts: opportunities.append("keyword_map_keyword_owner_conflict")
if no_candidate_symbolic or multi_candidate_symbolic:
    opportunities.append("planned_primary_target_mapping_incomplete")

category_summary=[
    {
        "id":int(c["id"]),
        "name":c.get("name",""),
        "dirname":c.get("dirname",""),
        "mid":c.get("mid",""),
        "published_news":int(news_by_cat[int(c["id"])]),
        "active":bool(c.get("disabled",0)==0 and c.get("show_flag",0)!=0),
    }
    for c in cats
]

payload={
    "task":"seo_content_architecture_audit_v1",
    "audit_status":"COMPLETE",
    "opportunity_count":len(sorted(set(opportunities))),
    "opportunity_classes":sorted(set(opportunities)),
    "inventory":{
        "sitemap_http":sitemap_http,
        "sitemap_url_count":len(locs),
        "crawled_page_count":len(pages),
        "published_news_count":len(news),
        "published_platform_count":len(platforms),
        "category_count":len(cats),
        "active_category_count":len(active_cats),
        "keyword_map_keyword_count":len(flat),
        "symbolic_primary_target_count":len(symbolic),
    },
    "crawl":{
        "http_error_count":len(http_fail),
        "noindex_count":len(noindex),
        "canonical_mismatch_count":len(canonical_mismatch),
        "orphan_page_count":len(orphan_urls),
        "duplicate_title_group_count":len(dup_titles),
        "duplicate_h1_group_count":len(dup_h1),
    },
    "cms":{
        "active_empty_category_count":len(empty_active),
        "article_body_zero_internal_link_count":len(news_zero_internal),
        "article_body_zero_internal_link_ids":news_zero_internal[:100],
        "categories":category_summary[:100],
    },
    "keyword_map":{
        "existing_targets":existing_target_status,
        "path_target_missing_count":len(path_target_missing),
        "keyword_owner_conflict_count":len(map_keyword_conflicts),
        "same_symbolic_target_multi_keyword_count":len(same_target_multi_keywords),
        "symbolic_target_single_candidate_count":resolved_symbolic_candidates,
        "symbolic_target_no_candidate_count":no_candidate_symbolic,
        "symbolic_target_multi_candidate_count":multi_candidate_symbolic,
        "symbolic_candidates":symbolic_candidates[:120],
    },
    "blocking_item":"NONE",
    "production_writes":False,
    "article_publishing":False,
    "secrets_disclosed":False,
}
with out.open("w",encoding="utf-8") as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True)
    f.write("\n")
PY

echo "SEO_CONTENT_ARCHITECTURE_AUDIT_V1=COMPLETE"
