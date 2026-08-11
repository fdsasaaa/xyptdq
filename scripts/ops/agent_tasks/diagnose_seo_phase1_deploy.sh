#!/bin/bash
# Read-only classification of the failed SEO Phase 1 deployment.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
LOG="/var/log/xyptdq-agent/deploy-seo-template-phase1-20260811-01.log"
CANONICAL="https://www.laocaimi.org"
[ -n "$RESULT_FILE" ] || exit 2

STAGE="unknown"
ERROR_CLASS="unknown"
LOG_EXISTS="NO"
if [ -s "$LOG" ]; then
  LOG_EXISTS="YES"
  grep -Fq -- '--- Record deployment ---' "$LOG" && STAGE="record" || true
  if [ "$STAGE" = unknown ]; then grep -Fq -- '--- Health check ---' "$LOG" && STAGE="health" || true; fi
  if [ "$STAGE" = unknown ]; then grep -Fq -- '--- SEO deployment assertions ---' "$LOG" && STAGE="seo_assertions" || true; fi
  if [ "$STAGE" = unknown ]; then grep -Fq -- '--- Repair web permissions ---' "$LOG" && STAGE="permissions" || true; fi
  if [ "$STAGE" = unknown ]; then grep -Fq -- '--- Generate sitemap ---' "$LOG" && STAGE="sitemap" || true; fi
  if [ "$STAGE" = unknown ]; then grep -Fq -- '--- Sync exact-ref site code ---' "$LOG" && STAGE="rsync" || true; fi
  if [ "$STAGE" = unknown ]; then grep -Fq -- '--- Pre-deploy backup ---' "$LOG" && STAGE="backup" || true; fi
  if [ "$STAGE" = unknown ]; then grep -Fq -- '--- Sanitize target-ref homepage robots ---' "$LOG" && STAGE="source_robots" || true; fi
  if [ "$STAGE" = unknown ]; then grep -Fq -- '--- Framework integrity preflight ---' "$LOG" && STAGE="framework_preflight" || true; fi
  if [ "$STAGE" = unknown ]; then grep -Fq -- '--- Create exact-ref deployment worktree ---' "$LOG" && STAGE="worktree" || true; fi

  if grep -Fq 'target ref is missing dayrui/CodeIgniter72/System/Cache/CacheFactory.php' "$LOG"; then ERROR_CLASS="framework_source_missing"
  elif grep -Fq 'frame.lock bytes are not exact' "$LOG"; then ERROR_CLASS="frame_lock_invalid"
  elif grep -Fq 'backup directory already exists' "$LOG"; then ERROR_CLASS="backup_id_collision"
  elif grep -Fq 'pre-deploy backup verification failed' "$LOG"; then ERROR_CLASS="backup_verification_failed"
  elif grep -Fq 'Database' "$LOG" && grep -Eiq 'mysqldump|database.*error|access denied' "$LOG"; then ERROR_CLASS="database_backup_failed"
  elif grep -Eiq 'rsync.*error|rsync error|failed to set times|permission denied' "$LOG"; then ERROR_CLASS="rsync_failed"
  elif grep -Fq 'CacheFactory.php missing after rsync' "$LOG"; then ERROR_CLASS="framework_postdeploy_missing"
  elif grep -Fq 'homepage template missing' "$LOG"; then ERROR_CLASS="homepage_template_missing"
  elif grep -Fq 'endpoint verification failed' "$LOG"; then ERROR_CLASS="endpoint_verification_failed"
  elif grep -Fq 'rendered homepage still contains robots=none' "$LOG"; then ERROR_CLASS="home_noindex_after_deploy"
  elif grep -Eiq 'health.*fail|HTTP.*500|php.*fatal|parse error|syntax error' "$LOG"; then ERROR_CLASS="health_or_template_runtime_failed"
  elif grep -Fq 'ERROR:' "$LOG"; then ERROR_CLASS="other_deploy_error"
  else ERROR_CLASS="no_error_marker_found"
  fi
fi

HOME_HTTP=$(curl -skL --max-time 20 -o /dev/null -w '%{http_code}' "$CANONICAL/" || echo 0)
ARTICLE_HTTP=$(curl -skL --max-time 20 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=91" || echo 0)
CATEGORY_HTTP=$(curl -skL --max-time 20 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=category&id=7" || echo 0)
PROD_SEO_HEADER="NO"
[ -f "$WEBROOT/template/pc/default/home/seo_header.html" ] && PROD_SEO_HEADER="YES"
PROD_LEGACY_ARTICLE="NO"
if grep -Fq 'content="none"' "$WEBROOT/template/pc/default/home/article.html" 2>/dev/null; then PROD_LEGACY_ARTICLE="YES"; fi
GIT_SEO_HEADER="NO"
git -C "$REPO" fetch --prune origin >/dev/null 2>&1 || true
if git -C "$REPO" cat-file -e 'origin/main:site/template/pc/default/home/seo_header.html' 2>/dev/null; then GIT_SEO_HEADER="YES"; fi

python3 - "$RESULT_FILE" "$LOG_EXISTS" "$STAGE" "$ERROR_CLASS" "$HOME_HTTP" "$ARTICLE_HTTP" "$CATEGORY_HTTP" "$PROD_SEO_HEADER" "$PROD_LEGACY_ARTICLE" "$GIT_SEO_HEADER" <<'PY'
import json,sys
(out,log_exists,stage,error_class,home,article,category,prod_header,legacy_article,git_header)=sys.argv[1:]
payload={
 'task':'diagnose_seo_phase1_deploy',
 'diagnosis_status':'PASS',
 'blocking_item':'NONE',
 'failed_deploy_log_exists':log_exists,
 'last_deploy_stage':stage,
 'error_class':error_class,
 'production_home_http':int(home),
 'production_article91_http':int(article),
 'production_category7_http':int(category),
 'production_seo_header_present':prod_header,
 'production_legacy_article_restored':legacy_article,
 'git_main_seo_header_present':git_header,
 'secrets_disclosed':False,
}
with open(out,'w',encoding='utf-8') as f:
 json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

echo "SEO_PHASE1_DEPLOY_DIAGNOSIS=PASS class=$ERROR_CLASS stage=$STAGE"
