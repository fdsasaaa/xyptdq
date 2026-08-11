#!/bin/bash
# Rollback-gated production deployment for homepage native lazy loading.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="44f1c90ab23763f2597bb9d14d8ce024b593f727"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"

PHASE="init"
DEPLOY="NO"
ROLLBACK="NO"
HOME_HTTP=0
MOBILE_HOME_HTTP=0
CATEGORY_HTTP=0
ARTICLE_HTTP=0
PLATFORM_HTTP=0
HOME_IMAGE_COUNT=-1
HOME_LAZY_COUNT=-1
HOME_ASYNC_COUNT=-1
HOME_MISSING_DIMENSIONS=-1
SITE_LOGO_EAGER="NO"
FRAMEWORK_OK="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
TMP="$(mktemp -d /tmp/xyptdq-home-lazy-deploy.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload() {
  local status="$1"
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$ROLLBACK" "$HOME_HTTP" "$MOBILE_HOME_HTTP" "$CATEGORY_HTTP" "$ARTICLE_HTTP" "$PLATFORM_HTTP" "$HOME_IMAGE_COUNT" "$HOME_LAZY_COUNT" "$HOME_ASYNC_COUNT" "$HOME_MISSING_DIMENSIONS" "$SITE_LOGO_EAGER" "$FRAMEWORK_OK" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,target,deploy,rollback,home,mhome,category,article,platform,image_count,lazy_count,async_count,missing_dims,logo_eager,framework,error_class,blocker)=sys.argv[1:]
payload={
  "task":"deploy_seo_home_lazy_images_v1",
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
  "home_image_count":int(image_count),
  "home_lazy_count":int(lazy_count),
  "home_decoding_async_count":int(async_count),
  "home_missing_width_or_height":int(missing_dims),
  "site_logo_eager":logo_eager,
  "framework_integrity":framework,
  "deploy_error_class":error_class,
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
  echo "[seo-home-lazy] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
  exit 1
}

cd "$REPO"
PHASE="repo_sync"
git fetch --prune origin >/dev/null 2>&1
git merge-base --is-ancestor "$TARGET_SHA" origin/main || { ERROR_CLASS="target_not_in_main"; block target_not_in_main; }

PHASE="source_verify"
git show "$TARGET_SHA:site/template/pc/default/home/index.html" > "$TMP/index.src"
grep -Fq 'width="216" height="60" loading="lazy" decoding="async"' "$TMP/index.src" || { ERROR_CLASS="platform_lazy_source_missing"; block platform_lazy_source_missing; }
grep -Fq 'width="227" height="71" loading="lazy" decoding="async"' "$TMP/index.src" || { ERROR_CLASS="display_lazy_source_missing"; block display_lazy_source_missing; }
if grep -F 'src="{SITE_LOGO}" width="114" height="114"' "$TMP/index.src" | grep -Fq 'loading="lazy"'; then
  ERROR_CLASS="site_logo_was_lazy_loaded"
  block site_logo_was_lazy_loaded
fi

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

python3 - "$TMP/home.html" <<'PY' > "$TMP/home-image.status"
import re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
imgs=re.findall(r'<img\b[^>]*>',s,re.I|re.S)
def attr(tag,name):
    m=re.search(r'\b'+re.escape(name)+r'=["\']([^"\']*)["\']',tag,re.I|re.S)
    return m.group(1).strip() if m else ''
lazy=sum(1 for t in imgs if attr(t,'loading').lower()=='lazy')
async_count=sum(1 for t in imgs if attr(t,'decoding').lower()=='async')
missing=sum(1 for t in imgs if not (attr(t,'width') and attr(t,'height')))
first_lazy=1 if imgs and attr(imgs[0],'loading').lower()=='lazy' else 0
print(len(imgs),lazy,async_count,missing,first_lazy,sep='\t')
PY
IFS=$'\t' read -r HOME_IMAGE_COUNT HOME_LAZY_COUNT HOME_ASYNC_COUNT HOME_MISSING_DIMENSIONS FIRST_LAZY < "$TMP/home-image.status"
[ "$HOME_IMAGE_COUNT" -ge 34 ] || { ERROR_CLASS="home_image_count_regressed"; block home_image_count_regressed; }
[ "$HOME_LAZY_COUNT" -ge 33 ] || { ERROR_CLASS="home_lazy_count_too_low"; block home_lazy_count_too_low; }
[ "$HOME_ASYNC_COUNT" -ge 33 ] || { ERROR_CLASS="home_async_count_too_low"; block home_async_count_too_low; }
[ "$HOME_MISSING_DIMENSIONS" = 0 ] || { ERROR_CLASS="home_image_dimensions_regressed"; block home_image_dimensions_regressed; }
if [ "$FIRST_LAZY" = 0 ]; then SITE_LOGO_EAGER="PASS"; else ERROR_CLASS="site_logo_rendered_lazy"; block site_logo_rendered_lazy; fi

if python3 - "$TMP/home.html" <<'PY'
import re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
raise SystemExit(0 if re.search(r'<meta[^>]+name=["\']robots["\'][^>]+content=["\'][^"\']*\bnone\b',s,re.I) else 1)
PY
then
  ERROR_CLASS="home_robots_none"
  block home_robots_none
fi

PHASE="framework_verify"
if [ -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" ] && [ -f "$WEBROOT/cache/frame.lock" ] && [ "$(od -An -tx1 -v "$WEBROOT/cache/frame.lock" | tr -d ' \n')" = "$EXPECTED_FRAME_LOCK_HEX" ]; then
  FRAMEWORK_OK="PASS"
else
  ERROR_CLASS="framework_integrity_failed"
  block framework_integrity_failed
fi

PHASE="final"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"
write_payload PASS
echo "SEO_HOME_LAZY_IMAGES_V1=PASS target=$TARGET_SHA lazy=$HOME_LAZY_COUNT"
