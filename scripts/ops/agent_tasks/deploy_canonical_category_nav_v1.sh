#!/bin/bash
# Rollback-gated deployment for canonical category navigation links.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="b641090da4e231b65ad9c24eb44c5d4283e7ab0d"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"
PHASE="init"
DEPLOY="NO"
ROLLBACK="NO"
PC_REQUIRED_LINKS=0
MOBILE_REQUIRED_LINKS=0
PC_FORBIDDEN_LINKS=0
MOBILE_FORBIDDEN_LINKS=0
ARTICLE_CANONICAL_OK="NO"
ARTICLE_DESCRIPTION_UNCHANGED="NO"
CATEGORY_CANONICAL_OK=0
FRAMEWORK_OK="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4

TMP="$(mktemp -d /tmp/xyptdq-canonical-nav.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload(){
  local status="$1"
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$ROLLBACK" \
    "$PC_REQUIRED_LINKS" "$MOBILE_REQUIRED_LINKS" "$PC_FORBIDDEN_LINKS" "$MOBILE_FORBIDDEN_LINKS" \
    "$ARTICLE_CANONICAL_OK" "$ARTICLE_DESCRIPTION_UNCHANGED" "$CATEGORY_CANONICAL_OK" \
    "$FRAMEWORK_OK" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,target,deploy,rollback,pcr,mr,pcf,mf,article_can,article_desc,cat_ok,framework,error_class,blocker)=sys.argv[1:]
payload={
  "task":"deploy_canonical_category_nav_v1",
  "deployment_status":status,
  "phase":phase,
  "target_sha":target,
  "deploy":deploy,
  "rollback":rollback,
  "pc_required_canonical_nav_link_count":int(pcr),
  "mobile_required_canonical_nav_link_count":int(mr),
  "pc_forbidden_nav_link_count":int(pcf),
  "mobile_forbidden_nav_link_count":int(mf),
  "article91_canonical_unchanged":article_can,
  "article91_description_unchanged":article_desc,
  "category_self_canonical_count":int(cat_ok),
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
  echo "[canonical-nav-deploy] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
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

extract_canonical(){
  python3 - "$1" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
for tag in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
    rel=re.search(r'\brel\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    if not rel or 'canonical' not in html.unescape(rel.group(1)).lower().split(): continue
    h=re.search(r'\bhref\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    print(html.unescape(h.group(1)).strip() if h else '')
    break
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
  for marker in \
    '/index.php?c=category&dir=gjfa' \
    '/index.php?c=category&dir=tzjq' \
    '/index.php?c=category&dir=zyyy' \
    '/index.php?c=category&dir=seo-articles'; do
    git show "$TARGET_SHA:$p" | grep -Fq "$marker" || {
      ERROR_CLASS="required_source_nav_marker_missing"; block required_source_nav_marker_missing;
    }
  done
  if git show "$TARGET_SHA:$p" | grep -Fq '{category module=share pid=0}'; then
    ERROR_CLASS="generic_share_nav_loop_still_present"; block generic_share_nav_loop_still_present;
  fi
done

PHASE="pre_deploy_baseline"
ARTICLE_HTTP=$(curl -skL --max-time 30 -o "$TMP/article.before.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=91")
[ "$ARTICLE_HTTP" = 200 ] || { ERROR_CLASS="article91_baseline_http_not_200"; block article91_baseline_http_not_200; }
ARTICLE_DESC_BEFORE="$(extract_desc "$TMP/article.before.html")"
ARTICLE_CAN_BEFORE="$(extract_canonical "$TMP/article.before.html")"
[ -n "$ARTICLE_DESC_BEFORE" ] || { ERROR_CLASS="article91_baseline_description_missing"; block article91_baseline_description_missing; }
[ "$ARTICLE_CAN_BEFORE" = "$CANONICAL/index.php?c=show&id=91" ] || { ERROR_CLASS="article91_baseline_canonical_unexpected"; block article91_baseline_canonical_unexpected; }

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

PHASE="render_verify"
PC_CODE=$(curl -skL --max-time 30 -o "$TMP/pc.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=91")
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
MOBILE_CODE=$(curl -skL --max-time 30 -A "$MOBILE_UA" -o "$TMP/mobile.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=91")
[ "$PC_CODE" = 200 ] || { ERROR_CLASS="article91_pc_http_not_200"; block article91_pc_http_not_200; }
[ "$MOBILE_CODE" = 200 ] || { ERROR_CLASS="article91_mobile_http_not_200"; block article91_mobile_http_not_200; }

python3 - "$TMP/pc.html" "$TMP/mobile.html" <<'PY' > "$TMP/nav.json"
import html,json,re,sys
from urllib.parse import parse_qsl,urljoin,urlsplit
base='https://www.laocaimi.org'
required={'gjfa','tzjq','zyyy','seo-articles'}
forbidden_dirs={'gdrz','rjxm'}
forbidden_ids={2,3,4,5,7}

def attr(tag,name):
    m=re.search(r'\b'+re.escape(name)+r'\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    return html.unescape(m.group(1).strip()) if m else ''
def nav_html(s, mobile=False):
    cls='category-nav' if mobile else 'xyptdq-site-nav'
    m=re.search(r'<nav\b[^>]*class=["\'][^"\']*\b'+re.escape(cls)+r'\b[^"\']*["\'][^>]*>(.*?)</nav\s*>',s,re.I|re.S)
    return m.group(1) if m else ''
def stats(path,mobile):
    s=open(path,encoding='utf-8',errors='ignore').read()
    n=nav_html(s,mobile)
    if not n: raise SystemExit('navigation_not_found')
    req=set(); forbidden=0
    for a in re.findall(r'<a\b[^>]*>',n,re.I|re.S):
        u=urljoin(base+'/',attr(a,'href'))
        p=urlsplit(u); q=dict(parse_qsl(p.query,keep_blank_values=True))
        if q.get('c')!='category': continue
        d=q.get('dir','')
        if d in required: req.add(d)
        if d in forbidden_dirs: forbidden+=1
        if q.get('id','').isdigit() and int(q['id']) in forbidden_ids: forbidden+=1
    return {'required':len(req),'forbidden':forbidden}
print(json.dumps({'pc':stats(sys.argv[1],False),'mobile':stats(sys.argv[2],True)}))
PY

PC_REQUIRED_LINKS=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pc"]["required"])' "$TMP/nav.json")
MOBILE_REQUIRED_LINKS=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["mobile"]["required"])' "$TMP/nav.json")
PC_FORBIDDEN_LINKS=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pc"]["forbidden"])' "$TMP/nav.json")
MOBILE_FORBIDDEN_LINKS=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["mobile"]["forbidden"])' "$TMP/nav.json")
[ "$PC_REQUIRED_LINKS" -eq 4 ] || { ERROR_CLASS="pc_required_links_incomplete"; block pc_required_links_incomplete; }
[ "$MOBILE_REQUIRED_LINKS" -eq 4 ] || { ERROR_CLASS="mobile_required_links_incomplete"; block mobile_required_links_incomplete; }
[ "$PC_FORBIDDEN_LINKS" -eq 0 ] || { ERROR_CLASS="pc_forbidden_links_present"; block pc_forbidden_links_present; }
[ "$MOBILE_FORBIDDEN_LINKS" -eq 0 ] || { ERROR_CLASS="mobile_forbidden_links_present"; block mobile_forbidden_links_present; }

ARTICLE_DESC_AFTER="$(extract_desc "$TMP/pc.html")"
ARTICLE_CAN_AFTER="$(extract_canonical "$TMP/pc.html")"
[ "$ARTICLE_DESC_AFTER" = "$ARTICLE_DESC_BEFORE" ] || { ERROR_CLASS="article91_description_changed"; block article91_description_changed; }
[ "$ARTICLE_CAN_AFTER" = "$ARTICLE_CAN_BEFORE" ] || { ERROR_CLASS="article91_canonical_changed"; block article91_canonical_changed; }
ARTICLE_DESCRIPTION_UNCHANGED="PASS"
ARTICLE_CANONICAL_OK="PASS"

CATEGORY_CANONICAL_OK=0
for d in gjfa tzjq zyyy seo-articles; do
  code=$(curl -skL --max-time 30 -o "$TMP/cat-$d.html" -w '%{http_code}' "$CANONICAL/index.php?c=category&dir=$d")
  [ "$code" = 200 ] || { ERROR_CLASS="category_http_not_200"; block category_http_not_200; }
  c="$(extract_canonical "$TMP/cat-$d.html")"
  [ "$c" = "$CANONICAL/index.php?c=category&dir=$d" ] || { ERROR_CLASS="category_not_self_canonical"; block category_not_self_canonical; }
  CATEGORY_CANONICAL_OK=$((CATEGORY_CANONICAL_OK+1))
done

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
echo "CANONICAL_CATEGORY_NAV_V1=PASS pc=$PC_REQUIRED_LINKS mobile=$MOBILE_REQUIRED_LINKS"
