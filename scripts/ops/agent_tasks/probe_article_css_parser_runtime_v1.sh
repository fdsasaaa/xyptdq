#!/bin/bash
# Read-only diagnosis for the production static-CSS managed-block parser runtime.
set -euo pipefail
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CSS_FILE="$WEBROOT/static/default/pc/css/style.bundle.css"
[ -n "$RESULT_FILE" ] || exit 2
[ -f "$CSS_FILE" ] || exit 3
python3 - "$CSS_FILE" "$RESULT_FILE" <<'PY'
import hashlib, inspect, json, pathlib, sys
css_path = pathlib.Path(sys.argv[1])
out_path = pathlib.Path(sys.argv[2])
raw = css_path.read_bytes()
try:
    raw.decode('utf-8', errors='strict')
    utf8_valid = True
except UnicodeDecodeError:
    utf8_valid = False
params = inspect.signature(pathlib.Path.write_text).parameters
payload = {
    'task': 'probe_article_css_parser_runtime_v1',
    'status': 'PASS',
    'python_version': '.'.join(map(str, sys.version_info[:3])),
    'path_write_text_newline_supported': 'newline' in params,
    'css_utf8_strict_valid': utf8_valid,
    'css_sha256': hashlib.sha256(raw).hexdigest(),
    'managed_start_count': raw.count(b'/* XYPTDQ_ARTICLE_READING_START */'),
    'managed_end_count': raw.count(b'/* XYPTDQ_ARTICLE_READING_END */'),
    'read_only': True,
    'database_changed': False,
    'templates_mutated': False,
    'publisher_queue_consumed': False,
}
out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + '\n', encoding='utf-8')
PY
