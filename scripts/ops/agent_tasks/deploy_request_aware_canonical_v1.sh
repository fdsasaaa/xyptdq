#!/bin/bash
# Rollback-gated deployment for request-aware canonical metadata.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="df18a4a6339f9c84a3d9fc14bc83eb812aac4bcd"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"

PHASE="init"
DEPLOY="NO"
ROLLBACK="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"
TMP="$(mktemp -d /tmp/xyptdq-canonical-deploy.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4

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
  'task':'deploy_request_aware_canonical_v1','deployment_status':status,'phase':phase,
  'target_sha':target,'deploy':deploy,'rollback':rollback,'deploy_error_class':error_class,
  'blocking_item':blocker,'article_publishing_attempted':False,'secrets_disclosed':False,
  **metrics
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}

rollback_templates(){
  set +e
  if [ -d "$TMP/template.before" ]; then
    rm -rf "$WEBROOT/template"
    cp -a "$TMP/template.before" "$WEBROOT/template"
    chown -R www-data:www-data "$WEBROOT/template" 2>/dev/null || true
    chmod -R u=rwX,go=rX "$WEBROOT/template" 2>/dev/null || true
    ROLLBACK="YES"
  fi
  set -e
}
block(){
  BLOCKING_ITEM="$1"
  if [ "$DEPLOY" = "PASS" ]; then rollback_templates; fi
  write_payload BLOCKED
  echo "[canonical-deploy] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
  exit 1
}

cd "$REPO"
PHASE="repo_sync"
git fetch --prune origin >/dev/null 2>&1
git merge-base --is-ancestor "$TARGET_SHA" origin/main || { ERROR_CLASS="target_not_in_main"; block target_not_in_main; }

PHASE="source_verify"
for p in site/template/pc/default/home/seo_header.html site/template/mobile/default/home/seo_header.html; do
  git show "$TARGET_SHA:$p" | grep -Fq '$xyptdq_route = strtolower' || { ERROR_CLASS="request_route_logic_missing"; block request_route_logic_missing; }
  git show "$TARGET_SHA:$p" | grep -Fq 'c=category&dir=' || { ERROR_CLASS="category_dir_canonical_missing"; block category_dir_canonical_missing; }
done

PHASE="rollback_snapshot"
cp -a "$WEBROOT/template" "$TMP/template.before"

PHASE="deploy"
git show "$TARGET_SHA:scripts/deploy_safe.sh" > "$TMP/deploy_safe.sh" || { ERROR_CLASS="deploy_safe_missing"; block deploy_safe_missing; }
chmod 700 "$TMP/deploy_safe.sh"
if ! XYPTDQ_REPO_DIR="$REPO" XYPTDQ_WEBROOT="$WEBROOT" bash "$TMP/deploy_safe.sh" "$TARGET_SHA" >"$TMP/deploy.log" 2>&1; then
  ERROR_CLASS="canonical_deploy_failed"; block deploy_safe_failed
fi
DEPLOY="PASS"

PHASE="render_verify"
python3 - "$TMP" "$CANONICAL" <<'PY' > "$TMP/metrics.json"
import html,json,re,subprocess,sys

tmp,base=sys.argv[1:]
def fetch(name,url):
    p=subprocess.run(['curl','-skL','--max-time','30','-o',f'{tmp}/{name}.html','-w','%{http_code}',url],stdout=subprocess.PIPE,text=True)
    code=int(p.stdout.strip() or 0)
    if code!=200: raise SystemExit(f'{name}_http_{code}')
    return open(f'{tmp}/{name}.html',encoding='utf-8',errors='ignore').read()
def attr(tag,name):
    m=re.search(r'\b'+re.escape(name)+r'\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    return html.unescape(m.group(1)).strip() if m else ''
def canonical(s):
    for tag in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
        if 'canonical' in attr(tag,'rel').lower().split(): return attr(tag,'href')
    return ''
def og_type(s):
    for tag in re.findall(r'<meta\b[^>]*>',s,re.I|re.S):
        if attr(tag,'property').lower()=='og:type': return attr(tag,'content').lower()
    return ''

news_dirs=['gjfa','seo-articles','tzjq','zyyy']
self_count=0
category_og_ok=True
for i,d in enumerate(news_dirs):
    url=f'{base}/index.php?c=category&dir={d}'
    s=fetch(f'category-{i}',url)
    self_count += int(canonical(s)==url)
    category_og_ok = category_og_ok and og_type(s)=='website'

rjxm=fetch('rjxm',f'{base}/index.php?c=category&dir=rjxm')
article=fetch('article91',f'{base}/index.php?c=show&id=91')
platform=fetch('platform19',f'{base}/index.php?c=show&id=19')
metrics={
  'news_category_self_canonical_count':self_count,
  'rjxm_canonical_home':'PASS' if canonical(rjxm)==base+'/' else 'NO',
  'article91_canonical':'PASS' if canonical(article)==f'{base}/index.php?c=show&id=91' else 'NO',
  'platform19_canonical':'PASS' if canonical(platform)==f'{base}/index.php?c=show&id=19' else 'NO',
  'article91_og_type_article':'PASS' if og_type(article)=='article' else 'NO',
  'category_og_type_website':'PASS' if category_og_ok else 'NO'
}
print(json.dumps(metrics,ensure_ascii=False))
PY
python3 - "$TMP/metrics.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1],encoding='utf-8'))
assert m['news_category_self_canonical_count']==4
assert m['rjxm_canonical_home']=='PASS'
assert m['article91_canonical']=='PASS'
assert m['platform19_canonical']=='PASS'
assert m['article91_og_type_article']=='PASS'
assert m['category_og_type_website']=='PASS'
PY

PHASE="framework_verify"
if [ -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" ] \
   && [ -f "$WEBROOT/cache/frame.lock" ] \
   && [ "$(od -An -tx1 -v "$WEBROOT/cache/frame.lock" | tr -d ' \n')" = "$EXPECTED_FRAME_LOCK_HEX" ]; then
  python3 - "$TMP/metrics.json" <<'PY'
import json,sys
p=sys.argv[1]; x=json.load(open(p,encoding='utf-8')); x['framework_integrity']='PASS'
json.dump(x,open(p,'w',encoding='utf-8'),ensure_ascii=False,indent=2,sort_keys=True)
PY
else
  ERROR_CLASS="framework_integrity_failed"; block framework_integrity_failed
fi

PHASE="final"
write_payload PASS
echo "REQUEST_AWARE_CANONICAL_V1=PASS"
