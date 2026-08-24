#!/bin/bash
# V2 production deploy retry after proving the canonical tips category is catid 3 (tzjq), not retired catid 7.
# Reuses the reviewed V2 rollback/verifier script with an exact pinned source transform.
set -euo pipefail
umask 077

REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
BASE_COMMIT="c5879cd70db28db92411d3411250e10e4c564e8b"
BASE_PATH="scripts/ops/agent_tasks/deploy_home_layout_v2.sh"
BASE_SHA256="f4ab0f337a838f8d40b19dad311894e0ce5a1929c8a320b5feaba6aaa72a8254"
NEW_TARGET="4afe3130db86a99876644bcd6fdc43f3117152ee"
TMP_BASE="$(mktemp /tmp/xyptdq-home-v2-catid3-base.XXXXXX.sh)"
TMP_SCRIPT="$(mktemp /tmp/xyptdq-home-v2-catid3.XXXXXX.sh)"
trap 'rm -f "$TMP_BASE" "$TMP_SCRIPT"' EXIT

[ -d "$REPO/.git" ] || exit 3
cd "$REPO"
git cat-file -e "$BASE_COMMIT^{commit}"
git show "$BASE_COMMIT:$BASE_PATH" > "$TMP_BASE"
ACTUAL="$(sha256sum "$TMP_BASE" | awk '{print $1}')"
[ "$ACTUAL" = "$BASE_SHA256" ] || { echo "HOME_V2_BASE_HASH_MISMATCH" >&2; exit 41; }

python3 - "$TMP_BASE" "$TMP_SCRIPT" "$NEW_TARGET" <<'PY'
from pathlib import Path
import sys
src = Path(sys.argv[1]).read_text(encoding='utf-8')
out = sys.argv[2]
target = sys.argv[3]
replacements = [
    ('TARGET_SHA="e8019c3e5eb573b138307c31ac3696a4c0dda449"', f'TARGET_SHA="{target}"', 'target sha'),
    ('module module=news catid=7', 'module module=news catid=3', 'tips module'),
    ('"$CANONICAL/index.php?c=category&id=7"', '"$CANONICAL/index.php?c=category&dir=tzjq"', 'category probe'),
    ('"category7_http"', '"category3_http"', 'result category key'),
    ('"task":"deploy_home_layout_v2"', '"task":"deploy_home_layout_v2_catid3"', 'task label'),
]
for old,new,label in replacements:
    count=src.count(old)
    if count < 1:
        raise SystemExit(f'missing expected {label}: {old}')
    src=src.replace(old,new)
Path(out).write_text(src,encoding='utf-8')
PY

chmod 700 "$TMP_SCRIPT"
exec bash "$TMP_SCRIPT"
