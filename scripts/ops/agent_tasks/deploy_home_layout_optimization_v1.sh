#!/bin/bash
# Rollback-gated production deployment for homepage information hierarchy optimization.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="a2119fd12ee6e5f5ddea056ffa15621e9250ca43"
EXPECTED_H1='信誉平台大全：彩票数据研究、方案验证与平台资料导航'
EXPECTED_SUMMARY='彩票玩法研究、数据分析、方案验证与平台资料整理'
EXPECTED_SECTION='投注技巧'
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"

PHASE="init"
DEPLOY="NO"
ROLLBACK="NO"
HOME_HTTP=0
CATEGORY_HTTP=0
ARTICLE_HTTP=0
PLATFORM_HTTP=0
HOME_SUMMARY="NO"
HOME_TIPS_SECTION="NO"
TOP_SEO_ARTICLE_NAV_REMOVED="NO"
TOP_CLUTTER_MOVED="NO"
FOOTER_INFO="NO"
MOBILE_TIPS_SECTION="NO"
CANONICAL_HOME="NO"
FRAMEWORK_OK="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
TMP="$(mktemp -d /tmp/xyptdq-home-layout-deploy.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload(){
  local status="$1"
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$ROLLBACK" \
    "$HOME_HTTP" "$CATEGORY_HTTP" "$ARTICLE_HTTP" "$PLATFORM_HTTP" "$HOME_SUMMARY" \
    "$HOME_TIPS_SECTION" "$TOP_SEO_ARTICLE_NAV_REMOVED" "$TOP_CLUTTER_MOVED" "$FOOTER_INFO" \
    "$MOBILE_TIPS_SECTION" "$CANONICAL_HOME" "$FRAMEWORK_OK" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,target,deploy,rollback,home,category,article,platform,summary,tips,nav_removed,
 clutter_moved,footer_info,mobile_tips,canonical_home,framework,error_class,blocker)=sys.argv[1:]
payload={
  "task":"deploy_home_layout_optimization_v1",
  "deployment_status":status,
  "phase":phase,
  "target_sha":target,
  "deploy":deploy,
  "rollback":rollback,
  "home_http":int(home),
  "category7_http":int(category),
  "article91_http":int(article),
  "platform19_http":int(platform),
  "home_summary_visible":summary,
  "home_tips_section_visible":tips,
  "top_seo_article_nav_removed":nav_removed,
  "top_clutter_moved_below_content":clutter_moved,
  "footer_info_present":footer_info,
  "mobile_tips_section_present":mobile_tips,
  "home_canonical":canonical_home,
  "framework_integrity":framework,
  "deploy_error_class":error_class,
  "blocking_item":blocker,
  "publisher_touched":False,
  "intake_touched":False,
  "draft_state_touched":False,
  "sitemap_logic_touched":False,
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
  echo "[home-layout-deploy] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
  exit 1
}

cd "$REPO"
PHASE="repo_sync"
git fetch --prune origin >/dev/null 2>&1
git merge-base --is-ancestor "$TARGET_SHA" origin/main || { ERROR_CLASS="target_not_in_main"; block target_not_in_main; }

PHASE="source_verify"
git show "$TARGET_SHA:site/template/pc/default/home/index.html" > "$TMP/index.src"
git show "$TARGET_SHA:site/template/mobile/default/home/index.html" > "$TMP/mobile.src"
grep -Fq "<h1>$EXPECTED_H1</h1>" "$TMP/index.src" || { ERROR_CLASS="expected_h1_source_missing"; block expected_h1_source_missing; }
grep -Fq "<div class=\"site-summary\">$EXPECTED_SUMMARY</div>" "$TMP/index.src" || { ERROR_CLASS="compact_summary_source_missing"; block compact_summary_source_missing; }
grep -Fq ">投注技巧" "$TMP/index.src" || { ERROR_CLASS="tips_heading_source_missing"; block tips_heading_source_missing; }
grep -Fq 'class="footer-info"' "$TMP/index.src" || { ERROR_CLASS="footer_info_source_missing"; block footer_info_source_missing; }
grep -Fq ">投注技巧</h2>" "$TMP/mobile.src" || { ERROR_CLASS="mobile_tips_heading_source_missing"; block mobile_tips_heading_source_missing; }
python3 - "$TMP/index.src" <<'PY' || { ERROR_CLASS="source_navigation_or_clutter_regressed"; block source_navigation_or_clutter_regressed; }
import re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
nav=re.search(r'<nav class="research-nav".*?</nav>',s,re.S)
if not nav: raise SystemExit(1)
if 'id=7' in nav.group(0) or 'SEO文章' in nav.group(0): raise SystemExit(2)
platform=s.find('<section class="container platform-section"')
if platform < 0: raise SystemExit(3)
top=s[:platform]
if '备用访问：' in top or '本站内容定位：' in top: raise SystemExit(4)
PY

PHASE="rollback_snapshot"
cp -a "$WEBROOT/template" "$TMP/template.before"

PHASE="deploy"
git show "$TARGET_SHA:scripts/deploy_safe.sh" > "$TMP/deploy_safe.sh" || { ERROR_CLASS="deploy_safe_missing"; block deploy_safe_missing; }
chmod 700 "$TMP/deploy_safe.sh"
if ! XYPTDQ_REPO_DIR="$REPO" XYPTDQ_WEBROOT="$WEBROOT" bash "$TMP/deploy_safe.sh" "$TARGET_SHA" >"$TMP/deploy.log" 2>&1; then
  ERROR_CLASS="canonical_deploy_failed"; block deploy_safe_failed
fi
DEPLOY="PASS"

PHASE="production_template_verify"
PC_PROD="$WEBROOT/template/pc/default/home/index.html"
MOBILE_PROD="$WEBROOT/template/mobile/default/home/index.html"
[ -f "$PC_PROD" ] || { ERROR_CLASS="production_pc_template_missing"; block production_pc_template_missing; }
[ -f "$MOBILE_PROD" ] || { ERROR_CLASS="production_mobile_template_missing"; block production_mobile_template_missing; }
grep -Fq "<div class=\"site-summary\">$EXPECTED_SUMMARY</div>" "$PC_PROD" || { ERROR_CLASS="production_summary_missing"; block production_summary_missing; }
grep -Fq 'class="footer-info"' "$PC_PROD" || { ERROR_CLASS="production_footer_info_missing"; block production_footer_info_missing; }
grep -Fq ">投注技巧</h2>" "$MOBILE_PROD" || { ERROR_CLASS="production_mobile_tips_missing"; block production_mobile_tips_missing; }
MOBILE_TIPS_SECTION="PASS"

PHASE="render_verify"
HOME_HTTP=$(curl -skL --max-time 30 -o "$TMP/home.html" -w '%{http_code}' "$CANONICAL/")
CATEGORY_HTTP=$(curl -skL --max-time 30 -o "$TMP/category.html" -w '%{http_code}' "$CANONICAL/index.php?c=category&id=7")
ARTICLE_HTTP=$(curl -skL --max-time 30 -o "$TMP/article.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=91")
PLATFORM_HTTP=$(curl -skL --max-time 30 -o "$TMP/platform.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=19")
for v in "$HOME_HTTP" "$CATEGORY_HTTP" "$ARTICLE_HTTP" "$PLATFORM_HTTP"; do
  [ "$v" = 200 ] || { ERROR_CLASS="representative_http_not_200"; block representative_http_not_200; }
done

python3 - "$TMP/home.html" "$EXPECTED_H1" "$EXPECTED_SUMMARY" "$EXPECTED_SECTION" <<'PY' > "$TMP/home.status"
import html,re,sys
path,expected_h1,summary,tips=sys.argv[1:]
s=open(path,encoding='utf-8',errors='ignore').read()
h1s=[]
for m in re.finditer(r'<h1\b[^>]*>(.*?)</h1\s*>',s,re.I|re.S):
    v=re.sub(r'<[^>]+>',' ',m.group(1))
    h1s.append(re.sub(r'\s+',' ',html.unescape(v)).strip())
canonical=False
for tag in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
    rel=re.search(r'\brel\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    href=re.search(r'\bhref\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    if rel and 'canonical' in html.unescape(rel.group(1)).lower().split() and href:
        canonical=html.unescape(href.group(1)).strip()=='https://www.laocaimi.org/'
        break
nav=re.search(r'<nav class="research-nav".*?</nav>',s,re.I|re.S)
nav_ok=bool(nav) and 'SEO文章' not in html.unescape(re.sub(r'<[^>]+>',' ',nav.group(0)))
platform=s.find('<section class="container platform-section"')
top=s[:platform] if platform >= 0 else s
clutter_ok=('备用访问：' not in top and '本站内容定位：' not in top)
summary_ok=summary in html.unescape(re.sub(r'<[^>]+>',' ',s))
tips_ok=bool(re.search(r'<h2\b[^>]*>\s*'+re.escape(tips)+r'\b',s,re.I|re.S))
footer_ok='class="footer-info"' in s and '网站说明与备用访问' in s
h1_ok=(len(h1s)==1 and h1s[0]==expected_h1)
print('PASS' if summary_ok else 'NO',
      'PASS' if tips_ok else 'NO',
      'PASS' if nav_ok else 'NO',
      'PASS' if clutter_ok else 'NO',
      'PASS' if footer_ok else 'NO',
      'PASS' if canonical else 'NO',
      'PASS' if h1_ok else 'NO', sep='\t')
PY
IFS=$'\t' read -r HOME_SUMMARY HOME_TIPS_SECTION TOP_SEO_ARTICLE_NAV_REMOVED TOP_CLUTTER_MOVED FOOTER_INFO CANONICAL_HOME H1_OK < "$TMP/home.status"
[ "$HOME_SUMMARY" = PASS ] || { ERROR_CLASS="rendered_summary_missing"; block rendered_summary_missing; }
[ "$HOME_TIPS_SECTION" = PASS ] || { ERROR_CLASS="rendered_tips_section_missing"; block rendered_tips_section_missing; }
[ "$TOP_SEO_ARTICLE_NAV_REMOVED" = PASS ] || { ERROR_CLASS="rendered_duplicate_nav_present"; block rendered_duplicate_nav_present; }
[ "$TOP_CLUTTER_MOVED" = PASS ] || { ERROR_CLASS="rendered_top_clutter_present"; block rendered_top_clutter_present; }
[ "$FOOTER_INFO" = PASS ] || { ERROR_CLASS="rendered_footer_info_missing"; block rendered_footer_info_missing; }
[ "$CANONICAL_HOME" = PASS ] || { ERROR_CLASS="home_canonical_regressed"; block home_canonical_regressed; }
[ "$H1_OK" = PASS ] || { ERROR_CLASS="homepage_h1_regressed"; block homepage_h1_regressed; }

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
echo "HOME_LAYOUT_OPTIMIZATION_V1=PASS"
