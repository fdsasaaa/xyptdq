#!/bin/bash
# Publisher V8 compatibility shim for Server Bridge.
# V7's logic is retained; this shim only ensures local recovery commits record
# executable bits for shell scripts that deploy.sh invokes directly.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
REQUIRED_COMMIT="${XYPTDQ_AGENT_REQUIRED_COMMIT:-}"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3

write_blocked() {
  local rc="$1"
  local reason="$2"
  python3 - "$RESULT_FILE" "$rc" "$reason" <<'PY'
import json, re, sys
out, rc, reason = sys.argv[1:]
reason = re.sub(r'[^A-Za-z0-9_.:-]', '', reason)[:120]
with open(out, 'w', encoding='utf-8') as fh:
    json.dump({
        'task': 'publisher_finalize_v8',
        'publisher_finalization': 'BLOCKED',
        'exit_code': int(rc),
        'phase': reason,
        'blocking_item': reason,
        'secrets_disclosed': False,
    }, fh, ensure_ascii=False, indent=2, sort_keys=True)
    fh.write('\n')
PY
}

cd "$REPO"
if [ -n "$(git status --porcelain)" ]; then
  write_blocked 20 "repo_dirty"
  exit 20
fi

git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null
if [ -n "$REQUIRED_COMMIT" ]; then
  git merge-base --is-ancestor "$REQUIRED_COMMIT" origin/main || {
    write_blocked 21 "required_commit"
    exit 21
  }
fi

V7="$REPO/scripts/ops/agent_tasks/publisher_finalize_v7.sh"
[ -f "$V7" ] || { write_blocked 22 "v7_missing"; exit 22; }
bash -n "$V7" || { write_blocked 23 "v7_syntax"; exit 23; }

BASH_ENV_FILE=$(mktemp /tmp/xyptdq-v8-bashenv.XXXXXX)
cleanup() { rm -f "$BASH_ENV_FILE"; }
trap cleanup EXIT

cat > "$BASH_ENV_FILE" <<'EOF'
git() {
  if [ "${1:-}" = "commit" ]; then
    chmod +x scripts/deploy.sh scripts/backup.sh scripts/health-check.sh
    /usr/bin/git update-index --chmod=+x scripts/deploy.sh scripts/backup.sh scripts/health-check.sh
  fi
  /usr/bin/git "$@"
}
EOF
chmod 600 "$BASH_ENV_FILE"

BASH_ENV="$BASH_ENV_FILE" bash "$V7"
