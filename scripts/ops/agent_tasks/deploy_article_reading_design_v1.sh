#!/bin/bash
# Rollback-gated deployment of article reading typography to PC/mobile show templates only.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="b03644009e6b532ed00a0b4c0aab862d7520562c"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
FILES=(
  "template/pc/default/home/show.html"
  "template/mobile/default/home/show.html"
)
ARTICLE_URL="$CANONICAL/index.php?c=show&id=92"

PHASE="init"
DEPLOY="NO"
ROLLBACK="NO"
SOURCE_HASH_MATCH="NO"
PC_HTTP=0
MOBILE_HTTP=0
PC_STYLE="NO"
MOBILE_STYLE="NO"
META_STABLE="NO"
FRAMEWORK_OK="NO"
CRON_BEFORE=-1
CRON_AFTER=-1
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
TMP="$(mktemp -d /tmp/xyptdq-article-design.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload(){ python3 - "$RESULT_FILE" "$1" "$PHASE" "$DEPLOY" "$ROLLBACK" "$SOURCE_HASH_MATCH" "$PC_HTTP" "$MOBILE_HTTP" "$PC_STYLE" "$MOBILE_STYLE" "$META_STABLE" "$FRAMEWORK_OK" "$CRON_BEFORE" "$CRON_AFTER" "$ERROR_CLASS" "$BLOCKING_ITEM" "$ARTICLE_URL" <<'PY'
import json,sys
(out,status,phase,deploy,rollback,hashmatch,pc_http,mobile_http,pc_style,mobile_style,meta_stable,framework,cron_before,cron_after,error_class,blocker,url)=sys.argv[1:]
p={
  "task":"deploy_article_reading_design_v1",
  "deployment_status":status,
  "phase":phase,
  "deploy":deploy,
  "rollback":rollback,
  "source_hash_match":hashmatch,
  "article_url":url,
  "pc_http":int(pc_http),
  "mobile_http":int(mobile_http),
  "pc_article_reading_style":pc_style,
  "mobile_article_reading_style":mobile_style,
  "title_canonical_stable":meta_stable,
  "framework_integrity":framework,
  "publisher_cron_count_before":int(cron_before),
  "publisher_cron_count_after":int(cron_after),
  "deploy_error_class":error_class,
  "blocking_item":blocker,
  "database_changed":False,
  "article_publishing_attempted":False,
  "publisher_policy_changed":False,
  "publisher_queue_consumed":False,
  "secrets_disclosed":False
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}

rollback_files(){
  set +e
  if [ -d "$TMP/before" ]; then
    for rel in "${FILES[@]}"; do
      if [ -f "$TMP/before/$rel" ]; then
        install -o www-data -g www-data -m 0644 "$TMP/before/$rel" "$WEBROOT/$rel"
      fi
    done
    ROLLBACK="YES"
  fi
  set -e
}

block(){
  BLOCKING_ITEM="$1"
  if [ "$DEPLOY" = "PASS" ]; then rollback_files; fi
  write_payload BLOCKED
  echo "[article-design] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
  exit 1
}

on_err(){
  rc=$?
  trap - ERR
  ERROR_CLASS="unhandled_runtime_error"
  BLOCKING_ITEM="phase_${PHASE}_exit_${rc}"
  if [ "$DEPLOY" = "PASS" ]; then rollback_files; fi
  write_payload BLOCKED || true
  exit "$rc"
}
trap on_err ERR

extract(){ python3 - "$1" "$2" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read(); kind=sys.argv[2]
def attr(tag,name):
 m=re.search(r'\b'+re.escape(name)+r'\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
 return html.unescape(m.group(1).strip()) if m else ''
def text(tag):
 m=re.search(r'<'+tag+r'\b[^>]*>(.*?)</'+tag+r'\s*>',s,re.I|re.S)
 return re.sub(r'\s+',' ',html.unescape(re.sub(r'<[^>]+>',' ',m.group(1)))).strip() if m else ''
if kind=='title': print(text('title'))
elif kind=='canonical':
 for t in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
  if 'canonical' in attr(t,'rel').lower().split(): print(attr(t,'href')); break
PY
}

cron_count(){
  (crontab -l 2>/dev/null || true) | grep -c 'run_scheduled_publish.sh' || true
}

PHASE="repo_sync"
cd "$REPO"
git fetch --prune origin >/dev/null 2>&1
git merge-base --is-ancestor "$TARGET_SHA" origin/main || { ERROR_CLASS="target_not_in_main"; block target_not_in_main; }

PHASE="source_verify"
git show "$TARGET_SHA:site/template/pc/default/home/show.html" | grep -Fq '.xyptdq-article-prose{max-width:760px' || { ERROR_CLASS="pc_style_marker_missing"; block pc_style_marker_missing; }
git show "$TARGET_SHA:site/template/pc/default/home/show.html" | grep -Fq 'xyptdq-content xyptdq-article-prose' || { ERROR_CLASS="pc_article_class_missing"; block pc_article_class_missing; }
git show "$TARGET_SHA:site/template/mobile/default/home/show.html" | grep -Fq '.xyptdq-article-prose{font-family:' || { ERROR_CLASS="mobile_style_marker_missing"; block mobile_style_marker_missing; }
git show "$TARGET_SHA:site/template/mobile/default/home/show.html" | grep -Fq 'xrcontent xyptdq-article-prose' || { ERROR_CLASS="mobile_article_class_missing"; block mobile_article_class_missing; }

PHASE="baseline"
CRON_BEFORE="$(cron_count)"
[ "$CRON_BEFORE" -eq 0 ] || { ERROR_CLASS="publisher_cron_present_before_deploy"; block publisher_cron_present_before_deploy; }
PC_HTTP=$(curl -skL --max-time 25 -o "$TMP/pc.before.html" -w '%{http_code}' "$ARTICLE_URL" || true)
MOBILE_HTTP=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mobile.before.html" -w '%{http_code}' "$ARTICLE_URL" || true)
[ "$PC_HTTP" = 200 ] && [ "$MOBILE_HTTP" = 200 ] || { ERROR_CLASS="baseline_article_http_error"; block baseline_article_http_error; }
extract "$TMP/pc.before.html" title > "$TMP/pc.title.before"
extract "$TMP/pc.before.html" canonical > "$TMP/pc.canonical.before"
extract "$TMP/mobile.before.html" title > "$TMP/mobile.title.before"
extract "$TMP/mobile.before.html" canonical > "$TMP/mobile.canonical.before"

PHASE="snapshot"
for rel in "${FILES[@]}"; do
  [ -f "$WEBROOT/$rel" ] || { ERROR_CLASS="production_template_missing"; block "production_template_missing_$rel"; }
  mkdir -p "$TMP/before/$(dirname "$rel")" "$TMP/source/$(dirname "$rel")"
  cp -a "$WEBROOT/$rel" "$TMP/before/$rel"
  git show "$TARGET_SHA:site/$rel" > "$TMP/source/$rel"
done

PHASE="deploy"
for rel in "${FILES[@]}"; do
  install -o www-data -g www-data -m 0644 "$TMP/source/$rel" "$WEBROOT/$rel"
done
DEPLOY="PASS"

PHASE="file_verify"
for rel in "${FILES[@]}"; do
  expected=$(sha256sum "$TMP/source/$rel" | awk '{print $1}')
  actual=$(sha256sum "$WEBROOT/$rel" | awk '{print $1}')
  [ "$expected" = "$actual" ] || { ERROR_CLASS="production_template_hash_mismatch"; block "production_template_hash_mismatch_$rel"; }
done
SOURCE_HASH_MATCH="PASS"

PHASE="render_verify"
pc_after=$(curl -skL --max-time 25 -o "$TMP/pc.after.html" -w '%{http_code}' "$ARTICLE_URL" || true)
mobile_after=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mobile.after.html" -w '%{http_code}' "$ARTICLE_URL" || true)
PC_HTTP="$pc_after"; MOBILE_HTTP="$mobile_after"
[ "$pc_after" = 200 ] && [ "$mobile_after" = 200 ] || { ERROR_CLASS="post_article_http_error"; block post_article_http_error; }
[ "$(extract "$TMP/pc.after.html" title)" = "$(cat "$TMP/pc.title.before")" ] || { ERROR_CLASS="pc_title_changed"; block pc_title_changed; }
[ "$(extract "$TMP/pc.after.html" canonical)" = "$(cat "$TMP/pc.canonical.before")" ] || { ERROR_CLASS="pc_canonical_changed"; block pc_canonical_changed; }
[ "$(extract "$TMP/mobile.after.html" title)" = "$(cat "$TMP/mobile.title.before")" ] || { ERROR_CLASS="mobile_title_changed"; block mobile_title_changed; }
[ "$(extract "$TMP/mobile.after.html" canonical)" = "$(cat "$TMP/mobile.canonical.before")" ] || { ERROR_CLASS="mobile_canonical_changed"; block mobile_canonical_changed; }
META_STABLE="PASS"

grep -Fq '.xyptdq-article-prose' "$TMP/pc.after.html" && grep -Fq 'xyptdq-content xyptdq-article-prose' "$TMP/pc.after.html" || { ERROR_CLASS="pc_render_style_missing"; block pc_render_style_missing; }
PC_STYLE="PASS"
grep -Fq '.xyptdq-article-prose' "$TMP/mobile.after.html" && grep -Fq 'xrcontent xyptdq-article-prose' "$TMP/mobile.after.html" || { ERROR_CLASS="mobile_render_style_missing"; block mobile_render_style_missing; }
MOBILE_STYLE="PASS"

PHASE="framework_verify"
if [ -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" ] && [ -f "$WEBROOT/cache/frame.lock" ] && [ "$(od -An -tx1 -v "$WEBROOT/cache/frame.lock" | tr -d ' \n')" = "$EXPECTED_FRAME_LOCK_HEX" ]; then
  FRAMEWORK_OK="PASS"
else
  ERROR_CLASS="framework_integrity_failed"; block framework_integrity_failed
fi

PHASE="publisher_safety"
CRON_AFTER="$(cron_count)"
[ "$CRON_AFTER" -eq "$CRON_BEFORE" ] && [ "$CRON_AFTER" -eq 0 ] || { ERROR_CLASS="publisher_cron_changed"; block publisher_cron_changed; }

PHASE="final"
trap - ERR
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"
write_payload PASS
echo "DEPLOY_ARTICLE_READING_DESIGN_V1=PASS"
