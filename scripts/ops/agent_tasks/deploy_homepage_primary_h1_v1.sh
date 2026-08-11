#!/bin/bash
# Rollback-gated production deployment for homepage primary-keyword H1.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="e30c095fc0651c47de92ed39495d043b320e5b66"
EXPECTED_H1='信誉平台大全：彩票数据研究、方案验证与平台资料导航'
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"

PHASE="init"
DEPLOY="NO"
ROLLBACK="NO"
HOME_HTTP=0
CATEGORY_HTTP=0
ARTICLE_HTTP=0
PLATFORM_HTTP=0
H1_COUNT=-1
H1_PRIMARY="NO"
PLATFORM_DETAIL_LINKS=-1
CANONICAL_HOME="NO"
FRAMEWORK_OK="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
TMP="$(mktemp -d /tmp/xyptdq-home-h1-deploy.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload(){
  local status="$1"
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$ROLLBACK" \
    "$HOME_HTTP" "$CATEGORY_HTTP" "$ARTICLE_HTTP" "$PLATFORM_HTTP" "$H1_COUNT" "$H1_PRIMARY" \
    "$PLATFORM_DETAIL_LINKS" "$CANONICAL_HOME" "$FRAMEWORK_OK" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,target,deploy,rollback,home,category,article,platform,h1_count,h1_primary,
 platform_links,canonical_home,framework,error_class,blocker)=sys.argv[1:]
payload={
  "task":"deploy_homepage_primary_h1_v1",
  "deployment_status":status,
  "phase":phase,
  "target_sha":target,
  "deploy":deploy,
  "rollback":rollback,
  "home_http":int(home),
  "category7_http":int(category),
  "article91_http":int(article),
  "platform19_http":int(platform),
  "home_h1_count":int(h1_count),
  "home_h1_contains_primary_keyword":h1_primary,
  "platform_detail_link_count":int(platform_links),
  "home_canonical":canonical_home,
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
  echo "[home-h1-deploy] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
  exit 1
}

cd "$REPO"
PHASE="repo_sync"
git fetch --prune origin >/dev/null 2>&1
git merge-base --is-ancestor "$TARGET_SHA" origin/main || { ERROR_CLASS="target_not_in_main"; block target_not_in_main; }

PHASE="source_verify"
git show "$TARGET_SHA:site/template/pc/default/home/index.html" > "$TMP/index.src"
grep -Fq "<h1>$EXPECTED_H1</h1>" "$TMP/index.src" || { ERROR_CLASS="expected_h1_source_missing"; block expected_h1_source_missing; }
[ "$(grep -o '<h1\b' "$TMP/index.src" | wc -l | tr -d ' ')" -eq 1 ] || { ERROR_CLASS="source_h1_not_single"; block source_h1_not_single; }

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
HOME_HTTP=$(curl -skL --max-time 30 -o "$TMP/home.html" -w '%{http_code}' "$CANONICAL/")
CATEGORY_HTTP=$(curl -skL --max-time 30 -o "$TMP/category.html" -w '%{http_code}' "$CANONICAL/index.php?c=category&id=7")
ARTICLE_HTTP=$(curl -skL --max-time 30 -o "$TMP/article.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=91")
PLATFORM_HTTP=$(curl -skL --max-time 30 -o "$TMP/platform.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=19")
for v in "$HOME_HTTP" "$CATEGORY_HTTP" "$ARTICLE_HTTP" "$PLATFORM_HTTP"; do
  [ "$v" = 200 ] || { ERROR_CLASS="representative_http_not_200"; block representative_http_not_200; }
done

python3 - "$TMP/home.html" "$EXPECTED_H1" <<'PY' > "$TMP/home.status"
import html,re,sys
path,expected=sys.argv[1:]
s=open(path,encoding='utf-8',errors='ignore').read()
h1s=[]
for m in re.finditer(r'<h1\b[^>]*>(.*?)</h1\s*>',s,re.I|re.S):
    v=re.sub(r'<[^>]+>',' ',m.group(1))
    h1s.append(re.sub(r'\s+',' ',html.unescape(v)).strip())
links=0
for a in re.findall(r'<a\b[^>]*>',s,re.I|re.S):
    t=re.search(r'\btitle\s*=\s*["\']([^"\']*)["\']',a,re.I|re.S)
    if t and html.unescape(t.group(1)).strip().endswith('平台资料详情'):
        links+=1
canonical=False
for tag in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
    rel=re.search(r'\brel\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    href=re.search(r'\bhref\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    if rel and 'canonical' in html.unescape(rel.group(1)).lower().split() and href:
        canonical=html.unescape(href.group(1)).strip()=='https://www.laocaimi.org/'
        break
print(len(h1s), 'YES' if (len(h1s)==1 and h1s[0]==expected and '信誉平台大全' in h1s[0]) else 'NO', links, 'PASS' if canonical else 'NO', sep='\t')
PY
IFS=$'\t' read -r H1_COUNT H1_PRIMARY PLATFORM_DETAIL_LINKS CANONICAL_HOME < "$TMP/home.status"
[ "$H1_COUNT" -eq 1 ] || { ERROR_CLASS="rendered_h1_not_single"; block rendered_h1_not_single; }
[ "$H1_PRIMARY" = YES ] || { ERROR_CLASS="primary_keyword_h1_missing"; block primary_keyword_h1_missing; }
[ "$PLATFORM_DETAIL_LINKS" -ge 20 ] || { ERROR_CLASS="platform_internal_links_regressed"; block platform_internal_links_regressed; }
[ "$CANONICAL_HOME" = PASS ] || { ERROR_CLASS="home_canonical_regressed"; block home_canonical_regressed; }

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
echo "HOMEPAGE_PRIMARY_H1_V1=PASS"
