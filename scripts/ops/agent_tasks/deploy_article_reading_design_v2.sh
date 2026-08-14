#!/bin/bash
# Cache-atomic deployment of article reading typography to PC/mobile show templates only.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="b03644009e6b532ed00a0b4c0aab862d7520562c"
ARTICLE_URL="$CANONICAL/index.php?c=show&id=92"
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
FILES=("template/pc/default/home/show.html" "template/mobile/default/home/show.html")
CACHES=("cache/template/template_DS_pc_DS_default_DS_home_DS_show.html.cache.php" "cache/template/template_DS_mobile_DS_default_DS_home_DS_show.html.cache.php")
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
TMP=$(mktemp -d /tmp/xyptdq-article-design-v2.XXXXXX); trap 'rm -rf "$TMP"' EXIT
PHASE=init; DEPLOY=NO; ROLLBACK=NO; PC_HTTP=0; MOBILE_HTTP=0; PC_STYLE=NO; MOBILE_STYLE=NO; META_STABLE=NO; CRON_BEFORE=-1; CRON_AFTER=-1; BLOCKER=NONE
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
write_result(){ python3 - "$RESULT_FILE" "$1" "$PHASE" "$DEPLOY" "$ROLLBACK" "$PC_HTTP" "$MOBILE_HTTP" "$PC_STYLE" "$MOBILE_STYLE" "$META_STABLE" "$CRON_BEFORE" "$CRON_AFTER" "$BLOCKER" <<'PY'
import json,sys
out,status,phase,deploy,rollback,ph,mh,ps,ms,meta,cb,ca,block=sys.argv[1:]
p={'task':'deploy_article_reading_design_v2','status':status,'phase':phase,'deploy':deploy,'rollback':rollback,'pc_http':int(ph),'mobile_http':int(mh),'pc_article_reading_style':ps,'mobile_article_reading_style':ms,'title_canonical_stable':meta,'publisher_cron_count_before':int(cb),'publisher_cron_count_after':int(ca),'blocking_item':block,'targeted_cache_invalidation':True,'whole_cache_cleared':False,'database_changed':False,'article_publishing_attempted':False,'publisher_queue_consumed':False}
json.dump(p,open(out,'w',encoding='utf-8'),ensure_ascii=False,indent=2,sort_keys=True); open(out,'a').write('\n')
PY
}
snapshot(){ mkdir -p "$TMP/source" "$TMP/before" "$TMP/cache_before"; for rel in "${FILES[@]}"; do [ -f "$WEBROOT/$rel" ] || return 1; mkdir -p "$TMP/before/$(dirname "$rel")" "$TMP/source/$(dirname "$rel")"; cp -a "$WEBROOT/$rel" "$TMP/before/$rel"; git -C "$REPO" show "$TARGET_SHA:site/$rel" > "$TMP/source/$rel"; done; : > "$TMP/cache_presence"; for rel in "${CACHES[@]}"; do mkdir -p "$TMP/cache_before/$(dirname "$rel")"; if [ -f "$WEBROOT/$rel" ]; then echo "1 $rel" >> "$TMP/cache_presence"; cp -a "$WEBROOT/$rel" "$TMP/cache_before/$rel"; else echo "0 $rel" >> "$TMP/cache_presence"; fi; done; }
rollback_all(){ set +e; for rel in "${FILES[@]}"; do [ -f "$TMP/before/$rel" ] && install -o www-data -g www-data -m 0644 "$TMP/before/$rel" "$WEBROOT/$rel"; done; while read -r had rel; do if [ "$had" = 1 ]; then mkdir -p "$WEBROOT/$(dirname "$rel")"; cp -a "$TMP/cache_before/$rel" "$WEBROOT/$rel"; else rm -f "$WEBROOT/$rel"; fi; done < "$TMP/cache_presence"; ROLLBACK=YES; set -e; }
block(){ BLOCKER="$1"; [ "$DEPLOY" = PASS ] && rollback_all; CRON_AFTER=$(cron_count); write_result BLOCKED; echo "DEPLOY_ARTICLE_READING_DESIGN_V2=BLOCKED item=$BLOCKER" >&2; exit 10; }
PHASE=repo_sync; git -C "$REPO" fetch --quiet origin main || block git_fetch_failed; git -C "$REPO" merge-base --is-ancestor "$TARGET_SHA" origin/main || block target_not_in_main
PHASE=source_verify; git -C "$REPO" show "$TARGET_SHA:site/template/pc/default/home/show.html" | grep -Fq 'xyptdq-content xyptdq-article-prose' || block pc_source_marker_missing; git -C "$REPO" show "$TARGET_SHA:site/template/mobile/default/home/show.html" | grep -Fq 'xrcontent xyptdq-article-prose' || block mobile_source_marker_missing
PHASE=baseline; CRON_BEFORE=$(cron_count); PC_HTTP=$(curl -skL --max-time 25 -o "$TMP/pc.before" -w '%{http_code}' "$ARTICLE_URL" || true); MOBILE_HTTP=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mobile.before" -w '%{http_code}' "$ARTICLE_URL" || true); [ "$PC_HTTP" = 200 ] && [ "$MOBILE_HTTP" = 200 ] || block baseline_http_error; extract "$TMP/pc.before" title > "$TMP/pt"; extract "$TMP/pc.before" canonical > "$TMP/pc"; extract "$TMP/mobile.before" title > "$TMP/mt"; extract "$TMP/mobile.before" canonical > "$TMP/mc"
PHASE=snapshot; snapshot || block production_template_missing
PHASE=deploy; for rel in "${FILES[@]}"; do install -o www-data -g www-data -m 0644 "$TMP/source/$rel" "$WEBROOT/$rel"; done; for rel in "${CACHES[@]}"; do rm -f "$WEBROOT/$rel"; done; DEPLOY=PASS
PHASE=render_verify; PC_HTTP=$(curl -skL --max-time 25 -o "$TMP/pc.after" -w '%{http_code}' "$ARTICLE_URL" || true); MOBILE_HTTP=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mobile.after" -w '%{http_code}' "$ARTICLE_URL" || true); [ "$PC_HTTP" = 200 ] && [ "$MOBILE_HTTP" = 200 ] || block post_http_error; [ "$(extract "$TMP/pc.after" title)" = "$(cat "$TMP/pt")" ] || block pc_title_changed; [ "$(extract "$TMP/pc.after" canonical)" = "$(cat "$TMP/pc")" ] || block pc_canonical_changed; [ "$(extract "$TMP/mobile.after" title)" = "$(cat "$TMP/mt")" ] || block mobile_title_changed; [ "$(extract "$TMP/mobile.after" canonical)" = "$(cat "$TMP/mc")" ] || block mobile_canonical_changed; META_STABLE=PASS; grep -Fq '.xyptdq-article-prose' "$TMP/pc.after" && grep -Fq 'xyptdq-content xyptdq-article-prose' "$TMP/pc.after" || block pc_render_style_missing; PC_STYLE=PASS; grep -Fq '.xyptdq-article-prose' "$TMP/mobile.after" && grep -Fq 'xrcontent xyptdq-article-prose' "$TMP/mobile.after" || block mobile_render_style_missing; MOBILE_STYLE=PASS
PHASE=publisher_safety; CRON_AFTER=$(cron_count); [ "$CRON_AFTER" -eq "$CRON_BEFORE" ] || block publisher_cron_changed
PHASE=final; write_result PASS; echo "DEPLOY_ARTICLE_READING_DESIGN_V2=PASS"
