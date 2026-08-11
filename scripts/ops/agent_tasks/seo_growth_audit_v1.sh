#!/bin/bash
# Read-only SEO growth audit: content depth, internal linking, image semantics,
# commercial-link attributes, and sitemap breadth. No production changes.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
CANONICAL="https://www.laocaimi.org"
[ -n "$RESULT_FILE" ] || exit 2

TMP="$(mktemp -d /tmp/xyptdq-seo-growth.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fetch() {
  local name="$1" url="$2"
  curl -skL --max-time 30 -o "$TMP/$name.html" -w '%{http_code}' "$url" > "$TMP/$name.code"
}

fetch home "$CANONICAL/"
fetch category "$CANONICAL/index.php?c=category&id=7"
fetch article "$CANONICAL/index.php?c=show&id=91"
fetch platform "$CANONICAL/index.php?c=show&id=19"
fetch sitemap "$CANONICAL/sitemap.xml"

python3 - "$TMP" "$RESULT_FILE" "$CANONICAL" <<'PY'
import html, json, pathlib, re, sys
from urllib.parse import urlparse

tmp = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
canonical = sys.argv[3]
host = urlparse(canonical).netloc.lower()

def code(name):
    try: return int((tmp/f"{name}.code").read_text().strip())
    except Exception: return 0

def text(name):
    try: return (tmp/f"{name}.html").read_text(encoding="utf-8",errors="ignore")
    except Exception: return ""

def tags(s, name):
    return re.findall(r"<"+name+r"\b[^>]*>", s, re.I|re.S)

def attr(tag, name):
    m=re.search(r"\b"+re.escape(name)+r"=[\"']([^\"']*)[\"']", tag, re.I|re.S)
    return html.unescape(m.group(1).strip()) if m else ""

def visible_text(s):
    s=re.sub(r"<script\b.*?</script\s*>"," ",s,flags=re.I|re.S)
    s=re.sub(r"<style\b.*?</style\s*>"," ",s,flags=re.I|re.S)
    s=re.sub(r"<!--.*?-->"," ",s,flags=re.S)
    s=re.sub(r"<[^>]+>"," ",s)
    s=html.unescape(s)
    s=re.sub(r"\s+"," ",s).strip()
    return s

def page_metrics(name):
    s=text(name)
    title_m=re.search(r"<title\b[^>]*>(.*?)</title\s*>",s,re.I|re.S)
    title=html.unescape(re.sub(r"<[^>]+>","",title_m.group(1))).strip() if title_m else ""
    desc=""
    for t in tags(s,"meta"):
        if attr(t,"name").lower()=="description":
            desc=attr(t,"content"); break
    links=tags(s,"a")
    internal=set(); external=[]
    commercial_unqualified=0
    for a in links:
        href=attr(a,"href")
        if not href or href.startswith(("#","javascript:","mailto:","tel:")): continue
        rel=set(attr(a,"rel").lower().split())
        p=urlparse(href)
        if not p.netloc or p.netloc.lower()==host:
            internal.add(href)
        else:
            external.append(href)
            if not ({"nofollow","sponsored"} & rel):
                commercial_unqualified += 1
    imgs=tags(s,"img")
    missing_alt=sum(1 for i in imgs if not attr(i,"alt"))
    missing_dimensions=sum(1 for i in imgs if not attr(i,"width") or not attr(i,"height"))
    lazy=sum(1 for i in imgs if attr(i,"loading").lower()=="lazy")
    headings={h:len(re.findall(r"<"+h+r"\b",s,re.I)) for h in ("h1","h2","h3")}
    body_chars=len(re.sub(r"\s+","",visible_text(s)))
    return {
        "http":code(name),
        "title_chars":len(title),
        "description_chars":len(desc),
        "visible_text_chars":body_chars,
        "h1_count":headings["h1"],
        "h2_count":headings["h2"],
        "h3_count":headings["h3"],
        "internal_link_count":len(internal),
        "external_link_count":len(external),
        "external_links_without_nofollow_or_sponsored":commercial_unqualified,
        "image_count":len(imgs),
        "images_missing_alt":missing_alt,
        "images_missing_width_or_height":missing_dimensions,
        "images_lazy":lazy,
    }

metrics={name:page_metrics(name) for name in ("home","category","article","platform")}
opportunities=[]

for name,m in metrics.items():
    if m["http"]!=200: opportunities.append(f"{name}_http")
    if m["title_chars"]<8: opportunities.append(f"{name}_title_too_short")
    if m["description_chars"]<30: opportunities.append(f"{name}_description_thin")
    if m["images_missing_alt"]>0: opportunities.append(f"{name}_image_alt")
    if m["images_missing_width_or_height"]>0: opportunities.append(f"{name}_image_dimensions")
    if m["external_links_without_nofollow_or_sponsored"]>0:
        opportunities.append(f"{name}_external_link_rel")

if metrics["home"]["internal_link_count"]<5:
    opportunities.append("home_internal_link_depth")
if metrics["category"]["internal_link_count"]<3:
    opportunities.append("category_internal_link_depth")
if metrics["article"]["visible_text_chars"]<500:
    opportunities.append("article_content_depth")
if metrics["article"]["h2_count"]<1:
    opportunities.append("article_heading_structure")
if metrics["platform"]["visible_text_chars"]<300:
    opportunities.append("platform_content_depth")

sitemap=text("sitemap")
locs=[html.unescape(x.strip()) for x in re.findall(r"<loc\b[^>]*>(.*?)</loc\s*>",sitemap,re.I|re.S)]
duplicates=len(locs)-len(set(locs))
noncanonical=sum(1 for u in locs if urlparse(u).netloc.lower()!=host)
if code("sitemap")!=200: opportunities.append("sitemap_http")
if duplicates: opportunities.append("sitemap_duplicates")
if noncanonical: opportunities.append("sitemap_noncanonical_hosts")
if len(locs)<5: opportunities.append("sitemap_breadth")

payload={
  "task":"seo_growth_audit_v1",
  "audit_status":"COMPLETE",
  "opportunity_count":len(sorted(set(opportunities))),
  "opportunity_classes":sorted(set(opportunities)),
  "home":metrics["home"],
  "category7":metrics["category"],
  "article91":metrics["article"],
  "platform19":metrics["platform"],
  "sitemap_http":code("sitemap"),
  "sitemap_url_count":len(locs),
  "sitemap_duplicate_count":duplicates,
  "sitemap_noncanonical_host_count":noncanonical,
  "blocking_item":"NONE",
  "secrets_disclosed":False
}
with out.open("w",encoding="utf-8") as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True)
    f.write("\n")
PY

echo "SEO_GROWTH_AUDIT_V1=COMPLETE"
