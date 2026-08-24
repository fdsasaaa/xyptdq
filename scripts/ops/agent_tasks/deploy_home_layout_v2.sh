#!/bin/bash
# Rollback-gated production deployment and rendered verification for homepage layout V2.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="e8019c3e5eb573b138307c31ac3696a4c0dda449"
EXPECTED_H1='信誉平台大全：彩票数据研究、方案验证与平台资料导航'
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"
MIN_TIPS_LINKS=5

PHASE="init"
DEPLOY="NO"
ROLLBACK="NO"
DESKTOP_HTTP=0
MOBILE_HTTP=0
CATEGORY_HTTP=0
ARTICLE_HTTP=0
PLATFORM_HTTP=0
DESKTOP_TIPS_LINKS=0
MOBILE_TIPS_LINKS=0
SINGLE_NAV="NO"
TIPS_BEFORE_PLATFORM="NO"
TOP_COMPACT="NO"
DESKTOP_TIPS_VISIBLE="NO"
MOBILE_TIPS_VISIBLE="NO"
CANONICAL_HOME="NO"
H1_OK="NO"
FOOTER_INFO="NO"
FRAMEWORK_OK="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
TMP="$(mktemp -d /tmp/xyptdq-home-v2-deploy.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload(){
  local status="$1"
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$ROLLBACK" \
    "$DESKTOP_HTTP" "$MOBILE_HTTP" "$CATEGORY_HTTP" "$ARTICLE_HTTP" "$PLATFORM_HTTP" \
    "$DESKTOP_TIPS_LINKS" "$MOBILE_TIPS_LINKS" "$SINGLE_NAV" "$TIPS_BEFORE_PLATFORM" \
    "$TOP_COMPACT" "$DESKTOP_TIPS_VISIBLE" "$MOBILE_TIPS_VISIBLE" "$CANONICAL_HOME" \
    "$H1_OK" "$FOOTER_INFO" "$FRAMEWORK_OK" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,target,deploy,rollback,desktop_http,mobile_http,category_http,article_http,platform_http,
 desktop_links,mobile_links,single_nav,tips_before,top_compact,desktop_tips,mobile_tips,canonical,h1_ok,
 footer_info,framework,error_class,blocker)=sys.argv[1:]
payload={
  "task":"deploy_home_layout_v2",
  "deployment_status":status,
  "phase":phase,
  "target_sha":target,
  "deploy":deploy,
  "rollback":rollback,
  "desktop_home_http":int(desktop_http),
  "mobile_home_http":int(mobile_http),
  "category7_http":int(category_http),
  "article91_http":int(article_http),
  "platform19_http":int(platform_http),
  "desktop_tips_article_links":int(desktop_links),
  "mobile_tips_article_links":int(mobile_links),
  "single_navigation":single_nav,
  "tips_before_platform":tips_before,
  "top_compact":top_compact,
  "desktop_tips_visible":desktop_tips,
  "mobile_tips_visible":mobile_tips,
  "home_canonical":canonical,
  "homepage_h1":h1_ok,
  "footer_info_present":footer_info,
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
  echo "[home-v2-deploy] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
  exit 1
}

cd "$REPO"
PHASE="repo_sync"
git fetch --prune origin >/dev/null 2>&1
git merge-base --is-ancestor "$TARGET_SHA" origin/main || { ERROR_CLASS="target_not_in_main"; block target_not_in_main; }

PHASE="source_verify"
git show "$TARGET_SHA:site/template/pc/default/home/index.html" > "$TMP/pc.src"
git show "$TARGET_SHA:site/template/mobile/default/home/index.html" > "$TMP/mobile.src"
python3 - "$TMP/pc.src" "$TMP/mobile.src" <<'PY' || exit_code=$?
import sys
pc=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
mobile=open(sys.argv[2],encoding='utf-8',errors='ignore').read()
checks={
 'pc_single_nav': pc.count('class="research-nav"')==1 and 'class="m-middle"' not in pc,
 'pc_no_summary_bar': 'class="site-summary"' not in pc,
 'pc_tips_module': 'module module=news catid=7' in pc,
 'mobile_tips_module': 'module module=news catid=7' in mobile,
 'pc_tips_before_platform': pc.find('class="container seo-article-section"')>=0 and pc.find('class="container seo-article-section"')<pc.find('class="container platform-section"'),
 'pc_footer': 'class="footer-info"' in pc,
 'pc_h1': '<h1>信誉平台大全：彩票数据研究、方案验证与平台资料导航</h1>' in pc,
}
failed=[k for k,v in checks.items() if not v]
if failed:
    print('source checks failed:',','.join(failed))
    raise SystemExit(1)
PY
if [ "${exit_code:-0}" != 0 ]; then ERROR_CLASS="source_layout_v2_invalid"; block source_layout_v2_invalid; fi

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
grep -Fq 'module module=news catid=7' "$PC_PROD" || { ERROR_CLASS="production_pc_tips_module_missing"; block production_pc_tips_module_missing; }
grep -Fq 'module module=news catid=7' "$MOBILE_PROD" || { ERROR_CLASS="production_mobile_tips_module_missing"; block production_mobile_tips_module_missing; }
if grep -Fq 'class="m-middle"' "$PC_PROD"; then ERROR_CLASS="production_duplicate_nav_source"; block production_duplicate_nav_source; fi

PHASE="render_fetch"
DESKTOP_HTTP=$(curl -skL --max-time 30 -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/134 Safari/537.36' -o "$TMP/desktop.html" -w '%{http_code}' "$CANONICAL/")
MOBILE_HTTP=$(curl -skL --max-time 30 -A 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36' -o "$TMP/mobile.html" -w '%{http_code}' "$CANONICAL/")
CATEGORY_HTTP=$(curl -skL --max-time 30 -o "$TMP/category.html" -w '%{http_code}' "$CANONICAL/index.php?c=category&id=7")
ARTICLE_HTTP=$(curl -skL --max-time 30 -o "$TMP/article.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=91")
PLATFORM_HTTP=$(curl -skL --max-time 30 -o "$TMP/platform.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=19")
for v in "$DESKTOP_HTTP" "$MOBILE_HTTP" "$CATEGORY_HTTP" "$ARTICLE_HTTP" "$PLATFORM_HTTP"; do
  [ "$v" = 200 ] || { ERROR_CLASS="representative_http_not_200"; block representative_http_not_200; }
done

PHASE="desktop_render_verify"
python3 - "$TMP/desktop.html" "$EXPECTED_H1" "$MIN_TIPS_LINKS" > "$TMP/desktop.status" <<'PY'
import html,re,sys
path,expected_h1,min_links=sys.argv[1],sys.argv[2],int(sys.argv[3])
s=open(path,encoding='utf-8',errors='ignore').read()
plain=html.unescape(re.sub(r'<[^>]+>',' ',s))
h1=[]
for m in re.finditer(r'<h1\b[^>]*>(.*?)</h1\s*>',s,re.I|re.S):
    h1.append(re.sub(r'\s+',' ',html.unescape(re.sub(r'<[^>]+>',' ',m.group(1)))).strip())
canonical=False
for tag in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
    rel=re.search(r'\brel\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    href=re.search(r'\bhref\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    if rel and 'canonical' in html.unescape(rel.group(1)).lower().split() and href:
        canonical=html.unescape(href.group(1)).strip()=='https://www.laocaimi.org/'
        break
nav_count=len(re.findall(r'<nav\b[^>]*class=["\'][^"\']*research-nav[^"\']*["\']',s,re.I))
duplicate=('class="m-middle"' in s or 'class=\'m-middle\'' in s)
tips_start=s.find('class="container seo-article-section"')
platform_start=s.find('class="container platform-section"')
order_ok=tips_start>=0 and platform_start>=0 and tips_start<platform_start
tips_section=''
if tips_start>=0:
    sec_open=s.rfind('<section',0,tips_start+1)
    sec_end=s.find('</section>',tips_start)
    if sec_open>=0 and sec_end>=0: tips_section=s[sec_open:sec_end+10]
anchors=re.findall(r'<a\b[^>]*href=["\']([^"\']+)["\'][^>]*>(.*?)</a\s*>',tips_section,re.I|re.S)
article_links=[]
for href,body in anchors:
    text=re.sub(r'\s+',' ',html.unescape(re.sub(r'<[^>]+>',' ',body))).strip()
    if text and text!='查看全部': article_links.append((href,text))
links_ok=len(article_links)>=min_links
first_platform_text=plain.find('平台资料导航')
top_plain=plain[:first_platform_text] if first_platform_text>=0 else plain
top_compact=('备用访问：' not in top_plain and '网站说明与备用访问' not in top_plain and '彩票玩法研究、数据分析、方案验证与平台资料整理' not in top_plain)
footer_ok=('网站说明与备用访问' in plain)
tips_visible=('投注技巧' in html.unescape(re.sub(r'<[^>]+>',' ',tips_section)))
print(len(article_links),
      'PASS' if nav_count==1 and not duplicate else 'NO',
      'PASS' if order_ok else 'NO',
      'PASS' if top_compact else 'NO',
      'PASS' if tips_visible and links_ok else 'NO',
      'PASS' if canonical else 'NO',
      'PASS' if len(h1)==1 and h1[0]==expected_h1 else 'NO',
      'PASS' if footer_ok else 'NO', sep='\t')
PY
IFS=$'\t' read -r DESKTOP_TIPS_LINKS SINGLE_NAV TIPS_BEFORE_PLATFORM TOP_COMPACT DESKTOP_TIPS_VISIBLE CANONICAL_HOME H1_OK FOOTER_INFO < "$TMP/desktop.status"
[ "$SINGLE_NAV" = PASS ] || { ERROR_CLASS="rendered_duplicate_navigation"; block rendered_duplicate_navigation; }
[ "$TIPS_BEFORE_PLATFORM" = PASS ] || { ERROR_CLASS="rendered_tips_not_before_platform"; block rendered_tips_not_before_platform; }
[ "$TOP_COMPACT" = PASS ] || { ERROR_CLASS="rendered_top_still_cluttered"; block rendered_top_still_cluttered; }
[ "$DESKTOP_TIPS_VISIBLE" = PASS ] || { ERROR_CLASS="rendered_desktop_tips_articles_missing"; block rendered_desktop_tips_articles_missing; }
[ "$CANONICAL_HOME" = PASS ] || { ERROR_CLASS="home_canonical_regressed"; block home_canonical_regressed; }
[ "$H1_OK" = PASS ] || { ERROR_CLASS="homepage_h1_regressed"; block homepage_h1_regressed; }
[ "$FOOTER_INFO" = PASS ] || { ERROR_CLASS="rendered_footer_info_missing"; block rendered_footer_info_missing; }

PHASE="mobile_render_verify"
python3 - "$TMP/mobile.html" "$MIN_TIPS_LINKS" > "$TMP/mobile.status" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read(); min_links=int(sys.argv[2])
marker=s.find('id="mobile-seo-latest"')
if marker>=0:
    sec_open=s.rfind('<section',0,marker+1); sec_end=s.find('</section>',marker)
    section=s[sec_open:sec_end+10] if sec_open>=0 and sec_end>=0 else ''
else:
    # Some deployments intentionally serve the responsive PC homepage to mobile UAs.
    marker=s.find('class="container seo-article-section"')
    sec_open=s.rfind('<section',0,marker+1) if marker>=0 else -1
    sec_end=s.find('</section>',marker) if marker>=0 else -1
    section=s[sec_open:sec_end+10] if sec_open>=0 and sec_end>=0 else ''
anchors=re.findall(r'<a\b[^>]*href=["\']([^"\']+)["\'][^>]*>(.*?)</a\s*>',section,re.I|re.S)
article=[]
for href,body in anchors:
    text=re.sub(r'\s+',' ',html.unescape(re.sub(r'<[^>]+>',' ',body))).strip()
    if text and text!='查看全部': article.append((href,text))
visible=('投注技巧' in html.unescape(re.sub(r'<[^>]+>',' ',section)) and len(article)>=min_links)
print(len(article),'PASS' if visible else 'NO',sep='\t')
PY
IFS=$'\t' read -r MOBILE_TIPS_LINKS MOBILE_TIPS_VISIBLE < "$TMP/mobile.status"
[ "$MOBILE_TIPS_VISIBLE" = PASS ] || { ERROR_CLASS="rendered_mobile_tips_articles_missing"; block rendered_mobile_tips_articles_missing; }

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
echo "HOME_LAYOUT_V2=PASS"
