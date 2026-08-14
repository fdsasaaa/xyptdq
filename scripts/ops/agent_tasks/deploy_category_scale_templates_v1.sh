#!/bin/bash
# Rollback-gated deployment of the four category-scale SEO templates only.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="2e59abc4f107059f96397be7bf8ef6d5d9d352fc"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
FILES=(
  "template/pc/default/home/seo_header.html"
  "template/pc/default/home/list.html"
  "template/mobile/default/home/seo_header.html"
  "template/mobile/default/home/list.html"
)

PHASE="init"
DEPLOY="NO"
ROLLBACK="NO"
SOURCE_HASH_MATCH="NO"
PC_PAGE1_HTTP=0
MOBILE_PAGE1_HTTP=0
PC_PAGE2_META="NO"
MOBILE_PAGE2_META="NO"
FRAMEWORK_OK="NO"
CRON_BEFORE=-1
CRON_AFTER=-1
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
TMP="$(mktemp -d /tmp/xyptdq-category-scale.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload(){ python3 - "$RESULT_FILE" "$1" "$PHASE" "$DEPLOY" "$ROLLBACK" "$SOURCE_HASH_MATCH" "$PC_PAGE1_HTTP" "$MOBILE_PAGE1_HTTP" "$PC_PAGE2_META" "$MOBILE_PAGE2_META" "$FRAMEWORK_OK" "$CRON_BEFORE" "$CRON_AFTER" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,deploy,rollback,hashmatch,pc1,mo1,pc2,mo2,framework,cron_before,cron_after,error_class,blocker)=sys.argv[1:]
p={
  "task":"deploy_category_scale_templates_v1",
  "deployment_status":status,
  "phase":phase,
  "deploy":deploy,
  "rollback":rollback,
  "source_hash_match":hashmatch,
  "pc_page1_http":int(pc1),
  "mobile_page1_http":int(mo1),
  "pc_page2_meta":pc2,
  "mobile_page2_meta":mo2,
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
  echo "[category-scale] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
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
git show "$TARGET_SHA:site/template/pc/default/home/seo_header.html" | grep -Fq '$xyptdq_is_category && $xyptdq_request_page > 1' || { ERROR_CLASS="pc_page_meta_marker_missing"; block pc_page_meta_marker_missing; }
git show "$TARGET_SHA:site/template/mobile/default/home/seo_header.html" | grep -Fq '$xyptdq_is_category && $xyptdq_request_page > 1' || { ERROR_CLASS="mobile_page_meta_marker_missing"; block mobile_page_meta_marker_missing; }
git show "$TARGET_SHA:site/template/pc/default/home/list.html" | grep -Fq '{module catid=$catid order=updatetime num=8}' || { ERROR_CLASS="pc_sidebar_scope_marker_missing"; block pc_sidebar_scope_marker_missing; }
git show "$TARGET_SHA:site/template/mobile/default/home/list.html" | grep -Fq 'xyptdq-mobile-pagination' || { ERROR_CLASS="mobile_pagination_marker_missing"; block mobile_pagination_marker_missing; }
git show "$TARGET_SHA:site/template/mobile/default/home/list.html" | grep -Fq 'dr_ajax_load_more' || { ERROR_CLASS="mobile_load_more_marker_missing"; block mobile_load_more_marker_missing; }

PHASE="baseline"
CRON_BEFORE="$(cron_count)"
[ "$CRON_BEFORE" -eq 0 ] || { ERROR_CLASS="publisher_cron_present_before_deploy"; block publisher_cron_present_before_deploy; }
PC_PAGE1_HTTP=$(curl -skL --max-time 25 -o "$TMP/pc1.before.html" -w '%{http_code}' "$CANONICAL/index.php?c=category&dir=tzjq" || true)
MOBILE_PAGE1_HTTP=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mo1.before.html" -w '%{http_code}' "$CANONICAL/index.php?c=category&dir=tzjq" || true)
[ "$PC_PAGE1_HTTP" = 200 ] && [ "$MOBILE_PAGE1_HTTP" = 200 ] || { ERROR_CLASS="baseline_category_http_error"; block baseline_category_http_error; }
extract "$TMP/pc1.before.html" title > "$TMP/pc1.title.before"
extract "$TMP/pc1.before.html" canonical > "$TMP/pc1.canonical.before"
extract "$TMP/mo1.before.html" title > "$TMP/mo1.title.before"
extract "$TMP/mo1.before.html" canonical > "$TMP/mo1.canonical.before"

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
pc1=$(curl -skL --max-time 25 -o "$TMP/pc1.after.html" -w '%{http_code}' "$CANONICAL/index.php?c=category&dir=tzjq" || true)
mo1=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mo1.after.html" -w '%{http_code}' "$CANONICAL/index.php?c=category&dir=tzjq" || true)
[ "$pc1" = 200 ] && [ "$mo1" = 200 ] || { ERROR_CLASS="post_category_http_error"; block post_category_http_error; }
[ "$(extract "$TMP/pc1.after.html" title)" = "$(cat "$TMP/pc1.title.before")" ] || { ERROR_CLASS="pc_page1_title_changed"; block pc_page1_title_changed; }
[ "$(extract "$TMP/pc1.after.html" canonical)" = "$(cat "$TMP/pc1.canonical.before")" ] || { ERROR_CLASS="pc_page1_canonical_changed"; block pc_page1_canonical_changed; }
[ "$(extract "$TMP/mo1.after.html" title)" = "$(cat "$TMP/mo1.title.before")" ] || { ERROR_CLASS="mobile_page1_title_changed"; block mobile_page1_title_changed; }
[ "$(extract "$TMP/mo1.after.html" canonical)" = "$(cat "$TMP/mo1.canonical.before")" ] || { ERROR_CLASS="mobile_page1_canonical_changed"; block mobile_page1_canonical_changed; }

pc2=$(curl -skL --max-time 25 -o "$TMP/pc2.after.html" -w '%{http_code}' "$CANONICAL/index.php?c=category&dir=tzjq&page=2" || true)
mo2=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mo2.after.html" -w '%{http_code}' "$CANONICAL/index.php?c=category&dir=tzjq&page=2" || true)
EXPECTED_PAGE2="$CANONICAL/index.php?c=category&dir=tzjq&page=2"
if [ "$pc2" = 200 ] && printf '%s' "$(extract "$TMP/pc2.after.html" title)" | grep -Fq '第2页' && [ "$(extract "$TMP/pc2.after.html" canonical)" = "$EXPECTED_PAGE2" ]; then PC_PAGE2_META="PASS"; else ERROR_CLASS="pc_page2_meta_failed"; block pc_page2_meta_failed; fi
if [ "$mo2" = 200 ] && printf '%s' "$(extract "$TMP/mo2.after.html" title)" | grep -Fq '第2页' && [ "$(extract "$TMP/mo2.after.html" canonical)" = "$EXPECTED_PAGE2" ]; then MOBILE_PAGE2_META="PASS"; else ERROR_CLASS="mobile_page2_meta_failed"; block mobile_page2_meta_failed; fi

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
echo "DEPLOY_CATEGORY_SCALE_TEMPLATES_V1=PASS"
