#!/bin/bash
# Safe production deployment of merged SEO template Phase 1 using deploy_safe.sh.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
PHASE1_COMMIT="74bde2c916c49e99b14772c5422fc7b65f69f4b1"
PHASE="init"
TARGET_SHA=""
DEPLOY="NO"
ROLLBACK="NO"
HOME_HTTP=0
CATEGORY_HTTP=0
ARTICLE_HTTP=0
PLATFORM_HTTP=0
CATEGORY_OK="NO"
ARTICLE_OK="NO"
PLATFORM_OK="NO"
MOBILE_ARTICLE_OK="NO"
MOBILE_CATEGORY_OK="NO"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
TMP="$(mktemp -d /tmp/xyptdq-seo-phase1-v3.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload(){
  local status="$1" blocker="$2"
  python3 - "$RESULT_FILE" "$status" "$blocker" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$ROLLBACK" "$HOME_HTTP" "$CATEGORY_HTTP" "$ARTICLE_HTTP" "$PLATFORM_HTTP" "$CATEGORY_OK" "$ARTICLE_OK" "$PLATFORM_OK" "$MOBILE_ARTICLE_OK" "$MOBILE_CATEGORY_OK" <<'PY'
import json,sys
(out,status,blocker,phase,target,deploy,rollback,home,cat,article,platform,catok,artok,platok,mart,mcat)=sys.argv[1:]
payload={
 'task':'deploy_seo_template_phase1_v3','deployment_status':status,'phase':phase,'blocking_item':blocker,
 'target_sha':target,'deploy':deploy,'rollback':rollback,
 'home_http':int(home),'category7_http':int(cat),'article91_http':int(article),'platform19_http':int(platform),
 'category7_seo':catok,'article91_seo':artok,'platform19_seo':platok,
 'mobile_article_seo':mart,'mobile_category_seo':mcat,'secrets_disclosed':False,
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
  local blocker="$1"
  if [ "$DEPLOY" = "PASS" ]; then rollback_templates; fi
  write_payload BLOCKED "$blocker"
  echo "[seo-phase1-v3] BLOCKED: $blocker" >&2
  exit 1
}

cd "$REPO"
PHASE="repo_sync"
git fetch --prune origin >/dev/null 2>&1
TARGET_SHA="$(git rev-parse origin/main^{commit})"
git merge-base --is-ancestor "$PHASE1_COMMIT" "$TARGET_SHA" || block phase1_commit_not_in_main
git cat-file -e "$TARGET_SHA:site/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" || block cache_factory_missing_in_target
git cat-file -e "$TARGET_SHA:site/cache/frame.lock" || block frame_lock_missing_in_target
FRAME_HEX=$(git show "$TARGET_SHA:site/cache/frame.lock" | od -An -tx1 -v | tr -d ' \n')
[ "$FRAME_HEX" = '436f646549676e697465723732' ] || block frame_lock_target_bytes_invalid

PHASE="rollback_snapshot"
cp -a "$WEBROOT/template" "$TMP/template.before"

PHASE="deploy"
git show "$TARGET_SHA:scripts/deploy_safe.sh" > "$TMP/deploy_safe.sh" || block deploy_safe_missing
chmod 700 "$TMP/deploy_safe.sh"
if ! XYPTDQ_REPO_DIR="$REPO" XYPTDQ_WEBROOT="$WEBROOT" bash "$TMP/deploy_safe.sh" "$TARGET_SHA" >"$TMP/deploy.log" 2>&1; then
  DEPLOY="PASS"
  block deploy_safe_failed
fi
DEPLOY="PASS"

fetch_page(){
  local name="$1" url="$2" ua="${3:-}"
  if [ -n "$ua" ]; then
    curl -skL --max-time 30 -A "$ua" -o "$TMP/$name.html" -w '%{http_code}' "$url" > "$TMP/$name.code"
  else
    curl -skL --max-time 30 -o "$TMP/$name.html" -w '%{http_code}' "$url" > "$TMP/$name.code"
  fi
}

PHASE="render_verify"
fetch_page home "$CANONICAL/"
fetch_page category "$CANONICAL/index.php?c=category&id=7"
fetch_page article "$CANONICAL/index.php?c=show&id=91"
fetch_page platform "$CANONICAL/index.php?c=show&id=19"
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
fetch_page mobile_article "$CANONICAL/index.php?c=show&id=91" "$MOBILE_UA"
fetch_page mobile_category "$CANONICAL/index.php?c=category&id=7" "$MOBILE_UA"
HOME_HTTP="$(cat "$TMP/home.code")"; CATEGORY_HTTP="$(cat "$TMP/category.code")"; ARTICLE_HTTP="$(cat "$TMP/article.code")"; PLATFORM_HTTP="$(cat "$TMP/platform.code")"
[ "$HOME_HTTP" = 200 ] || block home_http_not_200
[ "$CATEGORY_HTTP" = 200 ] || block category_http_not_200
[ "$ARTICLE_HTTP" = 200 ] || block article_http_not_200
[ "$PLATFORM_HTTP" = 200 ] || block platform_http_not_200

analyze(){
  python3 - "$1" "$2" <<'PY'
import re,sys
text=open(sys.argv[1],encoding='utf-8',errors='ignore').read(); kind=sys.argv[2]; low=text.lower()
def c(p): return len(re.findall(p,low,re.I|re.S))
def tags(name): return re.findall(r'<meta\b[^>]*name=["\']'+re.escape(name)+r'["\'][^>]*>',text,re.I)
def attr(tag,name):
 m=re.search(r'\b'+re.escape(name)+r'=["\']([^"\']*)["\']',tag,re.I); return m.group(1).strip() if m else ''
robots=[attr(t,'content').lower() for t in tags('robots')]
desc=[attr(t,'content') for t in tags('description')]
canonical=c(r'<link\b[^>]*rel=["\']canonical["\']')
jsonld=c(r'application/ld\+json')
ok=(c(r'<!doctype\b')==1 and c(r'<html\b')==1 and c(r'<head\b')==1 and c(r'<title\b')==1 and canonical==1 and c(r'<h1\b')==1 and jsonld>=1 and bool(desc and desc[0]) and not any('none' in x for x in robots))
if kind=='article': ok=ok and jsonld>=2
for bad in ('u3s1.com','demo.5moban.com','pblu.mobanqi.com'):
 ok=ok and bad not in low
print('PASS' if ok else 'FAIL')
PY
}
CATEGORY_OK="$(analyze "$TMP/category.html" category)"; ARTICLE_OK="$(analyze "$TMP/article.html" article)"; PLATFORM_OK="$(analyze "$TMP/platform.html" platform)"; MOBILE_ARTICLE_OK="$(analyze "$TMP/mobile_article.html" article)"; MOBILE_CATEGORY_OK="$(analyze "$TMP/mobile_category.html" category)"
[ "$CATEGORY_OK" = PASS ] || block category_seo_assertions_failed
[ "$ARTICLE_OK" = PASS ] || block article_seo_assertions_failed
[ "$PLATFORM_OK" = PASS ] || block platform_seo_assertions_failed
[ "$MOBILE_ARTICLE_OK" = PASS ] || block mobile_article_seo_assertions_failed
[ "$MOBILE_CATEGORY_OK" = PASS ] || block mobile_category_seo_assertions_failed

PHASE="framework_verify"
[ -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" ] || block production_cache_factory_missing
[ "$(od -An -tx1 -v "$WEBROOT/cache/frame.lock" | tr -d ' \n')" = '436f646549676e697465723732' ] || block production_frame_lock_invalid

PHASE="final"
write_payload PASS NONE
echo "SEO_TEMPLATE_PHASE1_V3=PASS target=$TARGET_SHA"
