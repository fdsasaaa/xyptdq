#!/bin/bash
# Server Bridge wrapper for the fetch-only publisher V6 finalizer.
# Raw finalizer output remains root-local; only whitelisted summary fields are
# written to the sanitized agent result payload.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
REQUIRED_COMMIT="${XYPTDQ_AGENT_REQUIRED_COMMIT:-}"

[ -n "$RESULT_FILE" ] || { echo "missing agent result file" >&2; exit 2; }
[ -d "$REPO/.git" ] || { echo "production repo missing" >&2; exit 3; }

write_blocked() {
  local rc="$1"
  python3 - "$RESULT_FILE" "$rc" <<'PY'
import json, sys
out, rc = sys.argv[1:]
with open(out, 'w', encoding='utf-8') as fh:
    json.dump({
        'task': 'finalize_publisher_v6',
        'publisher_finalization': 'BLOCKED',
        'exit_code': int(rc),
        'secrets_disclosed': False,
    }, fh, ensure_ascii=False, indent=2, sort_keys=True)
    fh.write('\n')
PY
}

cd "$REPO"
if [ -n "$(git status --porcelain)" ]; then
  write_blocked 20
  echo "production repo dirty" >&2
  exit 20
fi

git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null
if [ -n "$REQUIRED_COMMIT" ]; then
  git merge-base --is-ancestor "$REQUIRED_COMMIT" origin/main || {
    write_blocked 21
    echo "required agent commit not in origin/main" >&2
    exit 21
  }
fi

FINALIZER="$REPO/scripts/ops/chatgpt_finalize_publisher_v6.sh"
[ -f "$FINALIZER" ] || { write_blocked 22; exit 22; }
bash -n "$FINALIZER" || { write_blocked 23; exit 23; }

TMP_OUT=$(mktemp /tmp/xyptdq-finalizer-v6-agent.XXXXXX.log)
cleanup() { rm -f "$TMP_OUT"; }
trap cleanup EXIT

set +e
bash "$FINALIZER" >"$TMP_OUT" 2>&1
RC=$?
set -e

if [ "$RC" -ne 0 ]; then
  write_blocked "$RC"
  echo "publisher v6 finalizer blocked rc=$RC" >&2
  exit "$RC"
fi

python3 - "$TMP_OUT" "$RESULT_FILE" <<'PY'
import json, re, sys
src, out = sys.argv[1:]
allowed = {
    'Main source commit': 'main_source_commit',
    'Local recovery commit': 'local_recovery_commit',
    'Server deployed ref': 'server_deployed_ref',
    'Framework source integrity': 'framework_source_integrity',
    'Framework production integrity': 'framework_production_integrity',
    'Backup verification': 'backup_verification',
    'DB credential rotation': 'db_credential_rotation',
    'Exact-ref deploy': 'exact_ref_deploy',
    'Production robots=none': 'production_robots_none',
    'Rendered robots=none': 'rendered_robots_none',
    'Category probe': 'category_probe',
    'Category source': 'category_source',
    'Live target preflight': 'live_target_preflight',
    'Smoke command exit': 'smoke_command_exit',
    'Smoke publish': 'smoke_publish',
    'Smoke cms_id': 'smoke_cms_id',
    'Second publish idempotent': 'second_publish_idempotent',
    'SQL error present': 'sql_error_present',
    'Article HTTP': 'article_http',
    'Sitemap contains article': 'sitemap_contains_article',
    'Registry idempotency': 'registry_idempotency',
    'Secrets disclosed': 'secrets_disclosed_summary',
    'Blocking item': 'blocking_item',
}
values = {}
with open(src, 'r', encoding='utf-8', errors='replace') as fh:
    for raw in fh:
        line = raw.rstrip('\r\n')
        if ': ' not in line:
            continue
        key, value = line.split(': ', 1)
        if key in allowed:
            value = re.sub(r'[^\x20-\x7E\u4e00-\u9fff_-]', '', value)[:300]
            values[allowed[key]] = value
required = {
    'framework_source_integrity': 'PASS',
    'framework_production_integrity': 'PASS',
    'backup_verification': 'PASS',
    'exact_ref_deploy': 'PASS',
    'production_robots_none': 'ABSENT',
    'rendered_robots_none': 'ABSENT',
    'category_probe': 'PASS',
    'live_target_preflight': 'PASS',
    'smoke_command_exit': '0',
    'smoke_publish': 'PASS',
    'second_publish_idempotent': 'YES',
    'sql_error_present': 'NO',
    'article_http': '200',
    'sitemap_contains_article': 'YES',
    'registry_idempotency': 'PASS',
    'blocking_item': 'NONE',
}
for key, expected in required.items():
    if values.get(key) != expected:
        raise SystemExit(f'missing/invalid finalizer summary: {key}')
payload = {
    'task': 'finalize_publisher_v6',
    'publisher_finalization': 'PASS',
    'summary': values,
    'secrets_disclosed': False,
}
with open(out, 'w', encoding='utf-8') as fh:
    json.dump(payload, fh, ensure_ascii=False, indent=2, sort_keys=True)
    fh.write('\n')
PY

echo "PUBLISHER_FINALIZATION_V6_AGENT=PASS"
