#!/bin/bash
# V7 verifier stabilization for the reviewed V4 SEO文章 -> tzjq migration.
# Keeps the proven DB migration and rollback semantics unchanged. Applies:
# 1) the proven news_hits placeholder correction,
# 2) pipefail-safe zero-count verification,
# 3) bounded retry for the strict 301 checks to tolerate short PHP-FPM/OPcache propagation.
set -euo pipefail
umask 077

REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
BASE_COMMIT="7e467454d944f35840d05c1f7e472c226fe43359"
BASE_PATH="scripts/ops/agent_tasks/consolidate_seo_articles_into_tzjq_v4.sh"
BASE_SHA256="c44d2f9cb4f90734e9e337a20cb1326b01bb6a5426e708c3100eee5aff2a973d"
TMP_BASE="$(mktemp /tmp/xyptdq-consolidate-v7-base.XXXXXX.sh)"
TMP_SCRIPT="$(mktemp /tmp/xyptdq-consolidate-v7.XXXXXX.sh)"
trap 'rm -f "$TMP_BASE" "$TMP_SCRIPT"' EXIT

[ -d "$REPO/.git" ] || exit 3
cd "$REPO"
git cat-file -e "$BASE_COMMIT^{commit}"
git show "$BASE_COMMIT:$BASE_PATH" > "$TMP_BASE"
ACTUAL="$(sha256sum "$TMP_BASE" | awk '{print $1}')"
[ "$ACTUAL" = "$BASE_SHA256" ] || { echo "V7_BASE_HASH_MISMATCH" >&2; exit 41; }

python3 - "$TMP_BASE" "$TMP_SCRIPT" <<'PY'
from pathlib import Path
import sys
src = Path(sys.argv[1]).read_text(encoding='utf-8')

simple = [
    ('VALUES (?,0,0,0,0,0,?,?,?,?,?)', 'VALUES (?,0,0,0,0,0,?,?,?,?)', 'news_hits placeholder list'),
    ("NAV_PC=$(grep -o 'seo-articles' \"$TMP/home.pc\" | wc -l | tr -d ' ')", "NAV_PC=$( (grep -o 'seo-articles' \"$TMP/home.pc\" || true) | wc -l | tr -d ' ')", 'PC zero-count verifier'),
    ("NAV_MOBILE=$(grep -o 'seo-articles' \"$TMP/home.mobile\" | wc -l | tr -d ' ')", "NAV_MOBILE=$( (grep -o 'seo-articles' \"$TMP/home.mobile\" || true) | wc -l | tr -d ' ')", 'mobile zero-count verifier'),
    ("OLD_SITEMAP=$(grep -o 'c=category&amp;dir=seo-articles' \"$WEBROOT/sitemap.xml\" | wc -l | tr -d ' ')", "OLD_SITEMAP=$( (grep -o 'c=category&amp;dir=seo-articles' \"$WEBROOT/sitemap.xml\" || true) | wc -l | tr -d ' ')", 'old sitemap zero-count verifier'),
    ("TZ_SITEMAP=$(grep -o 'c=category&amp;dir=tzjq' \"$WEBROOT/sitemap.xml\" | wc -l | tr -d ' ')", "TZ_SITEMAP=$( (grep -o 'c=category&amp;dir=tzjq' \"$WEBROOT/sitemap.xml\" || true) | wc -l | tr -d ' ')", 'tzjq sitemap count verifier'),
]
for old, new, label in simple:
    count = src.count(old)
    if count != 1:
        raise SystemExit(f'expected exactly one {label}; found {count}')
    src = src.replace(old, new, 1)

old_dir = r'''code=$(curl -sk --max-time 20 -o /dev/null -D "$TMP/old-dir.headers" -w '%{http_code}' "$CANONICAL/index.php?c=category&dir=seo-articles")
loc=$(awk 'BEGIN{IGNORECASE=1}/^Location:/{sub(/\r$/,"",$0);sub(/^[^:]*:[[:space:]]*/,"",$0);print;exit}' "$TMP/old-dir.headers")
if [ "$code" = "301" ] && [ "$loc" = "$CANONICAL/index.php?c=category&dir=tzjq" ]; then REDIR_DIR="PASS"; else ERROR_CLASS="redirect_failed"; block old_dir_redirect_failed; fi'''
new_dir = r'''REDIR_DIR="NO"
for attempt in 1 2 3 4 5; do
  code=$(curl -sk --max-time 20 -o /dev/null -D "$TMP/old-dir.headers" -w '%{http_code}' "$CANONICAL/index.php?c=category&dir=seo-articles")
  loc=$(awk 'BEGIN{IGNORECASE=1}/^Location:/{sub(/\r$/,"",$0);sub(/^[^:]*:[[:space:]]*/,"",$0);print;exit}' "$TMP/old-dir.headers")
  if [ "$code" = "301" ] && [ "$loc" = "$CANONICAL/index.php?c=category&dir=tzjq" ]; then REDIR_DIR="PASS"; break; fi
  sleep 2
done
[ "$REDIR_DIR" = "PASS" ] || { ERROR_CLASS="redirect_failed"; block old_dir_redirect_failed; }'''

old_id = r'''code=$(curl -sk --max-time 20 -o /dev/null -D "$TMP/old-id.headers" -w '%{http_code}' "$CANONICAL/index.php?c=category&id=7")
loc=$(awk 'BEGIN{IGNORECASE=1}/^Location:/{sub(/\r$/,"",$0);sub(/^[^:]*:[[:space:]]*/,"",$0);print;exit}' "$TMP/old-id.headers")
if [ "$code" = "301" ] && [ "$loc" = "$CANONICAL/index.php?c=category&dir=tzjq" ]; then REDIR_ID="PASS"; else ERROR_CLASS="redirect_failed"; block old_id_redirect_failed; fi'''
new_id = r'''REDIR_ID="NO"
for attempt in 1 2 3 4 5; do
  code=$(curl -sk --max-time 20 -o /dev/null -D "$TMP/old-id.headers" -w '%{http_code}' "$CANONICAL/index.php?c=category&id=7")
  loc=$(awk 'BEGIN{IGNORECASE=1}/^Location:/{sub(/\r$/,"",$0);sub(/^[^:]*:[[:space:]]*/,"",$0);print;exit}' "$TMP/old-id.headers")
  if [ "$code" = "301" ] && [ "$loc" = "$CANONICAL/index.php?c=category&dir=tzjq" ]; then REDIR_ID="PASS"; break; fi
  sleep 2
done
[ "$REDIR_ID" = "PASS" ] || { ERROR_CLASS="redirect_failed"; block old_id_redirect_failed; }'''

for old, new, label in [(old_dir, new_dir, 'old-dir 301 verifier'), (old_id, new_id, 'old-id 301 verifier')]:
    count = src.count(old)
    if count != 1:
        raise SystemExit(f'expected exactly one {label}; found {count}')
    src = src.replace(old, new, 1)

old_task = "'task':'consolidate_seo_articles_into_tzjq_v4'"
if src.count(old_task) != 1:
    raise SystemExit('expected exactly one V4 task label')
src = src.replace(old_task, "'task':'consolidate_seo_articles_into_tzjq_v7'", 1)
src = src.replace('[seo-consolidate-v4]', '[seo-consolidate-v7]')
src = src.replace('SEO_ARTICLES_TO_TZJQ_V4=PASS', 'SEO_ARTICLES_TO_TZJQ_V7=PASS')
Path(sys.argv[2]).write_text(src, encoding='utf-8')
PY

chmod 700 "$TMP_SCRIPT"
set +e
bash "$TMP_SCRIPT"
RC=$?
set -e
exit "$RC"
