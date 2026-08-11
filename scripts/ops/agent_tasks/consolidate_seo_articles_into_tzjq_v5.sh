#!/bin/bash
# Minimal reviewed hotfix wrapper for V4. It materializes the exact V4 script by
# commit+SHA256, replaces exactly one malformed news_hits VALUES placeholder list,
# relabels the result task as V5, then runs the otherwise unchanged V4 logic.
set -euo pipefail
umask 077

REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
BASE_COMMIT="7e467454d944f35840d05c1f7e472c226fe43359"
BASE_PATH="scripts/ops/agent_tasks/consolidate_seo_articles_into_tzjq_v4.sh"
BASE_SHA256="c44d2f9cb4f90734e9e337a20cb1326b01bb6a5426e708c3100eee5aff2a973d"
TMP_SCRIPT="$(mktemp /tmp/xyptdq-consolidate-v5.XXXXXX.sh)"
trap 'rm -f "$TMP_SCRIPT"' EXIT

[ -d "$REPO/.git" ] || exit 3
cd "$REPO"
git cat-file -e "$BASE_COMMIT^{commit}"
git show "$BASE_COMMIT:$BASE_PATH" > "$TMP_SCRIPT.base"
trap 'rm -f "$TMP_SCRIPT" "$TMP_SCRIPT.base"' EXIT
ACTUAL="$(sha256sum "$TMP_SCRIPT.base" | awk '{print $1}')"
[ "$ACTUAL" = "$BASE_SHA256" ] || { echo "V5_BASE_HASH_MISMATCH" >&2; exit 41; }

python3 - "$TMP_SCRIPT.base" "$TMP_SCRIPT" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text(encoding='utf-8')
old='VALUES (?,0,0,0,0,0,?,?,?,?,?)'
new='VALUES (?,0,0,0,0,0,?,?,?,?)'
if src.count(old) != 1:
    raise SystemExit('expected exactly one malformed VALUES clause')
src=src.replace(old,new,1)
old_task="'task':'consolidate_seo_articles_into_tzjq_v4'"
if src.count(old_task) != 1:
    raise SystemExit('expected exactly one V4 task label')
src=src.replace(old_task,"'task':'consolidate_seo_articles_into_tzjq_v5'",1)
src=src.replace('[seo-consolidate-v4]','[seo-consolidate-v5]')
src=src.replace('SEO_ARTICLES_TO_TZJQ_V4=PASS','SEO_ARTICLES_TO_TZJQ_V5=PASS')
Path(sys.argv[2]).write_text(src,encoding='utf-8')
PY
chmod 700 "$TMP_SCRIPT"

set +e
bash "$TMP_SCRIPT"
RC=$?
set -e
exit "$RC"
