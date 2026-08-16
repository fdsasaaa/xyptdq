#!/bin/bash
set -euo pipefail
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
git -C "$REPO" fetch --prune origin main >/dev/null 2>&1
git -C "$REPO" checkout -q main
git -C "$REPO" reset --hard origin/main >/dev/null
exec /bin/bash "$REPO/scripts/ops/agent_tasks/audit_idle_intake_after_zero_fix_v1.sh"
