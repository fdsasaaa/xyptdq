#!/bin/bash
# Read-only probe for stylesheet URLs and matching production files used by article 92.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
URL="https://www.laocaimi.org/index.php?c=show&id=92"
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$WEBROOT" ] || exit 3
TMP=$(mktemp -d /tmp/xyptdq-css-probe.XXXXXX); trap 'rm -rf "$TMP"' EXIT
HTTP=$(curl -skL --max-time 25 -o "$TMP/page.html" -w '%{http_code}' "$URL" || true)
python3 - "$WEBROOT" "$TMP/page.html" "$RESULT_FILE" "$HTTP" <<'PY'
import hashlib,html,json,pathlib,re,sys,urllib.parse
root=pathlib.Path(sys.argv[1]); page=pathlib.Path(sys.argv[2]); out=pathlib.Path(sys.argv[3]); http=int(sys.argv[4] or 0)
s=page.read_text(encoding='utf-8',errors='ignore') if page.is_file() else ''
hrefs=[]
for tag in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
 def attr(name):
  m=re.search(r'\b'+re.escape(name)+r'\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S); return html.unescape(m.group(1).strip()) if m else ''
 if 'stylesheet' in attr('rel').lower().split():
  h=attr('href')
  if h: hrefs.append(h)
rows=[]
for href in hrefs:
 path=urllib.parse.urlparse(href).path
 base=pathlib.PurePosixPath(path).name
 matches=[]
 if base:
  for p in root.rglob(base):
   if not p.is_file(): continue
   try: data=p.read_bytes()
   except Exception: continue
   matches.append({'path':str(p.relative_to(root)),'size':len(data),'sha256':hashlib.sha256(data).hexdigest(),'mtime':int(p.stat().st_mtime)})
 rows.append({'href':href,'url_path':path,'basename':base,'production_matches':matches[:20]})
payload={'task':'probe_live_article_css_assets_v1','status':'PASS','read_only':True,'http':http,'stylesheets':rows,'stylesheet_count':len(rows),'page_body_returned':False,'files_mutated':False,'cms_write_attempted':False,'cron_mutated':False}
json.dump(payload,out.open('w'),ensure_ascii=False,indent=2); out.open('a').write('\n')
PY
echo PROBE_LIVE_ARTICLE_CSS_ASSETS_V1=PASS
