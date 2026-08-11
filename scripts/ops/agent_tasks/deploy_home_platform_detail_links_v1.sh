#!/bin/bash
# Rollback-gated production deployment for homepage -> platform detail internal links.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="eba6655a8e808a8e81fb25dbf57b825cc7a9ca0c"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"

PHASE="init"
DEPLOY="NO"
ROLLBACK="NO"
HOME_HTTP=0
MOBILE_HOME_HTTP=0
CATEGORY_HTTP=0
ARTICLE_HTTP=0
PLATFORM_HTTP=0
PLATFORM_DETAIL_LINKS=-1
UNIQUE_PLATFORM_DETAIL_LINKS=-1
EXTERNAL_UNQUALIFIED=-1
FRAMEWORK_OK="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4

TMP="$(mktemp -d /tmp/xyptdq-platform-links-deploy.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload() {
  local status="$1"
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$ROLLBACK" \
    "$HOME_HTTP" "$MOBILE_HOME_HTTP" "$CATEGORY_HTTP" "$ARTICLE_HTTP" "$PLATFORM_HTTP" \
    "$PLATFORM_DETAIL_LINKS" "$UNIQUE_PLATFORM_DETAIL_LINKS" "$EXTERNAL_UNQUALIFIED" \
    "$FRAMEWORK_OK" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,target,deploy,rollback,home,mhome,category,article,platform,
 detail_count,unique_count,external_unqualified,framework,error_class,blocker)=sys.argv[1:]
payload={
  "task":"deploy_home_platform_detail_links_v1",
  "deployment_status":status,
  "phase":phase,
  "target_sha":target,
  "deploy":deploy,
  "rollback":rollback,
  "home_http":int(home),
  "mobile_home_http":int(mhome),
  "category7_http":int(category),
  "article91_http":int(article),
  "platform19_http":int(platform),
  "platform_detail_link_count":int(detail_count),
  "unique_platform_detail_link_count":int(unique_count),
  "external_links_without_nofollow_or_sponsored":int(external_unqualified),
  "framework_integrity":framework,
  "deploy_error_class":error_class,
  "blocking_item":blocker,
  "article_publishing_attempted":False,
  "secrets_disclosed":False
}
with open(out,"w",encoding="utf-8") as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True)
    f.write("\n")
PY
}

rollback_templates() {
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

block() {
  BLOCKING_ITEM="$1"
  if [ "$DEPLOY" = "PASS" ]; then rollback_templates; fi
  write_payload BLOCKED
  echo "[platform-links-deploy] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
  exit 1
}

cd "$REPO"
PHASE="repo_sync"
git fetch --prune origin >/dev/null 2>&1
git merge-base --is-ancestor "$TARGET_SHA" origin/main || {
  ERROR_CLASS="target_not_in_main"; block target_not_in_main;
}

PHASE="source_verify"
git show "$TARGET_SHA:site/template/pc/default/home/index.html" > "$TMP/index.src"
grep -Fq '平台资料详情' "$TMP/index.src" || {
  ERROR_CLASS="platform_detail_link_source_missing"; block platform_detail_link_source_missing;
}
grep -Fq '.plat-item-top h2 a{color:inherit;text-decoration:none}' "$TMP/index.src" || {
  ERROR_CLASS="platform_detail_link_style_missing"; block platform_detail_link_style_missing;
}
grep -Fq 'rel="nofollow sponsored noopener"' "$TMP/index.src" || {
  ERROR_CLASS="commercial_rel_source_regressed"; block commercial_rel_source_regressed;
}

PHASE="rollback_snapshot"
cp -a "$WEBROOT/template" "$TMP/template.before"

PHASE="deploy"
git show "$TARGET_SHA:scripts/deploy_safe.sh" > "$TMP/deploy_safe.sh" || {
  ERROR_CLASS="deploy_safe_missing"; block deploy_safe_missing;
}
chmod 700 "$TMP/deploy_safe.sh"
if ! XYPTDQ_REPO_DIR="$REPO" XYPTDQ_WEBROOT="$WEBROOT" \
    bash "$TMP/deploy_safe.sh" "$TARGET_SHA" >"$TMP/deploy.log" 2>&1; then
  ERROR_CLASS="canonical_deploy_failed"
  block deploy_safe_failed
fi
DEPLOY="PASS"

fetch_page() {
  local name="$1" url="$2" ua="${3:-}"
  if [ -n "$ua" ]; then
    curl -skL --max-time 30 -A "$ua" -o "$TMP/$name.html" -w '%{http_code}' "$url" > "$TMP/$name.code"
  else
    curl -skL --max-time 30 -o "$TMP/$name.html" -w '%{http_code}' "$url" > "$TMP/$name.code"
  fi
}
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'

PHASE="render_verify"
fetch_page home "$CANONICAL/"
fetch_page mobile_home "$CANONICAL/" "$MOBILE_UA"
fetch_page category "$CANONICAL/index.php?c=category&id=7"
fetch_page article "$CANONICAL/index.php?c=show&id=91"
fetch_page platform "$CANONICAL/index.php?c=show&id=19"

HOME_HTTP="$(cat "$TMP/home.code")"
MOBILE_HOME_HTTP="$(cat "$TMP/mobile_home.code")"
CATEGORY_HTTP="$(cat "$TMP/category.code")"
ARTICLE_HTTP="$(cat "$TMP/article.code")"
PLATFORM_HTTP="$(cat "$TMP/platform.code")"
for v in "$HOME_HTTP" "$MOBILE_HOME_HTTP" "$CATEGORY_HTTP" "$ARTICLE_HTTP" "$PLATFORM_HTTP"; do
  [ "$v" = 200 ] || { ERROR_CLASS="http_not_200"; block representative_http_failed; }
done

python3 - "$TMP/home.html" "$CANONICAL" <<'PY' > "$TMP/link.status"
import html,re,sys
from urllib.parse import urljoin,urlparse
path,canonical=sys.argv[1:]
host=urlparse(canonical).netloc.lower()
s=open(path,encoding="utf-8",errors="ignore").read()

def attr(tag,name):
    m=re.search(r'\b'+re.escape(name)+r'\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    return html.unescape(m.group(1).strip()) if m else ""

anchors=re.findall(r'<a\b[^>]*>',s,re.I|re.S)
detail=[]
external_unqualified=0
for a in anchors:
    href=attr(a,"href")
    if not href or href.startswith(("#","javascript:","mailto:","tel:")):
        continue
    title=attr(a,"title")
    rel=set(attr(a,"rel").lower().split())
    p=urlparse(urljoin(canonical,href))
    internal=(not p.netloc) or p.netloc.lower()==host
    if internal and title.endswith("平台资料详情"):
        detail.append(urljoin(canonical,href))
    elif not internal and not ({"nofollow","sponsored"} & rel):
        external_unqualified += 1

print(len(detail),len(set(detail)),external_unqualified,sep="\t")
PY

IFS=$'\t' read -r PLATFORM_DETAIL_LINKS UNIQUE_PLATFORM_DETAIL_LINKS EXTERNAL_UNQUALIFIED < "$TMP/link.status"
[ "$PLATFORM_DETAIL_LINKS" -ge 20 ] || {
  ERROR_CLASS="platform_detail_links_too_few"; block platform_detail_links_too_few;
}
[ "$UNIQUE_PLATFORM_DETAIL_LINKS" -ge 20 ] || {
  ERROR_CLASS="platform_detail_unique_links_too_few"; block platform_detail_unique_links_too_few;
}
[ "$EXTERNAL_UNQUALIFIED" = 0 ] || {
  ERROR_CLASS="commercial_link_rel_regressed"; block commercial_link_rel_regressed;
}

PHASE="framework_verify"
if [ -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" ] \
   && [ -f "$WEBROOT/cache/frame.lock" ] \
   && [ "$(od -An -tx1 -v "$WEBROOT/cache/frame.lock" | tr -d ' \n')" = "$EXPECTED_FRAME_LOCK_HEX" ]; then
  FRAMEWORK_OK="PASS"
else
  ERROR_CLASS="framework_integrity_failed"
  block framework_integrity_failed
fi

PHASE="final"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"
write_payload PASS
echo "HOME_PLATFORM_DETAIL_LINKS_V1=PASS target=$TARGET_SHA detail_links=$PLATFORM_DETAIL_LINKS"
