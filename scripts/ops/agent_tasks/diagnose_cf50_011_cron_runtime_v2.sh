#!/bin/bash
# Read-only runtime diagnosis for the CF50 Wave1 Publisher cron.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
CRON="/etc/cron.d/xyptdq-publisher"
RUNNER="$REPO/scripts/content/run_scheduled_publish.sh"
SOURCE="/var/lib/xyptdq-content/CF50-20260813-wave1/scheduled"
STATE="/var/lib/xyptdq-publisher/CF50-20260813-wave1/state.json"
LOCK="/var/lib/xyptdq-publisher/CF50-20260813-wave1/publisher.lock"
[ -n "$RESULT_FILE" ] || exit 2

python3 - "$RESULT_FILE" "$CRON" "$RUNNER" "$SOURCE" "$STATE" "$LOCK" <<'PY'
import datetime, json, os, pathlib, re, shlex, stat, subprocess, sys

out, cron, runner, source, state, lock = sys.argv[1:]

def run(cmd, timeout=10):
    try:
        p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        return {"rc": p.returncode, "out": p.stdout.strip()[-12000:]}
    except Exception as e:
        return {"rc": 999, "out": f"{type(e).__name__}:{e}"}

def fmeta(path):
    p = pathlib.Path(path)
    if not p.exists():
        return {"exists": False}
    st = p.stat()
    b = p.read_bytes() if p.is_file() else b""
    return {
        "exists": True,
        "uid": st.st_uid,
        "gid": st.st_gid,
        "mode": oct(stat.S_IMODE(st.st_mode)),
        "size": st.st_size,
        "mtime_utc": datetime.datetime.fromtimestamp(st.st_mtime, datetime.timezone.utc).isoformat(),
        "has_crlf": b"\r\n" in b if p.is_file() else False,
        "has_nul": b"\x00" in b if p.is_file() else False,
        "ends_with_newline": b.endswith(b"\n") if p.is_file() and b else False,
    }

cron_text = pathlib.Path(cron).read_text(encoding="utf-8", errors="replace") if pathlib.Path(cron).exists() else ""
entry = ""
for line in cron_text.splitlines():
    s = line.strip()
    if s and not s.startswith("#") and not re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", s):
        entry = s
        break
parts = entry.split()
entry_user = parts[5] if len(parts) >= 6 else ""
entry_schedule = " ".join(parts[:5]) if len(parts) >= 5 else ""

services = {}
for unit in ("cron", "crond"):
    services[unit] = {
        "active": run(["systemctl", "is-active", unit]),
        "enabled": run(["systemctl", "is-enabled", unit]),
        "show": run(["systemctl", "show", unit, "-p", "LoadState", "-p", "ActiveState", "-p", "SubState", "-p", "UnitFileState", "-p", "FragmentPath"]),
    }

proc = run(["ps", "-eo", "pid=,comm=,args="])
proc_lines = [x for x in proc["out"].splitlines() if re.search(r"(^|\s)(cron|crond)(\s|$)", x)]
proc_summary = "\n".join(proc_lines[-20:])

journal = run(["journalctl", "-u", "cron", "--since", "2026-08-14 18:55:00", "--until", "2026-08-14 19:20:00", "--no-pager", "-o", "short-iso"], timeout=15)
journal_lines = [x for x in journal["out"].splitlines() if ("xyptdq" in x.lower() or "run_scheduled_publish" in x.lower())]
journal_filtered = "\n".join(journal_lines[-80:])

file_logs = []
for log in ("/var/log/syslog", "/var/log/cron.log"):
    p = pathlib.Path(log)
    if p.exists():
        try:
            lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
            hits = [x for x in lines if ("xyptdq" in x.lower() or "run_scheduled_publish" in x.lower())]
            file_logs.append(f"{log}:\n" + "\n".join(hits[-80:]))
        except Exception as e:
            file_logs.append(f"{log}:ERROR:{e}")

runner_meta = fmeta(runner)
runner_meta["bash_syntax"] = run(["/bin/bash", "-n", runner])
runner_meta["executable"] = os.access(runner, os.X_OK)

cron_meta = fmeta(cron)
cron_meta.update({
    "entry_schedule": entry_schedule,
    "entry_user": entry_user,
    "entry_has_source": f"XYPTDQ_PUBLISH_SOURCE={source}" in entry,
    "entry_has_state": f"XYPTDQ_PUBLISH_STATE={state}" in entry,
    "entry_has_lock": f"XYPTDQ_PUBLISH_LOCK={lock}" in entry,
    "entry_has_runner": runner in entry,
})

source_count = len(list(pathlib.Path(source).glob("*.json"))) if pathlib.Path(source).is_dir() else -1
active = any(v["active"]["out"] == "active" and v["active"]["rc"] == 0 for v in services.values())
root_cause = "undetermined"
if not active:
    root_cause = "cron_daemon_inactive"
elif not cron_meta.get("exists"):
    root_cause = "cron_file_missing"
elif cron_meta.get("uid") != 0 or cron_meta.get("mode") != "0o644":
    root_cause = "cron_file_owner_or_mode_invalid"
elif cron_meta.get("has_crlf") or cron_meta.get("has_nul") or not cron_meta.get("ends_with_newline"):
    root_cause = "cron_file_format_invalid"
elif entry_schedule != "7 * * * *" or entry_user != "root":
    root_cause = "cron_entry_schedule_or_user_invalid"
elif not all(cron_meta.get(k) for k in ("entry_has_source","entry_has_state","entry_has_lock","entry_has_runner")):
    root_cause = "cron_entry_binding_invalid"
elif not runner_meta.get("exists") or not runner_meta.get("executable") or runner_meta["bash_syntax"]["rc"] != 0:
    root_cause = "runner_not_executable_or_invalid"
elif journal_lines:
    root_cause = "cron_dispatched_check_runner_prelog_failure"
else:
    root_cause = "cron_active_but_no_dispatch_evidence"

payload = {
    "task": "diagnose_cf50_011_cron_runtime_v2",
    "status": "PASS",
    "read_only": True,
    "probable_root_cause": root_cause,
    "services": services,
    "cron_file": cron_meta,
    "runner": runner_meta,
    "processes": proc_summary,
    "journal_xyptdq_1855_1920": journal_filtered,
    "file_log_xyptdq_tail": "\n".join(file_logs)[-12000:],
    "source_exists": pathlib.Path(source).is_dir(),
    "source_json_count": source_count,
    "state_exists": pathlib.Path(state).exists(),
    "lock_exists": pathlib.Path(lock).exists(),
    "cms_write_attempted": False,
    "queue_consumed": False,
    "cron_mutated": False,
}
pathlib.Path(out).write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
echo DIAGNOSE_CF50_011_CRON_RUNTIME_V2=PASS
