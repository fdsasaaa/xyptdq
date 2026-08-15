#!/bin/bash
# Repair only the production Sitemap after proving the Publisher-managed canonical URL fix in a temporary file.
# Does not publish content, change Publisher cron, or re-enable publication policy.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
POLICY="$REPO/config/content_publication_policy.json"
GENERATOR="$REPO/scripts/seo/generate_sitemap.php"
VERIFY="$REPO/scripts/seo/verify_publication_seo.php"
STATE="/var/lib/xyptdq-publisher/CF50-20260813-wave1/state.json"
BASE="/var/lib/xyptdq-publisher/CF50-20260813-wave1"
SCHEDULED="$BASE/../CF50-20260813-wave1/../CF50-20260813-wave1"
PROD_SITEMAP="$WEBROOT/sitemap.xml"
EXPECTED_URL="https://www.laocaimi.org/index.php?c=show&id=94"
EXPECTED_KEY="lcm-creator-cf50-20260813-021"
EXPECTED_ID="LCM-CREATOR-cf50-20260813-021"
[ -n "$RESULT_FILE" ] || exit 2

TMP=$(mktemp -d /tmp/xyptdq-021-sitemap-repair.XXXXXX)
BACKUP="$TMP/sitemap.before"
ROLLBACK=false
MUTATED=false
SUCCESS=false
PHASE="preflight"
DETAIL=""
TEMP_HAS_94=false
PROD_HAS_94=false
LIVE_HAS_94=false
LIVE_CANONICAL=""
VERIFY_RC=99

write_result() {
  python3 - "$RESULT_FILE" "$PHASE" "$DETAIL" "$ROLLBACK" "$MUTATED" "$TEMP_HAS_94" "$PROD_HAS_94" "$LIVE_HAS_94" "$LIVE_CANONICAL" "$VERIFY_RC" <<'PY'
import json,sys
(out,phase,detail,rollback,mutated,temp94,prod94,live94,canonical,vrc)=sys.argv[1:]
p={
 'task':'repair_cf50_021_sitemap_v1','status':'PASS' if phase=='complete' else 'FAIL',
 'phase':phase,'detail':detail,'cms_id':94,'article_id':'LCM-CREATOR-cf50-20260813-021',
 'expected_url':'https://www.laocaimi.org/index.php?c=show&id=94',
 'temporary_sitemap_has_94':temp94=='true','production_sitemap_has_94':prod94=='true',
 'live_sitemap_has_94':live94=='true','live_page_canonical':canonical,
 'live_seo_verify_exit_code':int(vrc),'production_sitemap_mutated':mutated=='true',
 'rollback_performed':rollback=='true','cms_write_attempted':False,'cron_mutated':False,
 'publication_policy_mutated':False,'queue_consumed':False,'wave1_resumed':False,
 'durable_fix':'Publisher-registry managed CMS IDs emit canonical show-ID URLs in Sitemap'
}
with open(out,'w',encoding='utf-8') as f:
 json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}

fail() {
  PHASE="$1"; DETAIL="$2"
  if [ "$MUTATED" = true ] && [ -s "$BACKUP" ]; then
    cp "$BACKUP" "$PROD_SITEMAP" && chmod 0644 "$PROD_SITEMAP" && ROLLBACK=true || true
  fi
  write_result
  echo "CF50_021_SITEMAP_REPAIR=FAIL phase=$PHASE" >&2
  exit 20
}
trap 'rm -rf "$TMP"' EXIT

[ -d "$REPO/.git" ] || fail repo_sync "canonical repo missing"
[ -z "$(git -C "$REPO" status --porcelain)" ] || fail repo_sync "canonical repo dirty"
git -C "$REPO" fetch --prune origin main >/dev/null 2>&1 || fail repo_sync "fetch main failed"
git -C "$REPO" checkout -q main || fail repo_sync "checkout main failed"
git -C "$REPO" reset --hard origin/main >/dev/null || fail repo_sync "reset main failed"
[ -s "$POLICY" ] && [ -s "$GENERATOR" ] && [ -s "$VERIFY" ] || fail preflight "required website files missing"
[ -s "$STATE" ] || fail preflight "Wave1 state missing"

grep -Fq "xyptdq_publish_registry" "$GENERATOR" || fail preflight "managed Publisher Sitemap fix is not in main"
POLICY_OK=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (($x["publishing_enabled"]??true)===false && strpos((string)($x["mode"]??""),"021")!==false)?"yes":"no";' "$POLICY")
[ "$POLICY_OK" = yes ] || fail preflight "Wave1 is not fail-closed on the 021 gate"
STATE_OK=$(python3 - "$STATE" "$EXPECTED_KEY" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8')); e=(x.get('articles') or {}).get(sys.argv[2],{})
print('yes' if e.get('status')=='published' and int(e.get('cms_id') or 0)==94 else 'no')
PY
)
[ "$STATE_OK" = yes ] || fail preflight "021 is not the published CMS 94 state entry"
RECEIPT=$(find "$BASE/receipts" -maxdepth 1 -type f -name "${EXPECTED_KEY}.94.json" -print -quit 2>/dev/null || true)
[ -s "$RECEIPT" ] || fail preflight "021 publication receipt missing"

PHASE="temporary_generation"
XYPTDQ_WEBROOT="$WEBROOT" XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" XYPTDQ_SITEMAP="$TMP/sitemap.test.xml" php "$GENERATOR" >"$TMP/generate.out" 2>"$TMP/generate.err" || fail temporary_generation "temporary Sitemap generation failed"
[ -s "$TMP/sitemap.test.xml" ] || fail temporary_generation "temporary Sitemap missing"
grep -Fq "$EXPECTED_URL" "$TMP/sitemap.test.xml" || fail temporary_generation "temporary Sitemap still omits CMS 94 canonical URL"
TEMP_HAS_94=true

cp "$PROD_SITEMAP" "$BACKUP" || fail deploy "could not back up current production Sitemap"
PHASE="deploy"
XYPTDQ_WEBROOT="$WEBROOT" XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" XYPTDQ_SITEMAP="$PROD_SITEMAP" php "$GENERATOR" >"$TMP/deploy.out" 2>"$TMP/deploy.err" || fail deploy "production Sitemap generation failed"
MUTATED=true
grep -Fq "$EXPECTED_URL" "$PROD_SITEMAP" || fail deploy "production Sitemap omits CMS 94 after generation"
PROD_HAS_94=true

PHASE="live_verify"
curl -skL --max-time 25 -o "$TMP/live-sitemap.xml" "https://www.laocaimi.org/sitemap.xml" || fail live_verify "live Sitemap fetch failed"
grep -Fq "$EXPECTED_URL" "$TMP/live-sitemap.xml" || fail live_verify "live Sitemap omits CMS 94"
LIVE_HAS_94=true
curl -skL --max-time 25 -o "$TMP/page.html" "$EXPECTED_URL" || fail live_verify "CMS 94 page fetch failed"
LIVE_CANONICAL=$(python3 - "$TMP/page.html" <<'PY'
import html,re,sys,pathlib
s=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8',errors='ignore')
for tag in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
 r=re.search(r'''\brel\s*=\s*["']([^"']*)["']''',tag,re.I|re.S)
 if r and 'canonical' in r.group(1).lower().split():
  h=re.search(r'''\bhref\s*=\s*["']([^"']*)["']''',tag,re.I|re.S)
  if h: print(html.unescape(h.group(1).strip())); break
PY
)
[ "$LIVE_CANONICAL" = "$EXPECTED_URL" ] || fail live_verify "CMS 94 canonical mismatch"
set +e
php "$VERIFY" --receipt="$RECEIPT" >"$TMP/verify.out" 2>"$TMP/verify.err"
VERIFY_RC=$?
set -e
[ "$VERIFY_RC" -eq 0 ] || fail live_verify "021 live SEO verification still fails"

PHASE="complete"
DETAIL="CMS 94 canonical URL is present in temporary, production, and live Sitemap; live SEO verification passed; Wave1 remains paused pending repository policy resume"
SUCCESS=true
write_result
echo "CF50_021_SITEMAP_REPAIR=PASS"
