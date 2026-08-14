#!/bin/bash
# Pre-sync wrapper for the static article-reading CSS deployment.
# Fixes v1's stale-production-repo preflight ordering without weakening any v1 gate.
set -euo pipefail
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
[ "$(id -u)" -eq 0 ] || exit 3
[ -d "$REPO/.git" ] || exit 4
[ -z "$(git -C "$REPO" status --porcelain 2>/dev/null)" ] || exit 11
git -C "$REPO" fetch --quiet origin main || exit 12
git -C "$REPO" checkout -q main || exit 13
git -C "$REPO" reset --hard -q origin/main || exit 14
exec bash "$REPO/scripts/ops/agent_tasks/deploy_article_reading_static_css_v1.sh"
