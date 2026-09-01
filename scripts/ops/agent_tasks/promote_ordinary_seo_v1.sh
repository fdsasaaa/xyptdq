#!/bin/bash
# Ordinary SEO Auto Promotion Scheduler (durable, recurring).
# Corrected identity handling (Phase 2), stable queue (Phase 3), eligibility isolation
# (Phase 4), calendar-week quota (Phase 6). Runs as a server cron (Phase 5 installer).
# NEVER writes CMS directly; publication is exclusively via the native publisher cron.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
INTAKE_DRAFTS="/var/lib/xyptdq-content/intake/drafts"
STABLE_QUEUE="/var/lib/xyptdq-content/ordinary-seo/scheduled"
POLICY="$REPO/config/content_publication_policy.json"
INVENTORY_POLICY="$REPO/config/content_inventory_policy.json"
PROMOTE="$REPO/scripts/content/promote_draft.php"
PUBLISHER_STATE_DIR="/var/lib/xyptdq-publisher"

PHASE="init"
STATUS="BLOCKED"
BLOCKING_ITEM="NONE"
CANDIDATE_AVAILABLE=0
SCHEDULED_ACTIVE=0
WEEK_COUNT=0
ADDED=0

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3

write_result(){ python3 - "$RESULT_FILE" "$STATUS" "$PHASE" "$BLOCKING_ITEM" "$CANDIDATE_AVAILABLE" "$SCHEDULED_ACTIVE" "$WEEK_COUNT" "$ADDED" <<'PY'
import json, sys
out, status, phase, blocker, cand, active, week, added = sys.argv[1:]
p = {
  "task": "promote_ordinary_seo_v1",
  "status": status,
  "phase": phase,
  "blocking_item": blocker,
  "candidate_available": int(cand),
  "active_future_scheduled": int(active),
  "current_week_scheduled_or_published": int(week),
  "added_this_run": int(added),
  "cadence": "weekly_2_3",
  "cms_write": False,
  "publisher_invoked": False,
  "legacy_repository_queue_consumed": False,
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(p, f, ensure_ascii=False, indent=2, sort_keys=True); f.write("\n")
PY
}

block(){ BLOCKING_ITEM="$1"; STATUS="BLOCKED"; write_result; echo "[ordinary-seo-promote] BLOCKED: $1" >&2; exit 1; }

PHASE="sync_main"
cd "$REPO"
[ -z "$(git status --porcelain)" ] || block production_repo_dirty
git fetch --prune origin >/dev/null 2>&1
git reset --hard origin/main >/dev/null

PHASE="preflight"
[ -f "$POLICY" ] || block publication_policy_missing
[ -f "$INVENTORY_POLICY" ] || block inventory_policy_missing
[ -f "$PROMOTE" ] || block promote_script_missing
[ -d "$INTAKE_DRAFTS" ] || block intake_draft_buffer_missing
AUTH=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo ((($x["ordinary_seo_promotion"]["enabled"]??null)===true)?"yes":"no");' "$POLICY")
[ "$AUTH" = yes ] || block ordinary_seo_promotion_not_enabled_in_policy

PHASE="compute_state"
STATE=$(python3 - "$INTAKE_DRAFTS" "$STABLE_QUEUE" "$POLICY" "$INVENTORY_POLICY" <<'PY'
import json, pathlib, sys, datetime
drafts_root, queue_root, policy_path, inv_path = [pathlib.Path(x) for x in sys.argv[1:]]
zone = datetime.timezone(datetime.timedelta(hours=8))
now = datetime.datetime.now(zone)

policy = json.loads(policy_path.read_text(encoding="utf-8"))
inv = json.loads(inv_path.read_text(encoding="utf-8"))
cfg = policy.get("ordinary_seo_promotion", {})
prefixes = [str(x) for x in cfg.get("eligible_source_batch_prefixes", ["DAILY-"])]
excluded = [str(x) for x in cfg.get("excluded_source_batch_patterns", [])]
overrides = cfg.get("batch_eligibility_overrides", {})
weekly_max = int(cfg.get("weekly_max_articles", 3))
frozen = set(str(x) for x in (inv.get("cf50_terminal_baseline", {}).get("final5_frozen_pending_issue_264", [])))

# queue state
active_future = 0
week_count = 0
week_start = (now - datetime.timedelta(days=now.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
week_end = week_start + datetime.timedelta(days=7)
queue_by_key = {}
queue_by_rev = set()
if queue_root.is_dir():
    for p in queue_root.glob("*.json"):
        try:
            x = json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            continue
        if x.get("article_key"): queue_by_key[x["article_key"]] = p.name
        if x.get("source_revision_id"): queue_by_rev.add(x["source_revision_id"])
        try:
            when = datetime.datetime.fromisoformat(str(x.get("publish_at")))
        except Exception:
            continue
        if when > now:
            active_future += 1
        if week_start <= when < week_end:
            week_count += 1

# eligible candidates
cands = []
for p in sorted(drafts_root.glob("*.draft.json")):
    try:
        x = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        continue
    if x.get("publication_state") != "draft":
        continue
    batch = str(x.get("source_batch_id") or "")
    if not any(batch.startswith(pre) for pre in prefixes):
        continue
    if any(bad in batch for bad in excluded):
        continue
    if batch in overrides and overrides[batch] != "eligible":
        continue
    aid = str(x.get("source_article_id") or "")
    if aid and aid in frozen:
        continue
    rev = str(x.get("source_revision_id") or "")
    key = str(x.get("article_key") or "")
    if not rev or not key or not x.get("source_content_hash"):
        continue
    if key in queue_by_key or rev in queue_by_rev:
        continue
    # priority: DAILY-20260901 first, then by batch then revision
    cands.append({"path": str(p), "article_key": key, "revision_id": rev,
                  "batch": batch, "content_hash": str(x.get("source_content_hash"))})
cands.sort(key=lambda c: (0 if c["batch"] == "DAILY-20260901" else 1, c["batch"], c["revision_id"]))

out = {
    "active_future_scheduled": active_future,
    "current_week_scheduled_or_published": week_count,
    "weekly_max": weekly_max,
    "candidate_available": len(cands),
    "candidate": cands[0] if cands else None,
    "week_start_sgt": week_start.isoformat(),
    "week_end_sgt": week_end.isoformat(),
}
print(json.dumps(out, ensure_ascii=False, sort_keys=True))
PY
)
CANDIDATE_AVAILABLE=$(echo "$STATE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["candidate_available"])')
SCHEDULED_ACTIVE=$(echo "$STATE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["active_future_scheduled"])')
WEEK_COUNT=$(echo "$STATE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["current_week_scheduled_or_published"])')
WEEKLY_MAX=$(echo "$STATE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["weekly_max"])')

PHASE="quota_check"
[ "$WEEK_COUNT" -lt "$WEEKLY_MAX" ] || { PHASE="complete"; STATUS="PASS"; write_result; echo "ORDINARY_SEO_PROMOTE=PASS(week_quota_reached=$WEEK_COUNT/$WEEKLY_MAX)"; exit 0; }
[ "$SCHEDULED_ACTIVE" -lt 1 ] || { PHASE="complete"; STATUS="PASS"; write_result; echo "ORDINARY_SEO_PROMOTE=PASS(rolling_horizon_full=$SCHEDULED_ACTIVE)"; exit 0; }

PHASE="select_candidate"
[ "$CANDIDATE_AVAILABLE" -ge 1 ] || block no_eligible_draft_candidates
CAND_PATH=$(echo "$STATE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["candidate"]["path"])')
CAND_KEY=$(echo "$STATE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["candidate"]["article_key"])')

PHASE="next_slot"
PUBLISH_AT=$(python3 - <<'PY'
import datetime, sys
zone = datetime.timezone(datetime.timedelta(hours=8))
now = datetime.datetime.now(zone)
days = {"Tuesday": 1, "Thursday": 3, "Saturday": 5}
for i in range(14):
    d = now + datetime.timedelta(days=i)
    if d.strftime("%A") in days:
        at = d.replace(hour=10, minute=0, second=0, microsecond=0)
        if at > now:
            print(at.isoformat())
            break
PY
)
[ -n "$PUBLISH_AT" ] || block cannot_compute_next_slot

PHASE="promote_one"
install -d -o root -g www-data -m 0750 "$(dirname "$STABLE_QUEUE")" "$STABLE_QUEUE"
php "$PROMOTE" --input="$CAND_PATH" --publish-at="$PUBLISH_AT" --output="$STABLE_QUEUE/$CAND_KEY.json" >/dev/null
ADDED=1

PHASE="verify_one"
python3 - "$STABLE_QUEUE/$CAND_KEY.json" "$CAND_PATH" <<'PY'
import json, pathlib, sys, datetime
sched_path, draft_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
x = json.loads(sched_path.read_text(encoding="utf-8"))
d = json.loads(draft_path.read_text(encoding="utf-8"))
assert x.get("publication_state") == "scheduled"
assert x.get("article_key") == d.get("article_key")
assert x.get("source_article_id") == d.get("source_article_id")
assert x.get("source_revision_id") == d.get("source_revision_id")
assert x.get("source_content_hash") == d.get("source_content_hash")
assert x.get("source_batch_id") == d.get("source_batch_id")
assert str(x.get("source_batch_id", "")).startswith("DAILY-"), "CF50/other batch must never be auto-scheduled"
when = datetime.datetime.fromisoformat(str(x["publish_at"]))
assert when > datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))), "publish_at must be future"
assert int(x.get("catid") or 0) > 0
PY

PHASE="complete"
STATUS="PASS"
write_result
echo "ORDINARY_SEO_PROMOTE=PASS added=$ADDED publish_at=$PUBLISH_AT article_key=$CAND_KEY"
