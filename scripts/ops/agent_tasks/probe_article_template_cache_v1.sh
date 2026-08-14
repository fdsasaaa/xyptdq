#!/bin/bash
# Read-only probe for compiled/cached show-template artifacts. No mutation.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$WEBROOT" ] || exit 3
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
python3 - "$WEBROOT" "$TMP" <<'PY'
import hashlib,json,os,pathlib,sys,time
root=pathlib.Path(sys.argv[1]); out=pathlib.Path(sys.argv[2]); cache=root/'cache'
needles=(b'xyptdq-page-title',b'mobile-related-heading',b'fc-content-tool')
rows=[]
if cache.is_dir():
  for p in cache.rglob('*'):
    if not p.is_file(): continue
    try:
      if p.stat().st_size>5_000_000: continue
      b=p.read_bytes()
    except Exception: continue
    hits=[n.decode() for n in needles if n in b]
    if not hits: continue
    rows.append({'path':str(p.relative_to(root)),'size':len(b),'mtime':int(p.stat().st_mtime),'sha256':hashlib.sha256(b).hexdigest(),'markers':hits,'has_new_article_style':b'xyptdq-article-prose' in b})
rows=sorted(rows,key=lambda x:x['mtime'],reverse=True)[:40]
prod={}
for rel in ('template/pc/default/home/show.html','template/mobile/default/home/show.html'):
 p=root/rel
 if p.is_file():
  b=p.read_bytes(); prod[rel]={'sha256':hashlib.sha256(b).hexdigest(),'has_new_article_style':b'xyptdq-article-prose' in b,'mtime':int(p.stat().st_mtime)}
json.dump({'status':'PASS','read_only':True,'production_templates':prod,'candidate_cache_files':rows,'candidate_count':len(rows),'cache_root_exists':cache.is_dir()},out.open('w'),ensure_ascii=False,indent=2)
PY
python3 - "$RESULT_FILE" "$TMP" <<'PY'
import json,sys
x=json.load(open(sys.argv[2])); x.update({'task':'probe_article_template_cache_v1','cms_write_attempted':False,'cache_mutated':False,'templates_mutated':False})
json.dump(x,open(sys.argv[1],'w'),ensure_ascii=False,indent=2); open(sys.argv[1],'a').write('\n')
PY
echo PROBE_ARTICLE_TEMPLATE_CACHE_V1=PASS
