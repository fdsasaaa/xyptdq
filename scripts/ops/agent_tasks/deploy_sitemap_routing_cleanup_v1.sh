#!/bin/bash
# Safely regenerate production sitemap after routing/canonical cleanup.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="df18a4a6339f9c84a3d9fc14bc83eb812aac4bcd"
SITEMAP="$WEBROOT/sitemap.xml"

PHASE="init"
DEPLOY="NO"
ROLLBACK="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"
TMP="$(mktemp -d /tmp/xyptdq-sitemap-cleanup.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -f "$WEBROOT/config/database.php" ] || exit 4

write_payload(){
  local status="$1" metrics="${2:-$TMP/metrics.json}"
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$ROLLBACK" "$ERROR_CLASS" "$BLOCKING_ITEM" "$metrics" <<'PY'
import json,os,sys
out,status,phase,target,deploy,rollback,error_class,blocker,metrics_path=sys.argv[1:]
metrics={}
if os.path.isfile(metrics_path):
    try: metrics=json.load(open(metrics_path,encoding='utf-8'))
    except Exception: metrics={}
payload={
  'task':'deploy_sitemap_routing_cleanup_v1','deployment_status':status,'phase':phase,
  'target_sha':target,'deploy':deploy,'rollback':rollback,'deploy_error_class':error_class,
  'blocking_item':blocker,'article_publishing_attempted':False,'secrets_disclosed':False,
  **metrics
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}

rollback_sitemap(){
  set +e
  if [ -f "$TMP/sitemap.before.xml" ]; then
    cp -a "$TMP/sitemap.before.xml" "$SITEMAP"
    chmod 0644 "$SITEMAP" 2>/dev/null || true
    ROLLBACK="YES"
  fi
  set -e
}
block(){
  BLOCKING_ITEM="$1"
  if [ "$DEPLOY" = "PASS" ]; then rollback_sitemap; fi
  write_payload BLOCKED
  echo "[sitemap-cleanup] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
  exit 1
}

cd "$REPO"
PHASE="repo_sync"
git fetch --prune origin >/dev/null 2>&1
git merge-base --is-ancestor "$TARGET_SHA" origin/main || { ERROR_CLASS="target_not_in_main"; block target_not_in_main; }

PHASE="source_verify"
git show "$TARGET_SHA:scripts/seo/generate_sitemap.php" > "$TMP/generate_sitemap.php" || { ERROR_CLASS="generator_missing"; block generator_missing; }
php -l "$TMP/generate_sitemap.php" >/dev/null || { ERROR_CLASS="generator_php_invalid"; block generator_php_invalid; }
grep -Fq 'c.mid =' "$TMP/generate_sitemap.php" || { ERROR_CLASS="news_category_module_filter_missing"; block news_category_module_filter_missing; }
grep -Fq 'AND EXISTS (SELECT 1 FROM' "$TMP/generate_sitemap.php" || { ERROR_CLASS="nonempty_news_category_filter_missing"; block nonempty_news_category_filter_missing; }
grep -Fq 'INNER JOIN' "$TMP/generate_sitemap.php" || { ERROR_CLASS="shared_index_filter_missing"; block shared_index_filter_missing; }

PHASE="canonical_prerequisite"
python3 - "$CANONICAL" <<'PY'
import html,re,subprocess,sys
base=sys.argv[1]
def attr(tag,name):
    m=re.search(r'\b'+re.escape(name)+r'\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    return html.unescape(m.group(1)).strip() if m else ''
def canonical(s):
    for tag in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
        if 'canonical' in attr(tag,'rel').lower().split(): return attr(tag,'href')
    return ''
for d in ['gjfa','seo-articles','tzjq','zyyy']:
    url=f'{base}/index.php?c=category&dir={d}'
    p=subprocess.run(['curl','-skL','--max-time','20','-o','-','-w','\n%{http_code}',url],stdout=subprocess.PIPE,text=True)
    body,code=p.stdout.rsplit('\n',1)
    if code!='200' or canonical(body)!=url:
        raise SystemExit(f'canonical_prerequisite_failed:{d}:{code}:{canonical(body)}')
PY

PHASE="generate_candidate"
XYPTDQ_WEBROOT="$WEBROOT" \
XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" \
XYPTDQ_CANONICAL="$CANONICAL" \
XYPTDQ_SITEMAP="$TMP/generated.xml" \
php "$TMP/generate_sitemap.php" >"$TMP/generate.log" 2>&1 || { ERROR_CLASS="candidate_generation_failed"; block candidate_generation_failed; }
[ -s "$TMP/generated.xml" ] || { ERROR_CLASS="candidate_empty"; block candidate_empty; }

PHASE="candidate_verify"
python3 - "$TMP/generated.xml" "$CANONICAL" <<'PY' > "$TMP/metrics.json"
import concurrent.futures,html,json,re,subprocess,sys,xml.etree.ElementTree as ET
from urllib.parse import urlparse
path,base=sys.argv[1:]
root=ET.parse(path).getroot()
locs=[]
for el in root.iter():
    if el.tag.endswith('loc') and el.text:
        locs.append(html.unescape(el.text.strip()))
if len(locs)!=len(set(locs)): raise SystemExit('duplicate_sitemap_urls')
if not (60 <= len(locs) <= 75): raise SystemExit(f'unexpected_url_count:{len(locs)}')
host=urlparse(base).netloc.lower()
if any(urlparse(u).netloc.lower()!=host for u in locs): raise SystemExit('noncanonical_host')
required=[f'{base}/',f'{base}/index.php?c=category&dir=gjfa',f'{base}/index.php?c=category&dir=seo-articles',f'{base}/index.php?c=category&dir=tzjq',f'{base}/index.php?c=category&dir=zyyy']
for u in required:
    if u not in locs: raise SystemExit(f'required_url_missing:{u}')
for u in [f'{base}/index.php?c=category&dir=rjxm',f'{base}/index.php?c=category&dir=gdrz',f'{base}/index.php?c=show&id=85',f'{base}/index.php?c=show&id=86']:
    if u in locs: raise SystemExit(f'forbidden_url_present:{u}')
def check(u):
    p=subprocess.run(['curl','-skL','--max-time','15','-o','/dev/null','-w','%{http_code}',u],stdout=subprocess.PIPE,text=True)
    try: return u,int(p.stdout.strip() or 0)
    except Exception: return u,0
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
    results=list(ex.map(check,locs))
bad=[(u,c) for u,c in results if c!=200]
if bad: raise SystemExit('non200_urls:'+','.join(f'{urlparse(u).path}?{urlparse(u).query}:{c}' for u,c in bad[:10]))
print(json.dumps({
  'candidate_url_count':len(locs),'candidate_http_200_count':len(results),
  'excluded_show85':True,'excluded_show86':True,'excluded_rjxm_category':True,'excluded_empty_gdrz_category':True,
  'required_news_categories_present':4
},ensure_ascii=False))
PY

PHASE="backup_and_install"
if [ -f "$SITEMAP" ]; then cp -a "$SITEMAP" "$TMP/sitemap.before.xml"; fi
cp "$TMP/generated.xml" "$SITEMAP"
chmod 0644 "$SITEMAP"
DEPLOY="PASS"

PHASE="public_verify"
HTTP=$(curl -skL --max-time 30 -o "$TMP/public.xml" -w '%{http_code}' "$CANONICAL/sitemap.xml")
[ "$HTTP" = 200 ] || { ERROR_CLASS="public_sitemap_http_not_200"; block public_sitemap_http_not_200; }
[ "$(sha256sum "$TMP/public.xml" | awk '{print $1}')" = "$(sha256sum "$TMP/generated.xml" | awk '{print $1}')" ] || { ERROR_CLASS="public_sitemap_bytes_mismatch"; block public_sitemap_bytes_mismatch; }

PHASE="final"
write_payload PASS
echo "SITEMAP_ROUTING_CLEANUP_V1=PASS"
