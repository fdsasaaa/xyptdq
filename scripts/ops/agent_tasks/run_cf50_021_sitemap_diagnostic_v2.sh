#!/bin/bash
set -euo pipefail
exec /bin/bash "${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}/scripts/ops/agent_tasks/diagnose_cf50_021_sitemap_url_v2.sh"
