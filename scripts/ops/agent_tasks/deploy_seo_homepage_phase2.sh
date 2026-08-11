#!/bin/bash
# Rollback-gated production deployment for the rebuilt PC homepage.
# Deploys the exact reviewed Phase 2 merge commit and publishes only sanitized
# verification fields through the Server Bridge result file.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
PHASE2_COMMIT="fa8d30888affca4d088d195086b07d60a8354703"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"

PHASE="init"
TARGET_SHA="$PHASE2_COMMIT"
DEPLOY="NO"
ROLLBACK="NO"
SOURCE_SEO="NO"
HOME_HTTP=0
HOME_SEO="NO"
HOME_FUNCTIONS="NO"
MOBILE_HOME_HTTP=0
MOBILE_HOME_SEO="NO"
CATEGORY_HTTP=0
ARTICLE_HTTP=0
PLATFORM_HTTP=0
FRAMEWORK_OK="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4

TMP="$(mktemp -d /tmp/xyptdq-home-phase2.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload() {
  local status="$1"
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$ROLLBACK" "$SOURCE_SEO" "$HOME_HTTP" "$HOME_SEO" "$HOME_FUNCTIONS" "$MOBILE_HOME_HTTP" "$MOBILE_HOME_SEO" "$CATEGORY_HTTP" "$ARTICLE_HTTP" "$PLATFORM_HTTP" "$FRAMEWORK_OK" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,target,deploy,rollback,source_seo,home_http,home_seo,home_functions,mobile_http,mobile_seo,category_http,article_http,platform_http,framework_ok,error_class,blocker)=sys.argv[1:]
payload={
  'task':'deploy_seo_homepage_phase2',
  'deployment_status':status,
  'phase':phase,
  'target_sha':target,
  'deploy':deploy,
  'rollback':rollback,
  'source_homepage_seo':source_seo,
  'home_http':int(home_http),
  'home_seo':home_seo,
  'home_functions':home_functions,
  'mobile_home_http':int(mobile_http),
  'mobile_home_seo':mobile_seo,
  'category7_http':int(category_http),
  'article91_http':int(article_http),
  'platform19_http':int(platform_http),
  'framework_integrity':framework_ok,
  'deploy_error_class':error_class,
  'blocking_item':blocker,
  'secrets_disclosed':False,
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True)
    f.write('\n')
PY
}

rollback_templates() {
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

block() {
  BLOCKING_ITEM="$1"
  if [ "$DEPLOY" = "PASS" ]; then rollback_templates; fi
  write_payload BLOCKED
  echo "[seo-home-phase2] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
  exit 1
}

analyze_source() {
  python3 - "$1" <<'PY'
import re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
low=s.lower()
def c(p): return len(re.findall(p,s,re.I|re.S))
required=[
  '彩票数据研究、方案验证与平台资料导航',
  'class="click_pop"',
  'module module=xm',
  'seo-article-section',
  "dr_site_value('bywz')",
  "dr_site_value('banquanxinxi')",
  '{SITE_TONGJI}',
  '最新研究文章',
  '平台资料导航',
]
ok=(
  c(r'<!doctype\b')==1 and c(r'<html\b')==1 and c(r'<head\b')==1 and
  c(r'<body\b')==1 and c(r'</html\s*>')==1 and c(r'<title\b')==1 and
  c(r'<link\b[^>]*rel=["\']canonical["\']')==1 and c(r'<h1\b')==1 and
  c(r'application/ld\+json')>=1 and
  'content="none"' not in low and '站长素材' not in s and
  all(x in s for x in required)
)
print('PASS' if ok else 'FAIL')
PY
}

analyze_rendered_home() {
  python3 - "$1" <<'PY'
import re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read(); low=s.lower()
def c(p): return len(re.findall(p,s,re.I|re.S))
def metas(name): return re.findall(r'<meta\b[^>]*name=["\']'+re.escape(name)+r'["\'][^>]*>',s,re.I)
def attr(tag,name):
    m=re.search(r'\b'+re.escape(name)+r'=["\']([^"\']*)["\']',tag,re.I)
    return m.group(1).strip() if m else ''
robots=[attr(t,'content').lower() for t in metas('robots')]
desc=[attr(t,'content') for t in metas('description')]
required=['彩票数据研究、方案验证与平台资料导航','平台资料导航','最新研究文章','seo-article-section','click_pop','ptitem']
ok=(
  c(r'<!doctype\b')==1 and c(r'<html\b')==1 and c(r'<head\b')==1 and
  c(r'<body\b')==1 and c(r'</html\s*>')==1 and c(r'<title\b')==1 and
  c(r'<link\b[^>]*rel=["\']canonical["\']')==1 and c(r'<h1\b')==1 and
  c(r'application/ld\+json')>=1 and bool(desc and desc[0]) and
  not any('none' in x for x in robots) and
  '站长素材' not in s and all(x in s for x in required)
)
print('PASS' if ok else 'FAIL')
PY
}

analyze_rendered_mobile_home() {
  python3 - "$1" <<'PY'
import re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read(); low=s.lower()
def c(p): return len(re.findall(p,s,re.I|re.S))
ok=(c(r'<title\b')>=1 and c(r'<meta\b[^>]*name=["\']description["\']')>=1 and 'content="none"' not in low and '站长素材' not in s)
print('PASS' if ok else 'FAIL')
PY
}

cd "$REPO"
PHASE="repo_sync"
git fetch --prune origin >/dev/null 2>&1
if ! git merge-base --is-ancestor "$PHASE2_COMMIT" origin/main; then
  ERROR_CLASS="phase2_not_merged_to_main"; block phase2_not_merged_to_main
fi
if ! git cat-file -e "$TARGET_SHA:site/dayrui/CodeIgniter72/System/Cache/CacheFactory.php"; then
  ERROR_CLASS="cache_factory_missing_in_target"; block cache_factory_missing_in_target
fi
if ! git cat-file -e "$TARGET_SHA:site/cache/frame.lock"; then
  ERROR_CLASS="frame_lock_missing_in_target"; block frame_lock_missing_in_target
fi
FRAME_HEX=$(git show "$TARGET_SHA:site/cache/frame.lock" | od -An -tx1 -v | tr -d ' \n')
[ "$FRAME_HEX" = "$EXPECTED_FRAME_LOCK_HEX" ] || { ERROR_CLASS="frame_lock_target_invalid"; block frame_lock_target_invalid; }

PHASE="source_verify"
git show "$TARGET_SHA:site/template/pc/default/home/index.html" > "$TMP/home.source.html"
SOURCE_SEO="$(analyze_source "$TMP/home.source.html")"
[ "$SOURCE_SEO" = PASS ] || { ERROR_CLASS="source_homepage_assertions_failed"; block source_homepage_assertions_failed; }

PHASE="rollback_snapshot"
cp -a "$WEBROOT/template" "$TMP/template.before"

PHASE="deploy"
git show "$TARGET_SHA:scripts/deploy_safe.sh" > "$TMP/deploy_safe.sh" || { ERROR_CLASS="deploy_safe_missing"; block deploy_safe_missing; }
chmod 700 "$TMP/deploy_safe.sh"
if ! XYPTDQ_REPO_DIR="$REPO" XYPTDQ_WEBROOT="$WEBROOT" bash "$TMP/deploy_safe.sh" "$TARGET_SHA" >"$TMP/deploy.log" 2>&1; then
  ERROR_CLASS="canonical_deploy_failed"
  if grep -Fq 'pre-deploy backup verification failed' "$TMP/deploy.log"; then ERROR_CLASS="backup_verification_failed"
  elif grep -Fq 'backup checksum manifest missing' "$TMP/deploy.log"; then ERROR_CLASS="backup_manifest_missing"
  elif grep -Eiq 'rsync error|rsync:.*failed|permission denied' "$TMP/deploy.log"; then ERROR_CLASS="rsync_failed"
  elif grep -Fq 'rendered homepage still contains robots=none' "$TMP/deploy.log"; then ERROR_CLASS="rendered_home_robots_none"
  elif grep -Eiq 'PHP Fatal error|Parse error|HTTP 500|health.*FAIL|ERROR:' "$TMP/deploy.log"; then ERROR_CLASS="other_canonical_deploy_error"
  fi
  block deploy_safe_failed
fi
DEPLOY="PASS"

fetch_page() {
  local name="$1" url="$2" ua="${3:-}"
  if [ -n "$ua" ]; then
    curl -skL --max-time 30 -A "$ua" -o "$TMP/$name.html" -w '%{http_code}' "$url" > "$TMP/$name.code"
  else
    curl -skL --max-time 30 -o "$TMP/$name.html" -w '%{http_code}' "$url" > "$TMP/$name.code"
  fi
}

PHASE="render_verify"
fetch_page home "$CANONICAL/"
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
fetch_page mobile_home "$CANONICAL/" "$MOBILE_UA"
fetch_page category "$CANONICAL/index.php?c=category&id=7"
fetch_page article "$CANONICAL/index.php?c=show&id=91"
fetch_page platform "$CANONICAL/index.php?c=show&id=19"

HOME_HTTP="$(cat "$TMP/home.code")"
MOBILE_HOME_HTTP="$(cat "$TMP/mobile_home.code")"
CATEGORY_HTTP="$(cat "$TMP/category.code")"
ARTICLE_HTTP="$(cat "$TMP/article.code")"
PLATFORM_HTTP="$(cat "$TMP/platform.code")"

[ "$HOME_HTTP" = 200 ] || { ERROR_CLASS="home_http_not_200"; block home_http_not_200; }
[ "$MOBILE_HOME_HTTP" = 200 ] || { ERROR_CLASS="mobile_home_http_not_200"; block mobile_home_http_not_200; }
[ "$CATEGORY_HTTP" = 200 ] || { ERROR_CLASS="category_http_not_200"; block category_http_not_200; }
[ "$ARTICLE_HTTP" = 200 ] || { ERROR_CLASS="article_http_not_200"; block article_http_not_200; }
[ "$PLATFORM_HTTP" = 200 ] || { ERROR_CLASS="platform_http_not_200"; block platform_http_not_200; }

HOME_SEO="$(analyze_rendered_home "$TMP/home.html")"
[ "$HOME_SEO" = PASS ] || { ERROR_CLASS="rendered_home_seo_failed"; block rendered_home_seo_failed; }
HOME_FUNCTIONS="PASS"

MOBILE_HOME_SEO="$(analyze_rendered_mobile_home "$TMP/mobile_home.html")"
[ "$MOBILE_HOME_SEO" = PASS ] || { ERROR_CLASS="mobile_home_seo_failed"; block mobile_home_seo_failed; }

PHASE="framework_verify"
if [ -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" ] && [ -f "$WEBROOT/cache/frame.lock" ] && [ "$(od -An -tx1 -v "$WEBROOT/cache/frame.lock" | tr -d ' \n')" = "$EXPECTED_FRAME_LOCK_HEX" ]; then
  FRAMEWORK_OK="PASS"
else
  ERROR_CLASS="framework_integrity_failed"; block framework_integrity_failed
fi

PHASE="final"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"
write_payload PASS
echo "SEO_HOMEPAGE_PHASE2=PASS target=$TARGET_SHA"
