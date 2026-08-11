#!/bin/bash
# Rollback-gated production deployment for the factual H1 differentiation of show 74/75.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="65c6452e0efecd6eef93b660d54dd013a3df0a0f"
DUP_SHA="dbb8e77773b4bf902811040fe65903fa87692b3345a3ba0ab966518b539eb716"
AFFECTED_DESC_IDS="50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 82 83"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"
PHASE="init"; DEPLOY="NO"; ROLLBACK="NO"; DESC_PRECONDITION="NO"; H1_PC="NO"; H1_MOBILE="NO"; META_UNCHANGED="NO"; FRAMEWORK_OK="NO"; ERROR_CLASS="NONE"; BLOCKING_ITEM="NONE"
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
TMP="$(mktemp -d /tmp/xyptdq-h1-7475.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT

write_payload(){ python3 - "$RESULT_FILE" "$1" "$PHASE" "$DEPLOY" "$ROLLBACK" "$DESC_PRECONDITION" "$H1_PC" "$H1_MOBILE" "$META_UNCHANGED" "$FRAMEWORK_OK" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,deploy,rollback,desc,pc,mo,meta,framework,error_class,blocker)=sys.argv[1:]
p={"task":"deploy_show_74_75_h1_v1","deployment_status":status,"phase":phase,"deploy":deploy,"rollback":rollback,"description_fix_precondition":desc,"pc_h1_verified":pc,"mobile_h1_verified":mo,"canonical_and_description_unchanged":meta,"framework_integrity":framework,"deploy_error_class":error_class,"blocking_item":blocker,"article_publishing_attempted":False,"secrets_disclosed":False}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}
rollback_templates(){ set +e; if [ -d "$TMP/template.before" ]; then rm -rf "$WEBROOT/template"; cp -a "$TMP/template.before" "$WEBROOT/template"; chown -R www-data:www-data "$WEBROOT/template" 2>/dev/null || true; chmod -R u=rwX,go=rX "$WEBROOT/template" 2>/dev/null || true; ROLLBACK="YES"; fi; set -e; }
block(){ BLOCKING_ITEM="$1"; if [ "$DEPLOY" = "PASS" ]; then rollback_templates; fi; write_payload BLOCKED; echo "[h1-7475] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2; exit 1; }
on_err(){ rc=$?; trap - ERR; ERROR_CLASS="unhandled_runtime_error"; BLOCKING_ITEM="phase_${PHASE}_exit_${rc}"; if [ "$DEPLOY" = "PASS" ]; then rollback_templates; fi; write_payload BLOCKED || true; exit "$rc"; }; trap on_err ERR

extract(){ python3 - "$1" "$2" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read(); kind=sys.argv[2]
def attr(tag,name):
 m=re.search(r'\b'+re.escape(name)+r'\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S); return html.unescape(m.group(1).strip()) if m else ''
def txt(tag):
 m=re.search(r'<'+tag+r'\b[^>]*>(.*?)</'+tag+r'\s*>',s,re.I|re.S); return re.sub(r'\s+',' ',html.unescape(re.sub(r'<[^>]+>',' ',m.group(1)))).strip() if m else ''
if kind=='h1': print(txt('h1'))
elif kind=='desc':
 for t in re.findall(r'<meta\b[^>]*>',s,re.I|re.S):
  if attr(t,'name').lower()=='description': print(attr(t,'content')); break
elif kind=='canonical':
 for t in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
  if 'canonical' in attr(t,'rel').lower().split(): print(attr(t,'href')); break
PY
}

PHASE="repo_sync"; cd "$REPO"; git fetch --prune origin >/dev/null 2>&1; git merge-base --is-ancestor "$TARGET_SHA" origin/main || { ERROR_CLASS="target_not_in_main"; block target_not_in_main; }
PHASE="source_verify"
for p in site/template/pc/default/home/show.html site/template/mobile/default/home/show.html; do
 git show "$TARGET_SHA:$p" | grep -Fq "\$xyptdq_display_show_id === 74" || { ERROR_CLASS="id74_source_guard_missing"; block id74_source_guard_missing; }
 git show "$TARGET_SHA:$p" | grep -Fq "\$xyptdq_display_show_id === 75" || { ERROR_CLASS="id75_source_guard_missing"; block id75_source_guard_missing; }
 git show "$TARGET_SHA:$p" | grep -Fq "软件项目" || { ERROR_CLASS="software_role_marker_missing"; block software_role_marker_missing; }
 git show "$TARGET_SHA:$p" | grep -Fq "福利资源" || { ERROR_CLASS="resource_role_marker_missing"; block resource_role_marker_missing; }
done

PHASE="description_fix_precondition"
for id in $AFFECTED_DESC_IDS; do
 code=$(curl -skL --max-time 25 -o "$TMP/desc-$id.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id" || true); [ "$code" = 200 ] || { ERROR_CLASS="description_precondition_http_error"; block description_precondition_http_error; }
 d="$(extract "$TMP/desc-$id.html" desc)"; [ -n "$d" ] || { ERROR_CLASS="description_precondition_missing"; block description_precondition_missing; }
 [ "$(printf '%s' "$d" | sha256sum | awk '{print $1}')" != "$DUP_SHA" ] || { ERROR_CLASS="description_fix_not_yet_live"; block description_fix_not_yet_live; }
done
DESC_PRECONDITION="PASS"

PHASE="baseline_74_75"
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
for id in 74 75; do
 pc=$(curl -skL --max-time 25 -o "$TMP/pc-$id.before.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id" || true); mo=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mo-$id.before.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id" || true)
 [ "$pc" = 200 ] && [ "$mo" = 200 ] || { ERROR_CLASS="baseline_http_error"; block baseline_http_error; }
 extract "$TMP/pc-$id.before.html" desc > "$TMP/$id.desc.before"; extract "$TMP/pc-$id.before.html" canonical > "$TMP/$id.can.before"
done

PHASE="snapshot"; cp -a "$WEBROOT/template" "$TMP/template.before"
PHASE="deploy"; git show "$TARGET_SHA:scripts/deploy_safe.sh" > "$TMP/deploy_safe.sh"; chmod 700 "$TMP/deploy_safe.sh"; if ! XYPTDQ_REPO_DIR="$REPO" XYPTDQ_WEBROOT="$WEBROOT" bash "$TMP/deploy_safe.sh" "$TARGET_SHA" >"$TMP/deploy.log" 2>&1; then ERROR_CLASS="deploy_safe_failed"; block deploy_safe_failed; fi; DEPLOY="PASS"

PHASE="verify"
for id in 74 75; do
 pc=$(curl -skL --max-time 25 -o "$TMP/pc-$id.after.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id" || true); mo=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mo-$id.after.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id" || true)
 [ "$pc" = 200 ] && [ "$mo" = 200 ] || { ERROR_CLASS="post_http_error"; block post_http_error; }
 [ "$(extract "$TMP/pc-$id.after.html" desc)" = "$(cat "$TMP/$id.desc.before")" ] || { ERROR_CLASS="description_changed"; block description_changed; }
 [ "$(extract "$TMP/pc-$id.after.html" canonical)" = "$(cat "$TMP/$id.can.before")" ] || { ERROR_CLASS="canonical_changed"; block canonical_changed; }
done
[ "$(extract "$TMP/pc-74.after.html" h1)" = "长征（送首冲）｜软件项目" ] && [ "$(extract "$TMP/pc-75.after.html" h1)" = "长征（送首冲）｜福利资源" ] || { ERROR_CLASS="pc_h1_unexpected"; block pc_h1_unexpected; }; H1_PC="PASS"
[ "$(extract "$TMP/mo-74.after.html" h1)" = "长征（送首冲）｜软件项目" ] && [ "$(extract "$TMP/mo-75.after.html" h1)" = "长征（送首冲）｜福利资源" ] || { ERROR_CLASS="mobile_h1_unexpected"; block mobile_h1_unexpected; }; H1_MOBILE="PASS"; META_UNCHANGED="PASS"

PHASE="framework_verify"; if [ -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" ] && [ -f "$WEBROOT/cache/frame.lock" ] && [ "$(od -An -tx1 -v "$WEBROOT/cache/frame.lock" | tr -d ' \n')" = "$EXPECTED_FRAME_LOCK_HEX" ]; then FRAMEWORK_OK="PASS"; else ERROR_CLASS="framework_integrity_failed"; block framework_integrity_failed; fi
PHASE="final"; trap - ERR; ERROR_CLASS="NONE"; BLOCKING_ITEM="NONE"; write_payload PASS; echo "SHOW_74_75_H1_V1=PASS"
