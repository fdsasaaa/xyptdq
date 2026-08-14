#!/bin/bash
# Deploy article typography through the actual production PC shell used by both desktop and mobile UA.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="b03644009e6b532ed00a0b4c0aab862d7520562c"
ARTICLE_URL="$CANONICAL/index.php?c=show&id=92"
SOURCE_REL="template/pc/default/home/show.html"
CACHE_REL="cache/template/template_DS_pc_DS_default_DS_home_DS_show.html.cache.php"
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
TMP=$(mktemp -d /tmp/xyptdq-article-design-v3.XXXXXX); trap 'rm -rf "$TMP"' EXIT
DEPLOY=NO; ROLLBACK=NO; BLOCKER=NONE; PC_HTTP=0; MOBILE_HTTP=0; PC_STYLE=NO; MOBILE_STYLE=NO; META_STABLE=NO; CRON_BEFORE=-1; CRON_AFTER=-1
cron_count(){ local n=0; [ -f /etc/cron.d/xyptdq-publisher ] && n=$((n+1)); local u; u=$( (crontab -l 2>/dev/null || true) | grep -c 'run_scheduled_publish.sh' || true ); echo $((n+u)); }
extract(){ python3 - "$1" "$2" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read(); k=sys.argv[2]
def attr(tag,n):
 m=re.search(r'\b'+re.escape(n)+r'\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S); return html.unescape(m.group(1).strip()) if m else ''
def text(tag):
 m=re.search(r'<'+tag+r'\b[^>]*>(.*?)</'+tag+r'\s*>',s,re.I|re.S); return re.sub(r'\s+',' ',html.unescape(re.sub(r'<[^>]+>',' ',m.group(1)))).strip() if m else ''
if k=='title': print(text('title'))
elif k=='canonical':
 for t in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
  if 'canonical' in attr(t,'rel').lower().split(): print(attr(t,'href')); break
PY
}
write_result(){ python3 - "$RESULT_FILE" "$1" "$DEPLOY" "$ROLLBACK" "$PC_HTTP" "$MOBILE_HTTP" "$PC_STYLE" "$MOBILE_STYLE" "$META_STABLE" "$CRON_BEFORE" "$CRON_AFTER" "$BLOCKER" <<'PY'
import json,sys
out,status,deploy,rollback,ph,mh,ps,ms,meta,cb,ca,block=sys.argv[1:]
p={'task':'deploy_article_reading_design_v3','status':status,'deploy':deploy,'rollback':rollback,'pc_http':int(ph),'mobile_http':int(mh),'pc_article_reading_style':ps,'mobile_article_reading_style_via_pc_shell':ms,'title_canonical_stable':meta,'publisher_cron_count_before':int(cb),'publisher_cron_count_after':int(ca),'blocking_item':block,'actual_mobile_shell':'pc','targeted_cache_invalidation':True,'whole_cache_cleared':False,'database_changed':False,'article_publishing_attempted':False,'publisher_queue_consumed':False}
json.dump(p,open(out,'w',encoding='utf-8'),ensure_ascii=False,indent=2,sort_keys=True); open(out,'a').write('\n')
PY
}
rollback_all(){ set +e; [ -f "$TMP/source.before" ] && install -o www-data -g www-data -m 0644 "$TMP/source.before" "$WEBROOT/$SOURCE_REL"; if [ -f "$TMP/cache.had" ]; then mkdir -p "$WEBROOT/$(dirname "$CACHE_REL")"; cp -a "$TMP/cache.before" "$WEBROOT/$CACHE_REL"; else rm -f "$WEBROOT/$CACHE_REL"; fi; ROLLBACK=YES; set -e; }
block(){ BLOCKER="$1"; [ "$DEPLOY" = PASS ] && rollback_all; CRON_AFTER=$(cron_count); write_result BLOCKED; echo "DEPLOY_ARTICLE_READING_DESIGN_V3=BLOCKED item=$BLOCKER" >&2; exit 10; }
git -C "$REPO" fetch --quiet origin main || block git_fetch_failed
git -C "$REPO" merge-base --is-ancestor "$TARGET_SHA" origin/main || block target_not_in_main
git -C "$REPO" show "$TARGET_SHA:site/$SOURCE_REL" > "$TMP/source.new" || block source_read_failed
grep -Fq 'xyptdq-content xyptdq-article-prose' "$TMP/source.new" || block source_marker_missing
CRON_BEFORE=$(cron_count)
PC_HTTP=$(curl -skL --max-time 25 -o "$TMP/pc.before" -w '%{http_code}' "$ARTICLE_URL" || true)
MOBILE_HTTP=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mobile.before" -w '%{http_code}' "$ARTICLE_URL" || true)
[ "$PC_HTTP" = 200 ] && [ "$MOBILE_HTTP" = 200 ] || block baseline_http_error
grep -Fq 'xyptdq-site-header' "$TMP/mobile.before" || block mobile_not_using_pc_shell
extract "$TMP/pc.before" title > "$TMP/pt"; extract "$TMP/pc.before" canonical > "$TMP/pc"; extract "$TMP/mobile.before" title > "$TMP/mt"; extract "$TMP/mobile.before" canonical > "$TMP/mc"
[ -f "$WEBROOT/$SOURCE_REL" ] || block production_source_missing
cp -a "$WEBROOT/$SOURCE_REL" "$TMP/source.before"
if [ -f "$WEBROOT/$CACHE_REL" ]; then cp -a "$WEBROOT/$CACHE_REL" "$TMP/cache.before"; touch "$TMP/cache.had"; fi
install -o www-data -g www-data -m 0644 "$TMP/source.new" "$WEBROOT/$SOURCE_REL"
rm -f "$WEBROOT/$CACHE_REL"
DEPLOY=PASS
PC_HTTP=$(curl -skL --max-time 25 -o "$TMP/pc.after" -w '%{http_code}' "$ARTICLE_URL" || true)
MOBILE_HTTP=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mobile.after" -w '%{http_code}' "$ARTICLE_URL" || true)
[ "$PC_HTTP" = 200 ] && [ "$MOBILE_HTTP" = 200 ] || block post_http_error
[ "$(extract "$TMP/pc.after" title)" = "$(cat "$TMP/pt")" ] || block pc_title_changed
[ "$(extract "$TMP/pc.after" canonical)" = "$(cat "$TMP/pc")" ] || block pc_canonical_changed
[ "$(extract "$TMP/mobile.after" title)" = "$(cat "$TMP/mt")" ] || block mobile_title_changed
[ "$(extract "$TMP/mobile.after" canonical)" = "$(cat "$TMP/mc")" ] || block mobile_canonical_changed
META_STABLE=PASS
grep -Fq '.xyptdq-article-prose' "$TMP/pc.after" && grep -Fq 'xyptdq-content xyptdq-article-prose' "$TMP/pc.after" || block pc_render_style_missing
PC_STYLE=PASS
grep -Fq 'xyptdq-site-header' "$TMP/mobile.after" && grep -Fq '.xyptdq-article-prose' "$TMP/mobile.after" && grep -Fq 'xyptdq-content xyptdq-article-prose' "$TMP/mobile.after" || block mobile_pc_shell_style_missing
MOBILE_STYLE=PASS
CRON_AFTER=$(cron_count); [ "$CRON_AFTER" -eq "$CRON_BEFORE" ] || block publisher_cron_changed
write_result PASS
echo "DEPLOY_ARTICLE_READING_DESIGN_V3=PASS"
