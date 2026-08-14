#!/bin/bash
# Python 3.8 compatibility wrapper for the already-gated article reading CSS deploy.
# It does not change CSS rules, hashes, Publisher state, article content, or rollback gates.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
[ -n "$RESULT_FILE" ] || exit 2
[ "$(id -u)" -eq 0 ] || exit 3
[ -d "$REPO/.git" ] || exit 4
[ -z "$(git -C "$REPO" status --porcelain 2>/dev/null)" ] || exit 5
git -C "$REPO" fetch --quiet origin main
git -C "$REPO" checkout -q main
git -C "$REPO" reset --hard -q origin/main
BASE="$REPO/scripts/ops/agent_tasks/deploy_article_reading_static_css_v1.sh"
[ -f "$BASE" ] || exit 6
TMP=$(mktemp /tmp/xyptdq-article-css-v3.XXXXXX.sh)
trap 'rm -f "$TMP"' EXIT
python3 - "$BASE" "$TMP" <<'PY'
from pathlib import Path
import sys
src, out = map(Path, sys.argv[1:])
s = src.read_text(encoding='utf-8')
repls = {
    "base.write_text(s,encoding='utf-8',newline='\\n')": "with base.open('w',encoding='utf-8',newline='\\n') as fh: fh.write(s)",
    "out.write_text(s.rstrip()+\"\\n\\n\"+m,encoding='utf-8',newline='\\n')": "with out.open('w',encoding='utf-8',newline='\\n') as fh: fh.write(s.rstrip()+\"\\n\\n\"+m)",
}
for old, new in repls.items():
    if s.count(old) != 1:
        raise SystemExit(7)
    s = s.replace(old, new)
out.write_text(s, encoding='utf-8')
PY
exec bash "$TMP"
