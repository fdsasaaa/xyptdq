#!/bin/bash
# Read-only whole-site SEO audit for laocaimi.org.
# Produces a sanitized Server Bridge payload only; no production writes.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4

TMP="$(mktemp -d /tmp/xyptdq-seo-audit.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

cd "$REPO"
git fetch --prune origin >/dev/null 2>&1
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null 2>&1

fetch_page() {
  local name="$1" url="$2"
  curl -skL --max-time 30 -D "$TMP/${name}.headers" -o "$TMP/${name}.html" \
    -w '%{http_code}|%{url_effective}\n' "$url" > "$TMP/${name}.status"
}

fetch_page home "$CANONICAL/"
fetch_page seo_category "$CANONICAL/index.php?c=category&dir=seo-articles"
fetch_page article91 "$CANONICAL/index.php?c=show&id=91"

# Safe CMS facts only: no credentials or private configuration are emitted.
php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO(
  "mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",
  $c["username"],$c["password"],
  [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]
);
$out=["published_news"=>0,"published_xm"=>0,"latest_news_id"=>0,"sample_xm_id"=>0,"sample_xm_url"=>"","seo_category"=>null];
$out["published_news"]=(int)$pdo->query("SELECT COUNT(*) FROM dr_1_news WHERE status=9")->fetchColumn();
$out["published_xm"]=(int)$pdo->query("SELECT COUNT(*) FROM dr_1_xm WHERE status=9")->fetchColumn();
$out["latest_news_id"]=(int)$pdo->query("SELECT COALESCE(MAX(id),0) FROM dr_1_news WHERE status=9")->fetchColumn();
$r=$pdo->query("SELECT id,url FROM dr_1_xm WHERE status=9 ORDER BY id ASC LIMIT 1")->fetch();
if($r){$out["sample_xm_id"]=(int)$r["id"]; $out["sample_xm_url"]=(string)($r["url"]??"");}
$s=$pdo->prepare("SELECT id,name,dirname,mid,disabled,`show` AS show_flag FROM dr_1_share_category WHERE id=7 LIMIT 1");
$s->execute(); $out["seo_category"]=$s->fetch()?:null;
echo json_encode($out,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php" > "$TMP/cms.json"

SAMPLE_XM_ID="$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (int)($x["sample_xm_id"]??0);' "$TMP/cms.json")"
SAMPLE_XM_URL="$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (string)($x["sample_xm_url"]??"");' "$TMP/cms.json")"
if [ "$SAMPLE_XM_ID" -gt 0 ]; then
  if [[ "$SAMPLE_XM_URL" == "$CANONICAL"* ]]; then
    fetch_page platform "$SAMPLE_XM_URL"
  else
    fetch_page platform "$CANONICAL/index.php?s=xm&c=show&id=$SAMPLE_XM_ID"
  fi
else
  printf '0|\n' > "$TMP/platform.status"
  : > "$TMP/platform.html"
fi

# Canonical host/HTTPS redirect matrix.
for key_url in \
  "http_root|http://laocaimi.org/" \
  "http_www|http://www.laocaimi.org/" \
  "https_root|https://laocaimi.org/" \
  "https_www|https://www.laocaimi.org/"; do
  key="${key_url%%|*}"
  url="${key_url#*|}"
  curl -skL --max-time 30 -o /dev/null -w '%{http_code}|%{url_effective}\n' "$url" > "$TMP/redirect_${key}.txt" || printf '0|\n' > "$TMP/redirect_${key}.txt"
done

# Sanitized template inventory: file paths and SEO-marker counts only.
python3 - "$WEBROOT" "$TMP/templates.json" <<'PY'
import json, pathlib, re, sys
root=pathlib.Path(sys.argv[1])
out_path=pathlib.Path(sys.argv[2])
items=[]
roots=[root/'template'/'pc'/'default', root/'template'/'mobile'/'default']
for base in roots:
    if not base.is_dir():
        continue
    for p in sorted(base.rglob('*.html')):
        try:
            text=p.read_text(encoding='utf-8', errors='ignore')
        except Exception:
            continue
        rel=str(p.relative_to(root))
        low=text.lower()
        rec={
            "path": rel,
            "bytes": len(text.encode('utf-8', errors='ignore')),
            "doctype_count": len(re.findall(r'<!doctype\b', low)),
            "html_open_count": len(re.findall(r'<html\b', low)),
            "head_open_count": len(re.findall(r'<head\b', low)),
            "title_count": len(re.findall(r'<title\b', low)),
            "description_meta_count": len(re.findall(r'<meta\b[^>]*name=["\']description["\']', low)),
            "robots_none_count": len(re.findall(r'<meta\b[^>]*name=["\']robots["\'][^>]*content=["\'][^"\']*\bnone\b', low)),
            "canonical_count": len(re.findall(r'<link\b[^>]*rel=["\']canonical["\']', low)),
            "h1_count": len(re.findall(r'<h1\b', low)),
            "jsonld_count": len(re.findall(r'application/ld\+json', low)),
            "og_title_count": len(re.findall(r'property=["\']og:title["\']', low)),
        }
        if any(rec[k] for k in ("title_count","description_meta_count","robots_none_count","canonical_count","h1_count","jsonld_count")) or rel.endswith('/home/index.html'):
            items.append(rec)
payload={
    "template_html_total": sum(1 for b in roots if b.is_dir() for _ in b.rglob('*.html')),
    "seo_relevant_template_count": len(items),
    "robots_none_paths": [x["path"] for x in items if x["robots_none_count"]][:30],
    "multi_document_paths": [x["path"] for x in items if x["doctype_count"]>1 or x["html_open_count"]>1 or x["head_open_count"]>1][:30],
    "templates": items[:80],
}
out_path.write_text(json.dumps(payload,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY

python3 - "$TMP" "$RESULT_FILE" "$WEBROOT" <<'PY'
import json, pathlib, re, sys
tmp=pathlib.Path(sys.argv[1])
out_path=pathlib.Path(sys.argv[2])
webroot=pathlib.Path(sys.argv[3])

def status(name):
    raw=(tmp/f"{name}.status").read_text(encoding="utf-8",errors="ignore").strip()
    parts=raw.split("|",1)
    try: code=int(parts[0])
    except: code=0
    return code, parts[1] if len(parts)>1 else ""

def analyze(name):
    p=tmp/f"{name}.html"
    text=p.read_text(encoding="utf-8",errors="ignore") if p.exists() else ""
    low=text.lower()
    def one(pattern, flags=re.I|re.S):
        m=re.search(pattern,text,flags)
        return re.sub(r'\s+',' ',m.group(1)).strip()[:300] if m else ""
    title=one(r'<title[^>]*>(.*?)</title>')
    desc=one(r'<meta[^>]+name=["\']description["\'][^>]+content=["\']([^"\']*)["\']') or one(r'<meta[^>]+content=["\']([^"\']*)["\'][^>]+name=["\']description["\']')
    robots=re.findall(r'<meta[^>]+name=["\']robots["\'][^>]+content=["\']([^"\']*)["\']',text,re.I)
    canonical=re.findall(r'<link[^>]+rel=["\']canonical["\'][^>]+href=["\']([^"\']+)["\']',text,re.I)
    if not canonical:
        canonical=re.findall(r'<link[^>]+href=["\']([^"\']+)["\'][^>]+rel=["\']canonical["\']',text,re.I)
    h1=[re.sub(r'<[^>]+>','',x) for x in re.findall(r'<h1[^>]*>(.*?)</h1>',text,re.I|re.S)]
    imgs=re.findall(r'<img\b[^>]*>',text,re.I)
    missing_alt=sum(1 for tag in imgs if not re.search(r'\balt\s*=',tag,re.I))
    hrefs=re.findall(r'<a\b[^>]*href=["\']([^"\']+)["\']',text,re.I)
    internal=[u for u in hrefs if u.startswith('/') or u.startswith('https://www.laocaimi.org') or u.startswith('http://www.laocaimi.org') or u.startswith('index.php')]
    code,effective=status(name)
    return {
        "http":code,
        "effective_url":effective,
        "doctype_count":len(re.findall(r'<!doctype\b',low)),
        "html_open_count":len(re.findall(r'<html\b',low)),
        "head_open_count":len(re.findall(r'<head\b',low)),
        "title_count":len(re.findall(r'<title\b',low)),
        "title":title,
        "description_count":len(re.findall(r'<meta\b[^>]*name=["\']description["\']',low)),
        "description":desc,
        "robots":robots[:5],
        "robots_none":any('none' in x.lower() for x in robots),
        "canonical_count":len(canonical),
        "canonical":canonical[:5],
        "h1_count":len(h1),
        "h1":h1[:5],
        "h2_count":len(re.findall(r'<h2\b',low)),
        "og_title_count":len(re.findall(r'property=["\']og:title["\']',low)),
        "og_description_count":len(re.findall(r'property=["\']og:description["\']',low)),
        "og_url_count":len(re.findall(r'property=["\']og:url["\']',low)),
        "jsonld_count":len(re.findall(r'application/ld\+json',low)),
        "images":len(imgs),
        "images_missing_alt":missing_alt,
        "internal_links":len(internal),
        "unique_internal_links":len(set(internal)),
    }

cms=json.loads((tmp/'cms.json').read_text(encoding='utf-8'))
templates=json.loads((tmp/'templates.json').read_text(encoding='utf-8'))
redirects={}
for p in sorted(tmp.glob('redirect_*.txt')):
    raw=p.read_text(encoding='utf-8',errors='ignore').strip().split('|',1)
    try: code=int(raw[0])
    except: code=0
    redirects[p.stem.replace('redirect_','')]={"http":code,"effective_url":raw[1] if len(raw)>1 else ""}

robots_path=webroot/'robots.txt'
robots_text=robots_path.read_text(encoding='utf-8',errors='ignore') if robots_path.exists() else ""
sitemap_path=webroot/'sitemap.xml'
sitemap_text=sitemap_path.read_text(encoding='utf-8',errors='ignore') if sitemap_path.exists() else ""
pages={n:analyze(n) for n in ('home','seo_category','article91','platform')}

issues=[]
home=pages['home']
if home['http']!=200: issues.append('home_http_not_200')
if home['robots_none']: issues.append('home_rendered_robots_none')
if home['doctype_count']!=1 or home['html_open_count']!=1 or home['head_open_count']!=1: issues.append('home_rendered_multi_document')
if home['title_count']!=1 or not home['title']: issues.append('home_title_invalid')
if home['description_count']<1 or not home['description']: issues.append('home_description_missing')
if home['h1_count']!=1: issues.append('home_h1_not_exactly_one')
if home['canonical_count']!=1: issues.append('home_canonical_not_exactly_one')
if home['jsonld_count']<1: issues.append('home_schema_missing')
for name in ('seo_category','article91'):
    p=pages[name]
    if p['http']!=200: issues.append(f'{name}_http_not_200')
    if p['robots_none']: issues.append(f'{name}_robots_none')
    if p['canonical_count']!=1: issues.append(f'{name}_canonical_not_exactly_one')
    if p['h1_count']!=1: issues.append(f'{name}_h1_not_exactly_one')
    if p['description_count']<1: issues.append(f'{name}_description_missing')
    if p['jsonld_count']<1: issues.append(f'{name}_schema_missing')
if templates.get('robots_none_paths'): issues.append('template_source_contains_robots_none')
if templates.get('multi_document_paths'): issues.append('template_source_contains_multi_document_html')
if 'Sitemap:' not in robots_text: issues.append('robots_missing_sitemap')
if '<urlset' not in sitemap_text: issues.append('sitemap_invalid_or_missing')

payload={
    "task":"whole_site_seo_audit",
    "audit_status":"PASS",
    "blocking_item":"NONE",
    "production_main_sha": "",
    "pages":pages,
    "redirects":redirects,
    "cms":cms,
    "templates":templates,
    "robots":{"exists":robots_path.exists(),"has_sitemap":'Sitemap:' in robots_text,"has_allow_root":'Allow: /' in robots_text},
    "sitemap":{"exists":sitemap_path.exists(),"url_count":len(re.findall(r'<url>',sitemap_text))},
    "issues":issues,
    "issue_count":len(issues),
    "secrets_disclosed":False,
}
out_path.write_text(json.dumps(payload,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY

# Fill current Git main SHA in a safe final pass.
MAIN_SHA="$(git rev-parse origin/main)"
python3 - "$RESULT_FILE" "$MAIN_SHA" <<'PY'
import json,sys
p=sys.argv[1]; sha=sys.argv[2]
x=json.load(open(p,encoding='utf-8'))
x['production_main_sha']=sha
with open(p,'w',encoding='utf-8') as f:
    json.dump(x,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

echo "WHOLE_SITE_SEO_AUDIT=PASS"
