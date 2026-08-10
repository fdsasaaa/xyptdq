#!/bin/bash
# Install the deterministic publisher scheduler after smoke verification.
set -euo pipefail

REPO_DIR="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
CRON_FILE="/etc/cron.d/xyptdq-publisher"
CAPABILITIES="$REPO_DIR/config/publisher_capabilities.json"
RUNNER="$REPO_DIR/scripts/content/run_scheduled_publish.sh"

fail() {
    echo "[publisher-cron] ERROR: $*" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || fail "must run as root"
[ -f "$CAPABILITIES" ] || fail "capability manifest missing"
[ -f "$RUNNER" ] || fail "publisher runner missing"

VERIFIED=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (($x["verified"]??false)===true && ($x["durable_idempotency_verified"]??false)===true) ? "yes" : "no";' "$CAPABILITIES")
[ "$VERIFIED" = "yes" ] || fail "publisher is still write-locked; smoke verification must be merged first"

cat > "$CRON_FILE.tmp" <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Run hourly. publish_at inside each versioned article controls the actual release time.
# The publisher is idempotent and publishes at most XYPTDQ_PUBLISH_LIMIT (default 2) due items per run.
7 * * * * root XYPTDQ_REPO_DIR=/opt/xyptdq-repo /opt/xyptdq-repo/scripts/content/run_scheduled_publish.sh >/dev/null 2>&1
EOF
install -o root -g root -m 0644 "$CRON_FILE.tmp" "$CRON_FILE"
rm -f "$CRON_FILE.tmp"

echo "[publisher-cron] INSTALLED $CRON_FILE"
