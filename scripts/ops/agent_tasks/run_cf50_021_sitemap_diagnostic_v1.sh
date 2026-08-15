#!/bin/bash
set -euo pipefail
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
exec /bin/bash "$REPO/scripts/ops/agent_tasks/diagnose_cf50_021_sitemap_url_v1.sh"
