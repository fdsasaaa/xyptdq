#!/bin/bash
# Rollback-gated deployment for the exact duplicated platform meta-description hash fallback.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="3896887d20bb1604c577c6b57c26d51201600e22"
DUP_SHA="dbb8e77773b4bf902811040fe65903fa87692b3345a3ba0ab966518b539eb716"
AFFECTED_IDS="50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 82 83"
EXPECTED_COUNT=20
UNAFFECTED_PLATFORM_ID=19
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"

PHASE="init"
DEPLOY="NO"
ROLLBACK="NO"
PRE_MATCH_COUNT=0
PC_UNIQUE=0
MOBILE_UNIQUE=0
PC_WITH_TITLE=0
MOBILE_WITH_TITLE=0
UNAFFECTED_PLATFORM_UNCHANGED="NO"
ARTICLE_UNCHANGED="NO"
CANONICAL_NAV_OK="NO"
FRAMEWORK_OK="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4

TMP="$(mktemp -d /tmp/xyptdq-platform-meta-hash.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload(){
  local status="$1"
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$ROLLBACK" \
    "$PRE_MATCH_COUNT" "$PC_UNIQUE" "$MOBILE_UNIQUE" "$PC_WITH_TITLE" "$MOBILE_WITH_TITLE" \
    "$UNAFFECTED_PLATFORM_UNCHANGED" "$ARTICLE_UNCHANGED" "$CANONICAL_NAV_OK" "$FRAMEWORK_OK" \
    "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,target,deploy,rollback,pre,pcu,mu,pct,mt,unaffected,article,nav,framework,error_class,blocker)=sys.argv[1:]
payload={
  "task":"deploy_platform_duplicate_description_hash_fallback_v2",
  "deployment_status":status,
  "phase":phase,
  "target_sha":target,
  "deploy":deploy,
  "rollback":rollback,
  "pre_deploy_duplicate_hash_match_count":int(pre),
  "pc_unique_description_count":int(pcu),
  "mobile_unique_description_count":int(mu),
  "pc_descriptions_containing_platform_title":int(pct),
  "mobile_descriptions_containing_platform_title":int(mt),
  "unaffected_platform19_description_unchanged":unaffected,
  "article91_description_unchanged":article,
  "canonical_category_nav_preserved":nav,
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
  echo "[platform-meta-hash-deploy] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
  exit 1
}

extract_desc(){
  python3 - "$1" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
for tag in re.findall(r'<meta\b[^>]*>',s,re.I|re.S):
    n=re.search(r'\bname\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    if not n or html.unescape(n.group(1)).strip().lower()!='description': continue
    c=re.search(r'\bcontent\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    print(html.unescape(c.group(1)).strip() if c else '')
    break
PY
}

extract_h1(){
  python3 - "$1" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
m=re.search(r'<h1\b[^>]*>(.*?)</h1\s*>',s,re.I|re.S)
if m:
    t=re.sub(r'<[^>]+>',' ',m.group(1))
    print(re.sub(r'\s+',' ',html.unescape(t)).strip())
PY
}

cd "$REPO"
PHASE="repo_sync"
git fetch --prune origin >/dev/null 2>&1
git merge-base --is-ancestor "$TARGET_SHA" origin/main || {
  ERROR_CLASS="target_not_in_main"; block target_not_in_main;
}

PHASE="source_verify"
for p in site/template/pc/default/home/seo_header.html site/template/mobile/default/home/seo_header.html; do
  git show "$TARGET_SHA:$p" | grep -Fq "hash('sha256', \$xyptdq_desc)" || {
    ERROR_CLASS="hash_gate_missing"; block hash_gate_missing;
  }
  git show "$TARGET_SHA:$p" | grep -Fq "$DUP_SHA" || {
    ERROR_CLASS="duplicate_hash_marker_missing"; block duplicate_hash_marker_missing;
  }
  git show "$TARGET_SHA:$p" | grep -Fq "\$xyptdq_module === 'xm'" || {
    ERROR_CLASS="xm_scope_missing"; block xm_scope_missing;
  }
done

PHASE="pre_deploy_baseline"
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
PRE_MATCH_COUNT=0
for id in $AFFECTED_IDS; do
  code=$(curl -skL --max-time 25 -o "$TMP/pre-$id.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id")
  [ "$code" = 200 ] || { ERROR_CLASS="affected_page_http_not_200_before"; block affected_page_http_not_200_before; }
  d="$(extract_desc "$TMP/pre-$id.html")"
  [ -n "$d" ] || { ERROR_CLASS="affected_description_missing_before"; block affected_description_missing_before; }
  h="$(printf '%s' "$d" | sha256sum | awk '{print $1}')"
  if [ "$h" = "$DUP_SHA" ]; then PRE_MATCH_COUNT=$((PRE_MATCH_COUNT+1)); fi
done
[ "$PRE_MATCH_COUNT" -eq "$EXPECTED_COUNT" ] || { ERROR_CLASS="pre_deploy_hash_inventory_drift"; block pre_deploy_hash_inventory_drift; }

for id in "$UNAFFECTED_PLATFORM_ID" 91; do
  code=$(curl -skL --max-time 25 -o "$TMP/control-$id.before.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id")
  [ "$code" = 200 ] || { ERROR_CLASS="control_page_http_not_200_before"; block control_page_http_not_200_before; }
done
UNAFF_DESC_BEFORE="$(extract_desc "$TMP/control-$UNAFFECTED_PLATFORM_ID.before.html")"
ARTICLE_DESC_BEFORE="$(extract_desc "$TMP/control-91.before.html")"
[ -n "$UNAFF_DESC_BEFORE" ] || { ERROR_CLASS="unaffected_platform_description_missing"; block unaffected_platform_description_missing; }
[ -n "$ARTICLE_DESC_BEFORE" ] || { ERROR_CLASS="article91_description_missing"; block article91_description_missing; }
[ "$(printf '%s' "$UNAFF_DESC_BEFORE" | sha256sum | awk '{print $1}')" != "$DUP_SHA" ] || {
  ERROR_CLASS="unaffected_control_matches_duplicate_hash"; block unaffected_control_matches_duplicate_hash;
}

PHASE="rollback_snapshot"
cp -a "$WEBROOT/template" "$TMP/template.before"

PHASE="deploy"
git show "$TARGET_SHA:scripts/deploy_safe.sh" > "$TMP/deploy_safe.sh" || {
  ERROR_CLASS="deploy_safe_missing"; block deploy_safe_missing;
}
chmod 700 "$TMP/deploy_safe.sh"
if ! XYPTDQ_REPO_DIR="$REPO" XYPTDQ_WEBROOT="$WEBROOT" bash "$TMP/deploy_safe.sh" "$TARGET_SHA" >"$TMP/deploy.log" 2>&1; then
  ERROR_CLASS="canonical_deploy_failed"; block deploy_safe_failed
fi
DEPLOY="PASS"

PHASE="post_render_verify"
: > "$TMP/pc.desc"
: > "$TMP/mobile.desc"
PC_WITH_TITLE=0
MOBILE_WITH_TITLE=0

for id in $AFFECTED_IDS; do
  pc_code=$(curl -skL --max-time 25 -o "$TMP/pc-$id.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id")
  mo_code=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mo-$id.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id")
  [ "$pc_code" = 200 ] || { ERROR_CLASS="affected_pc_http_not_200_after"; block affected_pc_http_not_200_after; }
  [ "$mo_code" = 200 ] || { ERROR_CLASS="affected_mobile_http_not_200_after"; block affected_mobile_http_not_200_after; }
  pc_desc="$(extract_desc "$TMP/pc-$id.html")"
  mo_desc="$(extract_desc "$TMP/mo-$id.html")"
  ptitle="$(extract_h1 "$TMP/pc-$id.html")"
  mtitle="$(extract_h1 "$TMP/mo-$id.html")"
  [ -n "$pc_desc" ] && [ -n "$mo_desc" ] && [ -n "$ptitle" ] && [ -n "$mtitle" ] || {
    ERROR_CLASS="affected_render_metadata_missing"; block affected_render_metadata_missing;
  }
  [ "$(printf '%s' "$pc_desc" | sha256sum | awk '{print $1}')" != "$DUP_SHA" ] || {
    ERROR_CLASS="pc_duplicate_hash_persisted"; block pc_duplicate_hash_persisted;
  }
  [ "$(printf '%s' "$mo_desc" | sha256sum | awk '{print $1}')" != "$DUP_SHA" ] || {
    ERROR_CLASS="mobile_duplicate_hash_persisted"; block mobile_duplicate_hash_persisted;
  }
  printf '%s\n' "$pc_desc" >> "$TMP/pc.desc"
  printf '%s\n' "$mo_desc" >> "$TMP/mobile.desc"
  if printf '%s' "$pc_desc" | grep -Fq "$ptitle"; then PC_WITH_TITLE=$((PC_WITH_TITLE+1)); fi
  if printf '%s' "$mo_desc" | grep -Fq "$mtitle"; then MOBILE_WITH_TITLE=$((MOBILE_WITH_TITLE+1)); fi
done

PC_UNIQUE=$(sort -u "$TMP/pc.desc" | wc -l | tr -d ' ')
MOBILE_UNIQUE=$(sort -u "$TMP/mobile.desc" | wc -l | tr -d ' ')
[ "$PC_UNIQUE" -eq "$EXPECTED_COUNT" ] || { ERROR_CLASS="pc_descriptions_not_unique"; block pc_descriptions_not_unique; }
[ "$MOBILE_UNIQUE" -eq "$EXPECTED_COUNT" ] || { ERROR_CLASS="mobile_descriptions_not_unique"; block mobile_descriptions_not_unique; }
[ "$PC_WITH_TITLE" -eq "$EXPECTED_COUNT" ] || { ERROR_CLASS="pc_descriptions_missing_title"; block pc_descriptions_missing_title; }
[ "$MOBILE_WITH_TITLE" -eq "$EXPECTED_COUNT" ] || { ERROR_CLASS="mobile_descriptions_missing_title"; block mobile_descriptions_missing_title; }

for id in "$UNAFFECTED_PLATFORM_ID" 91; do
  code=$(curl -skL --max-time 25 -o "$TMP/control-$id.after.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id")
  [ "$code" = 200 ] || { ERROR_CLASS="control_page_http_not_200_after"; block control_page_http_not_200_after; }
done
UNAFF_DESC_AFTER="$(extract_desc "$TMP/control-$UNAFFECTED_PLATFORM_ID.after.html")"
ARTICLE_DESC_AFTER="$(extract_desc "$TMP/control-91.after.html")"
[ "$UNAFF_DESC_AFTER" = "$UNAFF_DESC_BEFORE" ] || { ERROR_CLASS="unaffected_platform_description_changed"; block unaffected_platform_description_changed; }
[ "$ARTICLE_DESC_AFTER" = "$ARTICLE_DESC_BEFORE" ] || { ERROR_CLASS="article91_description_changed"; block article91_description_changed; }
UNAFFECTED_PLATFORM_UNCHANGED="PASS"
ARTICLE_UNCHANGED="PASS"

python3 - "$TMP/control-91.after.html" <<'PY'
import html,re,sys
from urllib.parse import parse_qsl,urljoin,urlsplit
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
m=re.search(r'<nav\b[^>]*class=["\'][^"\']*\bxyptdq-site-nav\b[^"\']*["\'][^>]*>(.*?)</nav\s*>',s,re.I|re.S)
if not m: raise SystemExit(2)
dirs=set()
for a in re.findall(r'<a\b[^>]*>',m.group(1),re.I|re.S):
    h=re.search(r'\bhref\s*=\s*["\']([^"\']*)["\']',a,re.I|re.S)
    if not h: continue
    p=urlsplit(urljoin('https://www.laocaimi.org/',html.unescape(h.group(1))))
    q=dict(parse_qsl(p.query,keep_blank_values=True))
    if q.get('c')=='category' and q.get('dir'): dirs.add(q['dir'])
if dirs != {'gjfa','tzjq','zyyy','seo-articles'}: raise SystemExit(3)
PY
CANONICAL_NAV_OK="PASS"

PHASE="framework_verify"
if [ -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" ] \
   && [ -f "$WEBROOT/cache/frame.lock" ] \
   && [ "$(od -An -tx1 -v "$WEBROOT/cache/frame.lock" | tr -d ' \n')" = "$EXPECTED_FRAME_LOCK_HEX" ]; then
  FRAMEWORK_OK="PASS"
else
  ERROR_CLASS="framework_integrity_failed"; block framework_integrity_failed
fi

PHASE="final"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"
write_payload PASS
echo "PLATFORM_META_HASH_FALLBACK_V2=PASS count=$PRE_MATCH_COUNT pc_unique=$PC_UNIQUE mobile_unique=$MOBILE_UNIQUE"
