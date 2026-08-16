#!/bin/bash
set -euo pipefail
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
git -C "$REPO" fetch --prune origin main >/dev/null 2>&1
git -C "$REPO" checkout -q main
git -C "$REPO" reset --hard origin/main >/dev/null
exec /bin/bash "$REPO/scripts/ops/agent_tasks/activate_incremental_intake_v1.sh"
