#!/bin/bash
# Rollback-gated deploy for page-specific fallback meta descriptions.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="a463628011893a63682fedc92dffd48669ccda31"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"
OLD_GENERIC='提供彩票数据研究、方案验证、投注成本与风险分析、平台资料导航。内容用于信息与方法研究，不承诺任何收益。'

PHASE="init"
DEPLOY="NO"
ROLLBACK="NO"
HOME_HTTP=0
ARTICLE_HTTP=0
PLATFORM_SAMPLE_COUNT=0
PC_UNIQUE_DESCRIPTIONS=0
MOBILE_UNIQUE_DESCRIPTIONS=0
PLATFORM_DESC_WITH_TITLE=0
MOBILE_DESC_WITH_TITLE=0
ARTICLE_DESC_UNCHANGED="NO"
FRAMEWORK_OK="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
[ -f "$WEBROOT/config/database.php" ] || exit 5

TMP="$(mktemp -d /tmp/xyptdq-meta-desc-deploy.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload(){
  local status="$1"
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$ROLLBACK" \
    "$HOME_HTTP" "$ARTICLE_HTTP" "$PLATFORM_SAMPLE_COUNT" "$PC_UNIQUE_DESCRIPTIONS" \
    "$MOBILE_UNIQUE_DESCRIPTIONS" "$PLATFORM_DESC_WITH_TITLE" "$MOBILE_DESC_WITH_TITLE" \
    "$ARTICLE_DESC_UNCHANGED" "$FRAMEWORK_OK" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,target,deploy,rollback,home,article,sample,pc_unique,mobile_unique,
 pc_title,mobile_title,article_unchanged,framework,error_class,blocker)=sys.argv[1:]
payload={
  "task":"deploy_dynamic_meta_description_v1",
  "deployment_status":status,
  "phase":phase,
  "target_sha":target,
  "deploy":deploy,
  "rollback":rollback,
  "home_http":int(home),
  "article91_http":int(article),
  "platform_sample_count":int(sample),
  "pc_unique_description_count":int(pc_unique),
  "mobile_unique_description_count":int(mobile_unique),
  "pc_descriptions_containing_platform_title":int(pc_title),
  "mobile_descriptions_containing_platform_title":int(mobile_title),
  "article91_explicit_description_unchanged":article_unchanged,
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
  echo "[meta-desc-deploy] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
  exit 1
}

extract_desc(){
  python3 - "$1" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
for tag in re.findall(r'<meta\b[^>]*>',s,re.I|re.S):
    n=re.search(r'\bname\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    if not n or html.unescape(n.group(1)).strip().lower()!='description':
        continue
    c=re.search(r'\bcontent\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    print(html.unescape(c.group(1)).strip() if c else '')
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
  git show "$TARGET_SHA:$p" > "$TMP/$(basename "$(dirname "$p")")-$(basename "$p")" || {
    ERROR_CLASS="source_missing"; block source_missing;
  }
  git show "$TARGET_SHA:$p" | grep -Fq '整理相关资料、规则说明、数据或使用信息' || {
    ERROR_CLASS="dynamic_detail_fallback_missing"; block dynamic_detail_fallback_missing;
  }
  git show "$TARGET_SHA:$p" | grep -Fq '栏目：汇总相关资料、方法、规则、验证记录与风险说明' || {
    ERROR_CLASS="dynamic_category_fallback_missing"; block dynamic_category_fallback_missing;
  }
done

PHASE="sample_inventory"
php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$rows=$pdo->query("SELECT id,title FROM dr_1_xm WHERE status=9 ORDER BY id ASC LIMIT 5")->fetchAll();
echo json_encode($rows,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php" > "$TMP/platforms.json"
PLATFORM_SAMPLE_COUNT=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1],encoding="utf-8"))))' "$TMP/platforms.json")
[ "$PLATFORM_SAMPLE_COUNT" -eq 5 ] || { ERROR_CLASS="platform_sample_incomplete"; block platform_sample_incomplete; }

PHASE="pre_deploy_baseline"
curl -skL --max-time 30 -o "$TMP/article.before.html" "$CANONICAL/index.php?c=show&id=91"
ARTICLE_DESC_BEFORE="$(extract_desc "$TMP/article.before.html")"
[ -n "$ARTICLE_DESC_BEFORE" ] || { ERROR_CLASS="article91_baseline_description_missing"; block article91_baseline_description_missing; }

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
HOME_HTTP=$(curl -skL --max-time 30 -o "$TMP/home.html" -w '%{http_code}' "$CANONICAL/")
ARTICLE_HTTP=$(curl -skL --max-time 30 -o "$TMP/article.after.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=91")
[ "$HOME_HTTP" = 200 ] || { ERROR_CLASS="home_http_not_200"; block home_http_not_200; }
[ "$ARTICLE_HTTP" = 200 ] || { ERROR_CLASS="article91_http_not_200"; block article91_http_not_200; }
ARTICLE_DESC_AFTER="$(extract_desc "$TMP/article.after.html")"
[ "$ARTICLE_DESC_AFTER" = "$ARTICLE_DESC_BEFORE" ] || {
  ERROR_CLASS="explicit_article_description_changed"; block explicit_article_description_changed;
}
ARTICLE_DESC_UNCHANGED="PASS"

MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
python3 - "$TMP/platforms.json" <<'PY' > "$TMP/platform.tsv"
import json,sys
for x in json.load(open(sys.argv[1],encoding='utf-8')):
    print(f"{int(x['id'])}\t{str(x['title']).replace(chr(9),' ')}")
PY
: > "$TMP/pc.desc"
: > "$TMP/mobile.desc"
while IFS=$'\t' read -r pid ptitle; do
  pc_code=$(curl -skL --max-time 30 -o "$TMP/pc-$pid.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$pid")
  mobile_code=$(curl -skL --max-time 30 -A "$MOBILE_UA" -o "$TMP/mobile-$pid.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$pid")
  [ "$pc_code" = 200 ] || { ERROR_CLASS="platform_pc_http_not_200"; block platform_pc_http_not_200; }
  [ "$mobile_code" = 200 ] || { ERROR_CLASS="platform_mobile_http_not_200"; block platform_mobile_http_not_200; }
  pc_desc="$(extract_desc "$TMP/pc-$pid.html")"
  mobile_desc="$(extract_desc "$TMP/mobile-$pid.html")"
  [ -n "$pc_desc" ] || { ERROR_CLASS="platform_pc_description_missing"; block platform_pc_description_missing; }
  [ -n "$mobile_desc" ] || { ERROR_CLASS="platform_mobile_description_missing"; block platform_mobile_description_missing; }
  [ "$pc_desc" != "$OLD_GENERIC" ] || { ERROR_CLASS="platform_pc_old_generic_description"; block platform_pc_old_generic_description; }
  [ "$mobile_desc" != "$OLD_GENERIC" ] || { ERROR_CLASS="platform_mobile_old_generic_description"; block platform_mobile_old_generic_description; }
  printf '%s\n' "$pc_desc" >> "$TMP/pc.desc"
  printf '%s\n' "$mobile_desc" >> "$TMP/mobile.desc"
  if printf '%s' "$pc_desc" | grep -Fq "$ptitle"; then PLATFORM_DESC_WITH_TITLE=$((PLATFORM_DESC_WITH_TITLE+1)); fi
  if printf '%s' "$mobile_desc" | grep -Fq "$ptitle"; then MOBILE_DESC_WITH_TITLE=$((MOBILE_DESC_WITH_TITLE+1)); fi
done < "$TMP/platform.tsv"

PC_UNIQUE_DESCRIPTIONS=$(sort -u "$TMP/pc.desc" | wc -l | tr -d ' ')
MOBILE_UNIQUE_DESCRIPTIONS=$(sort -u "$TMP/mobile.desc" | wc -l | tr -d ' ')
[ "$PC_UNIQUE_DESCRIPTIONS" -eq "$PLATFORM_SAMPLE_COUNT" ] || { ERROR_CLASS="pc_descriptions_not_unique"; block pc_descriptions_not_unique; }
[ "$MOBILE_UNIQUE_DESCRIPTIONS" -eq "$PLATFORM_SAMPLE_COUNT" ] || { ERROR_CLASS="mobile_descriptions_not_unique"; block mobile_descriptions_not_unique; }
[ "$PLATFORM_DESC_WITH_TITLE" -eq "$PLATFORM_SAMPLE_COUNT" ] || { ERROR_CLASS="pc_description_missing_platform_title"; block pc_description_missing_platform_title; }
[ "$MOBILE_DESC_WITH_TITLE" -eq "$PLATFORM_SAMPLE_COUNT" ] || { ERROR_CLASS="mobile_description_missing_platform_title"; block mobile_description_missing_platform_title; }

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
echo "DYNAMIC_META_DESCRIPTION_V1=PASS samples=$PLATFORM_SAMPLE_COUNT"
