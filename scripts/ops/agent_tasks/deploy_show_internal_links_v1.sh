#!/bin/bash
# Rollback-gated deployment of PC/mobile show templates for canonical internal links.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="45c052cbc62fb33c466ac000d8b98f2b5fe1be40"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
FILES=("template/pc/default/home/show.html" "template/mobile/default/home/show.html")
PHASE="init"; DEPLOY="NO"; ROLLBACK="NO"; HASH_MATCH="NO"; PLATFORM_LINK="NO"; MOBILE_RELATED="NO"; FRAMEWORK_OK="NO"; CRON_BEFORE=-1; CRON_AFTER=-1; ERROR_CLASS="NONE"; BLOCKING_ITEM="NONE"
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
TMP="$(mktemp -d /tmp/xyptdq-show-links.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT

write_payload(){ python3 - "$RESULT_FILE" "$1" "$PHASE" "$DEPLOY" "$ROLLBACK" "$HASH_MATCH" "$PLATFORM_LINK" "$MOBILE_RELATED" "$FRAMEWORK_OK" "$CRON_BEFORE" "$CRON_AFTER" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,deploy,rollback,hashmatch,platform,related,framework,cron_before,cron_after,error_class,blocker)=sys.argv[1:]
p={"task":"deploy_show_internal_links_v1","deployment_status":status,"phase":phase,"deploy":deploy,"rollback":rollback,"source_hash_match":hashmatch,"platform_canonical_internal_link":platform,"mobile_related_content":related,"framework_integrity":framework,"publisher_cron_count_before":int(cron_before),"publisher_cron_count_after":int(cron_after),"deploy_error_class":error_class,"blocking_item":blocker,"database_changed":False,"article_publishing_attempted":False,"publisher_policy_changed":False,"publisher_queue_consumed":False,"secrets_disclosed":False}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}
rollback_files(){ set +e; if [ -d "$TMP/before" ]; then for rel in "${FILES[@]}"; do [ -f "$TMP/before/$rel" ] && install -o www-data -g www-data -m 0644 "$TMP/before/$rel" "$WEBROOT/$rel"; done; ROLLBACK="YES"; fi; set -e; }
block(){ BLOCKING_ITEM="$1"; [ "$DEPLOY" = "PASS" ] && rollback_files; write_payload BLOCKED; echo "[show-links] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2; exit 1; }
on_err(){ rc=$?; trap - ERR; ERROR_CLASS="unhandled_runtime_error"; BLOCKING_ITEM="phase_${PHASE}_exit_${rc}"; [ "$DEPLOY" = "PASS" ] && rollback_files; write_payload BLOCKED || true; exit "$rc"; }; trap on_err ERR
extract(){ python3 - "$1" "$2" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read(); kind=sys.argv[2]
def attr(tag,name):
 m=re.search(r'\b'+re.escape(name)+r'\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S); return html.unescape(m.group(1).strip()) if m else ''
def text(tag):
 m=re.search(r'<'+tag+r'\b[^>]*>(.*?)</'+tag+r'\s*>',s,re.I|re.S); return re.sub(r'\s+',' ',html.unescape(re.sub(r'<[^>]+>',' ',m.group(1)))).strip() if m else ''
if kind=='title': print(text('title'))
elif kind=='canonical':
 for t in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
  if 'canonical' in attr(t,'rel').lower().split(): print(attr(t,'href')); break
PY
}
cron_count(){ (crontab -l 2>/dev/null || true) | grep -c 'run_scheduled_publish.sh' || true; }

PHASE="repo_sync"; cd "$REPO"; git fetch --prune origin >/dev/null 2>&1; git merge-base --is-ancestor "$TARGET_SHA" origin/main || { ERROR_CLASS="target_not_in_main"; block target_not_in_main; }
PHASE="source_verify"
git show "$TARGET_SHA:site/template/pc/default/home/show.html" | grep -Fq '/index.php?c=category&dir=tzjq' || { ERROR_CLASS="pc_canonical_link_missing"; block pc_canonical_link_missing; }
git show "$TARGET_SHA:site/template/mobile/default/home/show.html" | grep -Fq '/index.php?c=category&dir=tzjq' || { ERROR_CLASS="mobile_canonical_link_missing"; block mobile_canonical_link_missing; }
if git show "$TARGET_SHA:site/template/mobile/default/home/show.html" | grep -Fq '/index.php?c=category&id=7'; then ERROR_CLASS="retired_mobile_link_still_present"; block retired_mobile_link_still_present; fi
git show "$TARGET_SHA:site/template/mobile/default/home/show.html" | grep -Fq 'mobile-related-heading' || { ERROR_CLASS="mobile_related_marker_missing"; block mobile_related_marker_missing; }
git show "$TARGET_SHA:site/template/mobile/default/home/show.html" | grep -Fq '{related module=MOD_DIR tag=$tag num=6}' || { ERROR_CLASS="mobile_related_query_missing"; block mobile_related_query_missing; }

PHASE="baseline"; CRON_BEFORE="$(cron_count)"; [ "$CRON_BEFORE" -eq 0 ] || { ERROR_CLASS="publisher_cron_present_before_deploy"; block publisher_cron_present_before_deploy; }
for spec in "pc74:$CANONICAL/index.php?c=show&id=74:" "mo74:$CANONICAL/index.php?c=show&id=74:$MOBILE_UA" "pc85:$CANONICAL/index.php?c=show&id=85:" "mo85:$CANONICAL/index.php?c=show&id=85:$MOBILE_UA"; do
 IFS=: read -r name url ua <<< "$spec"; if [ -n "$ua" ]; then code=$(curl -skL --max-time 25 -A "$ua" -o "$TMP/$name.before.html" -w '%{http_code}' "$url" || true); else code=$(curl -skL --max-time 25 -o "$TMP/$name.before.html" -w '%{http_code}' "$url" || true); fi; [ "$code" = 200 ] || { ERROR_CLASS="baseline_show_http_error"; block "baseline_show_http_error_$name"; }; extract "$TMP/$name.before.html" canonical > "$TMP/$name.canonical.before"; done

PHASE="snapshot"; for rel in "${FILES[@]}"; do [ -f "$WEBROOT/$rel" ] || { ERROR_CLASS="production_template_missing"; block "production_template_missing_$rel"; }; mkdir -p "$TMP/before/$(dirname "$rel")" "$TMP/source/$(dirname "$rel")"; cp -a "$WEBROOT/$rel" "$TMP/before/$rel"; git show "$TARGET_SHA:site/$rel" > "$TMP/source/$rel"; done
PHASE="deploy"; for rel in "${FILES[@]}"; do install -o www-data -g www-data -m 0644 "$TMP/source/$rel" "$WEBROOT/$rel"; done; DEPLOY="PASS"
PHASE="file_verify"; for rel in "${FILES[@]}"; do expected=$(sha256sum "$TMP/source/$rel"|awk '{print $1}'); actual=$(sha256sum "$WEBROOT/$rel"|awk '{print $1}'); [ "$expected" = "$actual" ] || { ERROR_CLASS="production_template_hash_mismatch"; block "production_template_hash_mismatch_$rel"; }; done; HASH_MATCH="PASS"

PHASE="render_verify"
for spec in "pc74:$CANONICAL/index.php?c=show&id=74:" "mo74:$CANONICAL/index.php?c=show&id=74:$MOBILE_UA" "pc85:$CANONICAL/index.php?c=show&id=85:" "mo85:$CANONICAL/index.php?c=show&id=85:$MOBILE_UA"; do
 IFS=: read -r name url ua <<< "$spec"; if [ -n "$ua" ]; then code=$(curl -skL --max-time 25 -A "$ua" -o "$TMP/$name.after.html" -w '%{http_code}' "$url" || true); else code=$(curl -skL --max-time 25 -o "$TMP/$name.after.html" -w '%{http_code}' "$url" || true); fi; [ "$code" = 200 ] || { ERROR_CLASS="post_show_http_error"; block "post_show_http_error_$name"; }; [ "$(extract "$TMP/$name.after.html" canonical)" = "$(cat "$TMP/$name.canonical.before")" ] || { ERROR_CLASS="show_canonical_changed"; block "show_canonical_changed_$name"; }; done
for name in pc74 mo74; do grep -Fq '/index.php?c=category&dir=tzjq' "$TMP/$name.after.html" || { ERROR_CLASS="canonical_internal_link_not_rendered"; block "canonical_internal_link_not_rendered_$name"; }; if grep -Fq '/index.php?c=category&id=7' "$TMP/$name.after.html"; then ERROR_CLASS="retired_internal_link_rendered"; block "retired_internal_link_rendered_$name"; fi; done; PLATFORM_LINK="PASS"
grep -Fq 'mobile-related-heading' "$TMP/mo85.after.html" || { ERROR_CLASS="mobile_related_heading_not_rendered"; block mobile_related_heading_not_rendered; }; MOBILE_RELATED="PASS"

PHASE="framework_verify"; if [ -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" ] && [ -f "$WEBROOT/cache/frame.lock" ] && [ "$(od -An -tx1 -v "$WEBROOT/cache/frame.lock" | tr -d ' \n')" = "$EXPECTED_FRAME_LOCK_HEX" ]; then FRAMEWORK_OK="PASS"; else ERROR_CLASS="framework_integrity_failed"; block framework_integrity_failed; fi
PHASE="publisher_safety"; CRON_AFTER="$(cron_count)"; [ "$CRON_AFTER" -eq "$CRON_BEFORE" ] && [ "$CRON_AFTER" -eq 0 ] || { ERROR_CLASS="publisher_cron_changed"; block publisher_cron_changed; }
PHASE="final"; trap - ERR; ERROR_CLASS="NONE"; BLOCKING_ITEM="NONE"; write_payload PASS; echo "DEPLOY_SHOW_INTERNAL_LINKS_V1=PASS"
