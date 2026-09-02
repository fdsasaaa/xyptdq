#!/bin/bash
# Read-only probe: did the publisher cron actually run, and what is the canary state?
# Confirms: publisher run logs (mtime/content-summary), sitemap mtime, ordinary-seo
# state/lock/receipts, stable queue contents, canonical repo dirtiness, cron lines.
# read_only=true, cms_write=false, cron_write=false, schedule_write=false, publisher_invoked=false
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
LOG_DIR="${XYPTDQ_PUBLISH_LOG_DIR:-/var/log/xyptdq-publisher}"
STABLE_QUEUE="/var/lib/xyptdq-content/ordinary-seo/scheduled"
ORD_STATE="/var/lib/xyptdq-publisher/ordinary-seo/state.json"
ORD_LOCK="/var/lib/xyptdq-publisher/ordinary-seo/publisher.lock"
PUBLISHER_CRON="${XYPTDQ_PUBLISHER_CRON:-/etc/cron.d/xyptdq-publisher}"
PROMOTION_CRON="${XYPTDQ_PROMOTION_CRON:-/etc/cron.d/xyptdq-promotion}"
SITEMAP="${XYPTDQ_SITEMAP:-/www/wwwroot/59.110.217.6/sitemap.xml}"

[ -n "$RESULT_FILE" ] || exit 2

write_result(){ python3 - "$RESULT_FILE" "$1" <<'PY'
import json, sys
out, status = sys.argv[1:]
p = {
  "task": "publisher_execution_probe_v1",
  "status": status,
  "phase": "complete",
  "blocking_item": "NONE",
  "cms_write": False,
  "cron_write": False,
  "schedule_write": False,
  "publisher_invoked": False,
  "read_only": True,
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(p, f, ensure_ascii=False, indent=2, sort_keys=True); f.write("\n")
PY
}

F=$(python3 - "$RESULT_FILE" "$REPO" "$LOG_DIR" "$STABLE_QUEUE" "$ORD_STATE" "$ORD_LOCK" "$PUBLISHER_CRON" "$PROMOTION_CRON" "$SITEMAP" <<'PY'
import json, os, pathlib, subprocess, sys
result_file, repo, log_dir, queue, ord_state, ord_lock, pub_cron, promo_cron, sitemap = sys.argv[1:]
out = {}
now = None
try:
    import datetime
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
except Exception:
    pass
out["server_now_utc"] = now

# 1. publisher run logs
ld = pathlib.Path(log_dir)
logs = sorted(ld.glob("run_*.log")) if ld.is_dir() else []
out["publisher_log_dir_exists"] = ld.is_dir()
out["publisher_log_count"] = len(logs)
if logs:
    latest = logs[-1]
    out["latest_publisher_log"] = latest.name
    out["latest_publisher_log_mtime_utc"] = datetime.datetime.fromtimestamp(latest.stat().st_mtime, datetime.timezone.utc).isoformat()
    try:
        tail = latest.read_text(encoding="utf-8", errors="replace").splitlines()[-15:]
        out["latest_publisher_log_tail"] = tail
    except Exception as e:
        out["latest_publisher_log_read_error"] = str(e)
else:
    out["latest_publisher_log"] = None

# 2. sitemap mtime
sp = pathlib.Path(sitemap)
out["sitemap_exists"] = sp.is_file()
if sp.is_file():
    out["sitemap_mtime_utc"] = datetime.datetime.fromtimestamp(sp.stat().st_mtime, datetime.timezone.utc).isoformat()

# 3. ordinary-seo state/lock/receipts
for label, path in (("ordinary_state", ord_state), ("ordinary_lock", ord_lock)):
    p = pathlib.Path(path)
    out[f"{label}_exists"] = p.is_file()
    if p.is_file():
        out[f"{label}_mtime_utc"] = datetime.datetime.fromtimestamp(p.stat().st_mtime, datetime.timezone.utc).isoformat()
state_dir = pathlib.Path(ord_state).parent
recs = sorted(state_dir.glob("receipts/*.json")) if (state_dir / "receipts").is_dir() else []
vers = sorted(state_dir.glob("seo-verification/*.json")) if (state_dir / "seo-verification").is_dir() else []
out["ordinary_receipt_count"] = len(recs)
out["ordinary_verification_count"] = len(vers)
if recs:
    out["ordinary_receipt_names"] = [r.name for r in recs]

# 4. stable queue contents
q = pathlib.Path(queue)
items = sorted(q.glob("*.json")) if q.is_dir() else []
out["stable_queue_count"] = len(items)
if items:
    for it in items:
        try:
            d = json.loads(it.read_text(encoding="utf-8"))
            out.setdefault("queue_items", []).append({
                "file": it.name,
                "article_key": d.get("article_key"),
                "source_batch_id": d.get("source_batch_id"),
                "publication_state": d.get("publication_state"),
                "publish_at": d.get("publish_at"),
                "source_revision_id": d.get("source_revision_id"),
                "source_content_hash": d.get("source_content_hash", "")[:16] + "..." if d.get("source_content_hash") else None,
            })
        except Exception as e:
            out.setdefault("queue_errors", []).append({"file": it.name, "error": str(e)})

# 5. canonical repo dirty + head
try:
    r = subprocess.run(["git", "-C", repo, "status", "--porcelain"], capture_output=True, text=True, timeout=15)
    out["canonical_repo_dirty"] = bool(r.stdout.strip())
    out["canonical_repo_dirty_lines"] = len([l for l in r.stdout.splitlines() if l.strip()])
except Exception as e:
    out["canonical_repo_git_error"] = str(e)
try:
    r = subprocess.run(["git", "-C", repo, "rev-parse", "--short", "HEAD"], capture_output=True, text=True, timeout=15)
    out["canonical_repo_head"] = r.stdout.strip()
except Exception:
    pass

# 6. cron lines
for label, path in (("publisher_cron", pub_cron), ("promotion_cron", promo_cron)):
    p = pathlib.Path(path)
    out[f"{label}_exists"] = p.is_file()
    if p.is_file():
        out[f"{label}_lines"] = p.read_text(encoding="utf-8", errors="replace").splitlines()
# held backup?
held = pathlib.Path(promo_cron + ".held-e2e-20260902")
out["promotion_cron_held_backup_exists"] = held.is_file()

print(json.dumps(out, ensure_ascii=False, sort_keys=True))
PY
)

STATUS="PASS"
if [ -z "$F" ]; then STATUS="FAIL"; fi
python3 - "$RESULT_FILE" "$STATUS" "$F" <<'PY'
import json, sys
result_file, status, findings = sys.argv[1:]
with open(result_file, "w", encoding="utf-8") as f:
    json.dump({
        "task": "publisher_execution_probe_v1",
        "status": status,
        "phase": "complete",
        "blocking_item": "NONE",
        "cms_write": False,
        "cron_write": False,
        "schedule_write": False,
        "publisher_invoked": False,
        "read_only": True,
        "findings": json.loads(findings),
    }, f, ensure_ascii=False, indent=2, sort_keys=True); f.write("\n")
PY
echo "PUBLISHER_EXECUTION_PROBE_V1=$STATUS"
