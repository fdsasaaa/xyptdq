#!/bin/bash
set -euo pipefail

REPO_DIR="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
V2="$REPO_DIR/scripts/ops/agent_tasks/publish_cf50_canary_001_v2.sh"
[ -f "$V2" ] || { echo "missing v2 canary script" >&2; exit 4; }

# v2 intentionally runs with pipefail. GNU grep returns 1 when a search has no
# matches, but for the two Publisher-cron count pipelines that means the desired
# count is zero, not an execution failure. Preserve grep output and all real
# errors (rc > 1), while normalizing the no-match case to success.
grep() {
  set +e
  command grep "$@"
  local rc=$?
  set -e
  if [ "$rc" -eq 1 ]; then
    return 0
  fi
  return "$rc"
}

source "$V2"
