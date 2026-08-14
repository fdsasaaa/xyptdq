#!/bin/bash
# Read-only probe for which show template/cache the mobile request actually renders.
# Safety boundary: metadata/marker inspection only; never returns article body or mutates production.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
URL="https://www.laocaimi.org/index.php?c=show&id=92"
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$WEBROOT" ] || exit 3
TMP=$(mktemp -d /tmp/xyptdq-mobile-render-probe.XXXXXX); trap 'rm -rf "$TMP"' EXIT
HTTP=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mobile.html" -w '%{http_code}' "$URL" || true)
python3 - "$WEBROOT" "$TMP/mobile.html" "$RESULT_FILE" "$HTTP" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); htmlp=pathlib.Path(sys.argv[2]); out=pathlib.Path(sys.argv[3]); http=int(sys.argv[4] or 0)
b=htmlp.read_bytes() if htmlp.is_file() else b''
render={
 'http':http,
 'pc_shell': b'xyptdq-site-header' in b,
 'mobile_shell': b'hui-header' in b,
 'pc_content_wrapper': b'xyptdq-content xyptdq-article-prose' in b,
 'mobile_content_wrapper': b'xrcontent xyptdq-article-prose' in b,
 'any_article_style_css': b'.xyptdq-article-prose' in b,
 'pc_related_marker': b'related-heading' in b,
 'mobile_related_marker': b'mobile-related-heading' in b,
}
needles=(b'hui-header',b'mobile-related-heading',b'fc-content-tool',b'xrcontent',b'xyptdq-article-prose')
rows=[]; cache=root/'cache'
if cache.is_dir():
 for p in cache.rglob('*'):
  if not p.is_file(): continue
  try:
   if p.stat().st_size>5_000_000: continue
   data=p.read_bytes()
  except Exception: continue
  hits=[n.decode() for n in needles if n in data]
  if not hits: continue
  rows.append({'path':str(p.relative_to(root)),'size':len(data),'mtime':int(p.stat().st_mtime),'sha256':hashlib.sha256(data).hexdigest(),'markers':hits,'has_new_article_style':b'xyptdq-article-prose' in data})
rows=sorted(rows,key=lambda x:x['mtime'],reverse=True)[:60]
prod={}
for rel in ('template/pc/default/home/show.html','template/mobile/default/home/show.html'):
 p=root/rel
 if p.is_file():
  data=p.read_bytes(); prod[rel]={'sha256':hashlib.sha256(data).hexdigest(),'has_new_article_style':b'xyptdq-article-prose' in data,'mtime':int(p.stat().st_mtime)}
payload={'task':'probe_mobile_article_render_cache_v1','status':'PASS','read_only':True,'mobile_render':render,'candidate_cache_files':rows,'candidate_count':len(rows),'production_templates':prod,'cache_mutated':False,'templates_mutated':False,'cms_write_attempted':False,'article_body_returned':False}
json.dump(payload,out.open('w'),ensure_ascii=False,indent=2); out.open('a').write('\n')
PY
echo PROBE_MOBILE_ARTICLE_RENDER_CACHE_V1=PASS
