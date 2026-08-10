#!/bin/bash
# One-time installer for the xyptdq GitHub -> server execution bridge.
set -euo pipefail
umask 077

REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
AGENT_ROOT="/var/lib/xyptdq-agent"
CONTROL_REPO="$AGENT_ROOT/control.git"
STATE_ROOT="$AGENT_ROOT/state"
LOG_ROOT="/var/log/xyptdq-agent"
BOOTSTRAP="/usr/local/sbin/xyptdq-agent-run"
SERVICE_FILE="/etc/systemd/system/xyptdq-agent.service"
TIMER_FILE="/etc/systemd/system/xyptdq-agent.timer"

fail() {
  echo "[agent-install] ERROR: $*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "run as root"
[ -d "$REPO/.git" ] || fail "production Git repository missing: $REPO"
command -v git >/dev/null || fail "git missing"
command -v python3 >/dev/null || fail "python3 missing"
command -v timeout >/dev/null || fail "timeout missing"
command -v flock >/dev/null || fail "flock missing"
command -v systemctl >/dev/null || fail "systemd missing"

cd "$REPO"
if [ -n "$(git status --porcelain)" ]; then
  git status --short
  fail "production repository is dirty; refusing reset"
fi

git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null
[ -f scripts/agent/worker.sh ] || fail "worker missing from latest main"
bash -n scripts/agent/worker.sh

# Read the existing authenticated remote without printing it. The bridge reuses
# the server's existing Git authentication; no credential is copied into Git.
REMOTE_URL=$(git remote get-url origin)
[ -n "$REMOTE_URL" ] || fail "origin URL missing"

mkdir -p "$AGENT_ROOT" "$STATE_ROOT" "$LOG_ROOT"
chmod 700 "$AGENT_ROOT" "$STATE_ROOT" "$LOG_ROOT"

if [ ! -d "$CONTROL_REPO" ]; then
  git init --bare --quiet "$CONTROL_REPO"
fi
if git --git-dir="$CONTROL_REPO" remote get-url origin >/dev/null 2>&1; then
  git --git-dir="$CONTROL_REPO" remote set-url origin "$REMOTE_URL"
else
  git --git-dir="$CONTROL_REPO" remote add origin "$REMOTE_URL"
fi
git --git-dir="$CONTROL_REPO" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git --git-dir="$CONTROL_REPO" fetch --quiet --prune origin \
  '+refs/heads/main:refs/remotes/origin/main'
git --git-dir="$CONTROL_REPO" cat-file -e 'refs/remotes/origin/main^{commit}' \
  || fail "control repo cannot resolve origin/main"

# Small immutable launcher. The full worker is loaded from canonical origin/main
# on every tick, so future worker fixes do not require another SSH installation.
cat > "$BOOTSTRAP" <<'EOF'
#!/bin/bash
set -euo pipefail
umask 077
CONTROL_REPO=/var/lib/xyptdq-agent/control.git
TMP_WORKER=$(mktemp /tmp/xyptdq-agent-worker.XXXXXX.sh)
cleanup() { rm -f "$TMP_WORKER"; }
trap cleanup EXIT

git --git-dir="$CONTROL_REPO" fetch --quiet --prune origin \
  '+refs/heads/main:refs/remotes/origin/main'
git --git-dir="$CONTROL_REPO" show \
  'refs/remotes/origin/main:scripts/agent/worker.sh' > "$TMP_WORKER"
bash -n "$TMP_WORKER"
bash "$TMP_WORKER"
EOF
chown root:root "$BOOTSTRAP"
chmod 0750 "$BOOTSTRAP"

cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=xyptdq GitHub server bridge worker
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
User=root
Group=root
ExecStart=/usr/local/sbin/xyptdq-agent-run
TimeoutStartSec=35min
Nice=5
StandardOutput=journal
StandardError=journal
EOF
chown root:root "$SERVICE_FILE"
chmod 0644 "$SERVICE_FILE"

cat > "$TIMER_FILE" <<'EOF'
[Unit]
Description=Poll xyptdq GitHub job queue every minute

[Timer]
OnBootSec=20s
OnUnitActiveSec=60s
AccuracySec=5s
Persistent=true
Unit=xyptdq-agent.service

[Install]
WantedBy=timers.target
EOF
chown root:root "$TIMER_FILE"
chmod 0644 "$TIMER_FILE"

systemctl daemon-reload
systemctl enable --now xyptdq-agent.timer >/dev/null

# Run once immediately. A queued bridge healthcheck, if present, should publish
# its sanitized result branch without waiting for the next timer tick.
set +e
systemctl start xyptdq-agent.service
FIRST_RC=$?
set -e

TIMER_STATE=$(systemctl is-active xyptdq-agent.timer 2>/dev/null || true)
[ "$TIMER_STATE" = "active" ] || fail "agent timer is not active"

echo "[agent-install] INSTALLED"
echo "[agent-install] timer=active"
echo "[agent-install] first_run_rc=$FIRST_RC"
echo "[agent-install] control_repo=ready"
echo "[agent-install] WorkBuddy is no longer required for routine server jobs"
