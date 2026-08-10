#!/bin/bash
# xyptdq Server Bridge worker.
# Polls versioned jobs from origin/main and executes only approved, exact-commit
# scripts. Raw task logs stay local; only sanitized JSON payloads are pushed.
set -euo pipefail
umask 077

CONTROL_REPO="${XYPTDQ_AGENT_CONTROL_REPO:-/var/lib/xyptdq-agent/control.git}"
STATE_ROOT="${XYPTDQ_AGENT_STATE_ROOT:-/var/lib/xyptdq-agent/state}"
LOG_ROOT="${XYPTDQ_AGENT_LOG_ROOT:-/var/log/xyptdq-agent}"
LOCK_FILE="${XYPTDQ_AGENT_LOCK_FILE:-/run/lock/xyptdq-agent.lock}"
PRODUCTION_REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
MAIN_REF="refs/remotes/origin/main"

log() {
  printf '[xyptdq-agent] %s\n' "$*"
}

fail() {
  printf '[xyptdq-agent] ERROR: %s\n' "$*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "worker must run as root"
[ -d "$CONTROL_REPO" ] || fail "control bare repository missing"
mkdir -p "$STATE_ROOT" "$LOG_ROOT" "$(dirname "$LOCK_FILE")"
chmod 700 "$STATE_ROOT" "$LOG_ROOT"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "another worker is active; exiting"
  exit 0
fi

# Fetch only the canonical control branch. Jobs never execute from unmerged PRs.
git --git-dir="$CONTROL_REPO" fetch --quiet --prune origin \
  '+refs/heads/main:refs/remotes/origin/main' || fail "cannot fetch origin/main"
git --git-dir="$CONTROL_REPO" cat-file -e "$MAIN_REF^{commit}" || fail "origin/main missing"

publish_result() {
  local job_id="$1"
  local state_dir="$2"
  local result_json="$state_dir/result.json"
  local result_branch="agent/results/$job_id"
  local remote_line

  [ -s "$result_json" ] || return 1

  remote_line=$(git --git-dir="$CONTROL_REPO" ls-remote --heads origin "$result_branch" 2>/dev/null || true)
  if [ -n "$remote_line" ]; then
    touch "$state_dir/pushed"
    log "result already remote for $job_id"
    return 0
  fi

  # If a previous push failed after the local result commit was created, retry it
  # without ever rerunning the task.
  if git --git-dir="$CONTROL_REPO" show-ref --verify --quiet "refs/heads/$result_branch"; then
    if git --git-dir="$CONTROL_REPO" push --quiet origin \
      "refs/heads/$result_branch:refs/heads/$result_branch"; then
      touch "$state_dir/pushed"
      log "retried result push for $job_id"
      return 0
    fi
    return 1
  fi

  local worktree
  worktree=$(mktemp -d /tmp/xyptdq-agent-result.XXXXXX)
  if ! git --git-dir="$CONTROL_REPO" worktree add --quiet --detach "$worktree" "$MAIN_REF"; then
    rm -rf "$worktree"
    return 1
  fi

  git -C "$worktree" config user.name 'xyptdq-server-agent'
  git -C "$worktree" config user.email 'xyptdq-agent@localhost'
  git -C "$worktree" checkout --quiet -b "$result_branch"
  mkdir -p "$worktree/ops/jobs/results"
  cp "$result_json" "$worktree/ops/jobs/results/$job_id.json"
  git -C "$worktree" add "ops/jobs/results/$job_id.json"
  git -C "$worktree" commit --quiet -m "Agent result: $job_id"

  local result_commit
  result_commit=$(git -C "$worktree" rev-parse HEAD)
  printf '%s\n' "$result_commit" > "$state_dir/result_commit"

  local push_ok=0
  if git -C "$worktree" push --quiet origin "$result_branch"; then
    push_ok=1
  fi

  git --git-dir="$CONTROL_REPO" worktree remove --force "$worktree" >/dev/null 2>&1 || true
  rm -rf "$worktree" >/dev/null 2>&1 || true

  if [ "$push_ok" -eq 1 ]; then
    touch "$state_dir/pushed"
    log "published result branch $result_branch"
    return 0
  fi
  return 1
}

write_result() {
  local state_dir="$1"
  local job_id="$2"
  local status="$3"
  local exit_code="$4"
  local started_at="$5"
  local finished_at="$6"
  local required_commit="$7"
  local script_path="$8"
  local script_sha="$9"
  local payload_file="${10}"

  python3 - "$state_dir/result.json" "$job_id" "$status" "$exit_code" \
    "$started_at" "$finished_at" "$required_commit" "$script_path" "$script_sha" \
    "$payload_file" <<'PY'
import json, os, sys
(out, job_id, status, exit_code, started, finished, commit, script, script_sha, payload_path) = sys.argv[1:]
payload = {}
if payload_path and os.path.isfile(payload_path) and os.path.getsize(payload_path) > 0:
    if os.path.getsize(payload_path) > 65536:
        raise SystemExit('payload too large')
    with open(payload_path, 'r', encoding='utf-8') as fh:
        payload = json.load(fh)
    if not isinstance(payload, dict):
        raise SystemExit('payload must be a JSON object')

blocked_keys = {'password', 'passwd', 'token', 'cookie', 'secret', 'private_key', 'dsn', 'database_password'}

def inspect(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if str(key).lower() in blocked_keys:
                raise SystemExit('sensitive payload key rejected')
            inspect(child)
    elif isinstance(value, list):
        for child in value:
            inspect(child)
    elif isinstance(value, str):
        upper = value.upper()
        if 'BEGIN PRIVATE KEY' in upper or 'BEGIN RSA PRIVATE KEY' in upper or 'BEGIN OPENSSH PRIVATE KEY' in upper:
            raise SystemExit('private key material rejected')
inspect(payload)

result = {
    'schema_version': 1,
    'job_id': job_id,
    'status': status,
    'exit_code': int(exit_code),
    'started_at': started,
    'finished_at': finished,
    'required_commit': commit,
    'script': script,
    'script_sha256': script_sha,
    'payload': payload,
    'raw_log_published': False,
}
with open(out, 'w', encoding='utf-8') as fh:
    json.dump(result, fh, ensure_ascii=False, indent=2, sort_keys=True)
    fh.write('\n')
PY
}

# Process at most one not-yet-handled job per timer tick.
mapfile -t JOB_PATHS < <(
  git --git-dir="$CONTROL_REPO" ls-tree -r --name-only "$MAIN_REF" ops/jobs/pending 2>/dev/null \
    | grep -E '^ops/jobs/pending/[a-z0-9][a-z0-9._-]{2,80}\.json$' \
    | sort || true
)

if [ "${#JOB_PATHS[@]}" -eq 0 ]; then
  log "no pending jobs"
  exit 0
fi

for job_path in "${JOB_PATHS[@]}"; do
  job_tmp=$(mktemp /tmp/xyptdq-agent-job.XXXXXX.json)
  git --git-dir="$CONTROL_REPO" show "$MAIN_REF:$job_path" > "$job_tmp"

  set +e
  meta=$(python3 - "$job_tmp" "$job_path" <<'PY'
import json, re, sys
path = sys.argv[2]
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    x = json.load(fh)
if not isinstance(x, dict) or x.get('schema_version') != 1:
    raise SystemExit(2)
job_id = str(x.get('job_id', ''))
commit = str(x.get('required_commit', ''))
script = str(x.get('script', ''))
sha = str(x.get('script_sha256', ''))
timeout = x.get('timeout_seconds', 900)
if not re.fullmatch(r'[a-z0-9][a-z0-9._-]{2,80}', job_id):
    raise SystemExit(3)
if path != f'ops/jobs/pending/{job_id}.json':
    raise SystemExit(4)
if not re.fullmatch(r'[0-9a-f]{40}', commit):
    raise SystemExit(5)
allowed = script == 'scripts/ops/chatgpt_finalize_publisher_v5.sh' or re.fullmatch(r'scripts/ops/agent_tasks/[A-Za-z0-9._/-]+\.sh', script)
if not allowed or '..' in script or script.startswith('/'):
    raise SystemExit(6)
if not re.fullmatch(r'[0-9a-f]{64}', sha):
    raise SystemExit(7)
if not isinstance(timeout, int) or timeout < 10 or timeout > 1800:
    raise SystemExit(8)
print(job_id)
print(commit)
print(script)
print(sha)
print(timeout)
PY
)
  parse_rc=$?
  set -e
  rm -f "$job_tmp"

  if [ "$parse_rc" -ne 0 ]; then
    log "invalid job document ignored: $job_path"
    continue
  fi

  mapfile -t META_LINES <<< "$meta"
  job_id="${META_LINES[0]}"
  required_commit="${META_LINES[1]}"
  script_path="${META_LINES[2]}"
  expected_sha="${META_LINES[3]}"
  timeout_seconds="${META_LINES[4]}"
  state_dir="$STATE_ROOT/$job_id"
  mkdir -p "$state_dir"
  chmod 700 "$state_dir"

  if [ -e "$state_dir/pushed" ]; then
    continue
  fi
  if [ -s "$state_dir/result.json" ]; then
    publish_result "$job_id" "$state_dir" || log "result push still pending for $job_id"
    exit 0
  fi

  # Never rerun a task after an interrupted worker. A new job id is required.
  if [ -e "$state_dir/running" ]; then
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '{}\n' > "$state_dir/payload.json"
    write_result "$state_dir" "$job_id" "INTERRUPTED" 125 "$now" "$now" \
      "$required_commit" "$script_path" "$expected_sha" "$state_dir/payload.json"
    rm -f "$state_dir/running"
    publish_result "$job_id" "$state_dir" || log "interrupted result push pending for $job_id"
    exit 0
  fi

  git --git-dir="$CONTROL_REPO" cat-file -e "$required_commit^{commit}" 2>/dev/null \
    || fail "required commit unavailable for $job_id"
  git --git-dir="$CONTROL_REPO" merge-base --is-ancestor "$required_commit" "$MAIN_REF" \
    || fail "required commit is not an ancestor of origin/main for $job_id"

  task_file=$(mktemp /tmp/xyptdq-agent-task.XXXXXX.sh)
  git --git-dir="$CONTROL_REPO" show "$required_commit:$script_path" > "$task_file" \
    || fail "cannot extract approved script for $job_id"
  actual_sha=$(sha256sum "$task_file" | awk '{print $1}')
  [ "$actual_sha" = "$expected_sha" ] || fail "script hash mismatch for $job_id"
  bash -n "$task_file" || fail "task shell syntax invalid for $job_id"
  chmod 700 "$task_file"

  started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s\n' "$started_at" > "$state_dir/running"
  payload_file="$state_dir/payload.json"
  log_file="$LOG_ROOT/$job_id.log"
  : > "$log_file"
  chmod 600 "$log_file"

  log "executing $job_id from $required_commit"
  set +e
  XYPTDQ_AGENT_JOB_ID="$job_id" \
  XYPTDQ_AGENT_REQUIRED_COMMIT="$required_commit" \
  XYPTDQ_AGENT_RESULT_FILE="$payload_file" \
  XYPTDQ_REPO_DIR="$PRODUCTION_REPO" \
    timeout --signal=TERM --kill-after=10s "${timeout_seconds}s" bash "$task_file" \
      >"$log_file" 2>&1
  task_rc=$?
  set -e
  finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  rm -f "$task_file"

  status="FAIL"
  if [ "$task_rc" -eq 0 ]; then
    status="PASS"
  fi
  if [ ! -s "$payload_file" ]; then
    printf '{}\n' > "$payload_file"
  fi

  if ! write_result "$state_dir" "$job_id" "$status" "$task_rc" "$started_at" "$finished_at" \
      "$required_commit" "$script_path" "$expected_sha" "$payload_file"; then
    # Payload validation failures must not leak the payload or rerun the task.
    printf '{}\n' > "$payload_file"
    write_result "$state_dir" "$job_id" "RESULT_REJECTED" 126 "$started_at" "$finished_at" \
      "$required_commit" "$script_path" "$expected_sha" "$payload_file"
  fi
  rm -f "$state_dir/running"

  if publish_result "$job_id" "$state_dir"; then
    log "job $job_id finished status=$status rc=$task_rc"
  else
    log "job $job_id finished, but result push is pending"
  fi
  exit 0
done

log "no unhandled valid jobs"
