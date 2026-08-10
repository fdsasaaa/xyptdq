# Server Bridge V1

## Purpose

Server Bridge V1 removes WorkBuddy from routine server operations. ChatGPT changes code and creates an immutable GitHub job; the production server polls canonical `main`, executes only an approved exact-commit script, and publishes a sanitized result on a unique Git branch.

The bridge is intentionally fail-closed. It is not a general remote shell.

## Trust boundary

The server executes jobs only when all of the following are true:

1. The job JSON exists under `ops/jobs/pending/` on canonical `origin/main`.
2. `schema_version` is `1`.
3. `job_id` matches the job filename and strict identifier rules.
4. `required_commit` is a 40-character Git SHA and is an ancestor of current `origin/main`.
5. The script is either the explicitly grandfathered publisher finalizer or is under `scripts/ops/agent_tasks/`.
6. The exact script bytes extracted from `required_commit` match `script_sha256` in the job.
7. Timeout is between 10 and 1800 seconds.
8. The job has not already been executed locally.

No arbitrary shell command string is accepted in a job document. Operational parameters belong in reviewed versioned scripts, not in job JSON.

## Job schema

Example:

```json
{
  "schema_version": 1,
  "job_id": "bridge-healthcheck-20260810-01",
  "required_commit": "0123456789abcdef0123456789abcdef01234567",
  "script": "scripts/ops/agent_tasks/bridge_healthcheck.sh",
  "script_sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "timeout_seconds": 120
}
```

## Result model

The worker captures raw stdout/stderr only in `/var/log/xyptdq-agent/` with root-only permissions. Raw logs are never pushed to GitHub.

A task may write a sanitized JSON object to the path provided in `XYPTDQ_AGENT_RESULT_FILE`. The worker wraps that payload with execution metadata and publishes:

`ops/jobs/results/<job_id>.json`

on branch:

`agent/results/<job_id>`

The server keeps persistent local execution state under `/var/lib/xyptdq-agent/state/` so an already-run task is not repeated merely because the pending job remains on `main`.

If the worker is interrupted after marking a job running but before recording a result, the next tick records `INTERRUPTED` rather than rerunning a potentially destructive operation. A new job id is required for retry.

## Polling

A systemd timer runs once per minute. Each tick processes at most one unhandled job.

Installed units:

- `/etc/systemd/system/xyptdq-agent.service`
- `/etc/systemd/system/xyptdq-agent.timer`

Launcher:

- `/usr/local/sbin/xyptdq-agent-run`

Control Git repository:

- `/var/lib/xyptdq-agent/control.git`

The launcher loads the current worker from canonical GitHub `main` each run, allowing reviewed bridge fixes without another manual SSH installation.

## Security rules

- Never place credentials, database configuration, private keys, tokens, cookies, or passwords in job JSON or result payloads.
- Never add arbitrary command fields to the job schema.
- Keep high-risk actions in dedicated, reviewed `scripts/ops/agent_tasks/*.sh` scripts.
- Tasks should create verified backups before destructive production changes.
- Result payloads must be structured facts, not raw command logs.
- Do not enable an operation merely because a task exited zero; task-specific verification remains required.

## One-time installation

Installation is performed once as root from the clean production Git repository:

```bash
cd /opt/xyptdq-repo
git fetch --prune origin
git checkout main
git reset --hard origin/main
bash scripts/agent/install.sh
```

After installation, routine server operations are driven by versioned GitHub jobs and should not require WorkBuddy or manual SSH commands.
