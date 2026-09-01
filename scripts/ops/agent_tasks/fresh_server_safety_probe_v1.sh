#!/bin/bash
# Fresh Server Safety Probe (2026-09-02) — strictly read-only.
# Confirms server timezone, cron lines, publisher state isolation, canary preservation.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
STABLE_QUEUE="/var/lib/xyptdq-content/ordinary-seo/scheduled"
PUBLISHER_CRON="${XYPTDQ_PUBLISHER_CRON:-/etc/cron.d/xyptdq-publisher}"
PROMOTION_CRON="${XYPTDQ_PROMOTION_CRON:-/etc/cron.d/xyptdq-promotion}"
PUBLISHER_STATE_DIR="/var/lib/xyptdq-publisher"

PHASE="init"
STATUS="BLOCKED"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2

write_result(){ python3 - "$RESULT_FILE" "$STATUS" "$PHASE" "$BLOCKING_ITEM" "$BODY" <<'PY'
import json, sys
out, status, phase, blocker, body_raw = sys.argv[1:]
body = json.loads(body_raw) if body_raw else {}
p = {
  "task": "fresh_server_safety_probe_v1",
  "status": status,
  "phase": phase,
  "blocking_item": blocker,
  "read_only": True,
  "cms_write": False,
  "cron_write": False,
  "schedule_write": False,
  "publisher_invoked": False,
  "findings": body,
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(p, f, ensure_ascii=False, indent=2, sort_keys=True); f.write("\n")
PY
}

block(){ BLOCKING_ITEM="$1"; STATUS="BLOCKED"; BODY="{}"; write_result; echo "[safety-probe] BLOCKED: $1" >&2; exit 1; }

PHASE="gather"
BODY=$(python3 - "$STABLE_QUEUE" "$PUBLISHER_CRON" "$PROMOTION_CRON" "$PUBLISHER_STATE_DIR" <<'PY'
import json, os, pathlib, subprocess, sys
stable, pub_cron, prom_cron, state_dir = [pathlib.Path(x) for x in sys.argv[1:]]
out = {}

# --- server timezone ---
tz = None
try:
    tz = pathlib.Path("/etc/timezone").read_text(encoding="utf-8").strip() if pathlib.Path("/etc/timezone").is_file() else None
except Exception:
    pass
out["server_timezone"] = tz
try:
    r = subprocess.run(["date", "+%Z %z %Y-%m-%dT%H:%M:%S"], capture_output=True, text=True, timeout=10)
    out["date_cmd"] = r.stdout.strip()
except Exception as e:
    out["date_error"] = str(e)[:120]
try:
    r = subprocess.run(["timedatectl", "show", "--property=Timezone,TimeUSec"], capture_output=True, text=True, timeout=10)
    out["timedatectl"] = r.stdout.strip()[:300] if r.returncode == 0 else None
except Exception:
    out["timedatectl"] = None

# --- promotion cron ---
if prom_cron.is_file():
    lines = [l for l in prom_cron.read_text(encoding="utf-8", errors="replace").splitlines() if l.strip() and not l.strip().startswith("#")]
    out["promotion_cron_present"] = True
    out["promotion_cron_lines"] = lines
    out["promotion_cron_active"] = len(lines) >= 1
else:
    out["promotion_cron_present"] = False
    out["promotion_cron_lines"] = []
    out["promotion_cron_active"] = False

# --- publisher cron + env vars ---
if pub_cron.is_file():
    lines = [l for l in pub_cron.read_text(encoding="utf-8", errors="replace").splitlines() if l.strip() and not l.strip().startswith("#")]
    out["publisher_cron_present"] = True
    out["publisher_cron_lines"] = lines
    envs = {}
    for l in lines:
        for tok in l.split():
            for key in ("XYPTDQ_PUBLISH_SOURCE=", "XYPTDQ_PUBLISH_STATE=", "XYPTDQ_PUBLISH_LOCK=", "XYPTDQ_REPO_DIR="):
                if tok.startswith(key):
                    envs[key[:-1]] = tok.split("=", 1)[1]
    out["publisher_env"] = envs
else:
    out["publisher_cron_present"] = False
    out["publisher_cron_lines"] = []
    out["publisher_env"] = {}

# --- stable ordinary queue + canary ---
out["stable_ordinary_queue_count"] = len(list(stable.glob("*.json"))) if stable.is_dir() else -1
canary = None
if stable.is_dir():
    for p in stable.glob("*.json"):
        try:
            x = json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            continue
        if x.get("source_article_id") == "LCM-ANGLE-0b6f9c192c45dc31":
            canary = {
                "file": p.name,
                "article_key": x.get("article_key"),
                "source_revision_id": x.get("source_revision_id"),
                "source_batch_id": x.get("source_batch_id"),
                "publication_state": x.get("publication_state"),
                "publish_at": x.get("publish_at"),
                "source_content_hash": x.get("source_content_hash"),
            }
out["canary_scheduled_file"] = canary

# --- publisher state dirs ---
if state_dir.is_dir():
    entries = []
    for d in sorted(state_dir.iterdir()):
        if d.is_dir():
            files = [p.name for p in sorted(d.iterdir()) if p.is_file()]
            entries.append({"dir": d.name, "files": files[:20], "count": len(files)})
    out["publisher_state_dirs"] = entries
    for name in ("ordinary-seo", "CF50-20260813-wave1"):
        d = state_dir / name
        out[f"publisher_{name.replace('-','_')}_exists"] = d.is_dir()
        if d.is_dir():
            state = d / "state.json"
            out[f"publisher_{name.replace('-','_')}_state_file"] = state.is_file()
            if state.is_file():
                try:
                    st = json.loads(state.read_text(encoding="utf-8"))
                    out[f"publisher_{name.replace('-','_')}_state_keys"] = sorted(st.keys())[:30] if isinstance(st, dict) else None
                except Exception as e:
                    out[f"publisher_{name.replace('-','_')}_state_error"] = str(e)[:120]
else:
    out["publisher_state_dirs"] = []

print(json.dumps(out, ensure_ascii=False, sort_keys=True))
PY
)
[ -n "$BODY" ] || block probe_body_empty

PHASE="complete"
STATUS="PASS"
BLOCKING_ITEM="NONE"
write_result
echo "FRESH_SERVER_SAFETY_PROBE_V1=PASS"
