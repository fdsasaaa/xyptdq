#!/bin/bash
# Rollback-gated production deployment for SEO Phase 3 platform detail depth.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="dfe07b92abc9d6b4d624a298530f076a517b5aef"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"

PHASE="init"
DEPLOY="NO"
ROLLBACK="NO"
HOME_HTTP=0
CATEGORY_HTTP=0
ARTICLE_HTTP=0
MOBILE_ARTICLE_HTTP=0
PLATFORM_HTTP=0
MOBILE_PLATFORM_HTTP=0
PLATFORM_GUIDE="NO"
MOBILE_PLATFORM_GUIDE="NO"
ARTICLE_SCHEMA="NO"
MOBILE_ARTICLE_SCHEMA="NO"
PLATFORM_SCHEMA="NO"
MOBILE_PLATFORM_SCHEMA="NO"
FRAMEWORK_OK="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4

TMP="$(mktemp -d /tmp/xyptdq-platform-depth.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload() {
  local status="$1"
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$ROLLBACK" "$HOME_HTTP" "$CATEGORY_HTTP" "$ARTICLE_HTTP" "$MOBILE_ARTICLE_HTTP" "$PLATFORM_HTTP" "$MOBILE_PLATFORM_HTTP" "$PLATFORM_GUIDE" "$MOBILE_PLATFORM_GUIDE" "$ARTICLE_SCHEMA" "$MOBILE_ARTICLE_SCHEMA" "$PLATFORM_SCHEMA" "$MOBILE_PLATFORM_SCHEMA" "$FRAMEWORK_OK" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,target,deploy,rollback,home,cat,article,marticle,platform,mplatform,pguide,mpguide,aschema,maschema,pschema,mpschema,framework,error,blocker)=sys.argv[1:]
payload={
 "task":"deploy_seo_platform_depth_v1",
 "deployment_status":status,
 "phase":phase,
 "target_sha":target,
 "deploy":deploy,
 "rollback":rollback,
 "home_http":int(home),
 "category7_http":int(cat),
 "article91_http":int(article),
 "mobile_article91_http":int(marticle),
 "platform19_http":int(platform),
 "mobile_platform19_http":int(mplatform),
 "platform_guide":pguide,
 "mobile_platform_guide":mpguide,
 "article_schema":aschema,
 "mobile_article_schema":maschema,
 "platform_schema_semantics":pschema,
 "mobile_platform_schema_semantics":mpschema,
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
  echo "[seo-platform-depth] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
  exit 1
}

cd "$REPO"
PHASE="repo_sync"
git fetch --prune origin >/dev/null 2>&1
git merge-base --is-ancestor "$TARGET_SHA" origin/main || { ERROR_CLASS="target_not_in_main"; block target_not_in_main; }

PHASE="source_verify"
for path in site/template/pc/default/home/show.html site/template/mobile/default/home/show.html; do
  git show "$TARGET_SHA:$path" > "$TMP/$(basename "$(dirname "$path")")-$(basename "$path").src"
  git show "$TARGET_SHA:$path" | grep -Fq '平台资料阅读与核验说明' || { ERROR_CLASS="platform_guide_missing_in_source"; block platform_guide_missing_in_source; }
  git show "$TARGET_SHA:$path" | grep -Fq "MOD_DIR=='xm'" || { ERROR_CLASS="platform_module_guard_missing"; block platform_module_guard_missing; }
done

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
fetch_page mobile_article "$CANONICAL/index.php?c=show&id=91" "$MOBILE_UA"
fetch_page platform "$CANONICAL/index.php?c=show&id=19"
fetch_page mobile_platform "$CANONICAL/index.php?c=show&id=19" "$MOBILE_UA"

HOME_HTTP="$(cat "$TMP/home.code")"
CATEGORY_HTTP="$(cat "$TMP/category.code")"
ARTICLE_HTTP="$(cat "$TMP/article.code")"
MOBILE_ARTICLE_HTTP="$(cat "$TMP/mobile_article.code")"
PLATFORM_HTTP="$(cat "$TMP/platform.code")"
MOBILE_PLATFORM_HTTP="$(cat "$TMP/mobile_platform.code")"

for v in "$HOME_HTTP" "$CATEGORY_HTTP" "$ARTICLE_HTTP" "$MOBILE_ARTICLE_HTTP" "$PLATFORM_HTTP" "$MOBILE_PLATFORM_HTTP"; do
  [ "$v" = 200 ] || { ERROR_CLASS="http_not_200"; block representative_http_failed; }
done

grep -Fq '平台资料阅读与核验说明' "$TMP/platform.html" && PLATFORM_GUIDE="PASS" || { ERROR_CLASS="platform_guide_not_rendered"; block platform_guide_not_rendered; }
grep -Fq '平台资料阅读与核验说明' "$TMP/mobile_platform.html" && MOBILE_PLATFORM_GUIDE="PASS" || { ERROR_CLASS="mobile_platform_guide_not_rendered"; block mobile_platform_guide_not_rendered; }

python3 - "$TMP/article.html" "$TMP/mobile_article.html" "$TMP/platform.html" "$TMP/mobile_platform.html" <<'PY' > "$TMP/schema.status"
import re,sys
def read(p): return open(p,encoding='utf-8',errors='ignore').read()
a,ma,p,mp=map(read,sys.argv[1:])
article=lambda s: bool(re.search(r'"@type"\s*:\s*"Article"',s))
webpage=lambda s: bool(re.search(r'"@type"\s*:\s*"WebPage"',s))
print("PASS" if article(a) else "FAIL")
print("PASS" if article(ma) else "FAIL")
print("PASS" if (webpage(p) and not article(p)) else "FAIL")
print("PASS" if (webpage(mp) and not article(mp)) else "FAIL")
PY
mapfile -t schema_status < "$TMP/schema.status"
ARTICLE_SCHEMA="${schema_status[0]}"
MOBILE_ARTICLE_SCHEMA="${schema_status[1]}"
PLATFORM_SCHEMA="${schema_status[2]}"
MOBILE_PLATFORM_SCHEMA="${schema_status[3]}"
[ "$ARTICLE_SCHEMA" = PASS ] || { ERROR_CLASS="article_schema_failed"; block article_schema_failed; }
[ "$MOBILE_ARTICLE_SCHEMA" = PASS ] || { ERROR_CLASS="mobile_article_schema_failed"; block mobile_article_schema_failed; }
[ "$PLATFORM_SCHEMA" = PASS ] || { ERROR_CLASS="platform_schema_failed"; block platform_schema_failed; }
[ "$MOBILE_PLATFORM_SCHEMA" = PASS ] || { ERROR_CLASS="mobile_platform_schema_failed"; block mobile_platform_schema_failed; }

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
echo "SEO_PLATFORM_DEPTH_V1=PASS target=$TARGET_SHA"
