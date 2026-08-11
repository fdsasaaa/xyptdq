#!/bin/bash
# Exact V6 verifier hotfix for the reviewed V4 migration.
# Keeps V4 migration/rollback semantics, fixes the proven SQL placeholder typo,
# and makes expected-zero grep counts pipefail-safe so correct zero matches do
# not trigger the ERR trap before the explicit verification gates run.
set -euo pipefail
umask 077

REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
BASE_COMMIT="7e467454d944f35840d05c1f7e472c226fe43359"
BASE_PATH="scripts/ops/agent_tasks/consolidate_seo_articles_into_tzjq_v4.sh"
BASE_SHA256="c44d2f9cb4f90734e9e337a20cb1326b01bb6a5426e708c3100eee5aff2a973d"
TMP_BASE="$(mktemp /tmp/xyptdq-consolidate-v6-base.XXXXXX.sh)"
TMP_SCRIPT="$(mktemp /tmp/xyptdq-consolidate-v6.XXXXXX.sh)"
trap 'rm -f "$TMP_BASE" "$TMP_SCRIPT"' EXIT

[ -d "$REPO/.git" ] || exit 3
cd "$REPO"
git cat-file -e "$BASE_COMMIT^{commit}"
git show "$BASE_COMMIT:$BASE_PATH" > "$TMP_BASE"
ACTUAL="$(sha256sum "$TMP_BASE" | awk '{print $1}')"
[ "$ACTUAL" = "$BASE_SHA256" ] || { echo "V6_BASE_HASH_MISMATCH" >&2; exit 41; }

python3 - "$TMP_BASE" "$TMP_SCRIPT" <<'PY'
from pathlib import Path
import sys
src = Path(sys.argv[1]).read_text(encoding='utf-8')

replacements = [
    (
        'VALUES (?,0,0,0,0,0,?,?,?,?,?)',
        'VALUES (?,0,0,0,0,0,?,?,?,?)',
        'news_hits placeholder list',
    ),
    (
        "NAV_PC=$(grep -o 'seo-articles' \"$TMP/home.pc\" | wc -l | tr -d ' ')",
        "NAV_PC=$( (grep -o 'seo-articles' \"$TMP/home.pc\" || true) | wc -l | tr -d ' ')",
        'PC zero-count verifier',
    ),
    (
        "NAV_MOBILE=$(grep -o 'seo-articles' \"$TMP/home.mobile\" | wc -l | tr -d ' ')",
        "NAV_MOBILE=$( (grep -o 'seo-articles' \"$TMP/home.mobile\" || true) | wc -l | tr -d ' ')",
        'mobile zero-count verifier',
    ),
    (
        "OLD_SITEMAP=$(grep -o 'c=category&amp;dir=seo-articles' \"$WEBROOT/sitemap.xml\" | wc -l | tr -d ' ')",
        "OLD_SITEMAP=$( (grep -o 'c=category&amp;dir=seo-articles' \"$WEBROOT/sitemap.xml\" || true) | wc -l | tr -d ' ')",
        'old sitemap zero-count verifier',
    ),
    (
        "TZ_SITEMAP=$(grep -o 'c=category&amp;dir=tzjq' \"$WEBROOT/sitemap.xml\" | wc -l | tr -d ' ')",
        "TZ_SITEMAP=$( (grep -o 'c=category&amp;dir=tzjq' \"$WEBROOT/sitemap.xml\" || true) | wc -l | tr -d ' ')",
        'tzjq sitemap count verifier',
    ),
]

for old, new, label in replacements:
    if src.count(old) != 1:
        raise SystemExit(f'expected exactly one {label}; found {src.count(old)}')
    src = src.replace(old, new, 1)

old_task = "'task':'consolidate_seo_articles_into_tzjq_v4'"
if src.count(old_task) != 1:
    raise SystemExit('expected exactly one V4 task label')
src = src.replace(old_task, "'task':'consolidate_seo_articles_into_tzjq_v6'", 1)
src = src.replace('[seo-consolidate-v4]', '[seo-consolidate-v6]')
src = src.replace('SEO_ARTICLES_TO_TZJQ_V4=PASS', 'SEO_ARTICLES_TO_TZJQ_V6=PASS')
Path(sys.argv[2]).write_text(src, encoding='utf-8')
PY

chmod 700 "$TMP_SCRIPT"
set +e
bash "$TMP_SCRIPT"
RC=$?
set -e
exit "$RC"
