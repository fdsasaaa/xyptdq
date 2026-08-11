#!/bin/bash
# Rollback-gated deployment for request-aware canonical / schema metadata.
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
CATEGORY_SELF_CANONICAL=0
R JXM_HOME_CANONICAL="NO"
ARTICLE_CANONICAL="NO"
PLATFORM_CANONICAL="NO"
ARTICLE_OG_TYPE="NO"
CATEGORY_OG_TYPE="NO"
FRAMEWORK_OK="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

# shellcheck disable=SC2034
RJXM_HOME_CANONICAL="NO"
unset R

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4

TMP="$(mktemp -d /tmp/xyptdq-canonical-deploy.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload(){
  local status="$1"
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$ROLLBACK" \
    "$CATEGORY_SELF_CANONICAL" "$RJXM_HOME_CANONICAL" "$ARTICLE_CANONICAL" "$PLATFORM_CANONICAL" \
    "$ARTICLE_OG_TYPE" "$CATEGORY_OG_TYPE" "$FRAMEWORK_OK" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,target,deploy,rollback,cat_self,rjxm,article_canon,platform_canon,
 article_og,category_og,framework,error_class,blocker)=sys.argv[1:]
payload={
  "task":"deploy_request_aware_canonical_v1",
  "deployment_status":status,
  "phase":phase,
  "target_sha":target,
  "deploy":deploy,
  "rollback":rollback,
  "news_category_self_canonical_count":int(cat_self),
  "rjxm_canonical_home":rjxm,
  "article91_canonical":article_canon,
  "platform19_canonical":platform_canon,
  "article91_og_type_article":article_og,
  "category_og_type_website":category_og,
  "framework_integrity":framework,
  "deploy_error_class":error_class,
  "blocking_item":blocker,
  "article_publishing_attempted":False,
  "secrets_disclosed":False
}
with open(out,"w",encoding="utf-8") as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write("\n")
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
  git show "$TARGET_SHA:$p" | grep -Fq "c=category&dir=" || { ERROR_CLASS="category_dir_canonical_missing"; block category_dir_canonical_missing; }
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
python3 - "$TMP" "$CANONICAL" <<'PY' > "$TMP/status.tsv"
import html,re,subprocess,sys
from urllib.parse import urljoin

tmp,base=sys.argv[1:]

def fetch(name,url):
    p=subprocess.run(['curl','-skL','--max-time','30','-o',f'{tmp}/{name}.html','-w','%{http_code}',url],stdout=subprocess.PIPE,text=True)
    code=int(p.stdout.strip() or 0)
    s=open(f'{tmp}/{name}.html',encoding='utf-8',errors='ignore').read()
    return code,s

def attr(tag,name):
    m=re.search(r'\b'+re.escape(name)+r'\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    return html.unescape(m.group(1)).strip() if m else ''

def canonical(s):
    for t in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
        if 'canonical' in attr(t,'rel').lower().split(): return attr(t,'href')
    return ''

def og_type(s):
    for t in re.findall(r'<meta\b[^>]*>',s,re.I|re.S):
        if attr(t,'property').lower()=='og:type': return attr(t,'content').lower()
    return ''

dirs=['gjfa','seo-articles','tzjq','zyyy']
self_count=0
category_og_ok=True
for i,d in enumerate(dirs):
    url=f'{base}/index.php?c=category&dir={d}'
    code,s=fetch(f'cat-{i}',url)
    if code!=200:
        raise SystemExit(f'category_http_{d}_{code}')
    if canonical(s)==url:
        self_count+=1
    if og_type(s)!='website':
        category_og_ok=False

code,rjxm=fetch('rjxm',f'{base}/index.php?c=category&dir=rjxm')
if code!=200: raise SystemExit(f'rjxm_http_{code}')
rjxm_home=canonical(rjxm)==base+'/'

code,article=fetch('article',f'{base}/index.php?c=show&id=91')
if code!=200: raise SystemExit(f'article_http_{code}')
article_canon=canonical(article)==f'{base}/index.php?c=show&id=91'
article_og=og_type(article)=='article'

code,platform=fetch('platform',f'{base}/index.php?c=show&id=19')
if code!=200: raise SystemExit(f'platform_http_{code}')
platform_canon=canonical(platform)==f'{base}/index.php?c=show&id=19'

print(self_count,'PASS' if rjxm_home else 'NO','PASS' if article_canon else 'NO','PASS' if platform_canon else 'NO','PASS' if article_og else 'NO','PASS' if category_og_ok else 'NO',sep='\t')
PY
IFS=$'\t' read -r CATEGORY_SELF_CANONICAL RJXM_HOME_CANONICAL ARTICLE_CANONICAL PLATFORM_CANONICAL ARTICLE_OG_TYPE CATEGORY_OG_TYPE < "$TMP/status.tsv"
[ "$CATEGORY_SELF_CANONICAL" -eq 4 ] || { ERROR_CLASS="news_category_canonical_mismatch"; block news_category_canonical_mismatch; }
[ "$RJXM_HOME_CANONICAL" = PASS ] || { ERROR_CLASS="rjxm_duplicate_consolidation_regressed"; block rjxm_duplicate_consolidation_regressed; }
[ "$ARTICLE_CANONICAL" = PASS ] || { ERROR_CLASS="article_canonical_regressed"; block article_canonical_regressed; }
[ "$PLATFORM_CANONICAL" = PASS ] || { ERROR_CLASS="platform_canonical_regressed"; block platform_canonical_regressed; }
[ "$ARTICLE_OG_TYPE" = PASS ] || { ERROR_CLASS="article_og_type_regressed"; block article_og_type_regressed; }
[ "$CATEGORY_OG_TYPE" = PASS ] || { ERROR_CLASS="category_og_type_regressed"; block category_og_type_regressed; }

PHASE="framework_verify"
if [ -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" ] \
   && [ -f "$WEBROOT/cache/frame.lock" ] \
   && [ "$(od -An -tx1 -v "$WEBROOT/cache/frame.lock" | tr -d ' \n')" = "$EXPECTED_FRAME_LOCK_HEX" ]; then
  FRAMEWORK_OK="PASS"
else
  ERROR_CLASS="framework_integrity_failed"; block framework_integrity_failed
fi

PHASE="final"
ERROR_CLASS="NONE"; BLOCKING_ITEM="NONE"; write_payload PASS
echo "REQUEST_AWARE_CANONICAL_V1=PASS"
