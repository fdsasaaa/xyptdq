#!/bin/bash
# Guarded production deployment for homepage tips-at-bottom + mobile single-column presentation.
# Reuses the previously reviewed V2 deploy verifier and applies only exact, asserted source transforms.
set -euo pipefail
umask 077

REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
BASE_COMMIT="c5879cd70db28db92411d3411250e10e4c564e8b"
BASE_PATH="scripts/ops/agent_tasks/deploy_home_layout_v2.sh"
BASE_SHA256="f4ab0f337a838f8d40b19dad311894e0ce5a1929c8a320b5feaba6aaa72a8254"
NEW_TARGET="88475d02e25e4dfe3eb7ef11cab27fc22a56816d"
TMP_BASE="$(mktemp /tmp/xyptdq-home-bottom-base.XXXXXX.sh)"
TMP_SCRIPT="$(mktemp /tmp/xyptdq-home-bottom.XXXXXX.sh)"
trap 'rm -f "$TMP_BASE" "$TMP_SCRIPT"' EXIT

[ -d "$REPO/.git" ] || exit 3
cd "$REPO"
git cat-file -e "$BASE_COMMIT^{commit}"
git show "$BASE_COMMIT:$BASE_PATH" > "$TMP_BASE"
ACTUAL="$(sha256sum "$TMP_BASE" | awk '{print $1}')"
[ "$ACTUAL" = "$BASE_SHA256" ] || { echo "HOME_BOTTOM_BASE_HASH_MISMATCH" >&2; exit 41; }

python3 - "$TMP_BASE" "$TMP_SCRIPT" "$NEW_TARGET" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1]).read_text(encoding='utf-8')
out = sys.argv[2]
target = sys.argv[3]

simple = [
    ('TARGET_SHA="e8019c3e5eb573b138307c31ac3696a4c0dda449"', f'TARGET_SHA="{target}"', 'target sha'),
    ('module module=news catid=7', 'module module=news catid=3', 'tips module'),
    ('"$CANONICAL/index.php?c=category&id=7"', '"$CANONICAL/index.php?c=category&dir=tzjq"', 'category probe'),
    ('"category7_http"', '"category3_http"', 'result category key'),
    ('"task":"deploy_home_layout_v2"', '"task":"deploy_home_tips_bottom_mobile_single_v1"', 'task label'),
    ('TIPS_BEFORE_PLATFORM', 'TIPS_AFTER_PLATFORM', 'tips order variable'),
    ('"tips_before_platform":tips_before', '"tips_after_platform":tips_before', 'tips order result key'),
    ("'pc_tips_before_platform'", "'pc_tips_after_platform'", 'source order check label'),
    ('rendered_tips_not_before_platform', 'rendered_tips_not_after_platform', 'render order error label'),
    ('HOME_LAYOUT_V2=PASS', 'HOME_TIPS_BOTTOM_MOBILE_SINGLE_V1=PASS', 'success marker'),
]
for old,new,label in simple:
    count = src.count(old)
    if count < 1:
        raise SystemExit(f'missing expected {label}: {old}')
    src = src.replace(old,new)

old_source_order = """ 'pc_tips_after_platform': pc.find('class=\"container seo-article-section\"')>=0 and pc.find('class=\"container seo-article-section\"')<pc.find('class=\"container platform-section\"'),
 'pc_footer': 'class=\"footer-info\"' in pc,"""
new_source_order = """ 'pc_tips_after_platform': pc.find('class=\"container seo-article-section\"')>=0 and pc.find('class=\"container platform-section\"')>=0 and pc.find('class=\"footer-info\"')>=0 and pc.find('class=\"container platform-section\"')<pc.find('class=\"container seo-article-section\"')<pc.find('class=\"footer-info\"'),
 'pc_mobile_single_column': 'column-count:1!important' in pc and 'text-overflow:ellipsis' in pc,
 'mobile_tips_after_main': mobile.find('class=\"page-content mobile-tips-section\"')>=0 and mobile.find('class=\"search-page search-content-1\"')>=0 and mobile.find('class=\"page-content mobile-tips-section\"')>mobile.find('class=\"search-page search-content-1\"'),
 'mobile_single_column': 'column-count:1!important' in mobile and 'columns:1!important' in mobile and 'text-overflow:ellipsis' in mobile,
 'pc_footer': 'class=\"footer-info\"' in pc,"""
if src.count(old_source_order) != 1:
    raise SystemExit('expected exactly one source order block')
src = src.replace(old_source_order, new_source_order, 1)

old_render_order = """tips_start=s.find('class=\"container seo-article-section\"')
platform_start=s.find('class=\"container platform-section\"')
order_ok=tips_start>=0 and platform_start>=0 and tips_start<platform_start"""
new_render_order = """tips_start=s.find('class=\"container seo-article-section\"')
platform_start=s.find('class=\"container platform-section\"')
footer_start=s.find('class=\"footer-info\"')
order_ok=tips_start>=0 and platform_start>=0 and footer_start>=0 and platform_start<tips_start<footer_start"""
if src.count(old_render_order) != 1:
    raise SystemExit('expected exactly one rendered order block')
src = src.replace(old_render_order, new_render_order, 1)

old_mobile_phase = 'PHASE="mobile_render_verify"\n'
new_mobile_phase = '''PHASE="mobile_layout_verify"
grep -Fq 'column-count:1!important' "$TMP/mobile.html" || { ERROR_CLASS="rendered_mobile_not_single_column"; block rendered_mobile_not_single_column; }
grep -Fq 'text-overflow:ellipsis' "$TMP/mobile.html" || { ERROR_CLASS="rendered_mobile_ellipsis_missing"; block rendered_mobile_ellipsis_missing; }

PHASE="mobile_render_verify"
'''
if src.count(old_mobile_phase) != 1:
    raise SystemExit('expected exactly one mobile render phase')
src = src.replace(old_mobile_phase, new_mobile_phase, 1)

Path(out).write_text(src, encoding='utf-8')
PY

chmod 700 "$TMP_SCRIPT"
exec bash "$TMP_SCRIPT"
