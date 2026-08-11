#!/bin/bash
# Classified SEO Phase 1 production deploy. Same safe deployment path as V3,
# but if canonical deploy fails, publish only a sanitized stage/error class.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
PHASE1_COMMIT="74bde2c916c49e99b14772c5422fc7b65f69f4b1"
PHASE="init"; TARGET_SHA=""; DEPLOY="NO"; ROLLBACK="NO"; ERROR_CLASS="NONE"; LAST_STAGE="init"
HOME_HTTP=0; CATEGORY_HTTP=0; ARTICLE_HTTP=0; PLATFORM_HTTP=0
CATEGORY_OK="NO"; ARTICLE_OK="NO"; PLATFORM_OK="NO"; MOBILE_ARTICLE_OK="NO"; MOBILE_CATEGORY_OK="NO"
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
TMP="$(mktemp -d /tmp/xyptdq-seo-phase1-v4.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload(){
  local status="$1" blocker="$2"
  python3 - "$RESULT_FILE" "$status" "$blocker" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$ROLLBACK" "$ERROR_CLASS" "$LAST_STAGE" "$HOME_HTTP" "$CATEGORY_HTTP" "$ARTICLE_HTTP" "$PLATFORM_HTTP" "$CATEGORY_OK" "$ARTICLE_OK" "$PLATFORM_OK" "$MOBILE_ARTICLE_OK" "$MOBILE_CATEGORY_OK" <<'PY'
import json,sys
(out,status,blocker,phase,target,deploy,rollback,error_class,last_stage,home,cat,article,platform,catok,artok,platok,mart,mcat)=sys.argv[1:]
payload={
 'task':'deploy_seo_template_phase1_v4','deployment_status':status,'phase':phase,'blocking_item':blocker,
 'target_sha':target,'deploy':deploy,'rollback':rollback,'deploy_error_class':error_class,'deploy_last_stage':last_stage,
 'home_http':int(home),'category7_http':int(cat),'article91_http':int(article),'platform19_http':int(platform),
 'category7_seo':catok,'article91_seo':artok,'platform19_seo':platok,'mobile_article_seo':mart,'mobile_category_seo':mcat,
 'secrets_disclosed':False,
}
with open(out,'w',encoding='utf-8') as f:
 json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}
rollback_templates(){
  set +e
  if [ -d "$TMP/template.before" ]; then
    rm -rf "$WEBROOT/template"; cp -a "$TMP/template.before" "$WEBROOT/template"
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
  echo "[seo-phase1-v4] BLOCKED: $blocker class=$ERROR_CLASS stage=$LAST_STAGE" >&2
  exit 1
}
classify_deploy_log(){
  local log="$1"
  LAST_STAGE="start"
  grep -Fq -- '--- Refresh Git refs ---' "$log" && LAST_STAGE="git_refresh" || true
  grep -Fq -- '--- Create exact-ref deployment worktree ---' "$log" && LAST_STAGE="worktree" || true
  grep -Fq -- '--- Framework integrity preflight ---' "$log" && LAST_STAGE="framework_preflight" || true
  grep -Fq -- '--- Sanitize target-ref homepage robots ---' "$log" && LAST_STAGE="source_robots" || true
  grep -Fq -- '--- Pre-deploy backup ---' "$log" && LAST_STAGE="backup" || true
  grep -Fq -- '--- Sync exact-ref site code ---' "$log" && LAST_STAGE="rsync" || true
  grep -Fq -- 'FRAMEWORK_PRODUCTION_INTEGRITY: PASS' "$log" && LAST_STAGE="framework_production" || true
  grep -Fq -- '--- Sanitize production homepage robots ---' "$log" && LAST_STAGE="production_robots" || true
  grep -Fq -- '--- Generate sitemap ---' "$log" && LAST_STAGE="sitemap" || true
  grep -Fq -- '--- Repair web permissions ---' "$log" && LAST_STAGE="permissions" || true
  grep -Fq -- '--- SEO deployment assertions ---' "$log" && LAST_STAGE="seo_assertions" || true
  grep -Fq -- '--- Health check ---' "$log" && LAST_STAGE="health" || true
  grep -Fq -- '--- Record deployment ---' "$log" && LAST_STAGE="record" || true

  if grep -Fq 'target ref is missing dayrui/CodeIgniter72/System/Cache/CacheFactory.php' "$log"; then ERROR_CLASS="framework_source_missing"
  elif grep -Fq 'expected exactly one frame.lock in target ref' "$log"; then ERROR_CLASS="frame_lock_count_invalid"
  elif grep -Fq 'frame.lock bytes are not exact CodeIgniter72' "$log"; then ERROR_CLASS="frame_lock_source_invalid"
  elif grep -Fq 'backup checksum manifest missing' "$log"; then ERROR_CLASS="backup_manifest_missing"
  elif grep -Fq 'pre-deploy backup verification failed' "$log"; then ERROR_CLASS="backup_verification_failed"
  elif grep -Eiq 'mysqldump:|Access denied|database backup' "$log"; then ERROR_CLASS="database_backup_failed"
  elif grep -Eiq 'rsync error|rsync:.*failed|permission denied' "$log"; then ERROR_CLASS="rsync_failed"
  elif grep -Fq 'CacheFactory.php missing after rsync' "$log"; then ERROR_CLASS="cache_factory_missing_after_rsync"
  elif grep -Fq 'frame.lock missing after rsync' "$log"; then ERROR_CLASS="frame_lock_missing_after_rsync"
  elif grep -Fq 'production frame.lock bytes changed during deploy' "$log"; then ERROR_CLASS="frame_lock_changed_after_rsync"
  elif grep -Fq 'legacy homepage robots=none remains' "$log"; then ERROR_CLASS="production_home_robots_none"
  elif grep -Fq 'robots.txt missing/empty' "$log"; then ERROR_CLASS="robots_missing"
  elif grep -Fq 'sitemap.xml missing/empty' "$log"; then ERROR_CLASS="sitemap_missing"
  elif grep -Fq 'endpoint verification failed' "$log"; then ERROR_CLASS="endpoint_verification_failed"
  elif grep -Fq 'rendered homepage still contains robots=none' "$log"; then ERROR_CLASS="rendered_home_robots_none"
  elif grep -Eiq 'PHP Fatal error|Parse error|HTTP 500|health.*FAIL|ERROR:' "$log"; then ERROR_CLASS="other_canonical_deploy_error"
  else ERROR_CLASS="no_known_error_marker"
  fi
}

cd "$REPO"; PHASE="repo_sync"; git fetch --prune origin >/dev/null 2>&1; TARGET_SHA="$(git rev-parse origin/main^{commit})"
git merge-base --is-ancestor "$PHASE1_COMMIT" "$TARGET_SHA" || { ERROR_CLASS="phase1_not_in_main"; block phase1_commit_not_in_main; }
git cat-file -e "$TARGET_SHA:site/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" || { ERROR_CLASS="cache_factory_missing_in_target"; block cache_factory_missing_in_target; }
git cat-file -e "$TARGET_SHA:site/cache/frame.lock" || { ERROR_CLASS="frame_lock_missing_in_target"; block frame_lock_missing_in_target; }
FRAME_HEX=$(git show "$TARGET_SHA:site/cache/frame.lock" | od -An -tx1 -v | tr -d ' \n')
[ "$FRAME_HEX" = '436f646549676e697465723732' ] || { ERROR_CLASS="frame_lock_target_bytes_invalid"; block frame_lock_target_bytes_invalid; }

PHASE="rollback_snapshot"; cp -a "$WEBROOT/template" "$TMP/template.before"
PHASE="deploy"; git show "$TARGET_SHA:scripts/deploy_safe.sh" > "$TMP/deploy_safe.sh" || { ERROR_CLASS="deploy_safe_missing"; block deploy_safe_missing; }
chmod 700 "$TMP/deploy_safe.sh"
if ! XYPTDQ_REPO_DIR="$REPO" XYPTDQ_WEBROOT="$WEBROOT" bash "$TMP/deploy_safe.sh" "$TARGET_SHA" >"$TMP/deploy.log" 2>&1; then
  DEPLOY="PASS"; classify_deploy_log "$TMP/deploy.log"; block deploy_safe_failed
fi
DEPLOY="PASS"; LAST_STAGE="canonical_deploy_complete"

fetch_page(){ local n="$1" u="$2" a="${3:-}"; if [ -n "$a" ]; then curl -skL --max-time 30 -A "$a" -o "$TMP/$n.html" -w '%{http_code}' "$u" > "$TMP/$n.code"; else curl -skL --max-time 30 -o "$TMP/$n.html" -w '%{http_code}' "$u" > "$TMP/$n.code"; fi; }
PHASE="render_verify"; LAST_STAGE="render_verify"
fetch_page home "$CANONICAL/"; fetch_page category "$CANONICAL/index.php?c=category&id=7"; fetch_page article "$CANONICAL/index.php?c=show&id=91"; fetch_page platform "$CANONICAL/index.php?c=show&id=19"
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
fetch_page mobile_article "$CANONICAL/index.php?c=show&id=91" "$MOBILE_UA"; fetch_page mobile_category "$CANONICAL/index.php?c=category&id=7" "$MOBILE_UA"
HOME_HTTP="$(cat "$TMP/home.code")"; CATEGORY_HTTP="$(cat "$TMP/category.code")"; ARTICLE_HTTP="$(cat "$TMP/article.code")"; PLATFORM_HTTP="$(cat "$TMP/platform.code")"
[ "$HOME_HTTP" = 200 ] || { ERROR_CLASS="home_http_not_200"; block home_http_not_200; }
[ "$CATEGORY_HTTP" = 200 ] || { ERROR_CLASS="category_http_not_200"; block category_http_not_200; }
[ "$ARTICLE_HTTP" = 200 ] || { ERROR_CLASS="article_http_not_200"; block article_http_not_200; }
[ "$PLATFORM_HTTP" = 200 ] || { ERROR_CLASS="platform_http_not_200"; block platform_http_not_200; }

analyze(){ python3 - "$1" "$2" <<'PY'
import re,sys
text=open(sys.argv[1],encoding='utf-8',errors='ignore').read(); kind=sys.argv[2]; low=text.lower()
def c(p): return len(re.findall(p,low,re.I|re.S))
def tags(name): return re.findall(r'<meta\b[^>]*name=["\']'+re.escape(name)+r'["\'][^>]*>',text,re.I)
def attr(tag,name):
 m=re.search(r'\b'+re.escape(name)+r'=["\']([^"\']*)["\']',tag,re.I); return m.group(1).strip() if m else ''
robots=[attr(t,'content').lower() for t in tags('robots')]; desc=[attr(t,'content') for t in tags('description')]
ok=(c(r'<!doctype\b')==1 and c(r'<html\b')==1 and c(r'<head\b')==1 and c(r'<title\b')==1 and c(r'<link\b[^>]*rel=["\']canonical["\']')==1 and c(r'<h1\b')==1 and c(r'application/ld\+json')>=1 and bool(desc and desc[0]) and not any('none' in x for x in robots))
if kind=='article': ok=ok and c(r'application/ld\+json')>=2
for bad in ('u3s1.com','demo.5moban.com','pblu.mobanqi.com'): ok=ok and bad not in low
print('PASS' if ok else 'FAIL')
PY
}
CATEGORY_OK="$(analyze "$TMP/category.html" category)"; ARTICLE_OK="$(analyze "$TMP/article.html" article)"; PLATFORM_OK="$(analyze "$TMP/platform.html" platform)"; MOBILE_ARTICLE_OK="$(analyze "$TMP/mobile_article.html" article)"; MOBILE_CATEGORY_OK="$(analyze "$TMP/mobile_category.html" category)"
[ "$CATEGORY_OK" = PASS ] || { ERROR_CLASS="category_seo_assertions_failed"; block category_seo_assertions_failed; }
[ "$ARTICLE_OK" = PASS ] || { ERROR_CLASS="article_seo_assertions_failed"; block article_seo_assertions_failed; }
[ "$PLATFORM_OK" = PASS ] || { ERROR_CLASS="platform_seo_assertions_failed"; block platform_seo_assertions_failed; }
[ "$MOBILE_ARTICLE_OK" = PASS ] || { ERROR_CLASS="mobile_article_seo_assertions_failed"; block mobile_article_seo_assertions_failed; }
[ "$MOBILE_CATEGORY_OK" = PASS ] || { ERROR_CLASS="mobile_category_seo_assertions_failed"; block mobile_category_seo_assertions_failed; }
PHASE="framework_verify"; LAST_STAGE="framework_verify"
[ -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" ] || { ERROR_CLASS="production_cache_factory_missing"; block production_cache_factory_missing; }
[ "$(od -An -tx1 -v "$WEBROOT/cache/frame.lock" | tr -d ' \n')" = '436f646549676e697465723732' ] || { ERROR_CLASS="production_frame_lock_invalid"; block production_frame_lock_invalid; }
PHASE="final"; LAST_STAGE="final"; ERROR_CLASS="NONE"; write_payload PASS NONE; echo "SEO_TEMPLATE_PHASE1_V4=PASS target=$TARGET_SHA"
