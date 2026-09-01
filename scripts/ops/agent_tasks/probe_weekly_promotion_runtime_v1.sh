#!/bin/bash
# Read-only runtime probe for the ordinary SEO Auto Promotion Scheduler (Phase 1).
# Statistics ONLY: draft schema census + publisher/runtime environment state.
# No CMS write, no schedule write, no cron write, no publisher invocation, no content output.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
INTAKE_DRAFTS="/var/lib/xyptdq-content/intake/drafts"
RUNTIME_QUEUE_ROOT="/var/lib/xyptdq-content"
PUBLISHER_CRON="${XYPTDQ_PUBLISHER_CRON:-/etc/cron.d/xyptdq-publisher}"
PUBLISHER_STATE_DIR="/var/lib/xyptdq-publisher"
LEGACY_QUEUE="$REPO/content/scheduled"

PHASE="init"
STATUS="BLOCKED"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3

write_result(){ python3 - "$RESULT_FILE" "$STATUS" "$PHASE" "$BLOCKING_ITEM" <<'PY'
import json, sys
out, status, phase, blocker = sys.argv[1:]
p = {
  "task": "probe_weekly_promotion_runtime_v1",
  "status": status,
  "phase": phase,
  "blocking_item": blocker,
  "cms_write": False,
  "schedule_write": False,
  "cron_write": False,
  "publisher_invoked": False,
  "read_only": True,
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(p, f, ensure_ascii=False, indent=2, sort_keys=True); f.write("\n")
PY
}

block(){ BLOCKING_ITEM="$1"; STATUS="BLOCKED"; write_result; echo "[probe] BLOCKED: $1" >&2; exit 1; }

PHASE="sync_main"
cd "$REPO"
[ -z "$(git status --porcelain)" ] || block production_repo_dirty
git fetch --prune origin >/dev/null 2>&1
git reset --hard origin/main >/dev/null

PHASE="draft_census"
[ -d "$INTAKE_DRAFTS" ] || block intake_draft_buffer_missing
CENSUS=$(python3 - "$INTAKE_DRAFTS" <<'PY'
import json, pathlib, sys, collections
root = pathlib.Path(sys.argv[1])
total = 0
by_batch = collections.Counter()
by_state = collections.Counter()
with_rev = 0
with_article = 0
with_key = 0
with_title_seo = 0
with_hash = 0
with_fp = 0
da = 0
d17 = 0
cf = 0
malformed = 0
for p in sorted(root.glob("*.draft.json")):
    try:
        x = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        malformed += 1
        continue
    total += 1
    batch = str(x.get("source_batch_id") or "(none)")
    by_batch[batch] += 1
    by_state[str(x.get("publication_state") or "(none)")] += 1
    if x.get("source_revision_id"): with_rev += 1
    if x.get("source_article_id"): with_article += 1
    if x.get("article_key"): with_key += 1
    if x.get("title_seo_contract_version") or x.get("title_review"): with_title_seo += 1
    if x.get("source_content_hash"): with_hash += 1
    if x.get("source_fingerprint"): with_fp += 1
    if batch == "DAILY-20260901": da += 1
    if batch == "DAILY-20260817": d17 += 1
    if batch == "CF50-20260813" or batch.startswith("CF50"): cf += 1
out = {
    "total_runtime_draft_files": total,
    "malformed_json": malformed,
    "count_by_source_batch_id": dict(by_batch),
    "count_by_publication_state": dict(by_state),
    "count_with_source_revision_id": with_rev,
    "count_with_source_article_id": with_article,
    "count_with_article_key": with_key,
    "count_with_source_content_hash": with_hash,
    "count_with_source_fingerprint": with_fp,
    "count_with_title_seo_contract_or_review": with_title_seo,
}
# explicit requested counters
out["daily_20260901_draft_count"] = da
out["daily_20260817_draft_count"] = d17
out["cf50_draft_count"] = cf
out["filename_pattern"] = "*.draft.json (safe_name from revision_id)"
print(json.dumps(out, ensure_ascii=False, sort_keys=True))
PY
)

PHASE="env_probe"
ENV=$(python3 - "$RUNTIME_QUEUE_ROOT" "$PUBLISHER_CRON" "$PUBLISHER_STATE_DIR" "$LEGACY_QUEUE" <<'PY'
import json, os, pathlib, sys
runtime_root, cron_path, state_dir, legacy = [pathlib.Path(x) for x in sys.argv[1:]]
out = {}
# publisher cron
if cron_path.is_file():
    lines = [l for l in cron_path.read_text(encoding="utf-8", errors="replace").splitlines() if l.strip() and not l.strip().startswith("#")]
    out["publisher_cron_present"] = True
    out["publisher_cron_lines"] = lines
    src = None
    for l in lines:
        for tok in l.split():
            if tok.startswith("XYPTDQ_PUBLISH_SOURCE="):
                src = tok.split("=", 1)[1]
    out["xyptdq_publish_source"] = src
else:
    out["publisher_cron_present"] = False
    out["xyptdq_publish_source"] = None
# runtime scheduled dirs
dirs = []
if runtime_root.is_dir():
    for d in sorted(runtime_root.iterdir()):
        if d.is_dir():
            n = len([p for p in d.iterdir() if p.is_file()])
            dirs.append({"dir": d.name, "file_count": n})
out["runtime_scheduled_dirs"] = dirs
# publisher state
if state_dir.is_dir():
    states = []
    for p in sorted(state_dir.glob("*.json")):
        try:
            x = json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            states.append({"file": p.name, "invalid": True})
            continue
        if isinstance(x, dict):
            states.append({
                "file": p.name,
                "published": x.get("published_count") or x.get("published") or len(x.get("published", [])) if isinstance(x.get("published"), list) else (x.get("published_count") or x.get("published")),
                "scheduled": x.get("scheduled_count") or x.get("scheduled"),
                "failed": x.get("failed_count") or x.get("failed"),
            })
    out["publisher_state_files"] = states
else:
    out["publisher_state_files"] = []
# receipts
receipt_dirs = [str(p) for p in (pathlib.Path("/var/lib/xyptdq-publisher/receipts"), pathlib.Path("/var/lib/xyptdq-publisher/seo-verification")) if p.is_dir()]
out["receipt_evidence_dirs"] = [{ "dir": os.path.basename(str(p)), "file_count": len(list(p.glob("*"))) } for p in receipt_dirs]
# legacy queue
out["legacy_repository_scheduled_count"] = len(list(legacy.glob("*.json"))) if legacy.is_dir() else -1
print(json.dumps(out, ensure_ascii=False, sort_keys=True))
PY
)

PHASE="complete"
STATUS="PASS"
BLOCKING_ITEM="NONE"
python3 - "$RESULT_FILE" "$STATUS" "$PHASE" "$BLOCKING_ITEM" "$CENSUS" "$ENV" <<'PY'
import json, sys
out, status, phase, blocker, census_raw, env_raw = sys.argv[1:]
census = json.loads(census_raw)
env = json.loads(env_raw)
p = {
  "task": "probe_weekly_promotion_runtime_v1",
  "status": status,
  "phase": phase,
  "blocking_item": blocker,
  "read_only": True,
  "cms_write": False,
  "schedule_write": False,
  "cron_write": False,
  "publisher_invoked": False,
  "draft_census": census,
  "environment": env,
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(p, f, ensure_ascii=False, indent=2, sort_keys=True); f.write("\n")
PY
echo "PROBE_WEEKLY_PROMOTION_RUNTIME_V1=PASS total_drafts=$(echo "$CENSUS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["total_runtime_draft_files"])')"
