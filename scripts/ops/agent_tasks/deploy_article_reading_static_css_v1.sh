#!/bin/bash
# Deploy a managed, tightly scoped article-reading CSS block to the live static bundle.
# No template/cache mutation, CMS write, queue consumption or cron change.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
ARTICLE_URL="https://www.laocaimi.org/index.php?c=show&id=92"
CSS_URL="https://www.laocaimi.org/static/default/pc/css/style.bundle.css"
CSS_REL="static/default/pc/css/style.bundle.css"
CSS_FILE="$WEBROOT/$CSS_REL"
MANAGED="$REPO/ops/assets/article_reading_design_v1.css"
BASE_SHA256="044f17e763fecd28709e79dc785c30512049691b1cf394d5a972b6607a71f055"
START='/* XYPTDQ_ARTICLE_READING_START */'
END='/* XYPTDQ_ARTICLE_READING_END */'
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
[ -n "$RESULT_FILE" ] || exit 2
[ "$(id -u)" -eq 0 ] || exit 3
[ -d "$REPO/.git" ] || exit 4
[ -f "$CSS_FILE" ] || exit 5
[ -f "$MANAGED" ] || exit 6
TMP=$(mktemp -d /tmp/xyptdq-article-static-css.XXXXXX); trap 'rm -rf "$TMP"' EXIT
DEPLOY=NO; ROLLBACK=NO; BLOCKER=NONE; PC_HTTP=0; MOBILE_HTTP=0; CSS_PUBLIC=NO; META_STABLE=NO; CRON_BEFORE=-1; CRON_AFTER=-1
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
write_result(){ python3 - "$RESULT_FILE" "$1" "$DEPLOY" "$ROLLBACK" "$PC_HTTP" "$MOBILE_HTTP" "$CSS_PUBLIC" "$META_STABLE" "$CRON_BEFORE" "$CRON_AFTER" "$BLOCKER" "$2" <<'PY'
import json,sys
out,status,deploy,rollback,ph,mh,css,meta,cb,ca,block,final_sha=sys.argv[1:]
p={'task':'deploy_article_reading_static_css_v1','status':status,'deploy':deploy,'rollback':rollback,'pc_http':int(ph),'mobile_http':int(mh),'public_css_marker':css,'title_canonical_stable':meta,'publisher_cron_count_before':int(cb),'publisher_cron_count_after':int(ca),'blocking_item':block,'css_path':'static/default/pc/css/style.bundle.css','css_url':'https://www.laocaimi.org/static/default/pc/css/style.bundle.css','base_sha256':'044f17e763fecd28709e79dc785c30512049691b1cf394d5a972b6607a71f055','final_sha256':final_sha,'managed_block':'XYPTDQ_ARTICLE_READING','templates_mutated':False,'template_cache_mutated':False,'whole_cache_cleared':False,'database_changed':False,'article_publishing_attempted':False,'publisher_queue_consumed':False}
json.dump(p,open(out,'w',encoding='utf-8'),ensure_ascii=False,indent=2,sort_keys=True); open(out,'a').write('\n')
PY
}
rollback_all(){ set +e; [ -f "$TMP/css.before" ] && cp -a "$TMP/css.before" "$CSS_FILE"; ROLLBACK=YES; set -e; }
block(){ BLOCKER="$1"; [ "$DEPLOY" = PASS ] && rollback_all; CRON_AFTER=$(cron_count); local sha=""; [ -f "$CSS_FILE" ] && sha=$(sha256sum "$CSS_FILE" | awk '{print $1}'); write_result BLOCKED "$sha"; echo "DEPLOY_ARTICLE_READING_STATIC_CSS_V1=BLOCKED item=$BLOCKER" >&2; exit 10; }
# Production repo must be canonical because the managed CSS asset is read from main.
[ -z "$(git -C "$REPO" status --porcelain 2>/dev/null)" ] || block production_repo_dirty
git -C "$REPO" fetch --quiet origin main || block git_fetch_failed
git -C "$REPO" checkout -q main || block checkout_main_failed
git -C "$REPO" reset --hard -q origin/main || block reset_main_failed
[ -f "$MANAGED" ] || block managed_css_missing_after_sync
grep -Fq "$START" "$MANAGED" || block managed_start_missing
grep -Fq "$END" "$MANAGED" || block managed_end_missing
[ "$(grep -Fc "$START" "$MANAGED")" -eq 1 ] || block managed_start_count
[ "$(grep -Fc "$END" "$MANAGED")" -eq 1 ] || block managed_end_count
# Capture baseline article metadata and require the already-active isolated Publisher cron.
CRON_BEFORE=$(cron_count); [ "$CRON_BEFORE" -eq 1 ] || block publisher_cron_not_1_before
PC_HTTP=$(curl -skL --max-time 25 -o "$TMP/pc.before" -w '%{http_code}' "$ARTICLE_URL" || true)
MOBILE_HTTP=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mobile.before" -w '%{http_code}' "$ARTICLE_URL" || true)
[ "$PC_HTTP" = 200 ] && [ "$MOBILE_HTTP" = 200 ] || block baseline_http_error
extract "$TMP/pc.before" title > "$TMP/pt"; extract "$TMP/pc.before" canonical > "$TMP/pc"
extract "$TMP/mobile.before" title > "$TMP/mt"; extract "$TMP/mobile.before" canonical > "$TMP/mc"
grep -Fq "$CSS_URL" "$TMP/pc.before" || block article_does_not_load_target_css
grep -Fq "$CSS_URL" "$TMP/mobile.before" || block mobile_article_does_not_load_target_css
cp -a "$CSS_FILE" "$TMP/css.before"
# Strip an existing managed block if present, validate the untouched base bundle hash, then append exactly one canonical block.
python3 - "$CSS_FILE" "$MANAGED" "$TMP/css.base" "$TMP/css.new" <<'PY' || block managed_block_parse_failed
import pathlib,sys
src,managed,base,out=map(pathlib.Path,sys.argv[1:])
s=src.read_text(encoding='utf-8',errors='strict'); m=managed.read_text(encoding='utf-8',errors='strict').strip()+"\n"
start='/* XYPTDQ_ARTICLE_READING_START */'; end='/* XYPTDQ_ARTICLE_READING_END */'
sc=s.count(start); ec=s.count(end)
if sc!=ec or sc>1: raise SystemExit(2)
if sc==1:
 a=s.index(start); b=s.index(end,a)+len(end)
 s=(s[:a].rstrip()+"\n"+s[b:].lstrip()).rstrip()+"\n"
base.write_text(s,encoding='utf-8',newline='\n')
out.write_text(s.rstrip()+"\n\n"+m,encoding='utf-8',newline='\n')
PY
BASE_ACTUAL=$(sha256sum "$TMP/css.base" | awk '{print $1}'); [ "$BASE_ACTUAL" = "$BASE_SHA256" ] || block production_css_base_hash_mismatch
[ "$(grep -Fc "$START" "$TMP/css.new")" -eq 1 ] || block candidate_start_count
[ "$(grep -Fc "$END" "$TMP/css.new")" -eq 1 ] || block candidate_end_count
# Atomic replacement while preserving the production file owner/group/mode.
cp "$TMP/css.new" "$TMP/css.install"
chown --reference="$CSS_FILE" "$TMP/css.install"
chmod --reference="$CSS_FILE" "$TMP/css.install"
mv "$TMP/css.install" "$CSS_FILE"
DEPLOY=PASS
FINAL_SHA=$(sha256sum "$CSS_FILE" | awk '{print $1}')
# Verify the public CSS URL serves the managed block without relying on template/page cache.
CSS_HTTP=$(curl -skL --max-time 25 -H 'Cache-Control: no-cache' -o "$TMP/public.css" -w '%{http_code}' "$CSS_URL?xyptdq_article_reading=1" || true)
[ "$CSS_HTTP" = 200 ] || block public_css_http_error
grep -Fq "$START" "$TMP/public.css" || block public_css_marker_missing
grep -Fq 'body article .xyptdq-card > .xyptdq-content' "$TMP/public.css" || block public_css_scoped_rule_missing
CSS_PUBLIC=PASS
# Article markup/SEO must remain stable; mobile currently uses the same responsive PC shell.
PC_HTTP=$(curl -skL --max-time 25 -o "$TMP/pc.after" -w '%{http_code}' "$ARTICLE_URL" || true)
MOBILE_HTTP=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mobile.after" -w '%{http_code}' "$ARTICLE_URL" || true)
[ "$PC_HTTP" = 200 ] && [ "$MOBILE_HTTP" = 200 ] || block post_http_error
[ "$(extract "$TMP/pc.after" title)" = "$(cat "$TMP/pt")" ] || block pc_title_changed
[ "$(extract "$TMP/pc.after" canonical)" = "$(cat "$TMP/pc")" ] || block pc_canonical_changed
[ "$(extract "$TMP/mobile.after" title)" = "$(cat "$TMP/mt")" ] || block mobile_title_changed
[ "$(extract "$TMP/mobile.after" canonical)" = "$(cat "$TMP/mc")" ] || block mobile_canonical_changed
META_STABLE=PASS
CRON_AFTER=$(cron_count); [ "$CRON_AFTER" -eq 1 ] || block publisher_cron_changed
write_result PASS "$FINAL_SHA"
echo "DEPLOY_ARTICLE_READING_STATIC_CSS_V1=PASS css_sha=$FINAL_SHA cron=1"
