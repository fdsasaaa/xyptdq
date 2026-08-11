#!/bin/bash
# Rollback-gated production deployment for verified image dimensions.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="a14adadb4b20108841f5a32b63c0fd636aee6a7a"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"

PHASE="init"
DEPLOY="NO"
ROLLBACK="NO"
HOME_HTTP=0
CATEGORY_HTTP=0
ARTICLE_HTTP=0
PLATFORM_HTTP=0
MOBILE_HOME_HTTP=0
HOME_MISSING=-1
CATEGORY_MISSING=-1
ARTICLE_MISSING=-1
PLATFORM_MISSING=-1
FRAMEWORK_OK="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4

TMP="$(mktemp -d /tmp/xyptdq-image-dims-deploy.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload() {
  local status="$1"
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$ROLLBACK" "$HOME_HTTP" "$CATEGORY_HTTP" "$ARTICLE_HTTP" "$PLATFORM_HTTP" "$MOBILE_HOME_HTTP" "$HOME_MISSING" "$CATEGORY_MISSING" "$ARTICLE_MISSING" "$PLATFORM_MISSING" "$FRAMEWORK_OK" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,target,deploy,rollback,home,cat,article,platform,mhome,hmiss,cmiss,amiss,pmiss,framework,error,blocker)=sys.argv[1:]
payload={
 "task":"deploy_seo_image_dimensions_v1",
 "deployment_status":status,
 "phase":phase,
 "target_sha":target,
 "deploy":deploy,
 "rollback":rollback,
 "home_http":int(home),
 "category7_http":int(cat),
 "article91_http":int(article),
 "platform19_http":int(platform),
 "mobile_home_http":int(mhome),
 "home_missing_width_or_height":int(hmiss),
 "category_missing_width_or_height":int(cmiss),
 "article_missing_width_or_height":int(amiss),
 "platform_missing_width_or_height":int(pmiss),
 "framework_integrity":framework,
 "deploy_error_class":error,
 "blocking_item":blocker,
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
  echo "[seo-image-dims] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
  exit 1
}

cd "$REPO"
PHASE="repo_sync"
git fetch --prune origin >/dev/null 2>&1
git merge-base --is-ancestor "$TARGET_SHA" origin/main || { ERROR_CLASS="target_not_in_main"; block target_not_in_main; }

PHASE="source_verify"
git show "$TARGET_SHA:site/template/pc/default/home/index.html" > "$TMP/index.src"
git show "$TARGET_SHA:site/template/pc/default/home/seo_header.html" > "$TMP/header.src"
grep -Fq 'src="{SITE_LOGO}" width="114" height="114" alt="信誉平台大全（彩研导航站）"' "$TMP/index.src" || { ERROR_CLASS="home_logo_dimensions_missing"; block home_logo_dimensions_missing; }
grep -Fq 'width="216" height="60" alt="{$t['"'"'title'"'"']}"' "$TMP/index.src" || { ERROR_CLASS="platform_logo_dimensions_missing"; block platform_logo_dimensions_missing; }
grep -Fq 'class="ad_pic"' "$TMP/index.src" || { ERROR_CLASS="display_image_missing"; block display_image_missing; }
grep -Fq 'width="227" height="71" alt="站点展示位"' "$TMP/index.src" || { ERROR_CLASS="display_image_dimensions_missing"; block display_image_dimensions_missing; }
grep -Fq 'src="{SITE_LOGO}" width="114" height="114" alt="信誉平台大全（彩研导航站）"' "$TMP/header.src" || { ERROR_CLASS="shared_logo_dimensions_missing"; block shared_logo_dimensions_missing; }

PHASE="rollback_snapshot"
cp -a "$WEBROOT/template" "$TMP/template.before"

PHASE="deploy"
git show "$TARGET_SHA:scripts/deploy_safe.sh" > "$TMP/deploy_safe.sh" || { ERROR_CLASS="deploy_safe_missing"; block deploy_safe_missing; }
chmod 700 "$TMP/deploy_safe.sh"
if ! XYPTDQ_REPO_DIR="$REPO" XYPTDQ_WEBROOT="$WEBROOT" bash "$TMP/deploy_safe.sh" "$TARGET_SHA" >"$TMP/deploy.log" 2>&1; then
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
fetch_page category "$CANONICAL/index.php?c=category&id=7"
fetch_page article "$CANONICAL/index.php?c=show&id=91"
fetch_page platform "$CANONICAL/index.php?c=show&id=19"
fetch_page mobile_home "$CANONICAL/" "$MOBILE_UA"

HOME_HTTP="$(cat "$TMP/home.code")"
CATEGORY_HTTP="$(cat "$TMP/category.code")"
ARTICLE_HTTP="$(cat "$TMP/article.code")"
PLATFORM_HTTP="$(cat "$TMP/platform.code")"
MOBILE_HOME_HTTP="$(cat "$TMP/mobile_home.code")"
for v in "$HOME_HTTP" "$CATEGORY_HTTP" "$ARTICLE_HTTP" "$PLATFORM_HTTP" "$MOBILE_HOME_HTTP"; do
  [ "$v" = 200 ] || { ERROR_CLASS="http_not_200"; block representative_http_failed; }
done

python3 - "$TMP" <<'PY' > "$TMP/image.status"
import pathlib,re,sys
tmp=pathlib.Path(sys.argv[1])
def attr(tag,name):
    m=re.search(r'\b'+re.escape(name)+r'=["\']([^"\']*)["\']',tag,re.I|re.S)
    return m.group(1).strip() if m else ''
for page in ['home','category','article','platform']:
    s=(tmp/f'{page}.html').read_text(encoding='utf-8',errors='ignore')
    imgs=re.findall(r'<img\b[^>]*>',s,re.I|re.S)
    missing=sum(1 for tag in imgs if not (attr(tag,'width') and attr(tag,'height')))
    print(f'{page}\t{len(imgs)}\t{missing}')
PY

while IFS=$'\t' read -r page total missing; do
  case "$page" in
    home) HOME_MISSING="$missing" ;;
    category) CATEGORY_MISSING="$missing" ;;
    article) ARTICLE_MISSING="$missing" ;;
    platform) PLATFORM_MISSING="$missing" ;;
  esac
done < "$TMP/image.status"

[ "$HOME_MISSING" = 0 ] || { ERROR_CLASS="home_image_dimensions_incomplete"; block home_image_dimensions_incomplete; }
[ "$CATEGORY_MISSING" = 0 ] || { ERROR_CLASS="category_image_dimensions_incomplete"; block category_image_dimensions_incomplete; }
[ "$ARTICLE_MISSING" = 0 ] || { ERROR_CLASS="article_image_dimensions_incomplete"; block article_image_dimensions_incomplete; }
[ "$PLATFORM_MISSING" = 0 ] || { ERROR_CLASS="platform_image_dimensions_incomplete"; block platform_image_dimensions_incomplete; }

if grep -Eiq '<meta[^>]+name=["'"']robots["'"'][^>]+content=["'"'][^"'"']*\bnone\b' "$TMP/home.html"; then
  ERROR_CLASS="home_robots_none"; block home_robots_none
fi

PHASE="framework_verify"
if [ -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" ] && [ -f "$WEBROOT/cache/frame.lock" ] && [ "$(od -An -tx1 -v "$WEBROOT/cache/frame.lock" | tr -d ' \n')" = "$EXPECTED_FRAME_LOCK_HEX" ]; then
  FRAMEWORK_OK="PASS"
else
  ERROR_CLASS="framework_integrity_failed"; block framework_integrity_failed
fi

PHASE="final"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"
write_payload PASS
echo "SEO_IMAGE_DIMENSIONS_V1=PASS target=$TARGET_SHA"
