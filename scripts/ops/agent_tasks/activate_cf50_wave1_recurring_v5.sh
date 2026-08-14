#!/bin/bash
# Activation v5: bind the isolated runtime environment expected by the tracked cron installer,
# then execute the already CI-validated v4 fail-closed activation gates unchanged.
set -euo pipefail
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
export XYPTDQ_REPO_DIR="$REPO"
export XYPTDQ_PUBLISH_SOURCE="/var/lib/xyptdq-content/CF50-20260813-wave1/scheduled"
export XYPTDQ_PUBLISH_STATE="/var/lib/xyptdq-publisher/CF50-20260813-wave1/state.json"
export XYPTDQ_PUBLISH_LOCK="/var/lib/xyptdq-publisher/CF50-20260813-wave1/publisher.lock"
exec bash "$REPO/scripts/ops/agent_tasks/activate_cf50_wave1_recurring_v4.sh"
