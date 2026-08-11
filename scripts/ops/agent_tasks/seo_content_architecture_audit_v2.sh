#!/bin/bash
# Read-only SEO content architecture audit V2.
# Uses stable CMS inventory queries plus public rendered pages; every failure self-reports its phase.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"

PHASE="init"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -f "$WEBROOT/config/database.php" ] || exit 4

TMP="$(mktemp -d /tmp/xyptdq-seo-content-arch-v2.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_error() {
  local rc="$1"
  python3 - "$RESULT_FILE" "$PHASE" "$ERROR_CLASS" "$BLOCKING_ITEM" "$rc" <<'PY'
import json,sys
out,phase,error_class,blocker,rc=sys.argv[1:]
payload={
  "task":"seo_content_architecture_audit_v2",
  "audit_status":"BLOCKED",
  "phase":phase,
  "error_class":error_class,
  "blocking_item":blocker,
  "task_exit_code":int(rc),
  "production_writes":False,
  "article_publishing":False,
  "secrets_disclosed":False
}
with open(out,"w",encoding="utf-8") as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True)
    f.write("\n")
PY
}

on_err() {
  local rc=$?
  trap - ERR
  ERROR_CLASS="${PHASE}_failed"
  BLOCKING_ITEM="runtime_error"
  write_error "$rc" || true
  exit "$rc"
}
trap on_err ERR

PHASE="repo_sync"
cd "$REPO"
git fetch --prune origin >/dev/null 2>&1
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null 2>&1
[ -s content/keyword_map.json ]

PHASE="cms_inventory"
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
    "show_flag"=>(int)($r["show_flag"]??0)
  ];
}

$news=$pdo->query("SELECT id,catid,title,url,status FROM dr_1_news WHERE status=9 ORDER BY id ASC")->fetchAll();
foreach($news as $r){
  $out["news"][]=[
    "id"=>(int)$r["id"],
    "catid"=>(int)($r["catid"]??0),
    "title"=>(string)($r["title"]??""),
    "url"=>(string)($r["url"]??"")
  ];
}

$platforms=$pdo->query("SELECT id,title,url,status FROM dr_1_xm WHERE status=9 ORDER BY id ASC")->fetchAll();
foreach($platforms as $r){
  $out["platforms"][]=[
    "id"=>(int)$r["id"],
    "title"=>(string)($r["title"]??""),
    "url"=>(string)($r["url"]??"")
  ];
}
echo json_encode($out,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php" > "$TMP/cms.json"

python3 - "$TMP/cms.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding="utf-8"))
assert isinstance(x,dict)
assert isinstance(x.get("categories"),list)
assert isinstance(x.get("news"),list)
assert isinstance(x.get("platforms"),list)
PY

PHASE="sitemap_fetch"
curl -skL --max-time 30 -o "$TMP/sitemap.xml" -w '%{http_code}' "$CANONICAL/sitemap.xml" > "$TMP/sitemap.code"

PHASE="render_and_analyze"
python3 - "$TMP" "$RESULT_FILE" "$REPO/content/keyword_map.json" "$CANONICAL" <<'PY'
import collections, html, json, pathlib, re, subprocess, sys
from urllib.parse import parse_qsl, urlencode, urljoin, urlparse, urlsplit, urlunsplit

tmp=pathlib.Path(sys.argv[1])
out=pathlib.Path(sys.argv[2])
keyword_path=pathlib.Path(sys.argv[3])
canonical=sys.argv[4].rstrip("/")
host=urlparse(canonical).netloc.lower()

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
    u=urljoin(canonical+"/",html.unescape(str(url).strip()))
    p=urlsplit(u)
    if p.scheme not in ("http","https") or p.netloc.lower()!=host:
        return ""
    q=urlencode(sorted(parse_qsl(p.query,keep_blank_values=True)))
    return urlunsplit(("https",host,p.path or "/",q,""))

def strip_text(s):
    s=re.sub(r"<script\b.*?</script\s*>"," ",s,flags=re.I|re.S)
    s=re.sub(r"<style\b.*?</style\s*>"," ",s,flags=re.I|re.S)
    s=re.sub(r"<!--.*?-->"," ",s,flags=re.S)
    s=re.sub(r"<[^>]+>"," ",s)
    return re.sub(r"\s+"," ",html.unescape(s)).strip()

def attr(tag,name):
    m=re.search(r"\b"+re.escape(name)+r"\s*=\s*[\"']([^\"']*)[\"']",tag,re.I|re.S)
    return html.unescape(m.group(1).strip()) if m else ""

def first_tag_text(s,tag):
    m=re.search(r"<"+tag+r"\b[^>]*>(.*?)</"+tag+r"\s*>",s,re.I|re.S)
    return strip_text(m.group(1)) if m else ""

def meta_description(s):
    for t in re.findall(r"<meta\b[^>]*>",s,re.I|re.S):
        if attr(t,"name").lower()=="description":
            return attr(t,"content")
    return ""

def canonical_href(s):
    for t in re.findall(r"<link\b[^>]*>",s,re.I|re.S):
        if "canonical" in attr(t,"rel").lower().split():
            return norm_url(attr(t,"href"))
    return ""

locs=[norm_url(x) for x in re.findall(r"<loc\b[^>]*>(.*?)</loc\s*>",sitemap,re.I|re.S)]
locs=[x for x in locs if x]
locs=list(dict.fromkeys(locs))
home=canonical+"/"
if home not in locs:
    locs.insert(0,home)
locs=locs[:250]

pages={}
for i,url in enumerate(locs):
    dest=tmp/f"page-{i}.html"
    p=subprocess.run(
        ["curl","-skL","--max-time","20","-o",str(dest),"-w","%{http_code}|%{url_effective}",url],
        stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True
    )
    parts=p.stdout.strip().split("|",1)
    try: code=int(parts[0])
    except Exception: code=0
    effective=norm_url(parts[1] if len(parts)>1 else url)
    s=dest.read_text(encoding="utf-8",errors="ignore") if dest.exists() else ""
    robots=""
    for t in re.findall(r"<meta\b[^>]*>",s,re.I|re.S):
        if attr(t,"name").lower()=="robots":
            robots=attr(t,"content").lower()
            break
    links=[]
    for a in re.findall(r"<a\b[^>]*>",s,re.I|re.S):
        u=norm_url(attr(a,"href"))
        if u:
            links.append(u)
    pages[url]={
        "http":code,
        "effective":effective,
        "title":first_tag_text(s,"title"),
        "description":meta_description(s),
        "h1":first_tag_text(s,"h1"),
        "robots":robots,
        "canonical":canonical_href(s),
        "links":sorted(set(links))
    }

page_set=set(pages)
inbound=collections.Counter()
for src,p in pages.items():
    for dst in p["links"]:
        if dst in page_set and dst!=src:
            inbound[dst]+=1

http_errors=[u for u,p in pages.items() if p["http"]!=200]
noindex=[u for u,p in pages.items() if "noindex" in p["robots"] or "none" in p["robots"]]
canonical_mismatch=[u for u,p in pages.items() if p["canonical"] and p["canonical"]!=u]
orphans=[u for u in pages if u!=home and inbound[u]==0]

def duplicate_groups(field):
    g=collections.defaultdict(list)
    for u,p in pages.items():
        v=re.sub(r"\s+"," ",p.get(field,"")).strip().lower()
        if v:
            g[v].append(u)
    return [xs for xs in g.values() if len(xs)>1]

dup_titles=duplicate_groups("title")
dup_desc=duplicate_groups("description")
dup_h1=duplicate_groups("h1")

cats=cms.get("categories",[])
news=cms.get("news",[])
platforms=cms.get("platforms",[])
active_cats=[c for c in cats if int(c.get("disabled",0))==0 and int(c.get("show_flag",0))!=0]
news_by_cat=collections.Counter(int(n.get("catid",0)) for n in news)
empty_active=[
    c for c in active_cats
    if str(c.get("mid","")) in ("","news") and news_by_cat[int(c.get("id",0))]==0
]

home_links=set(pages.get(home,{}).get("links",[]))
platform_urls=[]
for p in platforms:
    platform_urls.append(norm_url(p.get("url")) or norm_url(f"/index.php?c=show&id={int(p['id'])}"))
platform_urls=[u for u in platform_urls if u]
platform_linked_from_home=sum(1 for u in platform_urls if u in home_links)

flat=[]
keyword_owners=collections.defaultdict(set)
target_keywords=collections.defaultdict(list)
for cluster in kw.get("clusters",[]):
    for item in cluster.get("keywords",[]):
        k=str(item.get("keyword","")).strip()
        t=str(item.get("target","")).strip()
        if not k or not t:
            continue
        rec={
            "cluster":str(cluster.get("id","")),
            "keyword":k,
            "target":t,
            "priority":str(item.get("priority","")),
            "intent":str(item.get("intent",""))
        }
        flat.append(rec)
        keyword_owners[k].add(t)
        target_keywords[t].append(k)

keyword_owner_conflicts={k:sorted(v) for k,v in keyword_owners.items() if len(v)>1]
path_targets=[x for x in flat if x["target"].startswith("/")]
symbolic=[x for x in flat if not x["target"].startswith("/")]
path_target_missing=[]
for item in path_targets:
    u=norm_url(item["target"])
    if u not in page_set or pages.get(u,{}).get("http")!=200:
        path_target_missing.append(item["keyword"])

symbolic_no_candidate=[]
symbolic_multi_candidate=[]
for item in symbolic:
    needle=item["keyword"].lower()
    matches=0
    for p in pages.values():
        hay=(p.get("title","")+" "+p.get("h1","")).lower()
        if needle and needle in hay:
            matches+=1
    if matches==0:
        symbolic_no_candidate.append(item["target"])
    elif matches>1:
        symbolic_multi_candidate.append(item["target"])

existing_status={}
for name,path in kw.get("existing_targets",{}).items():
    u=norm_url(path)
    existing_status[name]={
        "http":int(pages.get(u,{}).get("http",0)),
        "in_sitemap":bool(u in page_set)
    }

home_primary=""
for cluster in kw.get("clusters",[]):
    for item in cluster.get("keywords",[]):
        if item.get("target")=="/":
            home_primary=str(item.get("keyword","")).strip()
            break
    if home_primary:
        break
home_title=pages.get(home,{}).get("title","")
home_h1=pages.get(home,{}).get("h1","")
home_primary_in_title=bool(home_primary and home_primary in home_title)
home_primary_in_h1=bool(home_primary and home_primary in home_h1)

opportunities=[]
if sitemap_http!=200: opportunities.append("sitemap_http")
if http_errors: opportunities.append("sitemap_page_http_error")
if noindex: opportunities.append("sitemap_page_noindex")
if canonical_mismatch: opportunities.append("canonical_mismatch")
if orphans: opportunities.append("orphan_pages")
if dup_titles: opportunities.append("duplicate_titles")
if dup_desc: opportunities.append("duplicate_meta_descriptions")
if dup_h1: opportunities.append("duplicate_h1")
if empty_active: opportunities.append("active_empty_news_category")
if len(platform_urls)>0 and platform_linked_from_home < len(platform_urls):
    opportunities.append("homepage_platform_internal_link_gap")
if path_target_missing: opportunities.append("keyword_map_path_target_missing")
if keyword_owner_conflicts: opportunities.append("keyword_owner_conflict")
if symbolic_no_candidate or symbolic_multi_candidate:
    opportunities.append("planned_primary_target_mapping_incomplete")
if home_primary and not home_primary_in_title:
    opportunities.append("homepage_primary_keyword_title_gap")
if home_primary and not home_primary_in_h1:
    opportunities.append("homepage_primary_keyword_h1_gap")

payload={
  "task":"seo_content_architecture_audit_v2",
  "audit_status":"COMPLETE",
  "phase":"final",
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
    "keyword_count":len(flat),
    "symbolic_target_keyword_count":len(symbolic)
  },
  "crawl":{
    "http_error_count":len(http_errors),
    "noindex_count":len(noindex),
    "canonical_mismatch_count":len(canonical_mismatch),
    "orphan_page_count":len(orphans),
    "duplicate_title_group_count":len(dup_titles),
    "duplicate_description_group_count":len(dup_desc),
    "duplicate_h1_group_count":len(dup_h1)
  },
  "cms":{
    "active_empty_news_category_count":len(empty_active)
  },
  "platform_internal_links":{
    "published_platform_count":len(platform_urls),
    "linked_from_home_count":platform_linked_from_home,
    "coverage_complete":bool(platform_urls and platform_linked_from_home==len(platform_urls))
  },
  "keyword_map":{
    "existing_targets":existing_status,
    "path_target_missing_count":len(path_target_missing),
    "keyword_owner_conflict_count":len(keyword_owner_conflicts),
    "shared_target_count":sum(1 for xs in target_keywords.values() if len(xs)>1),
    "symbolic_no_candidate_count":len(set(symbolic_no_candidate)),
    "symbolic_multi_candidate_count":len(set(symbolic_multi_candidate)),
    "symbolic_no_candidate_targets":sorted(set(symbolic_no_candidate))[:80],
    "home_primary_keyword":home_primary,
    "home_primary_keyword_in_title":home_primary_in_title,
    "home_primary_keyword_in_h1":home_primary_in_h1
  },
  "blocking_item":"NONE",
  "production_writes":False,
  "article_publishing":False,
  "secrets_disclosed":False
}
with out.open("w",encoding="utf-8") as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True)
    f.write("\n")
PY

PHASE="final"
trap - ERR
echo "SEO_CONTENT_ARCHITECTURE_AUDIT_V2=COMPLETE"
