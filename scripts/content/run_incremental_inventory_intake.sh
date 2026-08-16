#!/bin/bash
# Sync the private article repository through the dedicated read-only SSH key,
# then run the Draft-only incremental intake processor.
set -euo pipefail
umask 077

REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
INTAKE_ROOT="${XYPTDQ_INTAKE_ROOT:-/var/lib/xyptdq-content/intake}"
SOURCE_DIR="$INTAKE_ROOT/source/caipiaowenzhang"
KEY_FILE="$INTAKE_ROOT/credentials/caipiaowenzhang_readonly_ed25519"
KNOWN_HOSTS="$INTAKE_ROOT/credentials/github_known_hosts"
REMOTE="git@github.com:fdsasaaa/caipiaowenzhang.git"
MODE="${XYPTDQ_INTAKE_MODE:-dry-run}"
LIMIT="${XYPTDQ_INTAKE_LIMIT:-25}"
LOG_DIR="${XYPTDQ_INTAKE_LOG_DIR:-/var/log/xyptdq-intake}"

fail() {
  echo "[inventory-intake] ERROR: $*" >&2
  exit 1
}

[ -d "$REPO/.git" ] || fail "website repo missing"
[ -z "$(git -C "$REPO" status --porcelain)" ] || fail "website repo dirty"
git -C "$REPO" fetch --prune origin main >/dev/null 2>&1 || fail "website main fetch failed"
git -C "$REPO" checkout -q main || fail "website main checkout failed"
git -C "$REPO" reset --hard origin/main >/dev/null || fail "website main reset failed"

[ -s "$KEY_FILE" ] || fail "dedicated read-only SSH key missing"
[ -s "$KNOWN_HOSTS" ] || fail "pinned GitHub known_hosts missing"
[ -d "$SOURCE_DIR/.git" ] || fail "dedicated private source cache missing"
chmod 0600 "$KEY_FILE" "$KNOWN_HOSTS"
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -i $KEY_FILE -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$KNOWN_HOSTS -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no"

REMOTE_HEAD=$(git ls-remote "$REMOTE" refs/heads/main | awk '$2=="refs/heads/main"{print $1}') || fail "private source ls-remote failed"
printf '%s' "$REMOTE_HEAD" | grep -Eq '^[0-9a-f]{40}$' || fail "private source main SHA missing"
[ -z "$(git -C "$SOURCE_DIR" status --porcelain)" ] || fail "private source cache dirty"
git -C "$SOURCE_DIR" fetch -q --prune origin main || fail "private source main fetch failed"
git -C "$SOURCE_DIR" checkout -q main || fail "private source main checkout failed"
git -C "$SOURCE_DIR" reset --hard origin/main >/dev/null || fail "private source main reset failed"
SOURCE_HEAD=$(git -C "$SOURCE_DIR" rev-parse HEAD)
[ "$SOURCE_HEAD" = "$REMOTE_HEAD" ] || fail "private source checkout does not equal remote main"

mkdir -p "$LOG_DIR"
chmod 0750 "$LOG_DIR"
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
LOG_FILE="$LOG_DIR/run_${RUN_ID}.log"

python3 "$REPO/scripts/content/incremental_inventory_intake.py" \
  --source-repo="$SOURCE_DIR" \
  --website-repo="$REPO" \
  --ledger="$INTAKE_ROOT/state.json" \
  --draft-dir="$INTAKE_ROOT/drafts" \
  --lock="$INTAKE_ROOT/intake.lock" \
  --mode="$MODE" \
  --limit="$LIMIT" >"$LOG_FILE" 2>&1
chmod 0640 "$LOG_FILE"
cat "$LOG_FILE"
find "$LOG_DIR" -type f -name 'run_*.log' -mtime +60 -delete 2>/dev/null || true
