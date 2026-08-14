#!/bin/bash
# Install the deterministic publisher scheduler after smoke verification.
set -euo pipefail

REPO_DIR="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
CRON_FILE="/etc/cron.d/xyptdq-publisher"
CAPABILITIES="$REPO_DIR/config/publisher_capabilities.json"
RUNNER="$REPO_DIR/scripts/content/run_scheduled_publish.sh"
POLICY="$REPO_DIR/config/content_publication_policy.json"
SOURCE_QUEUE="${XYPTDQ_PUBLISH_SOURCE:-}"
STATE_PATH="${XYPTDQ_PUBLISH_STATE:-}"
LOCK_PATH="${XYPTDQ_PUBLISH_LOCK:-}"
QUEUE_ROOT="/var/lib/xyptdq-content"
STATE_ROOT="/var/lib/xyptdq-publisher"

fail() {
    echo "[publisher-cron] ERROR: $*" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || fail "must run as root"
[ -f "$CAPABILITIES" ] || fail "capability manifest missing"
[ -f "$RUNNER" ] || fail "publisher runner missing"
[ -f "$POLICY" ] || fail "publication policy missing; fail-closed"

VERIFIED=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (($x["verified"]??false)===true && ($x["durable_idempotency_verified"]??false)===true) ? "yes" : "no";' "$CAPABILITIES")
[ "$VERIFIED" = "yes" ] || fail "publisher is still write-locked; smoke verification must be merged first"

POLICY_ENABLED=$(php -r '
$x=json_decode(file_get_contents($argv[1]),true);
if(!is_array($x) || (int)($x["schema_version"]??0)!==1){exit(2);}
echo (($x["publishing_enabled"]??null)===true)?"yes":"no";
' "$POLICY") || fail "publication policy invalid; fail-closed"
[ "$POLICY_ENABLED" = "yes" ] || fail "scheduled publishing is frozen by content publication policy"

# Cron activation must bind the same isolated runtime source/state/lock paths that
# the runner expects. Never install a naked runner invocation that could fall
# back to repository inventory or a shared publisher state file.
[ -n "$SOURCE_QUEUE" ] || fail "XYPTDQ_PUBLISH_SOURCE is required"
[ -n "$STATE_PATH" ] || fail "XYPTDQ_PUBLISH_STATE is required"
[ -n "$LOCK_PATH" ] || fail "XYPTDQ_PUBLISH_LOCK is required"

case "$SOURCE_QUEUE" in
    /var/lib/xyptdq-content/*) ;;
    *) fail "publish source must be under /var/lib/xyptdq-content" ;;
esac
case "$STATE_PATH" in
    /var/lib/xyptdq-publisher/*) ;;
    *) fail "publisher state must be under /var/lib/xyptdq-publisher" ;;
esac
case "$LOCK_PATH" in
    /var/lib/xyptdq-publisher/*) ;;
    *) fail "publisher lock must be under /var/lib/xyptdq-publisher" ;;
esac
[[ "$STATE_PATH" == *.json ]] || fail "publisher state path must end in .json"
[[ "$LOCK_PATH" == *.lock ]] || fail "publisher lock path must end in .lock"
[ -d "$SOURCE_QUEUE" ] || fail "isolated publish source does not exist"

QUEUE_ROOT_REAL=$(realpath "$QUEUE_ROOT") || fail "isolated queue root missing"
SOURCE_REAL=$(realpath "$SOURCE_QUEUE") || fail "cannot resolve isolated publish source"
case "$SOURCE_REAL/" in
    "$QUEUE_ROOT_REAL"/*) ;;
    *) fail "resolved publish source escaped isolated queue root" ;;
esac

STATE_PARENT=$(dirname "$STATE_PATH")
LOCK_PARENT=$(dirname "$LOCK_PATH")
install -d -o root -g www-data -m 0750 "$STATE_ROOT" "$STATE_PARENT" "$LOCK_PARENT"
STATE_ROOT_REAL=$(realpath "$STATE_ROOT") || fail "publisher state root missing"
STATE_PARENT_REAL=$(realpath "$STATE_PARENT") || fail "cannot resolve publisher state parent"
LOCK_PARENT_REAL=$(realpath "$LOCK_PARENT") || fail "cannot resolve publisher lock parent"
case "$STATE_PARENT_REAL/" in
    "$STATE_ROOT_REAL"/*) ;;
    *) fail "resolved publisher state parent escaped state root" ;;
esac
case "$LOCK_PARENT_REAL/" in
    "$STATE_ROOT_REAL"/*) ;;
    *) fail "resolved publisher lock parent escaped state root" ;;
esac

printf -v REPO_Q '%q' "$REPO_DIR"
printf -v SOURCE_Q '%q' "$SOURCE_REAL"
printf -v STATE_Q '%q' "$STATE_PATH"
printf -v LOCK_Q '%q' "$LOCK_PATH"
printf -v RUNNER_Q '%q' "$RUNNER"

cat > "$CRON_FILE.tmp" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Run hourly. publish_at inside each isolated Scheduled article controls the actual release time.
# The publisher is idempotent and publishes at most XYPTDQ_PUBLISH_LIMIT (default 2) due items per run.
# Invoke the runner through /bin/bash so cron does not depend on the checkout file's executable bit.
7 * * * * root XYPTDQ_REPO_DIR=$REPO_Q XYPTDQ_PUBLISH_SOURCE=$SOURCE_Q XYPTDQ_PUBLISH_STATE=$STATE_Q XYPTDQ_PUBLISH_LOCK=$LOCK_Q /bin/bash $RUNNER_Q >/dev/null 2>&1
EOF
install -o root -g root -m 0644 "$CRON_FILE.tmp" "$CRON_FILE"
rm -f "$CRON_FILE.tmp"

echo "[publisher-cron] INSTALLED $CRON_FILE source=$SOURCE_REAL state=$STATE_PATH lock=$LOCK_PATH"
