#!/bin/bash
set -euo pipefail
exec /bin/bash "${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}/scripts/ops/agent_tasks/probe_article_repo_transport_v1.sh"
