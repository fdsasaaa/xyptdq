#!/bin/bash
# Read-only healthcheck task for the Server Bridge.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
CANONICAL="https://www.laocaimi.org"

[ -n "$RESULT_FILE" ] || { echo "missing XYPTDQ_AGENT_RESULT_FILE" >&2; exit 2; }
[ -d "$REPO/.git" ] || { echo "production repo missing" >&2; exit 3; }

HOME_HTTP=$(curl -sk --max-time 20 -o /dev/null -w '%{http_code}' "$CANONICAL/")
ROBOTS_HTTP=$(curl -sk --max-time 20 -o /dev/null -w '%{http_code}' "$CANONICAL/robots.txt")
SITEMAP_HTTP=$(curl -sk --max-time 20 -o /dev/null -w '%{http_code}' "$CANONICAL/sitemap.xml")
[ "$HOME_HTTP" = 200 ] || exit 10
[ "$ROBOTS_HTTP" = 200 ] || exit 11
[ "$SITEMAP_HTTP" = 200 ] || exit 12

REPO_SHA=$(git -C "$REPO" rev-parse HEAD)
MAIN_REMOTE=$(git -C "$REPO" rev-parse origin/main 2>/dev/null || echo N/A)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

python3 - "$RESULT_FILE" "$NOW" "$HOME_HTTP" "$ROBOTS_HTTP" "$SITEMAP_HTTP" "$REPO_SHA" "$MAIN_REMOTE" <<'PY'
import json, sys
out, now, home, robots, sitemap, repo_sha, remote_sha = sys.argv[1:]
payload = {
    "task": "bridge_healthcheck",
    "bridge_healthcheck": "PASS",
    "checked_at": now,
    "home_http": int(home),
    "robots_http": int(robots),
    "sitemap_http": int(sitemap),
    "production_repo_sha": repo_sha,
    "production_origin_main_sha": remote_sha,
    "secrets_disclosed": False,
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, ensure_ascii=False, indent=2, sort_keys=True)
    fh.write("\n")
PY

echo "BRIDGE_HEALTHCHECK=PASS"
